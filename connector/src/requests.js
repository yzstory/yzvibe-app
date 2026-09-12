// Bounded decoding before authentication (including the public pairing endpoint).
export const JSON_LIMIT = 256 * 1024;
export const UPLOAD_LIMIT = 20 * 1024 * 1024;
export const badRequest = (message, status = 400, code = 'invalid_request') => Object.assign(new Error(message), { status, code });

export function readBody(req, limit = JSON_LIMIT) {
  return new Promise((resolve, reject) => {
    let chunks = [], bytes = 0, settled = false;
    const fail = error => {
      if (settled) return;
      settled = true; chunks = []; reject(error);
      req.resume(); // Discard remaining bytes without retaining them; response closes oversized connections.
    };
    req.on('error', fail);
    req.on('aborted', () => fail(badRequest('请求已中断')));
    if (Number(req.headers['content-length']) > limit) {
      fail(badRequest('请求内容超过大小限制', 413, 'payload_too_large')); return;
    }
    req.on('data', chunk => {
      if (settled) return;
      bytes += chunk.length;
      if (bytes > limit) { fail(badRequest('请求内容超过大小限制', 413, 'payload_too_large')); return; }
      chunks.push(chunk);
    });
    req.on('end', () => { if (!settled) { settled = true; resolve(Buffer.concat(chunks)); } });
  });
}

export async function readJSON(req) {
  const bytes = await readBody(req);
  let body;
  try { body = bytes.length ? JSON.parse(bytes) : {}; } catch { throw badRequest('JSON 不合法'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw badRequest('请求须为 JSON 对象');
  return body;
}

export function messageInput(body, store, { requireID = false } = {}) {
  const { text = '', attachments = [], mode = 'auto', clientMessageId } = body;
  if (typeof text !== 'string' || text.length > 64_000) throw badRequest('消息须为不超过 64,000 字符的文字');
  if (!Array.isArray(attachments) || attachments.length > 6 || attachments.some(id => typeof id !== 'string' || !/^[\w-]{1,100}$/.test(id))) throw badRequest('最多附带 6 张有效图片');
  if (!['auto', 'queue', 'now'].includes(mode)) throw badRequest('发送模式不合法');
  if (requireID && (typeof clientMessageId !== 'string' || !/^[\w-]{8,100}$/.test(clientMessageId))) throw badRequest('缺少有效的消息 ID');
  if (clientMessageId != null && (typeof clientMessageId !== 'string' || !/^[\w-]{8,100}$/.test(clientMessageId))) throw badRequest('消息 ID 不合法');
  if (!text.trim() && !attachments.length) throw badRequest('消息不能为空');
  // Already accepted requests must remain queryable after an upload expires.
  if (store && attachments.some(id => !store.upload(id)?.mime?.startsWith('image/'))) throw badRequest('附带图片已失效，请重新选择', 422, 'attachment_missing');
  return { text, attachments, mode, clientMessageId };
}
