// Isolated Android smoke-test backend. Never opens a real coding agent or user transcript.
import { createConnector } from '../../connector/src/server.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-android-smoke-'));
const c = await createConnector({ port: 29876, home, defaultAgent: 'mock', name: 'Android 测试电脑', importTerminal: false, portFallback: false, log: () => {} });
await c.listen();
const a = c.store.createSession({ agent: 'codex', cwd: home, title: 'Android 联调会话' });
const b = c.store.createSession({ agent: 'omp', cwd: home, title: '草稿保留测试' });
const document = path.join(home, 'preview.md');
fs.writeFileSync(document, '# Android 文件预览\n\n这是 **渲染后的 Markdown**。\n\n| 平台 | 状态 |\n| --- | --- |\n| Android | 就绪 |\n');
c.store.addMessage(a.id, { role: 'assistant', text: `欢迎使用 **柚子Vibe**。长按正文可选字复制。\n\n| 功能 | 状态 |\n| --- | --- |\n| 会话同步 | 已连接 |\n| 语音 | 设备识别 |\n\n[查看 Markdown](${document})` });
fs.writeFileSync('/tmp/yz-android-smoke-pair.txt', `yzvibe://pair?host=127.0.0.1&port=29876&token=${c.pairing.token}&mode=local`, { mode: 0o600 });
console.log('Android fixture listening on 29876; pairing link written to /tmp/yz-android-smoke-pair.txt');
const close = async () => { await c.close(); fs.rmSync(home, { recursive: true, force: true }); process.exit(); };
setInterval(() => {}, 60000);
process.on('SIGTERM', close); process.on('SIGINT', close);
