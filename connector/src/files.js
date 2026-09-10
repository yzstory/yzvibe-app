// 远程文件：只读列表 / 预览 / 下载，限制在会话工作目录内
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const TEXT_EXT = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.json', '.md', '.txt', '.yml', '.yaml', '.swift', '.kt', '.py', '.go', '.rs', '.css', '.html', '.sh', '.toml', '.env', '.sql', '.xml', '.plist']);
const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.heic']);
const MAX_PREVIEW = 2 * 1024 * 1024;

/** 会话工作目录之外、但仍在用户主目录内的敏感文件：一律不给手机读。 */
const SENSITIVE = [
  /(^|\/)\.ssh(\/|$)/, /(^|\/)\.gnupg(\/|$)/, /(^|\/)\.aws(\/|$)/, /(^|\/)\.kube(\/|$)/,
  /(^|\/)Library\/Keychains(\/|$)/, /(^|\/)\.netrc$/, /(^|\/)\.npmrc$/, /(^|\/)\.pypirc$/,
  /(^|\/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$/, /\.credentials\.json$/, /(^|\/)credentials(\.json)?$/,
  /(^|\/)\.docker\/config\.json$/, /(^|\/)\.config\/gh(\/|$)/, /(^|\/)\.git-credentials$/,
];

export function expandHome(p) { return p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p; }

/** 把相对路径解析到 root 内，越界抛错。 */
export function resolveInside(root, rel = '') {
  const base = path.resolve(expandHome(root));
  const target = path.resolve(base, rel.replace(/^\/+/, ''));
  if (target !== base && !target.startsWith(base + path.sep)) throw Object.assign(new Error('路径越界'), { status: 403 });
  return { base, target };
}

export function kindOf(name, isDir) {
  if (isDir) return 'folder';
  const ext = path.extname(name).toLowerCase();
  if (ext === '.md') return 'markdown';
  if (IMAGE_EXT.has(ext)) return 'image';
  if (TEXT_EXT.has(ext)) return 'code';
  return 'other';
}

/** 解析可读文件：会话工作目录内一律放行；目录外只允许主目录内的非敏感文件（聊天里点文件路径会用到）。 */
export function resolveReadable(root, rel = '') {
  const raw = String(rel ?? '');
  const expanded = expandHome(raw);
  // 相对路径仍按工作目录解析，保持原有行为
  if (!path.isAbsolute(expanded)) return { ...resolveInside(root, raw), inCwd: true };

  const base = path.resolve(expandHome(root));
  const target = path.resolve(expanded);
  if (target === base || target.startsWith(base + path.sep)) return { base, target, inCwd: true };

  const home = path.resolve(os.homedir());
  const inHome = target === home || target.startsWith(home + path.sep);
  const rest = inHome ? target.slice(home.length) : '';
  if (!inHome || SENSITIVE.some((re) => re.test(rest))) {
    throw Object.assign(new Error('这个文件不在会话工作目录里，出于安全不提供访问'), { status: 403 });
  }
  return { base: home, target, inCwd: false };
}

/** 文件元信息（手机端文件查看器用）。 */
export function statFile(root, rel) {
  const { target, inCwd } = resolveReadable(root, rel);
  const st = fs.statSync(target);
  if (st.isDirectory()) throw Object.assign(new Error('是目录'), { status: 400 });
  const kind = kindOf(target, false);
  return {
    name: path.basename(target),
    path: target,
    displayPath: target.startsWith(os.homedir()) ? target.replace(os.homedir(), '~') : target,
    kind,
    size: st.size,
    modifiedAt: st.mtime.toISOString(),
    mime: mimeOf(target),
    textual: kind !== 'image' && st.size <= MAX_PREVIEW,
    inCwd,
  };
}

export function listDir(root, rel) {
  const { base, target } = resolveInside(root, rel);
  const entries = fs.readdirSync(target, { withFileTypes: true })
    .filter((e) => !e.name.startsWith('.') && e.name !== 'node_modules')
    .map((e) => {
      const full = path.join(target, e.name);
      let st; try { st = fs.statSync(full); } catch { return null; }
      return { name: e.name, path: path.relative(base, full), kind: kindOf(e.name, e.isDirectory()), size: e.isDirectory() ? 0 : st.size, modifiedAt: st.mtime.toISOString() };
    })
    .filter(Boolean)
    .sort((a, b) => (a.kind === 'folder') === (b.kind === 'folder') ? a.name.localeCompare(b.name) : a.kind === 'folder' ? -1 : 1);
  return { path: path.relative(base, target), entries };
}

export function previewFile(root, rel) {
  const { target } = resolveReadable(root, rel);
  const st = fs.statSync(target);
  if (st.isDirectory()) throw Object.assign(new Error('是目录'), { status: 400 });
  if (st.size > MAX_PREVIEW) throw Object.assign(new Error('文件过大，请下载'), { status: 413 });
  const kind = kindOf(target, false);
  if (kind === 'image') return { mime: mimeOf(target), body: fs.readFileSync(target) };
  return { mime: 'text/plain; charset=utf-8', body: fs.readFileSync(target) };
}

export function mimeOf(file) {
  const ext = path.extname(file).toLowerCase();
  return { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.pdf': 'application/pdf', '.json': 'application/json', '.md': 'text/markdown' }[ext] ?? 'application/octet-stream';
}
