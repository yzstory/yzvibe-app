import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parse } from 'yaml';
import { ompConfiguration, saveOmpConfiguration } from '../src/agents/omp-config.js';
import { createConnector } from '../src/server.js';
function fixture(t) { const home=fs.mkdtempSync(path.join(os.tmpdir(),'omp-config-'));t.after(()=>fs.rmSync(home,{recursive:true,force:true}));return home; }
function input(home, extra={}) {return {revision:ompConfiguration(home).revision,baseUrl:'https://example.com/v1/chat/completions',key:'test-not-a-real-key',modelName:'qwen-test',...extra};}
test('OMP starts empty, saves native YAML and returns no credential material',t=>{
 const home=fixture(t);assert.deepEqual(ompConfiguration(home).models,[]);
 const config=saveOmpConfiguration(input(home),home),m=config.models[0];
 assert.equal(m.baseUrl,'https://example.com/v1');assert.equal(m.modelName,'qwen-test');assert.equal(m.keyConfigured,true);
 assert.equal(JSON.stringify(config).includes('test-not-a-real-key'),false);assert.equal(JSON.stringify(config).includes('!cat'),false);
 const yaml=parse(fs.readFileSync(path.join(home,'models.yml'),'utf8'));const p=yaml.providers[m.providerId];
 assert.equal(p.api,'openai-completions');assert.equal(p.models[0].contextWindow,32768);assert.match(p.apiKey,/^!cat '/);
 const secret=path.join(home,'secrets',fs.readdirSync(path.join(home,'secrets'))[0]);
 assert.equal(fs.readFileSync(secret,'utf8'),'test-not-a-real-key');assert.equal(fs.statSync(secret).mode&0o777,0o600);
 assert.equal(fs.statSync(path.join(home,'models.yml')).mode&0o777,0o600);
});
test('OMP edit preserves terminal fields and other providers; blank Key retains secret',t=>{
 const home=fixture(t);
 fs.writeFileSync(path.join(home,'models.yml'),'customRoot: keep\nproviders:\n  other:\n    api: anthropic-messages\n    apiKey: terminal-secret\n    models:\n      - id: other-model\n');
 const added=saveOmpConfiguration(input(home),home),m=added.models.find(m=>m.editable);
 const before=parse(fs.readFileSync(path.join(home,'models.yml'),'utf8'));
 saveOmpConfiguration(input(home,{providerId:m.providerId,originalModelName:m.modelName,key:'',baseUrl:m.baseUrl}),home);
 const after=parse(fs.readFileSync(path.join(home,'models.yml'),'utf8'));
 assert.deepEqual(after.providers.other,before.providers.other);assert.equal(after.customRoot,'keep');assert.equal(after.providers[m.providerId].apiKey,before.providers[m.providerId].apiKey);
 assert.equal(JSON.stringify(ompConfiguration(home)).includes('terminal-secret'),false);
 assert.throws(()=>saveOmpConfiguration(input(home,{providerId:m.providerId,originalModelName:m.modelName,key:'',baseUrl:'https://different.example/v1'}),home),/重新填写/);
});
test('OMP rejects stale revisions, unsafe URLs and invalid config without overwriting files',t=>{
 const home=fixture(t),stale=input(home);saveOmpConfiguration(stale,home);
 const before=fs.readFileSync(path.join(home,'models.yml'),'utf8');
 assert.throws(()=>saveOmpConfiguration(stale,home),/已变化/);
 for(const baseUrl of ['http://remote.example/v1','https://u:pass@example.com','https://example.com/?key=secret'])assert.throws(()=>saveOmpConfiguration(input(home,{baseUrl}),home));
 assert.throws(()=>saveOmpConfiguration(input(home,{providerId:'../outside'}),home));
 assert.equal(fs.readFileSync(path.join(home,'models.yml'),'utf8'),before);
 fs.writeFileSync(path.join(home,'models.yml'),'providers: [invalid');assert.throws(()=>ompConfiguration(home),/格式/);
});
test('OMP configuration endpoint requires pairing and round-trips to the specified terminal home',async t=>{
 const home=fixture(t),ompHome=path.join(home,'native');
 const api=await createConnector({port:0,home:path.join(home,'connector'),ompHome,importTerminal:false,log:()=>{}});await api.listen();t.after(()=>api.close());
 const url=`http://127.0.0.1:${api.port}/agents/omp/config`;
 assert.equal((await fetch(url)).status,401);
 const token=api.store.addDevice('test').token,headers={authorization:`Bearer ${token}`,'content-type':'application/json'};
 const before=await (await fetch(url,{headers})).json();
 const r=await fetch(url,{method:'POST',headers,body:JSON.stringify({...input(ompHome),revision:before.revision})});assert.equal(r.status,200);
 assert.equal((await r.json()).models[0].modelName,'qwen-test');assert.ok(fs.existsSync(path.join(ompHome,'models.yml')));
});

test('OMP catalog excludes inherited provider catalogs and starts empty without explicit config', async ()=>{
 const {configuredModelOptions}=await import('../src/agents/omp-catalog.js');
 const native=[{provider:'xai',id:'grok-a'},{provider:'xai',id:'grok-b'},{provider:'custom',id:'qwen'}];
 assert.deepEqual(configuredModelOptions(native,{models:[]}),[]);
 assert.deepEqual(configuredModelOptions(native,{models:[{id:'custom/qwen'}]}).map(m=>m.id),['custom/qwen']);
});

test('OMP context budget can be configured and survives edits; invalid budgets do not overwrite configuration', t => {
 const home=fixture(t);
 const saved=saveOmpConfiguration(input(home,{contextWindow:262144}),home),m=saved.models[0];
 assert.equal(m.contextWindow,262144);
 const edit={providerId:m.providerId,originalModelName:m.modelName,key:'',baseUrl:m.baseUrl};
 assert.equal(saveOmpConfiguration(input(home,edit),home).models[0].contextWindow,262144);
 const before=fs.readFileSync(path.join(home,'models.yml'),'utf8');
 for(const contextWindow of [0,-1,1.5,'262144',10000001]) assert.throws(()=>saveOmpConfiguration(input(home,{...edit,contextWindow}),home),/上下文预算/);
 assert.equal(fs.readFileSync(path.join(home,'models.yml'),'utf8'),before);
 assert.equal(saveOmpConfiguration(input(home,{...edit,contextWindow:131072}),home).models[0].contextWindow,131072);
});
