import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { sanitizePath, agentEnv, resolveAgentBin, clearAgentBinCache } from '../src/agents/bin.js';

/** 造一个假的可执行文件。 */
function fakeBin(dir, name, body = '#!/bin/sh\nexit 0\n') {
  fs.mkdirSync(dir, { recursive: true });
  const p = path.join(dir, name);
  fs.writeFileSync(p, body, { mode: 0o755 });
  return p;
}

function withEnv(patch, fn) {
  const saved = { ...process.env };
  Object.assign(process.env, patch);
  for (const [k, v] of Object.entries(patch)) if (v === undefined) delete process.env[k];
  clearAgentBinCache();
  try { return fn(); } finally {
    for (const k of Object.keys(process.env)) if (!(k in saved)) delete process.env[k];
    Object.assign(process.env, saved);
    clearAgentBinCache();
  }
}

test('sanitizePath 剔除 npm/npx 注入的 node_modules/.bin，保留其它段', () => {
  const p = ['/home/u/node_modules/.bin', '/a/b/node_modules/.bin/', '/usr/local/bin', '/usr/bin'].join(path.delimiter);
  assert.equal(sanitizePath(p), ['/usr/local/bin', '/usr/bin'].join(path.delimiter));
  // 名字里带 node_modules 但不是 .bin 目录的，不能误删
  assert.equal(sanitizePath('/opt/node_modules_tools'), '/opt/node_modules_tools');
  // 全被过滤时退回原样，避免把 PATH 清空
  assert.equal(sanitizePath('/home/u/node_modules/.bin'), '/home/u/node_modules/.bin');
});

test('resolveAgentBin 跳过被 node_modules/.bin 遮蔽的旧 CLI', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-bin-'));
  const stale = path.join(home, 'node_modules/.bin');
  const real = path.join(home, '.local/bin');
  fakeBin(stale, 'claude');
  const realPath = fakeBin(real, 'claude');

  withEnv({ PATH: [stale, real].join(path.delimiter), YZVIBE_CLAUDE_BIN: undefined }, () => {
    assert.equal(resolveAgentBin('claude'), realPath);
    assert.equal(agentEnv().PATH, real);
  });
  fs.rmSync(home, { recursive: true, force: true });
});

test('resolveAgentBin 优先用 YZVIBE_<NAME>_BIN，找不到时退回命令名', () => {
  withEnv({ YZVIBE_CLAUDE_BIN: '/opt/custom/claude' }, () => {
    assert.equal(resolveAgentBin('claude'), '/opt/custom/claude');
  });
  withEnv({ PATH: '/nonexistent-yzvibe-dir', YZVIBE_CLAUDE_BIN: undefined }, () => {
    assert.equal(resolveAgentBin('claude'), 'claude');
  });
});

test('agentEnv 继承环境但换掉 PATH，且可叠加覆盖项', () => {
  withEnv({ PATH: ['/x/node_modules/.bin', '/usr/bin'].join(path.delimiter) }, () => {
    const env = agentEnv({ CLAUDECODE: undefined });
    assert.equal(env.PATH, '/usr/bin');
    assert.equal(env.CLAUDECODE, undefined);
    assert.equal(env.HOME, process.env.HOME);
  });
});
