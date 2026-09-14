import os from 'node:os';
import { ompConfiguration } from './omp-config.js';
import { OmpRPC } from './omp-rpc.js';
export const OMP_EFFORTS = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'auto'];
export const OMP_MODES = {
  normal: { flag: 'YzVibe tool guard', description: '工具执行前由手机审批；本地文件读取自动允许' },
  plan: { flag: 'YzVibe read-only tools', description: '只允许本地读取和搜索，禁止 Shell、写入与外部工具' },
  trust: { flag: 'YzVibe trust', description: '跳过工具审批，仍保留用户提问' },
};
let cached = null, flight = null;
export function modelOption(m) {
  return { id: `${m.provider}/${m.id}`, label: m.name ?? m.id,
    description: m.provider, efforts: m.thinking?.efforts ?? [], defaultEffort: m.thinking?.defaultLevel,
    contextWindow: m.contextWindow, imageInput: m.input?.includes('image') ?? false };
}
export function configuredModelOptions(models, configuration) {
  const configured = new Set(configuration.models.map(m => m.id));
  return models.map(modelOption).filter(m => configured.has(m.id));
}
export function ompCapabilities({ force = false } = {}) {
  let config; try { config = ompConfiguration(); } catch { config = { revision: null, models: [] }; }
  if (!force && cached?.revision === config.revision && cached && Date.now() - cached.at < 600_000) return Promise.resolve(cached.value);
  if (flight) return flight;
  flight = (async () => {
    const rpc = new OmpRPC({ cwd: os.tmpdir(), args: ['--no-session', '--no-tools', '--no-extensions'], timeout: 12_000 });
    rpc.on('disconnect', () => {});
    try {
      const ready = await rpc.ready;
      if (ready.supportedProtocolVersions?.includes(2)) await rpc.request('negotiate_protocol', { protocolVersion: 2 });
      const data = await rpc.request('get_available_models');
      const state = await rpc.request('get_state');
      const models = configuredModelOptions(data.models ?? [], config);
      const defaultId = state.model && `${state.model.provider}/${state.model.id}`;
      models.sort((a, b) => Number(b.id === defaultId) - Number(a.id === defaultId));
      const value = { modes: OMP_MODES, efforts: [], models, customModel: false, available: true };
      cached = { at: Date.now(), revision: config.revision, value }; return value;
    } catch {
      return { modes: OMP_MODES, efforts: [], models: [], customModel: false, available: false };
    } finally { rpc.close(); flight = null; }
  })();
  return flight;
}
