// 会话工作目录的改动概览：把 git 的输出整理成手机上能看的结构。
// 「Agent 到底改了什么」是审批之外最常问的问题，光看聊天记录很难拼出来。
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { expandHome, kindOf, resolveInside, assertNotSensitive } from './files.js';

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

/** 一次读取一个文件的 diff，避免从带引号/换行/重命名的 diff 头猜文件名。 */
async function fileDiff(dir, args, file) {
  const [patch, stat] = await Promise.all([
    git(dir, ['diff', '--no-ext-diff', '--no-textconv', '--no-renames', ...args, '--', file]),
    git(dir, ['diff', '--no-ext-diff', '--no-textconv', '--no-renames', '--numstat', '-z', ...args, '--', file]),
  ]);
  if (!patch.ok || !stat.ok) throw Object.assign(new Error('无法读取完整 Git diff'), { status: 422 });
  const stats = parseNumstat(stat.out)[file] ?? { added: 0, removed: 0 };
  return { ...stats, diff: patch.out || null };
}

/** 工作区分开展示暂存与未暂存；会话范围按基线差异建立文件列表。 */
export async function workingDiff(cwd, { base = null } = {}) {
  const root = await git(expandHome(cwd), ['rev-parse', '--show-toplevel']);
  if (!root.ok) return { repo: false, reason: '这个目录不在 git 仓库里，看不到改动对比。' };
  const dir = root.out.trim();
  const [branch, status, head, baseline] = await Promise.all([
    git(dir, ['rev-parse', '--abbrev-ref', 'HEAD']),
    git(dir, ['status', '--porcelain=v1', '-z', '--untracked-files=all', '--no-renames']),
    git(dir, ['log', '-1', '--format=%h %s']),
    base ? git(dir, ['diff', '--no-ext-diff', '--no-textconv', '--name-status', '-z', '--no-renames', base, '--']) : Promise.resolve(null),
  ]);
  if (!status.ok || (baseline && !baseline.ok)) throw Object.assign(new Error('Git 状态或会话基线不可用'), { status: 422 });
  let entries = parseStatus(status.out);
  if (baseline) {
    const current = new Map(entries.map((e) => [e.path, e]));
    const parts = baseline.out.split('\0');
    entries = [];
    for (let i = 0; i + 1 < parts.length; i += 2) {
      const file = parts[i + 1];
      entries.push({ path: file, staged: false, unstaged: false, untracked: false, ...current.get(file), status: STATUS_LABEL[parts[i][0]] ?? '已修改' });
    }
    entries.push(...[...current.values()].filter((e) => e.untracked));
  }
  const visible = entries.filter((e) => {
    try { assertNotSensitive(path.join(dir, e.path)); resolveInside(dir, e.path); return true; } catch { return false; }
  });
  let budget = MAX_DIFF_BYTES, truncated = visible.length > 200;
  const files = [];
  for (const e of visible.slice(0, 200)) {
    let added = 0, removed = 0, diff = null;
    if (budget <= 0) { truncated = true; files.push({ ...e, added: null, removed: null, diff: null, binary: false }); continue; }
    if (e.untracked) {
      const fresh = newFileDiff(resolveInside(dir, e.path).target);
      if (fresh) { diff = fresh.diff; added = fresh.lines; }
    } else {
      const sections = base ? [await fileDiff(dir, [base], e.path)] : await Promise.all([
        fileDiff(dir, ['--cached'], e.path), fileDiff(dir, [], e.path),
      ]);
      const labels = base ? ['基线以来'] : ['已暂存', '未暂存'];
      diff = sections.map((s, i) => s.diff ? `--- ${labels[i]} ---\n${s.diff}` : '').filter(Boolean).join('\n') || null;
      added = sections.some((s) => s.added === null) ? null : sections.reduce((n, s) => n + s.added, 0);
      removed = sections.some((s) => s.removed === null) ? null : sections.reduce((n, s) => n + s.removed, 0);
    }
    const limit = Math.min(MAX_FILE_DIFF, budget);
    if (diff && diff.length > limit) { diff = diff.slice(0, limit) + '\n…（diff 已截断）'; truncated = true; }
    if (diff) budget -= diff.length;
    files.push({ ...e, added, removed, diff, binary: added === null && removed === null && !e.untracked });
  }
  return { repo: true, root: dir, branch: branch.out.trim() || null, head: head.out.trim() || null, base,
    files, totals: { files: files.length, added: files.reduce((n, f) => n + (f.added ?? 0), 0), removed: files.reduce((n, f) => n + (f.removed ?? 0), 0) }, truncated };
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
