// Only project OMP's public progress fields; never forward raw subagent events/config.
const clip = (value, limit = 2000) => typeof value === 'string' ? value.slice(0, limit) : '';
const number = value => Number.isFinite(value) ? Math.max(0, value) : 0;
export const ompThinking = content => (Array.isArray(content) ? content : [])
  .filter(x => x.type === 'thinking').map(x => clip(x.thinking, 32_000)).join('\n').slice(0, 32_000);

export function ompSubagent(payload, previous = {}, now = Date.now()) {
  const p = payload.progress ?? payload;
  const id = p.id ?? payload.id;
  if (typeof id !== 'string' || !id) return null;
  const raw = p.status ?? payload.status;
  const status = raw === 'started' ? 'running' : ['pending', 'running', 'completed', 'failed', 'aborted'].includes(raw) ? raw
    : p.aborted ? 'aborted' : p.exitCode != null ? p.exitCode === 0 ? 'completed' : 'failed' : previous.status ?? 'running';
  const durationMs = p.durationMs == null ? number(previous.durationMs) + (['running', 'pending'].includes(previous.status)
    ? Math.max(0, now - Date.parse(previous.updatedAt)) || 0 : 0) : number(p.durationMs);
  return {
    id, name: clip(id, 100), agent: clip(payload.agent ?? p.agent ?? previous.agent, 100), status,
    task: clip(payload.task ?? p.task ?? payload.description ?? p.description ?? previous.task),
    detail: clip(p.retryState ? `等待重试 ${p.retryState.attempt}/${p.retryState.maxAttempts}：${p.retryState.errorMessage}`
      : p.retryFailure?.errorMessage ?? p.error ?? p.currentTool ?? p.lastIntent ?? previous.detail),
    toolCount: number(p.toolCount ?? previous.toolCount), durationMs, updatedAt: new Date(now).toISOString(),
  };
}

export function ompSubagentsFromDetails(details, previous = [], now = Date.now()) {
  const agents = new Map(previous.map(p => [p.id, p]));
  for (const p of [...(Array.isArray(details?.progress) ? details.progress : []), ...(Array.isArray(details?.results) ? details.results : [])]) {
    const value = ompSubagent(p, agents.get(p.id), now);
    if (value) agents.set(value.id, value);
  }
  return [...agents.values()];
}
