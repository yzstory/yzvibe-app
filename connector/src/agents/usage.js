// 每轮 token 用量的统一结构（Session.usage）。两种 Agent 的原始字段不同，这里归一：
//   turn  = 本轮：input / cacheWrite / cacheRead / output / thinking / contextTokens / contextWindow / costUSD / durationMs
//   total = 会话累计（连接器自己累加，不依赖 Agent 进程的累计值，重启进程也不会清零）
// 「上下文」口径与 Claude Code 一致：input + cacheWrite + cacheRead，即最后一次 API 调用送进模型的全部输入。

const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);

/** Claude：`result` 事件 + 最后一条 assistant 消息的 usage（用于上下文大小）+ init 里的模型名。 */
export function claudeTurnUsage(result, lastMessageUsage, model) {
  const u = result?.usage ?? {};
  const mu = result?.modelUsage ?? {};
  const modelId = Object.keys(mu).sort((a, b) => num(mu[b].inputTokens + mu[b].cacheReadInputTokens) - num(mu[a].inputTokens + mu[a].cacheReadInputTokens))[0] ?? model ?? null;
  const ctx = lastMessageUsage ? num(lastMessageUsage.input_tokens) + num(lastMessageUsage.cache_creation_input_tokens) + num(lastMessageUsage.cache_read_input_tokens) : null;
  return {
    model: modelId,
    input: num(u.input_tokens), cacheWrite: num(u.cache_creation_input_tokens), cacheRead: num(u.cache_read_input_tokens), output: num(u.output_tokens),
    thinking: num(u.output_tokens_details?.thinking_tokens),
    contextTokens: ctx, contextWindow: modelId && mu[modelId]?.contextWindow ? num(mu[modelId].contextWindow) : null,
    costUSD: result?.total_cost_usd != null ? Number(result.total_cost_usd) : null,
    durationMs: result?.duration_ms != null ? num(result.duration_ms) : null,
  };
}

/** Codex：`turn.completed.usage`；input_tokens 已含 cached_input_tokens。 */
export function codexTurnUsage(usage = {}, model, contextWindow) {
  const input = num(usage.input_tokens), cached = num(usage.cached_input_tokens);
  return {
    model: model ?? null,
    input: Math.max(0, input - cached), cacheWrite: 0, cacheRead: cached, output: num(usage.output_tokens),
    thinking: num(usage.reasoning_output_tokens),
    // exec 的 usage 是整轮累计，不能用来表示最后一次调用的上下文。
    contextTokens: null, contextWindow: null,
    costUSD: null, durationMs: null,
  };
}

/** 把本轮合并进会话累计。 */
export function accumulateUsage(prev, turn) {
  const t = prev?.total ?? { input: 0, cacheWrite: 0, cacheRead: 0, output: 0, thinking: 0, costUSD: 0, turns: 0 };
  return {
    model: turn.model ?? prev?.model ?? null,
    turn,
    total: {
      input: t.input + turn.input, cacheWrite: t.cacheWrite + turn.cacheWrite, cacheRead: t.cacheRead + turn.cacheRead,
      output: t.output + turn.output, thinking: (t.thinking ?? 0) + (turn.thinking ?? 0),
      costUSD: turn.costUSD != null ? (t.costUSD ?? 0) + turn.costUSD : (t.costUSD ?? null),
      turns: t.turns + 1,
    },
    updatedAt: new Date().toISOString(),
  };
}
