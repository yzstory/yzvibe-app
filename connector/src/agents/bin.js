// Agent CLI 的可执行文件解析。
//
// 连接器常以 `npx yzvibe` 启动，而 npx / npm run 会把各级 node_modules/.bin 塞到 PATH 最前面
// （包括家目录下的 ~/node_modules/.bin）。家里只要躺着一份过期的 @anthropic-ai/claude-code，
// 它就会遮蔽掉用户真正在用的 claude，表现为进程秒退 + `unknown option '--effort'` 这类
// “新参数不认识” 的错。所以查找时先把这些注入段剔掉，再按 PATH 取绝对路径。
import fs from 'node:fs';
import path from 'node:path';

/** 显式覆盖：YZVIBE_CLAUDE_BIN / YZVIBE_CODEX_BIN。 */
const overrideVar = (name) => `YZVIBE_${name.toUpperCase().replace(/[^A-Z0-9]+/g, '_')}_BIN`;

const NODE_MODULES_BIN = /(^|[\\/])node_modules[\\/]\.bin[\\/]?$/;

const cache = new Map();   // name → 绝对路径

function isExecutableFile(p) {
  try {
    if (!fs.statSync(p).isFile()) return false;
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch { return false; }
}

/** PATH 去掉 npm/npx 注入的 node_modules/.bin 段；全被过滤掉时退回原样，避免把 PATH 清空。 */
export function sanitizePath(pathValue = process.env.PATH ?? '') {
  const entries = pathValue.split(path.delimiter).filter(Boolean);
  const kept = entries.filter((p) => !NODE_MODULES_BIN.test(p));
  return (kept.length ? kept : entries).join(path.delimiter);
}

/** 子进程环境：沿用当前环境，但 PATH 换成剔除注入段后的版本（Agent 自己再起子进程时也不会被遮蔽）。 */
export function agentEnv(extra = {}) {
  return { ...process.env, PATH: sanitizePath(), ...extra };
}

/**
 * Agent CLI 的绝对路径。找不到就原样返回命令名，交给 spawn 抛 ENOENT，
 * 由调用方的 'error' 回调提示 “无法启动 xxx”。
 */
export function resolveAgentBin(name) {
  const override = process.env[overrideVar(name)]?.trim();
  if (override) return override;

  const cached = cache.get(name);
  if (cached && isExecutableFile(cached)) return cached;
  cache.delete(name);

  for (const dir of sanitizePath().split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.join(dir, name);
    if (isExecutableFile(candidate)) { cache.set(name, candidate); return candidate; }
  }
  return name;
}

/** 测试用：清掉解析缓存。 */
export function clearAgentBinCache() { cache.clear(); }
