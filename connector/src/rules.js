// 审批规则：把「这类操作以后别再问我」变成可持久化、可撤销的规则，存 ~/.yzvibe/rules.json。
// 之前只按「完全相同的命令字符串」记忆，Claude 每次命令都略有差别，等于没生效；这里支持按工具、
// 按命令前缀匹配，并可限定只在某个会话内、只在一段时间内有效。
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

export const MATCHES = ['tool', 'prefix', 'exact'];
export const SCOPES = ['session', 'global'];

const FILE = (home) => path.join(home, 'rules.json');

/** 命令的「前缀」建议：git status --short → `git status`，npm test → `npm test`，./x.sh → `./x.sh` */
export function commandPrefix(summary = '') {
  const words = String(summary).trim().split(/\s+/).filter(Boolean);
  if (!words.length) return '';
  const multi = /^(git|npm|pnpm|yarn|bun|cargo|go|docker|kubectl|brew|pip|python|python3|node|swift|xcodebuild|gh|make)$/;
  return multi.test(words[0]) && words[1] && !words[1].startsWith('-') ? `${words[0]} ${words[1]}` : words[0];
}

/** 审批卡上给用户的「总是允许」选项（手机端直接渲染成按钮）。 */
export function suggestionsFor({ toolName, kind, summary }) {
  const out = [];
  if (kind === 'shell') {
    const prefix = commandPrefix(summary);
    if (prefix) out.push({ label: `总是允许 ${prefix} 开头的命令`, match: 'prefix', value: prefix, scope: 'session', ttlMinutes: null });
  }
  out.push({ label: `本会话 1 小时内不再询问 ${toolName}`, match: 'tool', value: toolName, scope: 'session', ttlMinutes: 60 });
  if (kind === 'write') out.push({ label: '本会话内所有文件改动都放行', match: 'tool', value: toolName, scope: 'session', ttlMinutes: null });
  return out.slice(0, 3);
}

export class Rules {
  constructor(home) {
    this.home = home;
    this.list = [];
    try { const raw = JSON.parse(fs.readFileSync(FILE(home), 'utf8')); if (Array.isArray(raw)) this.list = raw; } catch {}
    this.prune();
  }

  save() { try { fs.mkdirSync(this.home, { recursive: true }); fs.writeFileSync(FILE(this.home), JSON.stringify(this.list, null, 2)); } catch {} }

  /** 丢掉过期规则；返回是否有变化。 */
  prune(now = Date.now()) {
    const before = this.list.length;
    this.list = this.list.filter((r) => !r.expiresAt || new Date(r.expiresAt).getTime() > now);
    if (this.list.length !== before) this.save();
    return this.list.length !== before;
  }

  all(sessionId = null) {
    this.prune();
    return this.list.filter((r) => !sessionId || r.scope === 'global' || r.sessionId === sessionId);
  }

  /** 新增一条规则；同 scope + match + value 已存在就续期而不是重复添加。 */
  add({ sessionId = null, agent = null, tool, match = 'tool', value, scope = 'session', ttlMinutes = null, label = null }) {
    if (!MATCHES.includes(match) || !SCOPES.includes(scope)) throw Object.assign(new Error('规则不合法'), { status: 400 });
    if (match !== 'tool' && !value) throw Object.assign(new Error('规则缺少匹配内容'), { status: 400 });
    if (scope === 'session' && !sessionId) scope = 'global';
    const expiresAt = ttlMinutes ? new Date(Date.now() + ttlMinutes * 60_000).toISOString() : null;
    const same = this.list.find((r) => r.scope === scope && r.sessionId === (scope === 'session' ? sessionId : null) && r.match === match && r.value === (value ?? null) && r.tool === (tool ?? null));
    if (same) { same.expiresAt = expiresAt; this.save(); return same; }
    const rule = {
      id: randomUUID(), scope, sessionId: scope === 'session' ? sessionId : null, agent: agent ?? null,
      tool: tool ?? null, match, value: value ?? null, label, createdAt: new Date().toISOString(), expiresAt, hits: 0, lastHitAt: null,
    };
    this.list.unshift(rule);
    this.save();
    return rule;
  }

  remove(id) {
    const before = this.list.length;
    this.list = this.list.filter((r) => r.id !== id);
    if (this.list.length === before) return false;
    this.save();
    return true;
  }

  /** 清掉某个会话的所有规则（会话关闭时）。 */
  removeForSession(sessionId) {
    const before = this.list.length;
    this.list = this.list.filter((r) => r.sessionId !== sessionId);
    if (this.list.length !== before) this.save();
  }

  /** 命中则返回规则（并计数），否则 null。 */
  match({ sessionId, agent, toolName, summary }) {
    this.prune();
    const hit = this.list.find((r) => {
      if (r.scope === 'session' && r.sessionId !== sessionId) return false;
      if (r.agent && agent && r.agent !== agent) return false;
      if (r.tool && r.tool !== toolName) return false;
      if (r.match === 'tool') return true;
      if (r.match === 'exact') return summary === r.value;
      if (r.match === 'prefix') return typeof summary === 'string' && summary.startsWith(r.value);
      return false;
    });
    if (!hit) return null;
    hit.hits += 1;
    hit.lastHitAt = new Date().toISOString();
    this.save();
    return hit;
  }
}
