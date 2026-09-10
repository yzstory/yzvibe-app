// 连接器的可达地址集合，以及局域网内的 Bonjour 广播。
//
// 为什么需要：Cloudflare 的临时隧道每次重开都是新地址，电脑重启一次手机就连不上了。
// 只记一个地址就必须重新扫码。这里让连接器把自己所有的地址都报出来，手机依次尝试；
// 同一 Wi-Fi 下还能用 Bonjour 直接发现，地址全变了也不用重扫。
import { spawn } from 'node:child_process';
import os from 'node:os';
import { lanAddresses } from './pairing.js';

/** 本机的 Tailscale IPv4（100.64.0.0/10）。 */
export function tailscaleAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list ?? []) {
      if (i.family === 'IPv4' && !i.internal && /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(i.address)) out.push(i.address);
    }
  }
  return out;
}

/**
 * 所有可达地址，按「先试哪个」排序：当前主地址 → Tailscale → 局域网 → 回环。
 * 每一项都是完整 base URL，手机拿到后逐个探活。
 */
export function collectEndpoints({ host, port, mode }) {
  const seen = new Set();
  const out = [];
  const add = (url) => { if (url && !seen.has(url)) { seen.add(url); out.push(url); } };
  const withPort = (h) => `http://${h}:${port}`;

  if (host) add(String(host).includes('://') ? String(host).replace(/\/+$/, '') : withPort(host));
  for (const ip of tailscaleAddresses()) add(withPort(ip));
  for (const ip of lanAddresses()) add(withPort(ip));
  add(withPort('127.0.0.1'));
  return out;
}

/**
 * 在局域网里广播 `_yzvibe._tcp`，手机同一 Wi-Fi 下可以直接发现，不依赖任何固定地址。
 * macOS 用系统自带的 dns-sd，Linux 用 avahi-publish；都没有就静默跳过（不影响其它功能）。
 */
export function advertiseBonjour({ name, port, connectorId, log = () => {} }) {
  const safeName = String(name).replace(/[^\w \-.一-龥]/g, '').slice(0, 60) || 'YzVibe';
  const txt = [`id=${connectorId}`, `v=1`, `name=${safeName}`];
  const attempts = process.platform === 'darwin'
    ? [['dns-sd', ['-R', safeName, '_yzvibe._tcp', 'local', String(port), ...txt]]]
    : [['avahi-publish', ['-s', safeName, '_yzvibe._tcp', String(port), ...txt]],
       ['dns-sd', ['-R', safeName, '_yzvibe._tcp', 'local', String(port), ...txt]]];

  let child = null;
  const tryNext = (i) => {
    if (i >= attempts.length) { log('[yzvibe] 没有可用的 Bonjour 工具，跳过局域网广播'); return; }
    const [cmd, args] = attempts[i];
    let c;
    try { c = spawn(cmd, args, { stdio: 'ignore' }); } catch { return tryNext(i + 1); }
    c.on('error', () => tryNext(i + 1));
    c.on('exit', (code) => { if (child === c && code !== 0 && code !== null) tryNext(i + 1); });
    child = c;
  };
  tryNext(0);
  return () => { try { child?.kill(); } catch {} child = null; };
}
