import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';

/** One private stdio transport. Request ids and pending approvals never cross processes. */
export class CodexRPC extends EventEmitter {
  constructor({ cwd, spawnProcess = spawn, timeout = 60_000 }) {
    super();
    this.pending = new Map(); this.nextId = 0; this.timeout = timeout;
    this.closed = false; this.buffer = ''; this.stderr = '';
    this.proc = spawnProcess('codex', ['app-server', '--listen', 'stdio://'], {
      cwd, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env },
    });
    this.proc.stdout.setEncoding('utf8');
    this.proc.stdout.on('data', data => {
      this.buffer += data;
      if (this.buffer.length > 64 * 1024 * 1024) return this.close(new Error('Codex 消息超过大小限制'));
      let end;
      while ((end = this.buffer.indexOf('\n')) >= 0) {
        const line = this.buffer.slice(0, end).trim(); this.buffer = this.buffer.slice(end + 1);
        if (!line) continue;
        let message;
        try { message = JSON.parse(line); } catch { this.close(new Error('Codex 返回了无效的协议消息')); return; }
        if (message.method) this.emit(message.id != null ? 'request' : 'notification', message);
        else {
          const pending = this.pending.get(message.id);
          if (!pending) continue;
          this.pending.delete(message.id); clearTimeout(pending.timer);
          if (message.error) pending.reject(new Error(message.error.message ?? 'Codex 请求失败'));
          else pending.resolve(message.result);
        }
      }
    });
    this.proc.stderr.on('data', data => { this.stderr = (this.stderr + data).slice(-2000); });
    this.proc.on('error', error => this.close(error));
    this.proc.stdin.on('error', error => this.close(error));
    this.proc.on('close', code => this.close(new Error(`Codex App Server 连接已结束（${code ?? 'signal'}）`)));
  }

  write(message) {
    if (this.closed) throw new Error('Codex App Server 未连接');
    this.proc.stdin.write(JSON.stringify(message) + '\n');
  }
  request(method, params, timeout = this.timeout) {
    if (this.closed) return Promise.reject(new Error('Codex App Server 未连接'));
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id); reject(new Error(`Codex ${method} 响应超时`));
      }, timeout);
      timer.unref?.(); this.pending.set(id, { resolve, reject, timer });
      try { this.write({ id, method, params }); }
      catch (error) { this.pending.delete(id); clearTimeout(timer); reject(error); }
    });
  }
  notify(method, params) { this.write({ method, params }); }
  respond(id, result) { if (!this.closed) this.write({ id, result }); }
  reject(id, message) { if (!this.closed) this.write({ id, error: { code: -32601, message } }); }
  close(error = new Error('Codex App Server 已停止')) {
    if (this.closed) return;
    this.closed = true;
    for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(error); }
    this.pending.clear();
    this.proc.kill('SIGTERM');
    const timer = setTimeout(() => { if (this.proc.exitCode == null) this.proc.kill('SIGKILL'); }, 2000);
    timer.unref?.();
    this.emit('disconnect', error);
  }
}
