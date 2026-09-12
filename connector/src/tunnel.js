// Cloudflare Tunnel：优先用 PATH 里的 cloudflared，其次 npx cloudflared；解析出 https://xxx.trycloudflare.com
// 固定走 --protocol http2：不少网络（尤其经代理 / 校园网）封 QUIC，默认协议会拿到地址却始终注册不上边缘节点。
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { HOME } from './store.js';

const RELAY_FILE = path.join(HOME, 'relay.json');
const TUNNEL_ARGS = (port) => ['tunnel', '--url', `http://localhost:${port}`, '--no-autoupdate', '--protocol', 'http2'];

export function loadRelay() { try { return JSON.parse(fs.readFileSync(RELAY_FILE, 'utf8')).url; } catch { return null; } }
export function saveRelay(url) { fs.mkdirSync(HOME, { recursive: true }); fs.writeFileSync(RELAY_FILE, JSON.stringify({ url, savedAt: new Date().toISOString() })); }

/** 起隧道；拿到地址且边缘连接注册成功后 resolve（注册超时也 resolve，但 registered=false 并告警）。 */
export function startCloudflareTunnel(port, { timeoutMs = 40_000, registerMs = 20_000, log = console.log, spawnProcess = spawn } = {}) {
  return new Promise((resolve, reject) => {
    const candidates = [['cloudflared', TUNNEL_ARGS(port)], ['npx', ['-y', 'cloudflared', ...TUNNEL_ARGS(port)]]];
    let idx = 0;
    const tryNext = () => {
      if (idx >= candidates.length) return reject(new Error('找不到 cloudflared'));
      const [cmd, args] = candidates[idx++];
      let child;
      try { child = spawnProcess(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] }); } catch { return tryNext(); }
      let done = false, invalidated = false, output = "", url = null, registerTimer = null;
      const timer = setTimeout(() => { if (!done) { done = true; clearTimeout(registerTimer); child.kill(); reject(new Error('cloudflared 超时')); } }, timeoutMs);
      const finish = (registered) => { if (done) return; done = true; clearTimeout(timer); clearTimeout(registerTimer); resolve({ url, child, registered }); };
      const onData = (buf) => {
        // stdout/stderr chunks can split both URLs and error messages.
        output = (output + String(buf)).slice(-8192);
        const s = output;
        if (/Unauthorized: Tunnel not found/i.test(s) && !invalidated) {
          invalidated = true;
          log('[yzvibe] Cloudflare 已注销临时隧道，关闭失效进程以重新申请地址');
          if (!done) {
            done = true; clearTimeout(timer); clearTimeout(registerTimer);
            reject(new Error('Cloudflare 临时隧道已失效'));
          }
          child.kill();
          return;
        }
        if (!url) {
          const m = s.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
          if (m) { url = m[0]; registerTimer = setTimeout(() => { log(`[yzvibe] 隧道 ${url} 已分配但 ${Math.round(registerMs / 1000)} 秒内未注册到 Cloudflare 边缘，手机可能连不上；请检查网络 / 代理`); finish(false); }, registerMs); }
        }
        if (url && !done && /Registered tunnel connection/.test(s)) finish(true);
        // 注册后只记录明显的错误（断连 / 失败），避免刷屏
        if (done && /\b(ERR|error|failed)\b/i.test(String(buf))) for (const line of String(buf).split('\n')) if (/\b(ERR|error|failed)\b/i.test(line)) log(`[cloudflared] ${line.replace(/^\S+\s+\S+\s+/, '').trim()}`);
      };
      child.stdout.on('data', onData); child.stderr.on('data', onData);
      child.on('error', () => { if (!done) { done = true; clearTimeout(timer); clearTimeout(registerTimer); tryNext(); } });
      child.on('exit', () => { if (!done) { done = true; clearTimeout(timer); clearTimeout(registerTimer); tryNext(); } });
    };
    tryNext();
  });
}

/** Recover until successful; a temporary offline network must not permanently disable remote access. */
export async function retryTunnel(open, { stopped = () => false, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), log = console.log } = {}) {
  let delay = 5000;
  while (!stopped()) {
    await sleep(delay);
    if (stopped()) return null;
    try { return await open(); }
    catch (error) { log(`[yzvibe] Tunnel 重连失败：${error.message}；将继续重试`); }
    delay = Math.min(delay * 2, 60_000);
  }
  return null;
}
