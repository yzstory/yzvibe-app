// 账号额度（剩余用量）。Claude：优先调 Claude Code 自己用的 api/oauth/usage（本机钥匙串里的 OAuth token），
// 拿不到时退回最近一次流式输出里的 rate_limit_event。Codex 非交互模式暂无额度接口。
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
const CACHE_TTL = 60_000;

let cache = null;            // { at, quota }
let lastRateLimit = null;    // 最近一次 rate_limit_event 的 rate_limit_info

/** 流式输出里的 rate_limit_event → 记住，作为 OAuth 接口失败时的兜底。 */
export function rememberRateLimit(info) { if (info && typeof info === 'object') lastRateLimit = { ...info, at: Date.now() }; }

/** 读 Claude Code 的 OAuth access token：macOS 钥匙串，其次 ~/.claude/.credentials.json。 */
export async function claudeOAuthToken() {
  const parse = (raw) => { try { return JSON.parse(raw)?.claudeAiOauth?.accessToken ?? null; } catch { return null; } };
  if (process.platform === 'darwin') {
    const fromKeychain = await new Promise((resolve) => {
      execFile('security', ['find-generic-password', '-s', 'Claude Code-credentials', '-w'], { timeout: 5000 }, (err, out) => resolve(err ? null : parse(String(out).trim())));
    });
    if (fromKeychain) return fromKeychain;
  }
  try { return parse(fs.readFileSync(path.join(process.env.CLAUDE_CONFIG_DIR ?? path.join(os.homedir(), '.claude'), '.credentials.json'), 'utf8')); } catch { return null; }
}

const WINDOW_LABELS = {
  five_hour: '当前会话（5 小时）',
  seven_day: '本周（所有模型）',
  seven_day_overage_included: '本周（Fable）',
  seven_day_opus: '本周（Opus）',
  seven_day_sonnet: '本周（Sonnet）',
};

/** api/oauth/usage 的返回 → 统一结构。 */
export function normalizeOAuthUsage(json = {}) {
  const limits = [];
  const seen = new Set();
  const push = (id, label, percent, resetsAt) => {
    if (percent == null || seen.has(id)) return;
    seen.add(id);
    limits.push({ id, label, percent: Math.round(Number(percent)), resetsAt: resetsAt ? new Date(resetsAt).toISOString() : null });
  };
  for (const l of json.limits ?? []) {
    if (l.kind === 'session') push('session', WINDOW_LABELS.five_hour, l.percent, l.resets_at);
    else if (l.kind === 'weekly_all') push('weekly_all', WINDOW_LABELS.seven_day, l.percent, l.resets_at);
    else if (l.kind === 'weekly_scoped') {
      const name = l.scope?.model?.display_name ?? l.scope?.surface ?? '限定';
      push(`weekly_${String(name).toLowerCase()}`, `本周（${name}）`, l.percent, l.resets_at);
    }
  }
  // 老字段兜底（limits 数组缺席时）
  if (json.five_hour) push('session', WINDOW_LABELS.five_hour, json.five_hour.utilization, json.five_hour.resets_at);
  if (json.seven_day) push('weekly_all', WINDOW_LABELS.seven_day, json.seven_day.utilization, json.seven_day.resets_at);
  if (json.seven_day_opus) push('weekly_opus', WINDOW_LABELS.seven_day_opus, json.seven_day_opus.utilization, json.seven_day_opus.resets_at);
  if (json.seven_day_sonnet) push('weekly_sonnet', WINDOW_LABELS.seven_day_sonnet, json.seven_day_sonnet.utilization, json.seven_day_sonnet.resets_at);
  const eu = json.extra_usage;
  const extra = eu ? { enabled: Boolean(eu.is_enabled), usedCredits: Number(eu.used_credits ?? 0), monthlyLimit: eu.monthly_limit ?? null, percent: Math.round(Number(eu.utilization ?? 0)), currency: eu.currency ?? 'USD' } : null;
  return { agent: 'claude', source: 'oauth', fetchedAt: new Date().toISOString(), limits, extraUsage: extra };
}

/** rate_limit_event.rate_limit_info → 统一结构（utilization 是 0–1）。 */
export function quotaFromRateLimit(info) {
  if (!info?.unifiedWindows) return null;
  const limits = Object.entries(info.unifiedWindows).map(([k, w]) => ({
    id: k === 'five_hour' ? 'session' : k === 'seven_day' ? 'weekly_all' : k === 'seven_day_overage_included' ? 'weekly_fable' : `weekly_${k.replace(/^seven_day_/, '')}`,
    label: WINDOW_LABELS[k] ?? k,
    percent: Math.round(Number(w.utilization ?? 0) * 100),
    resetsAt: w.resetsAt ? new Date(Number(w.resetsAt) * 1000).toISOString() : null,
  }));
  return { agent: 'claude', source: 'rate_limit_event', fetchedAt: new Date(info.at ?? Date.now()).toISOString(), limits, extraUsage: null };
}

/** GET /quota?agent=claude|codex 的实现。失败时返回 { error } 而不是抛，方便手机端展示。 */
export async function agentQuota(agent = 'claude', { fetchImpl = fetch, force = false } = {}) {
  if (agent === 'codex') return { agent: 'codex', source: 'none', fetchedAt: new Date().toISOString(), limits: [], extraUsage: null, unavailable: 'Codex 非交互模式暂无额度接口；请在终端里运行 codex 查看 /status' };
  if (!force && cache && Date.now() - cache.at < CACHE_TTL) return cache.quota;
  let quota;
  try {
    const token = await claudeOAuthToken();
    if (!token) throw new Error('本机未找到 Claude Code 登录凭证，请先在终端运行 claude 登录');
    const res = await fetchImpl(USAGE_URL, { headers: { authorization: `Bearer ${token}`, 'anthropic-beta': 'oauth-2025-04-20', 'content-type': 'application/json' }, signal: AbortSignal.timeout(10_000) });
    if (!res.ok) throw new Error(`额度服务返回 HTTP ${res.status}`);
    quota = normalizeOAuthUsage(await res.json());
  } catch (e) {
    const fallback = quotaFromRateLimit(lastRateLimit);
    quota = fallback ? { ...fallback, warning: e.message } : { agent: 'claude', source: 'none', fetchedAt: new Date().toISOString(), limits: [], extraUsage: null, error: e.message };
  }
  cache = { at: Date.now(), quota };
  return quota;
}

/** 测试用：清缓存。 */
export function resetQuotaCache() { cache = null; lastRateLimit = null; }
