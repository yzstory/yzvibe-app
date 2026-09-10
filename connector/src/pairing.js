// 一次性配对 Token + 二维码
import { randomBytes } from 'node:crypto';
import os from 'node:os';

export class Pairing {
  constructor(ttlMs = 10 * 60_000) { this.ttlMs = ttlMs; this.rotate(); }
  rotate() { this.token = randomBytes(12).toString('base64url'); this.expiresAt = Date.now() + this.ttlMs; return this.token; }
  get expired() { return Date.now() > this.expiresAt; }
  /** 当前有效的配对码；过期就换一个新的（长期后台运行时靠这个保证随时能配对）。 */
  current() { if (this.expired) this.rotate(); return this.token; }
  consume(token) {
    if (token !== this.token || this.expired) { if (this.expired) this.rotate(); return false; }
    this.rotate();
    return true;
  }
}

/** 本机可用的局域网 IPv4（排除回环与 Tailscale CGNAT 段）。 */
export function lanAddresses() {
  const out = [];
  for (const [name, list] of Object.entries(os.networkInterfaces())) {
    for (const i of list ?? []) {
      if (i.family !== 'IPv4' || i.internal) continue;
      if (i.address.startsWith('100.')) continue;       // Tailscale
      if (/^(utun|tun|docker|br-|veth)/.test(name)) continue;
      out.push(i.address);
    }
  }
  return out;
}

export function pairURL({ host, port, token, mode, name }) {
  const u = new URL('yzvibe://pair');
  u.searchParams.set('host', host);
  if (!host.includes('://')) u.searchParams.set('port', String(port));
  u.searchParams.set('token', token);
  u.searchParams.set('mode', mode);
  u.searchParams.set('name', name);
  return u.toString();
}

export async function printQR(text) {
  try {
    const { default: qr } = await import('qrcode-terminal');
    await new Promise((res) => qr.generate(text, { small: true }, (s) => { console.log(s); res(); }));
  } catch {
    console.log('(未安装 qrcode-terminal，无法绘制二维码)');
  }
  console.log(`配对链接: ${text}\n`);
}
