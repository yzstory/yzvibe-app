import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const ompChildPids = new Set();

export function ompExecutable() {
  if (process.env.YZVIBE_OMP_BIN) return process.env.YZVIBE_OMP_BIN;
  const local = path.join(os.homedir(), '.local/bin/omp');
  return fs.existsSync(local) ? local : 'omp';
}

/** OMP's NDJSON protocol is not JSON-RPC. Never reuse the Codex transport. */
export class OmpRPC extends EventEmitter {
  constructor({ cwd, args = [], env = {}, spawnProcess = spawn, timeout = 30_000 } = {}) {
    super(); this.pending = new Map(); this.nextId = 0; this.closed = false; this.buffer = ''; this.timeout = timeout;
    this.ready = new Promise((resolve, reject) => { this.readyResolve = resolve; this.readyReject = reject; });
    this.ready.catch(() => {});
    this.readyTimer = setTimeout(() => this.close(new Error('OMP 启动超时')), timeout);
    this.readyTimer.unref?.();
    this.proc = spawnProcess(ompExecutable(), ['--mode', 'rpc', ...args], { cwd, env: { ...process.env, ...env }, stdio: ['pipe', 'pipe', 'pipe'] });
    if (this.proc.pid) ompChildPids.add(this.proc.pid);
    this.proc.on('close', () => ompChildPids.delete(this.proc.pid));
    this.proc.stdout.setEncoding('utf8');
    this.proc.stdout.on('data', chunk => {
      this.buffer += chunk;
      if (Buffer.byteLength(this.buffer) > 70 * 1024 * 1024) return this.close(new Error('OMP 消息超过限制'));
      let end;
      while ((end = this.buffer.indexOf('\n')) >= 0 && !this.closed) {
        const line = this.buffer.slice(0, end); this.buffer = this.buffer.slice(end + 1);
        if (!line.trim()) continue;
        try { this.frame(JSON.parse(line)); } catch { this.close(new Error('OMP 协议消息无效')); }
      }
    });
    // Drain stderr, but never forward raw logs/configuration/secrets to a phone.
    this.proc.stderr.on('data', () => {});
    this.proc.stdin.on('error', error => this.close(error));
    this.proc.on('error', error => this.close(error));
    this.proc.on('close', code => this.close(new Error(`OMP 进程已结束（${code ?? 'signal'}）`)));
  }
  frame(frame) {
    if (frame.type === 'rpc_chunk') {
      if (!this.chunks) {
        if (frame.index !== 0 || !Number.isInteger(frame.count) || frame.count < 1 || frame.count > 128 || !Number.isInteger(frame.byteLength) || frame.byteLength < 1 || frame.byteLength > 64 * 1024 * 1024) throw new Error('chunk');
        this.chunks = { id: frame.chunkId, count: frame.count, size: frame.byteLength, parts: [], bytes: 0 };
      }
      const c = this.chunks;
      if (frame.chunkId !== c.id || frame.index !== c.parts.length || frame.count !== c.count || frame.byteLength !== c.size || typeof frame.data !== 'string') throw new Error('chunk sequence');
      const bytes = Buffer.from(frame.data, 'base64'); c.bytes += bytes.length; c.parts.push(bytes);
      if (c.bytes > c.size) throw new Error('chunk overflow');
      if (c.parts.length === c.count) {
        if (c.bytes !== c.size) throw new Error('chunk length');
        this.chunks = null;
        this.frame(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(c.parts))));
      }
      return;
    }
    if (this.chunks) throw new Error('interrupted chunks');
    if (frame.type === 'ready') { clearTimeout(this.readyTimer); this.readyResolve(frame); return; }
    if (frame.type === 'response') {
      const pending = this.pending.get(frame.id);
      if (!pending) { if (frame.success === false) this.emit('lateError', frame); return; }
      clearTimeout(pending.timer); this.pending.delete(frame.id);
      if (frame.success) pending.resolve(frame.data ?? {});
      else pending.reject(Object.assign(new Error(frame.error ?? 'OMP 请求失败'), { code: frame.code }));
    } else this.emit('event', frame);
  }
  write(frame) {
    if (this.closed) throw new Error('OMP 未连接');
    const line = JSON.stringify(frame) + '\n';
    if (Buffer.byteLength(line) > 1024 * 1024) throw new Error('OMP 单次输入超过 1 MiB，请减少图片或文字大小');
    this.proc.stdin.write(line);
  }
  request(type, params = {}, timeout = this.timeout) {
    const id = `yz-${++this.nextId}`;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`OMP ${type} 响应超时`)); }, timeout);
      timer.unref?.(); this.pending.set(id, { resolve, reject, timer });
      try { this.write({ ...params, type, id }); } catch (e) { clearTimeout(timer); this.pending.delete(id); reject(e); }
    });
  }
  close(error = new Error('OMP 已停止')) {
    if (this.closed) return;
    this.closed = true; clearTimeout(this.readyTimer); this.readyReject(error);
    for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(error); }
    this.pending.clear(); this.proc.kill('SIGTERM');
    const timer = setTimeout(() => { if (this.proc.exitCode == null) this.proc.kill('SIGKILL'); }, 2000); timer.unref?.();
    this.emit('disconnect', error);
  }
}
