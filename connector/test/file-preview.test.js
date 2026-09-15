import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { statFile, resolveReadable, mimeOf } from '../src/files.js';
import { createConnector } from '../src/server.js';
test('generated temporary Markdown/images/video are readable but credentials and symlink escapes remain blocked',t=>{
 const root=fs.mkdtempSync(path.join(os.homedir(),'.yzvibe-preview-')),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'yzvibe-preview-'));
 t.after(()=>{fs.rmSync(root,{recursive:true,force:true});fs.rmSync(tmp,{recursive:true,force:true});});
 for (const [name,kind] of [['报告 A&B.markdown','markdown'],['clip.mp4','video'],['photo.png','image']]) {
  const file=path.join(tmp,name);fs.writeFileSync(file,'fixture');const meta=statFile(root,file);assert.equal(meta.kind,kind);assert.equal(meta.textual,kind==='markdown');
 }
 for(const secret of ['~/.omp/agent/secrets/provider.key','~/.appstoreconnect/credentials.env','/etc/passwd'])assert.throws(()=>resolveReadable(root,secret),e=>e.status===403);
 fs.symlinkSync('/etc/passwd',path.join(tmp,'escape.md'));assert.throws(()=>resolveReadable(root,path.join(tmp,'escape.md')),e=>e.status===403);
 assert.equal(mimeOf('clip.MOV'),'video/quicktime');assert.equal(mimeOf('clip.mp4'),'video/mp4');
});
test('authenticated media transfer preserves special filenames and exact bytes',async t=>{
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'yzvibe-media-http-'));t.after(()=>fs.rmSync(home,{recursive:true,force:true}));
 const api=await createConnector({port:0,home,importTerminal:false,log:()=>{}});await api.listen();t.after(()=>api.close());
 const token=api.store.addDevice('fixture').token;const s=api.store.createSession({agent:'mock',cwd:home});
 const filename='视频 #1&A.mp4',bytes=Buffer.from([0,1,2,255]);fs.writeFileSync(path.join(home,filename),bytes);
 const url=new URL(`http://127.0.0.1:${api.port}/files/download`);url.searchParams.set('sessionId',s.id);url.searchParams.set('path',filename);
 assert.equal((await fetch(url)).status,401);
 const r=await fetch(url,{headers:{authorization:`Bearer ${token}`}});assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'video/mp4');assert.deepEqual(Buffer.from(await r.arrayBuffer()),bytes);
});

test('HTML preview serves scoped resources with correct MIME and rejects authentication/path escapes', async t => {
 const home = fs.mkdtempSync(path.join(os.tmpdir(), 'yzvibe-web-'));
 t.after(() => fs.rmSync(home, { recursive: true, force: true }));
 const api = await createConnector({port:0,home,importTerminal:false,log:()=>{}}); await api.listen(); t.after(()=>api.close());
 const token = api.store.addDevice('fixture').token;
 const s = api.store.createSession({agent:'mock',cwd:home});
 const page = path.join(home,'pages'); fs.mkdirSync(page); fs.mkdirSync(path.join(page,'assets'));
 fs.writeFileSync(path.join(page,'index.html'), '<h1>Rendered</h1>');
 fs.writeFileSync(path.join(page,'assets','样式 #1.css'), 'body{color:red}');
 fs.writeFileSync(path.join(home,'outside.json'), '{}');
 fs.symlinkSync(path.join(home,'outside.json'),path.join(page,'escape.json'));
 fs.writeFileSync(path.join(page,'.env'),'FIXTURE_ONLY');
 const url = new URL(`http://127.0.0.1:${api.port}/files/web-preview`);
 url.searchParams.set('sessionId',s.id); url.searchParams.set('entry','pages/index.html');
 const get = resource => {url.searchParams.set('resource',resource); return fetch(url,{headers:{authorization:`Bearer ${token}`}});};
 assert.equal((await fetch(url)).status,401);
 let r = await get('index.html'); assert.equal(r.status,200); assert.equal(r.headers.get('content-type'),'text/html'); assert.match(await r.text(), /Rendered/);
 r = await get('assets/样式 #1.css'); assert.equal(r.status,200); assert.equal(r.headers.get('content-type'),'text/css');
 for (const resource of ['../outside.json','escape.json','.env']) assert.equal((await get(resource)).status,403);
 assert.equal((await get('missing.png')).status,404);
});
