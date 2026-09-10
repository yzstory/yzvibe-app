#!/usr/bin/env node
// YzVibe 桌面连接器 CLI（默认在后台运行，终端可以关掉）
//   yzvibe [start] [flags]    后台启动并打印配对二维码（已在运行则直接出示二维码）
//   yzvibe run [flags]        前台运行（Ctrl+C 退出；调试或 launchd 用）
//   yzvibe stop / restart     停止 / 用上次的参数重启
//   yzvibe status             运行状态、地址、会话数
//   yzvibe qr [--json|--link] 再次出示配对方式：二维码 / 外链 / 可粘贴的 JSON 配置
//   yzvibe logs [-f]          看日志（~/.yzvibe/yzvibe.log），-f 持续跟随
//   yzvibe install [flags]    注册为开机自启服务（macOS launchd / Linux systemd --user）
//   yzvibe uninstall          取消开机自启
// flags：
//   --access=remote|local|<url>|<ip>   remote=Cloudflare Tunnel（默认，找不到 cloudflared 退回局域网）
//   --agent=claude|codex|mock          新会话默认 Agent；mock 不调用 Claude，用假 Agent 演示
//   --port=19876 --name="我的 Mac"      端口被占用时自动后移
//   --force                            不复用已保存的 relay 地址
import { startConnector, DEFAULT_PORT } from '../src/server.js';
import { readDaemonInfo, startDaemon, stopDaemon, printStatus, printPairing, tailLog, installService, uninstallService, serviceInstalled, LOG_FILE } from '../src/daemon.js';

const COMMANDS = new Set(['start', 'run', 'stop', 'restart', 'status', 'qr', 'logs', 'install', 'uninstall', 'help']);
const argv = process.argv.slice(2);
const command = COMMANDS.has(argv[0]) ? argv[0] : 'start';
const flags = COMMANDS.has(argv[0]) ? argv.slice(1) : argv;
const args = {};
for (let i = 0; i < flags.length; i++) {
  const m = flags[i].match(/^--?([^=]+)(?:=(.*))?$/);
  if (!m) { args[flags[i]] = true; continue; }
  // `-n 20` / `--lines 20` 这种空格分隔的值
  if (m[2] === undefined && /^\d+$/.test(flags[i + 1] ?? '')) args[m[1]] = flags[++i];
  else args[m[1]] = m[2] ?? true;
}

if (command === 'help' || args.help || args.h) {
  console.log(`用法: yzvibe [start|run|stop|restart|status|qr|logs|install|uninstall] [--access=remote|local|<url>|<ip>] [--port=${DEFAULT_PORT}] [--name=<设备名>] [--agent=claude|codex|mock] [--force]
  start      后台启动并打印配对二维码（默认命令；已在运行则直接出示二维码）
  run        前台运行，Ctrl+C 退出
  stop       停止后台连接器
  restart    用上次的参数重启（也可附带新参数）
  status     运行状态、地址、会话数
  qr         再次出示配对方式：二维码 + 外链 + JSON 配置（--json / --link 只输出一项）
  logs [-f]  查看日志（-f 持续跟随）
  install    注册开机自启（macOS launchd / Linux systemd --user）
  uninstall  取消开机自启`);
  process.exit(0);
}

const connectorOpts = () => ({
  access: args.access ?? 'remote',
  port: Number(args.port ?? process.env.YZVIBE_PORT ?? DEFAULT_PORT),
  name: args.name,
  defaultAgent: args.agent ?? 'claude',
  force: Boolean(args.force),
  flags,
});

/** 后台模式下每行日志带时间戳，方便在 yzvibe logs 里对照。 */
function timestampConsole() {
  const pad = (n) => String(n).padStart(2, '0');
  const stamp = () => { const d = new Date(); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; };
  for (const k of ['log', 'error', 'warn']) {
    const orig = console[k].bind(console);
    console[k] = (first, ...rest) => orig(stamp(), ...(typeof first === 'string' ? [first.replace(/^\n+/, '')] : [first]), ...rest);
  }
}

async function main() {
  switch (command) {
    case 'run':
      if (process.env.YZVIBE_DAEMON) timestampConsole();
      await startConnector(connectorOpts());
      return;
    case 'start': {
      const { info, alreadyRunning } = await startDaemon(flags);
      if (alreadyRunning) console.log(`[yzvibe] 连接器已在后台运行（PID ${info.pid}${flags.length ? '，本次参数未生效，改参数请用 yzvibe restart ' + flags.join(' ') : ''}）。\n`);
      else console.log(`[yzvibe] 连接器已在后台启动（PID ${info.pid}，${info.mode} ${info.host}${String(info.host).includes('://') ? '' : ':' + info.port}）。关掉终端也会继续运行；yzvibe stop 停止，yzvibe logs -f 看日志。\n`);
      await printPairing(info);
      return;
    }
    case 'stop': {
      const info = await stopDaemon();
      console.log(info ? `[yzvibe] 已停止（PID ${info.pid}）。${info.managed ? ' 已注册开机自启，重新登录后仍会启动；彻底关闭请 yzvibe uninstall。' : ''}` : '[yzvibe] 连接器没有在运行。');
      return;
    }
    case 'restart': {
      const prev = await stopDaemon();
      const useFlags = flags.length ? flags : prev?.flags ?? [];
      if (prev) console.log(`[yzvibe] 已停止旧实例（PID ${prev.pid}），用参数 [${useFlags.join(' ') || '默认'}] 重启…`);
      const { info } = await startDaemon(useFlags);
      console.log(`[yzvibe] 连接器已在后台启动（PID ${info.pid}，${info.mode} ${info.host}）。\n`);
      await printPairing(info);
      return;
    }
    case 'status':
      await printStatus(readDaemonInfo());
      if (serviceInstalled()) console.log('  自启     已注册（yzvibe uninstall 取消）');
      return;
    case 'qr': {
      const info = readDaemonInfo();
      if (!info) { console.log('[yzvibe] 连接器没有在运行，先 yzvibe start。'); process.exitCode = 1; return; }
      await printPairing(info, { only: args.json ? 'json' : args.link ? 'link' : null });
      return;
    }
    case 'logs':
      await tailLog({ follow: Boolean(args.f || args.follow), lines: Number(args.n ?? args.lines ?? 60) });
      return;
    case 'install': {
      const file = await installService(flags);
      console.log(`[yzvibe] 已注册开机自启：${file}\n[yzvibe] 服务正在拉起连接器…`);
      const { info } = await startDaemon(flags);
      console.log(`[yzvibe] 运行中（PID ${info.pid}，${info.mode} ${info.host}）。日志：${LOG_FILE}\n`);
      await printPairing(info);
      return;
    }
    case 'uninstall': {
      const file = await uninstallService();
      await stopDaemon();
      console.log(file ? `[yzvibe] 已取消开机自启并停止：${file}` : '[yzvibe] 没有注册过开机自启。');
      return;
    }
  }
}

main().catch((e) => { console.error(`[yzvibe] ${command} 失败:`, e.message); process.exit(1); });
