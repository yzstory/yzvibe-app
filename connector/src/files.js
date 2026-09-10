// 远程文件：只读列表 / 预览 / 下载，限制在会话工作目录内
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const TEXT_EXT = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.json', '.md', '.txt', '.yml', '.yaml', '.swift', '.kt', '.py', '.go', '.rs', '.css', '.html', '.sh', '.toml', '.env', '.sql', '.xml', '.plist']);
const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.heic']);
const MAX_PREVIEW = 2 * 1024 * 1024;

/** 无论是否在工作目录内，已知凭据都不通过文件接口提供。 */
const SENSITIVE = [
  /(^|\/)\.ssh(\/|$)/, /(^|\/)\.gnupg(\/|$)/, /(^|\/)\.aws(\/|$)/, /(^|\/)\.kube(\/|$)/,
  /(^|\/)Library\/Keychains(\/|$)/, /(^|\/)\.netrc$/, /(^|\/)\.npmrc$/, /(^|\/)\.pypirc$/,
  /(^|\/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$/, /\.credentials\.json$/, /(^|\/)credentials(\.json)?$/,
  /(^|\/)\.docker\/config\.json$/, /(^|\/)\.config\/gh(\/|$)/, /(^|\/)\.git-credentials$/,
  /(^|\/)\.yzvibe\/(devices\.json|daemon\.json|apns\.json|mcp-[^/]+\.json)$/, /\.p8$/,
  /(^|\/)\.codex\/auth\.json$/,
];

const inside = (base, target) => target === base || target.startsWith(base + path.sep);
const forbidden = () => Object.assign(new Error('路径越界或文件包含敏感凭据'), { status: 403 });
export function assertNotSensitive(target) {
  if (SENSITIVE.some((re) => re.test(target))) throw forbidden();
}

// 不存在的路径也解析最近存在的父目录，避免经符号链接创建/查询到边界之外。
function realPath(target) {
  try { return fs.realpathSync(target); }
  catch (e) {
    if (e.code !== 'ENOENT') throw e;
    const parent = path.dirname(target);
    if (parent === target) throw e;
    return path.join(realPath(parent), path.basename(target));
  }
}

export function expandHome(p) { return p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p; }

/** 把相对路径解析到 root 内，越界抛错。 */
export function resolveInside(root, rel = '') {
  const base = realPath(path.resolve(expandHome(root)));
  const lexical = path.resolve(base, rel.replace(/^\/+/, ''));
  assertNotSensitive(lexical);
  if (!inside(base, lexical)) throw forbidden();
  const target = realPath(lexical);
  assertNotSensitive(target);
  if (!inside(base, target)) throw forbidden();
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

/** 相对路径/工作区别名不能越界；显式绝对路径还允许读取主目录内的非敏感文件。 */
export function resolveReadable(root, rel = '') {
  const raw = String(rel ?? '');
  const expanded = expandHome(raw);
  // 相对路径仍按工作目录解析，保持原有行为
  if (!path.isAbsolute(expanded)) return { ...resolveInside(root, raw), inCwd: true };

  const lexicalBase = path.resolve(expandHome(root));
  const lexical = path.resolve(expanded);
  assertNotSensitive(lexical);
  if (inside(lexicalBase, lexical)) return { ...resolveInside(root, path.relative(lexicalBase, lexical)), inCwd: true };
  const base = realPath(lexicalBase);
  const target = realPath(lexical);
  assertNotSensitive(target);
  if (inside(base, lexical)) return { ...resolveInside(base, path.relative(base, lexical)), inCwd: true };

  const home = realPath(path.resolve(os.homedir()));
  if (!inside(home, target)) {
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
      let st; try { st = fs.statSync(resolveInside(base, path.relative(base, full)).target); } catch { return null; }
      return { name: e.name, path: path.relative(base, full), kind: kindOf(e.name, st.isDirectory()), size: st.isDirectory() ? 0 : st.size, modifiedAt: st.mtime.toISOString() };
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
