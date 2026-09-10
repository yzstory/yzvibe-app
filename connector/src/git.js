// 会话工作目录的改动概览：把 git 的输出整理成手机上能看的结构。
// 「Agent 到底改了什么」是审批之外最常问的问题，光看聊天记录很难拼出来。
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { expandHome, kindOf } from './files.js';

const MAX_DIFF_BYTES = 400 * 1024;
const MAX_FILE_DIFF = 60 * 1024;

function git(cwd, args, { maxBuffer = 8 * 1024 * 1024, timeout = 15_000 } = {}) {
  return new Promise((resolve) => {
    execFile('git', ['-C', cwd, ...args], { maxBuffer, timeout }, (err, stdout, stderr) => {
      resolve({ ok: !err, out: String(stdout ?? ''), err: String(stderr ?? err?.message ?? '') });
    });
  });
}

const STATUS_LABEL = { M: '已修改', A: '新增', D: '删除', R: '重命名', C: '复制', U: '冲突', '?': '未跟踪' };

/** `git status --porcelain=v1 -z` → 每个文件的状态。 */
function parseStatus(out) {
  const entries = [];
  for (const chunk of out.split('\0')) {
    if (!chunk) continue;
    const x = chunk[0], y = chunk[1], file = chunk.slice(3);
    if (!file) continue;
    const untracked = x === '?';
    entries.push({
      path: file,
      staged: !untracked && x !== ' ',
      unstaged: !untracked && y !== ' ',
      untracked,
      status: STATUS_LABEL[untracked ? '?' : (x !== ' ' ? x : y)] ?? '已修改',
    });
  }
  return entries;
}

/** `git diff --numstat -z` → { path: {added, removed} } */
function parseNumstat(out) {
  const map = {};
  const parts = out.split('\0').filter(Boolean);
  for (let i = 0; i < parts.length; i++) {
    const m = parts[i].match(/^(\d+|-)\t(\d+|-)\t(.*)$/);
    if (!m) continue;
    let file = m[3];
    if (file === '') { file = parts[i + 2] ?? parts[++i] ?? ''; i++; }   // 重命名：旧名\0新名
    map[file] = { added: m[1] === '-' ? null : Number(m[1]), removed: m[2] === '-' ? null : Number(m[2]) };
  }
  return map;
}

/** 拆 `git diff` 的输出：按文件分块。 */
function splitDiff(text) {
  const map = {};
  const blocks = text.split(/^diff --git /m).slice(1);
  for (const b of blocks) {
    const m = b.match(/^a\/(.+?) b\/(.+?)$/m);
    const file = m?.[2] ?? m?.[1];
    if (!file) continue;
    const body = ('diff --git ' + b).slice(0, MAX_FILE_DIFF);
    map[file] = body.length >= MAX_FILE_DIFF ? body + '\n…（这个文件的 diff 太长，已截断）' : body;
  }
  return map;
}

/**
 * 会话工作目录的改动。不是 git 仓库时返回 { repo: false }，手机端会给一句说明而不是空白页。
 * @param base 可选：跟某个基线比（例如会话开始时记下的 commit）
 */
export async function workingDiff(cwd, { base = null } = {}) {
  const dir = expandHome(cwd);
  const root = await git(dir, ['rev-parse', '--show-toplevel']);
  if (!root.ok) return { repo: false, reason: '这个目录不在 git 仓库里，看不到改动对比。' };

  const [branchRes, statusRes, numstatRes, cachedNumstatRes, diffRes, cachedDiffRes, headRes] = await Promise.all([
    git(dir, ['rev-parse', '--abbrev-ref', 'HEAD']),
    git(dir, ['status', '--porcelain=v1', '-z']),
    git(dir, base ? ['diff', '--numstat', '-z', base] : ['diff', '--numstat', '-z']),
    base ? Promise.resolve({ ok: true, out: '' }) : git(dir, ['diff', '--numstat', '-z', '--cached']),
    git(dir, base ? ['diff', base] : ['diff']),
    base ? Promise.resolve({ ok: true, out: '' }) : git(dir, ['diff', '--cached']),
    git(dir, ['log', '-1', '--format=%h %s']),
  ]);

  const stats = { ...parseNumstat(numstatRes.out), ...parseNumstat(cachedNumstatRes.out) };
  const diffs = { ...splitDiff(diffRes.out), ...splitDiff(cachedDiffRes.out) };
  const entries = parseStatus(statusRes.out);

  let budget = MAX_DIFF_BYTES;
  const files = entries.map((e) => {
    const st = stats[e.path] ?? { added: null, removed: null };
    let diff = diffs[e.path] ?? null;
    // 新文件 git diff 里没有内容，直接把正文当成全是 + 的改动显示
    if (!diff && e.untracked && budget > 0) {
      const added = newFileDiff(path.join(dir, e.path));
      if (added) { diff = added.diff; st.added = added.lines; st.removed = 0; }
    }
    if (diff && budget <= 0) diff = null;
    if (diff) budget -= diff.length;
    return { ...e, added: st.added, removed: st.removed, diff, binary: st.added === null && st.removed === null && !e.untracked };
  });

  return {
    repo: true,
    root: root.out.trim(),
    branch: branchRes.out.trim() || null,
    head: headRes.out.trim() || null,
    base: base ?? null,
    files,
    totals: {
      files: files.length,
      added: files.reduce((n, f) => n + (f.added ?? 0), 0),
      removed: files.reduce((n, f) => n + (f.removed ?? 0), 0),
    },
    truncated: budget <= 0,
  };
}

/** 未跟踪的新文件：小的文本文件直接展示全文（全是 + 行），大的或二进制的跳过。 */
function newFileDiff(file) {
  try {
    const st = fs.statSync(file);
    if (!st.isFile() || st.size > 64 * 1024) return null;
    if (kindOf(file, false) === 'image') return null;
    const text = fs.readFileSync(file, 'utf8');
    if (text.includes('\u0000')) return null;
    const lines = text.split('\n');
    if (lines.at(-1) === '') lines.pop();
    return { lines: lines.length, diff: `新文件 ${path.basename(file)}\n` + lines.map((l) => `+${l}`).join('\n') };
  } catch { return null; }
}

/** 会话开始时记一个基线 commit，之后就能只看「这次会话改了什么」。 */
export async function headCommit(cwd) {
  const r = await git(expandHome(cwd), ['rev-parse', 'HEAD']);
  return r.ok ? r.out.trim() : null;
}
