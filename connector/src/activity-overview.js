const swiftDate = value => new Date(value).getTime() / 1000 - 978307200;

/** Bounded payload shared by the expanded island and lock screen. Paused queues aren't running tasks. */
export function activityOverview(sessions, now = new Date()) {
  const active = sessions.filter(s => ['running', 'waiting_approval'].includes(s.status))
    .sort((a, b) => (b.status === 'waiting_approval') - (a.status === 'waiting_approval')
      || new Date(a.runStartedAt ?? a.updatedAt) - new Date(b.runStartedAt ?? b.updatedAt) || a.id.localeCompare(b.id));
  const pending = active.reduce((n, s) => n + Math.max(s.pendingApprovals ?? 0, s.status === 'waiting_approval' ? 1 : 0), 0);
  const running = active.filter(s => s.status === 'running');
  return {
    status: pending ? 'waiting_approval' : active.length ? 'running' : 'idle',
    headline: active.length ? `${active.length} 个任务进行中` : '这一轮忙完啦',
    pendingApprovals: pending, queued: active.reduce((n, s) => n + (s.queue?.length ?? 0), 0), contextPercent: null,
    updatedAt: swiftDate(now), totalTasks: active.length,
    startedAt: running.length ? Math.min(...running.map(s => swiftDate(s.runStartedAt ?? s.updatedAt))) : null,
    tasks: active.slice(0, 3).map(s => ({ id: s.id, title: [...s.title].slice(0, 60).join(''),
      agent: s.agent === 'codex' ? 'Codex' : s.agent === 'claude' ? 'Claude' : s.agent,
      status: s.status, startedAt: swiftDate(s.runStartedAt ?? s.updatedAt) })),
  };
}
