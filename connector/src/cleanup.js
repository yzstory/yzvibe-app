// 定期清理：连接器长期后台运行，上传的图片、已关会话的消息、日志都是只增不减的，这里给它们定个保质期。
import fs from 'node:fs';
import path from 'node:path';

const DAY = 86_400_000;

/** 删掉 maxAgeDays 之前上传的图片（聊天记录里的旧图会显示「图片不可用」）。 */
export function pruneUploads(home, { maxAgeDays = 14, now = Date.now() } = {}) {
  const dir = path.join(home, 'uploads');
  let names; try { names = fs.readdirSync(dir); } catch { return { removed: 0, bytes: 0 }; }
  let removed = 0, bytes = 0;
  for (const n of names) {
    const f = path.join(dir, n);
    try {
      const st = fs.statSync(f);
      if (!st.isFile() || now - st.mtimeMs <= maxAgeDays * DAY) continue;
      bytes += st.size; fs.unlinkSync(f); removed += 1;
    } catch {}
  }
  return { removed, bytes };
}

/** 已关闭且很久没动的会话：删消息文件并从 sessions.json 里移除。返回被删的会话 id。 */
export function pruneSessions(sessions, home, { maxAgeDays = 45, now = Date.now() } = {}) {
  const stale = sessions.filter((s) => s.status === 'closed' && now - new Date(s.updatedAt || s.createdAt || 0).getTime() > maxAgeDays * DAY);
  for (const s of stale) {
    try { fs.unlinkSync(path.join(home, 'messages', `${s.id}.json`)); } catch {}
  }
  return stale.map((s) => s.id);
}

/** 孤儿消息文件（会话记录已经不在了）。 */
export function pruneOrphanMessages(sessions, home) {
  const alive = new Set(sessions.map((s) => s.id));
  const dir = path.join(home, 'messages');
  let names; try { names = fs.readdirSync(dir); } catch { return 0; }
  let removed = 0;
  for (const n of names) {
    const id = n.replace(/\.json$/, '');
    if (alive.has(id)) continue;
    try { fs.unlinkSync(path.join(dir, n)); removed += 1; } catch {}
  }
  return removed;
}

/** 一次完整清理；startCleanupLoop 每 6 小时跑一次。 */
export function runCleanup(store, { log = () => {}, maxUploadDays = 14, maxSessionDays = 45 } = {}) {
  const up = pruneUploads(store.home, { maxAgeDays: maxUploadDays });
  const gone = pruneSessions(store.sessions, store.home, { maxAgeDays: maxSessionDays });
  if (gone.length) store.forgetSessions(gone);
  const orphans = pruneOrphanMessages(store.sessions, store.home);
  const parts = [];
  if (up.removed) parts.push(`旧图片 ${up.removed} 张（${(up.bytes / 1e6).toFixed(1)} MB）`);
  if (gone.length) parts.push(`过期会话 ${gone.length} 个`);
  if (orphans) parts.push(`孤儿消息文件 ${orphans} 个`);
  if (parts.length) log(`[yzvibe] 已清理：${parts.join('，')}`);
  return { uploads: up, sessions: gone.length, orphans };
}

export function startCleanupLoop(store, opts = {}) {
  const tick = () => { try { runCleanup(store, opts); } catch (e) { opts.log?.(`[yzvibe] 清理失败：${e.message}`); } };
  tick();
  const timer = setInterval(tick, 6 * 3600_000);
  timer.unref?.();
  return () => clearInterval(timer);
}
