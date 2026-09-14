/** The read tool also accepts executable virtual URIs; only plain local paths bypass approval. */
export function localRead(tool, input = {}) {
  if (!['read', 'grep', 'find', 'ls'].includes(tool)) return false;
  const values = [input.path, input.file, ...(Array.isArray(input.paths) ? input.paths : [])].filter(x => x != null);
  return values.every(x => typeof x === 'string' && !/[a-z][a-z0-9+.-]*:\/\//i.test(x));
}
export function ompToolDecision(mode, tool, input) {
  if (mode === 'trust') return 'allow';
  if (localRead(tool, input)) return 'allow';
  return mode === 'plan' ? 'deny' : 'ask';
}
