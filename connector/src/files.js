// 远程文件：只读列表 / 预览 / 下载，限制在会话工作目录内
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const TEXT_EXT = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.json', '.md', '.txt', '.yml', '.yaml', '.swift', '.kt', '.py', '.go', '.rs', '.css', '.html', '.sh', '.toml', '.env', '.sql', '.xml', '.plist']);
const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.heic']);
const MAX_PREVIEW = 2 * 1024 * 1024;

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
  const { target } = resolveInside(root, rel);
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
