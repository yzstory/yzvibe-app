// 会话选项（mode / model / effort）与各 Agent 的能力表。
// 三个选项在两种 Agent 上的语义不同，这里集中映射，Claude / Codex 驱动只负责把结果拼进命令行。
import { execFile } from 'node:child_process';

export const MODES = ['plan', 'normal', 'trust'];

/** Claude Code：--permission-mode / --dangerously-skip-permissions / --effort / --model */
export const CLAUDE = {
  efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
  // 显式版本号，避免别名随 CLI 升级漂移；手机端「模型列表」里可手动改
  models: [
    { id: 'claude-fable-5-1', label: 'Fable 5.1' },
    { id: 'claude-opus-5', label: 'Opus 5' },
    { id: 'claude-sonnet-5', label: 'Sonnet 5' },
    { id: 'claude-haiku-4-5-20251001', label: 'Haiku 4.5' },
  ],
  modes: {
    plan: { flag: '--permission-mode plan', description: '只读分析并给出计划，批准计划后才开始改动' },
    normal: { flag: '--permission-prompt-tool', description: '敏感操作发到手机审批' },
    trust: { flag: '--dangerously-skip-permissions', description: '跳过所有权限检查，不再产生审批' },
  },
};

/** Codex CLI：-c sandbox_mode / --dangerously-bypass-approvals-and-sandbox / -c model_reasoning_effort / -m */
export const CODEX = {
  efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
  models: [
    { id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol' },
    { id: 'gpt-5.6-terra', label: 'GPT-5.6 Terra' },
    { id: 'gpt-5.6-luna', label: 'GPT-5.6 Luna' },
    { id: 'gpt-5.5', label: 'GPT-5.5' },
  ],
  modes: {
    plan: { flag: 'sandbox_mode=read-only', description: '只读沙箱，只分析与规划，不改文件' },
    normal: { flag: 'sandbox_mode=workspace-write', description: '在工作目录沙箱内自动执行；沙箱外的操作会被拒绝，不会发审批' },
    trust: { flag: '--dangerously-bypass-approvals-and-sandbox', description: '无沙箱、无确认，完全信任' },
  },
};

/** 把 POST /sessions 或 PATCH 的 body 归一成 { mode, model, effort }；非法值会被丢弃。yolo:true 等价 mode:'trust'。 */
export function normalizeOptions(body = {}, agent = 'claude') {
  const caps = agent === 'codex' ? CODEX : CLAUDE;
  const out = {};
  if (typeof body.mode === 'string' && MODES.includes(body.mode)) out.mode = body.mode;
  else if (body.yolo === true) out.mode = 'trust';
  if (body.model === null || body.model === '') out.model = null;
  else if (typeof body.model === 'string' && /^[\w.\-:/@]{1,80}$/.test(body.model)) out.model = body.model;
  if (body.effort === null || body.effort === '') out.effort = null;
  else if (typeof body.effort === 'string' && (caps.efforts.includes(body.effort) || body.effort === 'ultra')) out.effort = body.effort;
  return out;
}

/** Claude 启动参数中与会话选项有关的部分。 */
export function claudeOptionArgs({ mode = 'normal', model = null, effort = null } = {}) {
  const args = [];
  if (mode === 'trust') args.push('--dangerously-skip-permissions');
  else {
    args.push('--permission-prompt-tool', 'mcp__yzvibe__approve');
    if (mode === 'plan') args.push('--permission-mode', 'plan');
  }
  if (model) args.push('--model', model);
  if (effort) args.push('--effort', effort);
  return args;
}

/** Codex `exec` / `exec resume` 都接受的选项参数。 */
export function codexOptionArgs({ mode = 'normal', model = null, effort = null } = {}) {
  const args = ['--json', '--skip-git-repo-check'];
  if (mode === 'trust') args.push('--dangerously-bypass-approvals-and-sandbox');
  else args.push('-c', `sandbox_mode="${mode === 'plan' ? 'read-only' : 'workspace-write'}"`, '-c', 'approval_policy="never"');
  if (model) args.push('-m', model);
  if (effort) args.push('-c', `model_reasoning_effort="${effort}"`);
  return args;
}

/** Codex 规划模式没有原生 plan 概念：用只读沙箱 + 提示词约束。 */
export const CODEX_PLAN_PREFIX = '【规划模式】只分析代码并给出分步计划，不要修改任何文件、不要执行有副作用的命令。计划写完后停下，等我确认。\n\n';

// ---------- 能力表（GET /agents） ----------

let codexCatalog = null;   // { at, models }
const CATALOG_TTL = 10 * 60_000;

/** `codex debug models` 的模型目录；失败或超时时退回内置列表。 */
export async function codexModels() {
  if (codexCatalog && Date.now() - codexCatalog.at < CATALOG_TTL) return codexCatalog.models;
  const models = await new Promise((resolve) => {
    execFile('codex', ['debug', 'models'], { timeout: 8000, maxBuffer: 8 * 1024 * 1024 }, (err, stdout) => {
      if (err) return resolve(null);
      try {
        const list = (JSON.parse(stdout).models ?? [])
          .filter((m) => m.visibility !== 'hide' && m.slug)
          .sort((a, b) => (a.priority ?? 99) - (b.priority ?? 99))
          .map((m) => ({ id: m.slug, label: m.display_name ?? m.slug, description: m.description,
                         efforts: (m.supported_reasoning_levels ?? []).map((l) => l.effort), defaultEffort: m.default_reasoning_level,
                         contextWindow: m.context_window ?? null }));
        resolve(list.length ? list : null);
      } catch { resolve(null); }
    });
  });
  codexCatalog = { at: Date.now(), models: models ?? CODEX.models };
  return codexCatalog.models;
}

/** 某个 Codex 模型的上下文窗口；未指定模型时取目录里的第一个（Codex 默认模型）。 */
export async function codexContextWindow(model) {
  const list = await codexModels();
  const m = (model && list.find((x) => x.id === model)) || list[0];
  return m?.contextWindow ?? 272_000;
}

export async function agentCapabilities() {
  return {
    claude: { modes: CLAUDE.modes, efforts: CLAUDE.efforts, models: CLAUDE.models, customModel: true },
    codex: { modes: CODEX.modes, efforts: CODEX.efforts, models: await codexModels(), customModel: true },
  };
}
