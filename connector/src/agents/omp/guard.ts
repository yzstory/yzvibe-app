// Loaded only by YzVibe's OMP child. Never installed into the user's global extensions.
export default function (pi: any) {
  const endpoint = process.env.YZVIBE_OMP_PERMISSION_URL;
  const secret = process.env.YZVIBE_OMP_SECRET;
  const sessionId = process.env.YZVIBE_OMP_SESSION;
  if (!endpoint || !secret || !sessionId) throw new Error('YzVibe permission bridge unavailable');
  pi.on('tool_call', async (event: any) => {
    try {
      const response = await fetch(endpoint, {
        method: 'POST', headers: { 'content-type': 'application/json', 'x-yzvibe-secret': secret },
        body: JSON.stringify({ sessionId, toolName: event.toolName, input: event.input }),
        signal: AbortSignal.timeout(620_000),
      });
      if (!response.ok) return { block: true, reason: 'Permission bridge unavailable' };
      const result = await response.json() as { decision?: string };
      if (result.decision !== 'allow' && result.decision !== 'allow_once') return { block: true, reason: 'Operation denied by YzVibe' };
    } catch { return { block: true, reason: 'Permission bridge disconnected' }; }
  });
  pi.on('session_start', async (_event: any, ctx: any) => {
    ctx.ui.notify('yzvibe-omp-guard-ready-v1', 'info');
  });
}
