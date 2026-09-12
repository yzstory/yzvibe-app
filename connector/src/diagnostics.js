import { execFile } from 'node:child_process';

function authentication(agent) {
  return new Promise(resolve => {
    execFile(agent, agent === 'claude' ? ['auth', 'status', '--json'] : ['login', 'status'], { timeout: 4000, maxBuffer: 32 * 1024 }, (error, stdout, stderr) => {
      if (agent === 'claude') {
        try { const loggedIn = JSON.parse(stdout).loggedIn; return resolve(loggedIn === true ? 'logged_in' : loggedIn === false ? 'logged_out' : 'unknown'); } catch {}
      } else {
        const text = stdout + stderr;
        if (/not logged in/i.test(text)) return resolve('logged_out');
        if (!error && /logged in/i.test(text)) return resolve('logged_in');
      }
      resolve('unknown'); // Never expose the command output, email, organization or API key hints.
    });
  });
}

function probe(agent) {
  return new Promise(resolve => {
    execFile(agent, ['--version'], { timeout: 4000, maxBuffer: 16 * 1024 }, async (error, stdout) => {
      // Only export a version number. CLI stdout/stderr can contain account or configuration details.
      const version = String(stdout ?? '').match(/\b\d+\.\d+\.\d+(?:[-.][\w]+)*/)?.[0] ?? null;
      const auth = error ? 'unknown' : await authentication(agent);
      resolve({ id: agent, available: !error, version, status: error?.code === 'ENOENT' ? 'missing' : error ? 'unavailable' : 'ready',
        authentication: auth, advice: error ? `在电脑终端确认 ${agent} 已安装且可运行，再重启连接器。`
          : auth === 'logged_out' ? `请在电脑终端登录 ${agent} 后重试任务。`
          : auth === 'logged_in' ? '已读取本机登录状态；模型服务的实际请求仍可能受网络或额度影响。'
          : `无法确认账户状态，请在电脑终端检查 ${agent} 登录。` });
    });
  });
}

export async function diagnostics({ version, store, pusher, device, probeAgent = probe }) {
  const agents = await Promise.all(['claude', 'codex'].map(probeAgent));
  return { generatedAt: new Date().toISOString(), version, protocolVersion: 2, agents,
    push: { configured: pusher.ready, registered: Boolean(device.push?.token) },
    storage: { sessions: store.sessions.length, pendingMessages: store.sessions.reduce((n, s) => n + (s.queue?.length ?? 0), 0),
      uncertainMessages: store.sessions.reduce((n, s) => n + (s.queue ?? []).filter(q => q.deliveryState === 'uncertain').length, 0) },
    privacy: '仅包含版本、检查状态和数量；不含配对凭据、账户、路径或会话正文。' };
}
