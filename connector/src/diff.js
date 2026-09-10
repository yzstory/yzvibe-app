// 极简行级 diff（LCS），用于把 Edit / Write 的改动在手机上显示成 +/- 行。
const MAX_LINES = 400;

function lcs(a, b) {
  const n = a.length, m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  return dp;
}

/** 返回 `[{ type: '+'|'-'|' ', text }]`；行数超过上限时截断。 */
export function lineDiff(oldText = '', newText = '') {
  const a = String(oldText).split('\n'), b = String(newText).split('\n');
  if (a.length + b.length > 2 * MAX_LINES) {
    return [...a.slice(0, MAX_LINES).map((text) => ({ type: '-', text })), ...b.slice(0, MAX_LINES).map((text) => ({ type: '+', text }))];
  }
  const dp = lcs(a, b);
  const out = [];
  let i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) { out.push({ type: ' ', text: a[i] }); i++; j++; }
    else if (dp[i + 1][j] >= dp[i][j + 1]) { out.push({ type: '-', text: a[i] }); i++; }
    else { out.push({ type: '+', text: b[j] }); j++; }
  }
  while (i < a.length) out.push({ type: '-', text: a[i++] });
  while (j < b.length) out.push({ type: '+', text: b[j++] });
  return out;
}

/** 只保留改动行前后各 ctx 行，中间用 `…` 折叠；再拼成带 +/- 前缀的文本。 */
export function diffText(oldText, newText, { context = 2, maxChars = 4000 } = {}) {
  const rows = lineDiff(oldText, newText);
  if (!rows.some((r) => r.type !== ' ')) return '';      // 没有改动就不显示 diff
  const keep = new Set();
  rows.forEach((r, i) => {
    if (r.type === ' ') return;
    for (let k = Math.max(0, i - context); k <= Math.min(rows.length - 1, i + context); k++) keep.add(k);
  });
  const out = [];
  let gap = false;
  rows.forEach((r, i) => {
    if (keep.has(i)) { out.push(`${r.type}${r.text}`); gap = false; }
    else if (!gap) { out.push('…'); gap = true; }
  });
  const text = out.join('\n');
  return text.length > maxChars ? `${text.slice(0, maxChars)}\n…（已截断）` : text;
}

/** Edit / Write / MultiEdit 的输入 → 可读的改动预览。 */
export function diffFromToolInput(name, input = {}) {
  if (name === 'Write') {
    const body = String(input.content ?? '');
    return diffText('', body);
  }
  if (name === 'Edit') {
    if (input.replace_all && input.old_string == null) return null;
    return diffText(String(input.old_string ?? ''), String(input.new_string ?? ''));
  }
  if (name === 'MultiEdit' && Array.isArray(input.edits)) {
    return input.edits.map((e, i) => `@@ 第 ${i + 1} 处 @@\n${diffText(String(e.old_string ?? ''), String(e.new_string ?? ''), { maxChars: 1200 })}`).join('\n').slice(0, 4000);
  }
  if (name === 'NotebookEdit') return diffText(String(input.old_source ?? ''), String(input.new_source ?? ''));
  return null;
}
