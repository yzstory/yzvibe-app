#!/usr/bin/env node
// YzVibe 桌面连接器 CLI
//   npx yzvibe                     默认：Cloudflare Tunnel（找不到 cloudflared 时退回局域网）
//   npx yzvibe --access=local      只在局域网配对
//   npx yzvibe --access=https://x  使用自己的 relay（cloudflared / ngrok）
//   npx yzvibe --access=100.64.1.2 使用 Tailscale 等指定 IP
//   npx yzvibe --agent=codex       新会话默认用 Codex CLI（手机端新建会话时也可单独选）
//   npx yzvibe --agent=mock        不调用 Claude，用内置假 Agent 演示完整流程
//   npx yzvibe --port=19876 --name="我的 Mac"   （默认 19876；被占用时自动后移）
import { startConnector, DEFAULT_PORT } from '../src/server.js';

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] ?? true] : [a, true];
  }),
);

if (args.help || args.h) {
  console.log(`用法: yzvibe [--access=remote|local|<url>|<ip>] [--port=${DEFAULT_PORT}] [--name=<设备名>] [--agent=claude|codex|mock] [--force]`);
  process.exit(0);
}

startConnector({
  access: args.access ?? 'remote',
  port: Number(args.port ?? process.env.YZVIBE_PORT ?? DEFAULT_PORT),
  name: args.name,
  defaultAgent: args.agent ?? 'claude',
  force: Boolean(args.force),
}).catch((e) => {
  console.error('[yzvibe] 启动失败:', e.message);
  process.exit(1);
});
