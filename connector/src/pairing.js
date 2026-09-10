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

/** 连接器自己的 http(s) 根地址：relay / tunnel 模式 host 已含协议，局域网 / Tailscale 拼端口。 */
export function baseURL({ host, port }) { return String(host).includes('://') ? String(host).replace(/\/+$/, '') : `http://${host}:${port}`; }

/** 手机浏览器打开的外链：落地页会自动跳到 yzvibe:// 唤起 App，并提供 JSON 兜底。 */
export function pairLink(opts) { return `${baseURL(opts)}/pair?token=${encodeURIComponent(opts.token)}`; }

/** 可以直接粘贴进 App 的完整配置。 */
export function pairConfig({ host, port, token, mode, name, expiresAt, connectorId, version }) {
  return {
    yzvibe: 1,
    name,
    host,
    port: String(host).includes('://') ? null : port,
    token,
    mode,
    ...(connectorId && { connectorId }),
    ...(version && { version }),
    ...(expiresAt && { expiresAt }),
    url: pairURL({ host, port, token, mode, name }),
    link: pairLink({ host, port, token }),
  };
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** 手机浏览器落地页：自动唤起 App，附「打开 App」按钮与可复制的 JSON 配置。 */
export function pairPageHTML(config, { minutesLeft = 10 } = {}) {
  const json = JSON.stringify(config, null, 2);
  return `<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="color-scheme" content="light dark"><title>连接 ${esc(config.name)} · YzVibe</title>
<style>
:root{--bg:#faf7f2;--card:#fff;--ink:#2b2622;--dim:#7a6f66;--line:#e7dfd5;--brand:#c0562e;--brand-ink:#fff}
@media (prefers-color-scheme:dark){:root{--bg:#17140f;--card:#211d18;--ink:#f2ece4;--dim:#a1958a;--line:#332c25}}
*{box-sizing:border-box}
body{margin:0;padding:28px 20px 40px;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;-webkit-text-size-adjust:100%}
main{max-width:520px;margin:0 auto}
h1{font-size:22px;margin:0 0 6px}
p.sub{color:var(--dim);margin:0 0 22px;font-size:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:18px;margin-bottom:16px}
.row{display:flex;justify-content:space-between;gap:12px;padding:7px 0;font-size:14px;border-bottom:1px solid var(--line)}
.row:last-child{border-bottom:0}
.row span:first-child{color:var(--dim);flex:0 0 auto}
.row span:last-child{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;text-align:right;word-break:break-all}
a.btn,button.btn{display:block;width:100%;padding:15px;border-radius:14px;border:0;font-size:17px;font-weight:600;text-align:center;text-decoration:none;cursor:pointer;margin-bottom:10px;font-family:inherit}
.primary{background:var(--brand);color:var(--brand-ink)}
.ghost{background:transparent;color:var(--ink);border:1px solid var(--line)}
pre{background:var(--bg);border:1px solid var(--line);border-radius:12px;padding:14px;overflow:auto;font-size:12px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;margin:0;-webkit-user-select:all;user-select:all}
.hint{color:var(--dim);font-size:13px;margin:14px 0 0}
</style></head><body><main>
<h1>连接 ${esc(config.name)}</h1>
<p class="sub">配对码一次性，约 ${minutesLeft} 分钟内有效。</p>
<a class="btn primary" id="open" href="${esc(config.url)}">在 YzVibe 中打开</a>
<button class="btn ghost" id="copy">复制配置 JSON</button>
<div class="card">
  <div class="row"><span>电脑</span><span>${esc(config.name)}</span></div>
  <div class="row"><span>地址</span><span>${esc(config.host)}${config.port ? ':' + config.port : ''}</span></div>
  <div class="row"><span>方式</span><span>${esc(config.mode)}</span></div>
</div>
<p class="hint">没有自动跳转？点上面的按钮。App 里也可以在「设备 › 手动添加 › 粘贴配置」里粘贴下面的 JSON。</p>
<pre id="json">${esc(json)}</pre>
</main><script>
var link = document.getElementById('open').href;
// 首次打开自动尝试唤起 App（从后台返回时不重复触发）
if (!sessionStorage.getItem('yz-tried')) { sessionStorage.setItem('yz-tried', '1'); setTimeout(function () { location.href = link; }, 350); }
document.getElementById('copy').addEventListener('click', function () {
  var t = document.getElementById('json').textContent, b = this;
  (navigator.clipboard ? navigator.clipboard.writeText(t) : Promise.reject()).then(function () { b.textContent = '已复制'; }, function () { b.textContent = '请长按下方 JSON 复制'; });
  setTimeout(function () { b.textContent = '复制配置 JSON'; }, 2000);
});
</script></body></html>
`;
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
