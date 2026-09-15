import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { ompThinking, ompSubagentsFromDetails } from './omp-progress.js';
export const OMP_HOME = process.env.PI_CODING_AGENT_DIR ?? path.join(os.homedir(), '.omp/agent');
const cache = new Map();
const textOf = c => typeof c === 'string' ? c : (Array.isArray(c) ? c : []).filter(x => x.type === 'text').map(x => x.text ?? '').join('\n');
function entries(file, maxBytes = 64 * 1024 * 1024, tail = false) {
  const fd = fs.openSync(file, 'r');
  try { const total = fs.fstatSync(fd).size; if (maxBytes === 64 * 1024 * 1024 && total > maxBytes) throw new Error('OMP 历史超过 64 MB，请在电脑端压缩或分支后重试'); const size = Math.min(total, maxBytes); const b = Buffer.alloc(size); fs.readSync(fd, b, 0, size, tail ? total - size : 0); return b.toString('utf8').split('\n').flatMap(l => { try { return [JSON.parse(l)]; } catch { return []; } }); }
  finally { fs.closeSync(fd); }
}
export function scanOmpSessions({ ompHome = OMP_HOME } = {}) {
  const root = path.join(ompHome, 'sessions'); const files = [];
  let dirs; try { dirs = fs.readdirSync(root, { withFileTypes: true }).filter(d => d.isDirectory()); } catch { return []; }
  for (const d of dirs) {
    let names; try { names = fs.readdirSync(path.join(root, d.name)); } catch { continue; }
    for (const n of names) {
      if (!n.endsWith('.jsonl')) continue;
      const file = path.join(root, d.name, n); let st; try { st = fs.statSync(file); } catch { continue; }
      if (st.isFile() && Date.now() - st.mtimeMs < 45 * 86400_000) files.push({ file, st });
    }
  }
  return files.sort((a,b) => b.st.mtimeMs-a.st.mtimeMs).slice(0,80).flatMap(({ file, st }) => {
    try {
    const hit = cache.get(file); if (hit?.size === st.size && hit?.mtime === st.mtimeMs) return hit.value;
    const rows = entries(file, 256 * 1024), h = rows.find(e => e.type === 'session');
    if (!h?.id || !h.cwd || !fs.existsSync(h.cwd)) return [];
    const first = rows.find(e => e.message?.role === 'user');
    const titles = [...rows, ...entries(file, 256 * 1024, true)];
    const name = titles.findLast(e => e.type === 'title_change' || e.type === 'title')?.title || h.title || textOf(first?.message?.content).slice(0,80);
    const value = [{ id: `omp:${h.id}`, agent: 'omp', agentSessionId: h.id, cwd: h.cwd, title: name || 'OMP 会话',
      createdAt: h.timestamp || st.birthtime.toISOString(), updatedAt: st.mtime.toISOString(), source: 'terminal', status: 'idle', mode: 'normal', file, branch: null, pendingApprovals: 0 }];
    cache.set(file, { size: st.size, mtime: st.mtimeMs, value }); return value;
    } catch { return []; }
  });
}
export function parseOmpTranscript(file, sessionId, addUpload) {
  const rows = entries(file); const byId = new Map(rows.filter(e => e.id && e.type !== 'session').map(e => [e.id,e]));
  let leaf = rows.findLast(e => e.id && e.type !== 'session'); const branch = [], seen = new Set();
  while (leaf && !seen.has(leaf.id)) { branch.push(leaf); seen.add(leaf.id); leaf = byId.get(leaf.parentId); }
  const out = [];
  for (const e of branch.reverse()) {
    const m = e.message; if (!m) continue;
    if (m.role === 'toolResult') {
      const tool = out.flatMap(x => x.toolCalls).find(t => t.id === m.toolCallId);
      const images = importOmpImages(m.content, addUpload, path.join(path.dirname(path.dirname(path.dirname(file))), 'blobs'));
      if (images.length) out.push({ id: `omp-image-${e.id}`, sessionId, role: 'assistant', text: '', attachments: images, toolCalls: [], streaming: false, createdAt: e.timestamp });
      if (tool) {
        tool.state = m.isError ? 'error' : 'done'; tool.output = textOf(m.content).slice(0,64000);
        // A transcript is a snapshot, not proof that an old background job is still alive.
        tool.subagents = ompSubagentsFromDetails(m.details, [], Date.parse(e.timestamp) || Date.now()).map(p =>
          ['pending', 'running'].includes(p.status) ? { ...p, status: 'unknown', detail: '历史快照，实时状态未知' } : p);
      }
      continue;
    }
    if (!['user','assistant'].includes(m.role)) continue;
    const toolCalls = (Array.isArray(m.content) ? m.content : []).filter(x=>x.type==='toolCall').map(t=>({ id:t.id,name:t.name,input:t.arguments,detail:JSON.stringify(t.arguments),state:'done' }));
    out.push({ id:`omp-history-${e.id}`,sessionId,role:m.role,text:textOf(m.content),thinking:ompThinking(m.content),attachments:importOmpImages(m.content, addUpload, path.join(path.dirname(path.dirname(path.dirname(file))), 'blobs')),toolCalls,streaming:false,createdAt:e.timestamp });
  }
  return out.slice(-300);
}

/** Import native images once into the existing authenticated upload store. */
export function importOmpImages(content, addUpload, blobDir = path.join(OMP_HOME, 'blobs')) {
  if (!addUpload || !Array.isArray(content)) return [];
  return content.filter(c => c.type === 'image').slice(0, 20).flatMap(c => {
    if (!/^image\/(png|jpeg|gif|webp)$/.test(c.mimeType ?? '') || typeof c.data !== 'string') return [];
    try {
      let bytes;
      if (/^blob:sha256:[a-f0-9]{64}$/.test(c.data)) {
        const file = path.join(blobDir, c.data.slice(12));
        if (fs.statSync(file).size > 20 * 1024 * 1024) return [];
        bytes = fs.readFileSync(file);
      } else {
        if (c.data.length > 28 * 1024 * 1024 || !/^[A-Za-z0-9+/]*={0,2}$/.test(c.data)) return [];
        bytes = Buffer.from(c.data, 'base64');
      }
      return bytes.length ? [addUpload(`omp-image.${c.mimeType.split('/')[1]}`, c.mimeType, bytes)] : [];
    } catch { return []; }
  });
}
