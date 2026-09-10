// 会话里可用的斜杠命令与 skill。
// 分两类：`app` 由手机自己处理（新建会话、切模型、打开改动视图…），`agent` 原样当成消息发给 CLI。
// skill / 自定义命令是从磁盘上扫出来的，所以电脑上装了什么，手机上就能看到什么。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { expandHome } from './files.js';

export const CLAUDE_HOME = process.env.CLAUDE_CONFIG_DIR ?? path.join(os.homedir(), '.claude');
export const CODEX_HOME = process.env.CODEX_HOME ?? path.join(os.homedir(), '.codex');

/** 手机端自己执行的命令，两种 Agent 通用。 */
const APP_COMMANDS = [
  { name: 'new', args: '[提示词]', description: '在同一目录新建一个会话', action: 'new-session' },
  { name: 'clear', args: '', description: '清空上下文：等于在同一目录新建会话', action: 'new-session' },
  { name: 'stop', args: '', description: '中断当前这一轮', action: 'stop' },
  { name: 'diff', args: '', description: '看这个目录现在有哪些改动', action: 'diff' },
  { name: 'files', args: '[路径]', description: '浏览远程文件', action: 'files' },
  { name: 'usage', args: '', description: '本轮用量与账号剩余额度', action: 'usage' },
  { name: 'model', args: '<模型>', description: '切换模型', action: 'model' },
  { name: 'effort', args: '<low|medium|high|xhigh|max>', description: '切换思考强度', action: 'effort' },
  { name: 'mode', args: '<plan|normal|trust>', description: '切换权限模式', action: 'mode' },
  { name: 'rules', args: '', description: '看 / 撤销自动放行规则', action: 'rules' },
];

/**
 * 常见内置命令的中文说明。命令清单本身以 Claude 在 `system.init` 里自报的为准
 * （实测 64 个里只有 doctor / color / reload-plugins 是终端专用），这里只补一句人话。
 */
const CLAUDE_BUILTIN_DESC = {
  compact: { description: '压缩上下文：长会话变慢或快到上限时用', args: '[要保留的重点]' },
  autocompact: { description: '开关自动压缩', args: '' },
  context: { description: '看上下文里各部分各占多少', args: '' },
  usage: { description: '账号用量与剩余额度', args: '' },
  'usage-credits': { description: '额外用量额度', args: '' },
  init: { description: '生成 / 更新这个仓库的 CLAUDE.md', args: '' },
  review: { description: '审查当前改动', args: '[目标]' },
  'code-review': { description: '按等级审查当前改动', args: '[low|medium|high|max]' },
  'security-review': { description: '从安全角度审查当前改动', args: '' },
  simplify: { description: '只做简化与复用的清理，不找 bug', args: '' },
  recap: { description: '回顾这次会话做了什么', args: '' },
  insights: { description: '会话洞察', args: '' },
  mcp: { description: '看 MCP 服务器状态', args: '' },
  agents: { description: '看可用的子 Agent', args: '' },
  rename: { description: '给会话改名', args: '<新名字>' },
  import: { description: '导入一段内容到上下文', args: '<路径>' },
};

// ---------- 磁盘扫描 ----------

/** 解析 SKILL.md / 命令文件开头的 YAML frontmatter（只取 name、description、argument-hint）。
 *  描述可能是很长的一整行（见过 10KB 的），所以别按小片段截断后再找结束分隔符。 */
export function parseFrontmatter(text = '') {
  if (!text.startsWith('---')) return {};
  const end = text.search(/\n---[ \t]*(\r?\n|$)/);
  if (end < 0) return {};
  const out = {};
  let key = null;
  for (const raw of text.slice(4, end).split('\n')) {
    const m = raw.match(/^([\w-]+):\s*(.*)$/);
    if (m) {
      key = m[1];
      let v = m[2].trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
      if (v) out[key] = v;
    } else if (key && /^\s+\S/.test(raw) && out[key] !== undefined) {
      out[key] += ' ' + raw.trim();       // 折行的长描述
    }
  }
  return out;
}

const HEAD_BYTES = 64 * 1024;

function readSkill(dir, { source, prefix = '' }) {
  const file = path.join(dir, 'SKILL.md');
  let text; try { text = fs.readFileSync(file, 'utf8').slice(0, HEAD_BYTES); } catch { return null; }
  const fm = parseFrontmatter(text);
  const name = fm.name || path.basename(dir);
  return {
    name: prefix ? `${prefix}:${name}` : name,
    description: (fm.description ?? '').slice(0, 400),
    args: fm['argument-hint'] ?? '',
    kind: 'skill', source, file,
  };
}

/** 注意用 statSync 而不是 dirent.isDirectory()：个人 skill 常常是指向别处的符号链接。 */
function skillsIn(root, opts) {
  let names; try { names = fs.readdirSync(root); } catch { return []; }
  return names
    .filter((n) => !n.startsWith('.'))
    .filter((n) => { try { return fs.statSync(path.join(root, n)).isDirectory(); } catch { return false; } })
    .map((n) => readSkill(path.join(root, n), opts))
    .filter(Boolean);
}

/** 插件带来的 skill：从 installed_plugins.json 里的 installPath 找。 */
function pluginSkills(home) {
  let manifest;
  try { manifest = JSON.parse(fs.readFileSync(path.join(home, 'plugins', 'installed_plugins.json'), 'utf8')); } catch { return []; }
  const out = [];
  for (const [key, entries] of Object.entries(manifest.plugins ?? {})) {
    const pluginName = key.split('@')[0];
    for (const e of entries ?? []) {
      if (!e.installPath) continue;
      for (const sub of ['skills', path.join('.claude', 'skills')]) {
        out.push(...skillsIn(path.join(e.installPath, sub), { source: `插件 ${pluginName}`, prefix: pluginName }));
      }
    }
  }
  return out;
}

/** `~/.claude/commands/*.md` 与项目里的 `.claude/commands/*.md`。 */
function markdownCommands(dir, source) {
  let names; try { names = fs.readdirSync(dir); } catch { return []; }
  return names.filter((n) => n.endsWith('.md')).map((n) => {
    let text = ''; try { text = fs.readFileSync(path.join(dir, n), 'utf8').slice(0, HEAD_BYTES); } catch {}
    const fm = parseFrontmatter(text);
    const body = text.replace(/^---[\s\S]*?\n---\n/, '').trim();
    return {
      name: n.replace(/\.md$/, ''),
      description: (fm.description ?? body.split('\n')[0] ?? '').replace(/^#+\s*/, '').slice(0, 200),
      args: fm['argument-hint'] ?? '',
      kind: 'command', source,
    };
  });
}

function dedupe(list) {
  const seen = new Set();
  return list.filter((x) => x?.name && !seen.has(x.name) && seen.add(x.name));
}

/**
 * 某个会话里能用的命令与 skill。
 * @param agent 'claude' | 'codex' | 其它
 * @param cwd   会话工作目录（用来找项目级的 skill / 命令）
 * @param session 会话对象；有 Claude 自报的清单时优先用它
 */
export function sessionCommands(agent = 'claude', cwd = os.homedir(), { claudeHome = CLAUDE_HOME, codexHome = CODEX_HOME, session = null } = {}) {
  const dir = expandHome(cwd);
  const app = APP_COMMANDS.map((c) => ({ ...c, kind: 'app', source: 'YzVibe' }));

  if (agent === 'codex') {
    // Codex 的 skill 在 ~/.codex/skills/<name>/SKILL.md（和 Claude 同一种格式）。
    // codex exec 不解析斜杠命令，所以这些只能当提示词插进消息里，标出来别让人误会。
    const skills = dedupe(skillsIn(path.join(codexHome, 'skills'), { source: 'Codex skill' }))
      .map((s) => ({ ...s, insertAsText: true }));
    return { agent, app, agentCommands: [], skills, prompts: [], note: 'Codex 的非交互模式不认斜杠命令，选中的 skill 会以说明文字的形式插进消息里。' };
  }

  const onDisk = dedupe([
    ...skillsIn(path.join(dir, '.claude', 'skills'), { source: '项目 skill' }),
    ...skillsIn(path.join(claudeHome, 'skills'), { source: '个人 skill' }),
    ...pluginSkills(claudeHome),
  ]);
  const byName = new Map(onDisk.map((s) => [s.name, s]));
  const custom = dedupe([
    ...markdownCommands(path.join(dir, '.claude', 'commands'), '项目命令'),
    ...markdownCommands(path.join(claudeHome, 'commands'), '个人命令'),
  ]);
  for (const c of custom) if (!byName.has(c.name)) byName.set(c.name, c);

  // Claude 自报的清单优先；还没跑过一轮（拿不到 init 事件）时退回扫盘结果
  const reported = session?.slashCommands ?? null;
  const terminalOnly = new Set(session?.terminalOnly ?? []);
  const skillNames = new Set(session?.agentSkills ?? onDisk.map((s) => s.name));

  const names = reported ? reported.filter((n) => !terminalOnly.has(n)) : [...byName.keys(), ...Object.keys(CLAUDE_BUILTIN_DESC)];
  const entries = dedupe(names.map((name) => {
    const hit = byName.get(name);
    const builtin = CLAUDE_BUILTIN_DESC[name];
    return {
      name,
      description: hit?.description || builtin?.description || '',
      args: hit?.args || builtin?.args || '',
      kind: skillNames.has(name) || hit?.kind === 'skill' ? 'skill' : 'agent',
      source: hit?.source || (builtin ? 'Claude Code 内置' : (skillNames.has(name) ? 'skill' : 'Claude Code')),
    };
  }));

  return {
    agent,
    app,
    agentCommands: entries.filter((e) => e.kind === 'agent'),
    skills: entries.filter((e) => e.kind === 'skill'),
    prompts: [],
    reported: Boolean(reported),
  };
}
