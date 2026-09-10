// 后台守护：`yzvibe start` 把连接器放到后台跑，终端随时可以关；start / stop / status / qr / logs / install 都在这里。
// 运行中的实例把 { pid, port, host, mode, secret… } 写到 ~/.yzvibe/daemon.json（0600），CLI 靠它找到进程并通过
// /internal/status（带 secret）拿当前配对码，不用重启就能反复出示二维码。
import { spawn, execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { HOME } from './store.js';
import { printQR } from './pairing.js';

export const DAEMON_FILE = path.join(HOME, 'daemon.json');
export const LOG_FILE = path.join(HOME, 'yzvibe.log');
const SERVICE_LABEL = 'com.yzvibe.connector';
const MAX_LOG_BYTES = 5 * 1024 * 1024;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };
const fmtAge = (iso) => { const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000); return s < 60 ? `${Math.round(s)} 秒` : s < 3600 ? `${Math.round(s / 60)} 分钟` : s < 86400 ? `${(s / 3600).toFixed(1)} 小时` : `${(s / 86400).toFixed(1)} 天`; };

// ---------- daemon.json ----------
export function writeDaemonInfo(info) {
  fs.mkdirSync(HOME, { recursive: true });
  fs.writeFileSync(DAEMON_FILE, JSON.stringify(info, null, 2), { mode: 0o600 });
}
export function clearDaemonInfo(pid = process.pid) {
  try { if (JSON.parse(fs.readFileSync(DAEMON_FILE, 'utf8')).pid === pid) fs.unlinkSync(DAEMON_FILE); } catch {}
}
/** 正在运行的实例；文件存在但进程已不在（上次没正常退出）就清掉并返回 null。 */
export function readDaemonInfo() {
  let info; try { info = JSON.parse(fs.readFileSync(DAEMON_FILE, 'utf8')); } catch { return null; }
  if (!info?.pid || !alive(info.pid)) { try { fs.unlinkSync(DAEMON_FILE); } catch {} return null; }
  return info;
}

async function internal(info, pathname, { timeoutMs = 3000 } = {}) {
  const res = await fetch(`http://127.0.0.1:${info.port}${pathname}`, { headers: { 'x-yzvibe-secret': info.secret }, signal: AbortSignal.timeout(timeoutMs) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

// ---------- 日志 ----------
/** 超过 5MB 就把旧日志挪到 .1（只留一份），避免无限增长。 */
export function rotateLog(file = LOG_FILE) {
  try { if (fs.statSync(file).size > MAX_LOG_BYTES) fs.renameSync(file, `${file}.1`); } catch {}
}
export function tailLog({ lines = 60, follow = false, file = LOG_FILE } = {}) {
  let text = ''; try { text = fs.readFileSync(file, 'utf8'); } catch { console.log(`（还没有日志：${file}）`); if (!follow) return; }
  const all = text.split('\n'); if (all.at(-1) === '') all.pop();
  console.log(all.slice(-lines).join('\n'));
  if (!follow) return;
  let pos = Buffer.byteLength(text);
  return new Promise(() => {
    fs.watchFile(file, { interval: 500 }, (cur) => {
      if (cur.size < pos) pos = 0;                                 // 被轮转/清空
      if (cur.size === pos) return;
      const fd = fs.openSync(file, 'r'); const buf = Buffer.alloc(cur.size - pos);
      fs.readSync(fd, buf, 0, buf.length, pos); fs.closeSync(fd); pos = cur.size;
      process.stdout.write(buf.toString('utf8'));
    });
  });
}

// ---------- start / stop / status ----------
function binPath() { return path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'bin', 'yzvibe.js'); }

/** 后台拉起 `yzvibe run <flags>`，等它写好 daemon.json 并通过健康检查后返回实例信息。 */
export async function startDaemon(flags = [], { waitMs = 75_000 } = {}) {
  const running = readDaemonInfo();
  if (running) return { info: running, alreadyRunning: true };
  if (serviceInstalled()) {                                     // 装过开机自启：交给 launchd / systemd 拉起
    await serviceControl('start');
  } else {
    fs.mkdirSync(HOME, { recursive: true }); rotateLog();
    const out = fs.openSync(LOG_FILE, 'a');
    const child = spawn(process.execPath, [binPath(), 'run', ...flags], { detached: true, stdio: ['ignore', out, out], env: { ...process.env, YZVIBE_DAEMON: '1' } });
    fs.closeSync(out);
    child.unref();
    const info = await waitReady((i) => i.pid === child.pid, waitMs, () => alive(child.pid));
    return { info, alreadyRunning: false };
  }
  return { info: await waitReady(() => true, waitMs), alreadyRunning: false };
}

async function waitReady(match, waitMs, stillAlive = () => true) {
  const t0 = Date.now();
  while (Date.now() - t0 < waitMs) {
    const info = readDaemonInfo();
    if (info && match(info)) { try { await internal(info, '/internal/status'); return info; } catch {} }
    if (!stillAlive()) break;
    await sleep(300);
  }
  let tail = ''; try { tail = fs.readFileSync(LOG_FILE, 'utf8').split('\n').slice(-15).join('\n'); } catch {}
  throw new Error(`连接器没有在 ${Math.round(waitMs / 1000)} 秒内就绪，最近日志：\n${tail}`);
}

export async function stopDaemon({ timeoutMs = 8000 } = {}) {
  const info = readDaemonInfo();
  if (!info) return null;
  if (info.managed && serviceInstalled()) { await serviceControl('stop'); }
  else { try { process.kill(info.pid, 'SIGTERM'); } catch {} }
  const t0 = Date.now();
  while (alive(info.pid) && Date.now() - t0 < timeoutMs) await sleep(150);
  if (alive(info.pid)) { try { process.kill(info.pid, 'SIGKILL'); } catch {} await sleep(300); }
  try { fs.unlinkSync(DAEMON_FILE); } catch {}
  return info;
}

/** 运行中实例的状态 + 当前配对码（连接器会把过期的配对码换新）。 */
export async function fetchStatus(info) { return internal(info, '/internal/status'); }

export async function printStatus(info) {
  if (!info) { console.log('YzVibe 连接器：未运行。用 `yzvibe start` 启动。'); return; }
  let st = null; try { st = await fetchStatus(info); } catch {}
  const host = st?.host ?? info.host, mode = st?.mode ?? info.mode;
  const modeLabel = { tunnel: 'Cloudflare Tunnel', relay: '自定义 Relay', local: '局域网', tailscale: 'Tailscale' }[mode] ?? mode;
  console.log(`YzVibe 连接器：${st ? '运行中' : '进程在但未响应'}${info.managed ? `（${info.managed} 托管，开机自启）` : ''}`);
  console.log(`  PID      ${info.pid}   已运行 ${fmtAge(info.startedAt)}`);
  console.log(`  地址     ${host}${String(host).includes('://') ? '' : `:${info.port}`}   （${modeLabel}，本机端口 ${info.port}）`);
  console.log(`  Agent    ${info.agent}${info.flags?.length ? `   启动参数 ${info.flags.join(' ')}` : ''}`);
  console.log(`  日志     ${LOG_FILE}`);
  if (st) console.log(`  会话     ${st.stats.sessions} 个（运行中 ${st.stats.running}，待审批 ${st.stats.pendingApprovals}），已配对手机 ${st.stats.devices} 台`);
}

/** 三种配对方式：扫码 / 手机浏览器打开外链 / 复制 JSON 粘贴进 App。`only` 可指定 'json' | 'link' 只输出一项（便于管道）。 */
export async function printPairing(info, { only = null } = {}) {
  const st = await fetchStatus(info);
  const p = st.pairing;
  if (only === 'json') return console.log(JSON.stringify(p.config, null, 2));
  if (only === 'link') return console.log(p.link);
  const minutes = Math.max(1, Math.round((new Date(p.expiresAt) - Date.now()) / 60000));
  console.log(`用手机 YzVibe App「设备 › 扫码配对」扫描（${minutes} 分钟内有效，一次性；过期后再运行 yzvibe qr）：\n`);
  await printQR(p.url);
  console.log(`② 或者用手机浏览器打开这个链接，页面会自动唤起 App：\n   ${p.link}\n`);
  console.log(`③ 或者复制下面的 JSON，在 App「设备 › 手动添加 › 粘贴配置」里粘贴：\n`);
  console.log(JSON.stringify(p.config, null, 2) + '\n');
  console.log(`（只要链接：yzvibe qr --link；只要 JSON：yzvibe qr --json）`);
  if (st.mode === 'local') console.log('提示：手机需与电脑在同一 Wi-Fi；远程访问请用 `yzvibe restart --access=remote`（Cloudflare Tunnel）。');
}

// ---------- 开机自启（macOS launchd / Linux systemd --user） ----------
function plistPath() { return path.join(os.homedir(), 'Library', 'LaunchAgents', `${SERVICE_LABEL}.plist`); }
function unitPath() { return path.join(process.env.XDG_CONFIG_HOME ?? path.join(os.homedir(), '.config'), 'systemd', 'user', 'yzvibe.service'); }
export function serviceInstalled() { return process.platform === 'darwin' ? fs.existsSync(plistPath()) : process.platform === 'linux' ? fs.existsSync(unitPath()) : false; }
const run = (cmd, args) => new Promise((resolve, reject) => execFile(cmd, args, { timeout: 15000 }, (err, out, errOut) => (err ? reject(new Error((errOut || out || err.message).trim())) : resolve(String(out)))));
/** 调用 install 时若设置了这些环境变量，一并写进服务定义（数据目录 / 端口 / 各家 CLI 的配置目录）。 */
const passthroughEnv = () => ['YZVIBE_HOME', 'YZVIBE_PORT', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME'].filter((k) => process.env[k]).map((k) => [k, process.env[k]]);
const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

async function serviceControl(action) {
  if (process.platform === 'darwin') {
    const target = `gui/${process.getuid()}/${SERVICE_LABEL}`;
    if (action === 'start') { await run('launchctl', ['bootstrap', `gui/${process.getuid()}`, plistPath()]).catch(() => {}); await run('launchctl', ['kickstart', target]).catch(() => {}); }
    else await run('launchctl', ['bootout', target]).catch(() => {});
  } else if (process.platform === 'linux') {
    await run('systemctl', ['--user', action === 'start' ? 'start' : 'stop', 'yzvibe.service']);
  } else throw new Error('当前系统不支持开机自启');
}

export async function installService(flags = []) {
  const running = readDaemonInfo();
  if (running && !running.managed) await stopDaemon();            // 手动起的实例让位给服务
  const args = [process.execPath, binPath(), 'run', ...flags];
  fs.mkdirSync(HOME, { recursive: true });
  if (process.platform === 'darwin') {
    const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${SERVICE_LABEL}</string>
  <key>ProgramArguments</key><array>${args.map((a) => `<string>${xml(a)}</string>`).join('')}</array>
  <key>WorkingDirectory</key><string>${xml(os.homedir())}</string>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>${xml(process.env.PATH ?? '/usr/local/bin:/usr/bin:/bin')}</string>
    <key>HOME</key><string>${xml(os.homedir())}</string>
    <key>YZVIBE_DAEMON</key><string>1</string>
    <key>YZVIBE_MANAGED</key><string>launchd</string>${passthroughEnv().map(([k, v]) => `\n    <key>${k}</key><string>${xml(v)}</string>`).join('')}
  </dict>
  <key>StandardOutPath</key><string>${xml(LOG_FILE)}</string>
  <key>StandardErrorPath</key><string>${xml(LOG_FILE)}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
</dict></plist>
`;
    fs.mkdirSync(path.dirname(plistPath()), { recursive: true });
    await run('launchctl', ['bootout', `gui/${process.getuid()}/${SERVICE_LABEL}`]).catch(() => {});
    fs.writeFileSync(plistPath(), plist);
    await run('launchctl', ['bootstrap', `gui/${process.getuid()}`, plistPath()]);
    return plistPath();
  }
  if (process.platform === 'linux') {
    const unit = `[Unit]
Description=YzVibe connector
After=network-online.target

[Service]
ExecStart=${args.map((a) => JSON.stringify(a)).join(' ')}
Restart=always
RestartSec=5
Environment=PATH=${process.env.PATH ?? '/usr/local/bin:/usr/bin:/bin'}
Environment=YZVIBE_DAEMON=1
Environment=YZVIBE_MANAGED=systemd${passthroughEnv().map(([k, v]) => `\nEnvironment=${k}=${v}`).join('')}
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=default.target
`;
    fs.mkdirSync(path.dirname(unitPath()), { recursive: true });
    fs.writeFileSync(unitPath(), unit);
    await run('systemctl', ['--user', 'daemon-reload']);
    await run('systemctl', ['--user', 'enable', '--now', 'yzvibe.service']);
    return unitPath();
  }
  throw new Error('当前系统不支持开机自启（仅 macOS / Linux）');
}

export async function uninstallService() {
  if (!serviceInstalled()) return null;
  if (process.platform === 'darwin') { await run('launchctl', ['bootout', `gui/${process.getuid()}/${SERVICE_LABEL}`]).catch(() => {}); fs.unlinkSync(plistPath()); return plistPath(); }
  await run('systemctl', ['--user', 'disable', '--now', 'yzvibe.service']).catch(() => {});
  fs.unlinkSync(unitPath()); await run('systemctl', ['--user', 'daemon-reload']).catch(() => {});
  return unitPath();
}
