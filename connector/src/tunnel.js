// Cloudflare Tunnel：优先用 PATH 里的 cloudflared，其次 npx cloudflared；解析出 https://xxx.trycloudflare.com
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { HOME } from './store.js';

const RELAY_FILE = path.join(HOME, 'relay.json');

export function loadRelay() { try { return JSON.parse(fs.readFileSync(RELAY_FILE, 'utf8')).url; } catch { return null; } }
export function saveRelay(url) { fs.mkdirSync(HOME, { recursive: true }); fs.writeFileSync(RELAY_FILE, JSON.stringify({ url, savedAt: new Date().toISOString() })); }

export function startCloudflareTunnel(port, { timeoutMs = 30_000 } = {}) {
  return new Promise((resolve, reject) => {
    const candidates = [['cloudflared', ['tunnel', '--url', `http://localhost:${port}`, '--no-autoupdate']],
                        ['npx', ['-y', 'cloudflared', 'tunnel', '--url', `http://localhost:${port}`, '--no-autoupdate']]];
    let idx = 0;
    const tryNext = () => {
      if (idx >= candidates.length) return reject(new Error('找不到 cloudflared'));
      const [cmd, args] = candidates[idx++];
      let child;
      try { child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] }); } catch { return tryNext(); }
      let done = false;
      const timer = setTimeout(() => { if (!done) { done = true; child.kill(); reject(new Error('cloudflared 超时')); } }, timeoutMs);
      const onData = (buf) => {
        const m = String(buf).match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
        if (m && !done) { done = true; clearTimeout(timer); resolve({ url: m[0], child }); }
      };
      child.stdout.on('data', onData); child.stderr.on('data', onData);
      child.on('error', () => { if (!done) { done = true; clearTimeout(timer); tryNext(); } });
      child.on('exit', (code) => { if (!done) { done = true; clearTimeout(timer); tryNext(); } });
    };
    tryNext();
  });
}
