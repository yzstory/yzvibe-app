import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { parseDocument } from 'yaml';
import { badRequest } from '../requests.js';
export const ompConfigHome = () => process.env.PI_CODING_AGENT_DIR ?? path.join(os.homedir(), '.omp/agent');
const hash = s => createHash('sha256').update(s).digest('hex');
function read(home) {
  const file = path.join(home, 'models.yml');
  let text = ''; try { if (fs.statSync(file).size > 1024 * 1024) throw badRequest('OMP 配置过大，无法编辑'); text = fs.readFileSync(file, 'utf8'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const doc = parseDocument(text || 'providers: {}\n');
  if (doc.errors.length) throw badRequest('OMP 配置格式有误，请先在电脑修复');
  let data; try { data = doc.toJS({ maxAliasCount: 50 }); } catch { throw badRequest('OMP 配置无法解析'); }
  if (!data || typeof data !== 'object' || Array.isArray(data) || (data.providers != null && (typeof data.providers !== 'object' || Array.isArray(data.providers)))) throw badRequest('OMP 供应商配置格式不支持');
  return { file, text, doc, data, revision: hash(text) };
}
function publicURL(value) {
  try { const u = new URL(value); return u.username || u.password || u.search || u.hash ? '' : u.href.replace(/\/$/, ''); } catch { return ''; }
}
export function ompConfiguration(home = ompConfigHome()) {
  const { data, revision } = read(home);
  const models = [];
  for (const [providerId, provider] of Object.entries(data.providers ?? {})) {
    if (!provider || !Array.isArray(provider.models)) continue;
    for (const m of provider.models) {
      if (!m || typeof m.id !== 'string') continue;
      models.push({ id: `${providerId}/${m.id}`, providerId, modelName: m.id, label: m.name || m.id,
        baseUrl: publicURL(provider.baseUrl), keyConfigured: !!provider.apiKey,
        editable: /^[a-zA-Z0-9_-]{1,80}$/.test(providerId) && provider.api === 'openai-completions' && !!publicURL(provider.baseUrl) });
    }
  }
  return { revision, models };
}
export function ompConfigRevision(home = ompConfigHome()) { return read(home).revision; }
export function saveOmpConfiguration(input, home = ompConfigHome()) {
  const state = read(home);
  if (input.revision !== state.revision) throw badRequest('电脑端配置已变化，请刷新后重新保存', 409);
  let url; try { url = new URL(input.baseUrl); } catch { throw badRequest('Base URL 不合法'); }
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw badRequest('Base URL 只能包含协议、地址和路径，不能包含密码或查询参数');
  if (url.protocol === 'http:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) throw badRequest('远程接口请使用 HTTPS');
  const baseUrl = url.href.replace(/\/+$/, '').replace(/\/chat\/completions$/, '');
  const modelName = typeof input.modelName === 'string' ? input.modelName.trim() : '';
  if (!/^[\w.\-:/@]{1,80}$/.test(modelName)) throw badRequest('模型名称须为 1–80 位模型 ID');
  const providerId = input.providerId ?? `yzvibe-${randomUUID().slice(0,8)}`;
  if (!/^[a-zA-Z0-9_-]{1,80}$/.test(providerId) || ['__proto__', 'prototype', 'constructor'].includes(providerId)) throw badRequest('供应商 ID 不合法');
  const old = Object.hasOwn(state.data.providers ?? {}, providerId) ? state.data.providers[providerId] : null;
  if (input.providerId && (!old || old.api !== 'openai-completions')) throw badRequest('此供应商请在终端编辑');
  if (typeof input.key !== 'string' || input.key.length > 8192 || /[\r\n\x00]/.test(input.key)) throw badRequest('API Key 格式不合法');
  if (input.originalModelName && input.originalModelName !== modelName) throw badRequest('已有模型的 ID 不可修改，请添加新模型');
  const key = input.key.trim();
  if (!key && old?.baseUrl && publicURL(old.baseUrl) !== baseUrl) throw badRequest('更改接口地址时请重新填写 API Key'); if (!key && !old?.apiKey) throw badRequest('请填写 API Key');
  const models = [...(old?.models ?? [])];
  const index = models.findIndex(m => m.id === (input.originalModelName ?? modelName));
  if (input.originalModelName && index < 0) throw badRequest('原模型已变化，请刷新', 409);
  if (models.some((m,i) => i !== index && m.id === modelName)) throw badRequest('该供应商已有同名模型');
  // Preserve known capabilities only when the model identity has not changed.
  const model = index >= 0 && models[index].id === modelName ? models[index] : {
    id: modelName, name: modelName, reasoning: false, input: ['text'], contextWindow: 32768, maxTokens: 4096,
    compat: { supportsStore: false, supportsDeveloperRole: false, supportsReasoningEffort: false, maxTokensField: 'max_tokens' },
  };
  if (index >= 0) models[index] = model; else models.push(model);
  fs.mkdirSync(home, { recursive: true, mode: 0o700 });
  let keyPath, temp;
  try {
    let apiKey = old?.apiKey;
    if (key) {
      const dir = path.join(home, 'secrets'); fs.mkdirSync(dir, { recursive: true, mode: 0o700 }); fs.chmodSync(dir, 0o700);
      keyPath = path.join(dir, `${providerId}-${randomUUID()}.key`);
      fs.writeFileSync(keyPath, key, { flag: 'wx', mode: 0o600 });
      apiKey = `!cat '${keyPath.replaceAll("'", "'\\''")}'`;
    }
    state.doc.setIn(['providers', providerId], { ...old, baseUrl, api: 'openai-completions', apiKey, models });
    temp = `${state.file}.${randomUUID()}.tmp`;
    fs.writeFileSync(temp, state.doc.toString(), { flag: 'wx', mode: 0o600 });
    if (read(home).revision !== state.revision) throw badRequest('电脑端配置已变化，请刷新后重新保存', 409);
    fs.renameSync(temp, state.file); temp = null; keyPath = null;
    return ompConfiguration(home);
  } finally {
    if (temp) fs.rmSync(temp, { force: true });
    if (keyPath) fs.rmSync(keyPath, { force: true });
  }
}
