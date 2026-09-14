import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { OmpRPC } from '../src/agents/omp-rpc.js';
import { ompToolDecision } from '../src/agents/omp-policy.js';
import { scanOmpSessions, parseOmpTranscript } from '../src/agents/omp-transcripts.js';
import { normalizeOptions } from '../src/agents/options.js';
import { modelOption } from '../src/agents/omp-catalog.js';
import { Store } from '../src/store.js';
import { OmpAgent } from '../src/agents/omp.js';

function transport(t) {
  const proc = new EventEmitter(); proc.stdout = new PassThrough(); proc.stderr = new PassThrough(); proc.stdin = new PassThrough(); proc.kill = () => { proc.exitCode = 0; };
  const rpc = new OmpRPC({spawnProcess:()=>proc,timeout:500}); rpc.on('disconnect',()=>{}); t.after(()=>rpc.close());
  const frame=e=>proc.stdout.write(JSON.stringify(e)+'\n');
  return {rpc,frame,proc};
}
test('OMP transport correlates responses, distinguishes late errors, and fails pending requests on disconnect', async t => {
  const {rpc,frame}=transport(t); frame({type:'ready',protocolVersion:1}); await rpc.ready;
  const a=rpc.request('get_state'), b=rpc.request('get_available_models');
  frame({type:'response',id:'yz-2',success:true,data:{models:[]}}); frame({type:'response',id:'yz-1',success:true,data:{sessionId:'s'}});
  assert.equal((await a).sessionId,'s'); assert.deepEqual((await b).models,[]);
  let late; rpc.on('lateError',e=>late=e); frame({type:'response',id:'yz-1',success:false,error:'late'}); assert.equal(late.error,'late');
  const pending=rpc.request('prompt'); rpc.close(); await assert.rejects(pending,/停止/);
});
test('OMP v2 frames reassemble Unicode and reject interrupted sequences', async t=>{
  const {rpc,frame}=transport(t); frame({type:'ready'}); await rpc.ready;
  const result=rpc.request('get_messages'); const data=Buffer.from(JSON.stringify({type:'response',id:'yz-1',success:true,data:{text:'柚子🍊'}}));
  for(let i=0;i<2;i++)frame({type:'rpc_chunk',chunkId:'c',index:i,count:2,byteLength:data.length,data:data.subarray(i===0?0:13,i===0?13:data.length).toString('base64')});
  assert.equal((await result).text,'柚子🍊');
  frame({type:'rpc_chunk',chunkId:'bad',index:0,count:2,byteLength:2,data:Buffer.from('a').toString('base64')}); frame({type:'agent_start'});
  assert.equal(rpc.closed,true);
});
test('OMP policy enforces Plan before rules/Trust and never treats executable URI reads as local',()=>{
  assert.equal(ompToolDecision('plan','bash',{command:'echo hello'}),'deny');
  assert.equal(ompToolDecision('plan','read',{path:'xd://exec'}),'deny');
  assert.equal(ompToolDecision('plan','write',{path:'/tmp/a'}),'deny');
  assert.equal(ompToolDecision('normal','write',{path:'/tmp/a'}),'ask');
  assert.equal(ompToolDecision('normal','task',{}),'ask');
  assert.equal(ompToolDecision('plan','read',{path:'/tmp/a'}),'allow');
  assert.equal(ompToolDecision('trust','write',{}),'allow');
});
test('OMP models preserve provider identity and actual effort support',()=>{
  assert.deepEqual(modelOption({provider:'proxy',id:'qwen',input:['text']}).efforts,[]);
  assert.equal(modelOption({provider:'proxy',id:'qwen'}).id,'proxy/qwen');
  assert.equal(normalizeOptions({effort:'ultra'},'omp').effort,undefined);
  assert.equal(normalizeOptions({effort:'minimal'},'omp').effort,'minimal');
});
test('OMP imports the active branch, keeps tool results and reads renamed sessions',t=>{
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'omp-history-')); t.after(()=>fs.rmSync(home,{recursive:true,force:true}));
  const dir=path.join(home,'sessions','cwd');fs.mkdirSync(dir,{recursive:true}); const file=path.join(dir,'session.jsonl');
  fs.writeFileSync(file,[{type:'session',id:'native',cwd:home,timestamp:new Date().toISOString()},
    {type:'message',id:'a',parentId:null,message:{role:'user',content:'hello'}},
    {type:'message',id:'b',parentId:'a',message:{role:'assistant',content:[{type:'text',text:'discarded'}]}},
    {type:'message',id:'c',parentId:'a',message:{role:'assistant',content:[{type:'toolCall',id:'tool',name:'read',arguments:{path:'a'}}]}},
    {type:'message',id:'d',parentId:'c',message:{role:'toolResult',toolCallId:'tool',content:[{type:'text',text:'file'}]}},
    {type:'title_change',id:'e',parentId:'d',title:'renamed'}].map(JSON.stringify).join('\n'));
  const list=scanOmpSessions({ompHome:home});assert.equal(list[0].id,'omp:native');assert.equal(list[0].title,'renamed');
  const messages=parseOmpTranscript(file,list[0].id);assert.equal(messages.length,2);assert.equal(messages[1].toolCalls[0].output,'file');
});
test('OMP ignores intermediate agent_end and retains failed tool state after terminal completion',async t=>{
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'omp-agent-')); const store=new Store(home),session=store.createSession({agent:'omp',cwd:home});
  const rpc=new EventEmitter();rpc.request=async()=>({});rpc.close=()=>{};
  const agent=new OmpAgent({session,store});agent.rpc=rpc;
  agent.active={prefix:'test',messages:new Set(),done:new Set(),usage:[],started:Date.now()};store.setStatus(session.id,'running');
  t.after(()=>{agent.dispose();fs.rmSync(home,{recursive:true,force:true});});
  agent.event({type:'message_start',message:{role:'assistant'}});
  agent.event({type:'message_update',assistantMessageEvent:{type:'text_delta',delta:'Hello'}});
  agent.event({type:'message_end',message:{role:'assistant',content:[{type:'text',text:'Hello world'}]}});
  agent.event({type:'tool_execution_start',toolCallId:'t',toolName:'bash',args:{command:'false'}});
  agent.event({type:'tool_execution_end',toolCallId:'t',toolName:'bash',isError:true,result:{content:[{type:'text',text:'failed'}],details:{exitCode:1}}});
  agent.event({type:'agent_end',isTerminal:false});assert.equal(session.status,'running');
  agent.event({type:'agent_end'});await new Promise(r=>setImmediate(r));
  assert.equal(session.status,'idle');assert.equal(store.messagesOf(session.id)[0].text,'Hello world');assert.equal(store.messagesOf(session.id)[0].toolCalls[0].state,'error');
});

test('OMP imports image blobs without allowing traversal or oversized data', async t => {
  const { importOmpImages } = await import('../src/agents/omp-transcripts.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omp-blobs-')); t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const hash = 'a'.repeat(64); fs.writeFileSync(path.join(dir,hash),Buffer.from([1,2,3]));
  const uploads=[]; const add=(name,mime,bytes)=>{uploads.push({name,mime,bytes});return 'image-id';};
  assert.deepEqual(importOmpImages([{type:'image',mimeType:'image/png',data:`blob:sha256:${hash}`}],add,dir),['image-id']);
  assert.deepEqual([...uploads[0].bytes],[1,2,3]);
  assert.deepEqual(importOmpImages([{type:'image',mimeType:'image/png',data:'blob:sha256:../../secret'}],add,dir),[]);
});
test('OMP interruption only resumes the queue for explicit send-now; disconnect marks tools failed', async t=>{
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'omp-stop-'));t.after(()=>fs.rmSync(home,{recursive:true,force:true}));
  const store=new Store(home),s=store.createSession({agent:'omp',cwd:home});
  const agent=new OmpAgent({session:s,store});agent.rpc={request:async()=>({}),close(){}};
  const begin=()=>{agent.active={prefix:'run',messages:new Set(),done:new Set(),usage:[],started:Date.now()};store.setStatus(s.id,'running');};
  begin();agent.stop({resumeQueue:true});await agent.finish('interrupted');assert.equal(Boolean(s.queuePaused),false);
  store.enqueue(s.id,{text:'queued'});begin();agent.stop();await agent.finish('interrupted');assert.equal(s.queuePaused,true);
  begin();agent.event({type:'tool_execution_start',toolCallId:'t',toolName:'write',args:{path:'x'}});agent.fail(new Error('Disconnected'));
  assert.equal(store.messagesOf(s.id).flatMap(m=>m.toolCalls).find(t=>t.name==='write').state,'error');assert.equal(s.status,'error');
});

test('OMP surfaces compaction warnings and native abort without an empty success bubble', async t => {
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'omp-aborted-'));t.after(()=>fs.rmSync(home,{recursive:true,force:true}));
 const store=new Store(home),s=store.createSession({agent:'omp',cwd:home});
 const agent=new OmpAgent({session:s,store});agent.rpc={request:async()=>({}),close(){}};
 agent.active={prefix:'run',messages:new Set(),done:new Set(),usage:[],started:Date.now()};
 store.setStatus(s.id,'running');store.enqueue(s.id,{text:'later'});
 agent.event({type:'auto_compaction_end',result:{warning:'freed too little'}});
 assert.match(store.messagesOf(s.id)[0].text,/上下文压缩/);
 assert.equal(s.status,'running');
 agent.event({type:'message_start',message:{role:'assistant'}});
 agent.event({type:'message_end',message:{role:'assistant',content:[],stopReason:'aborted',errorMessage:'Interrupted by user'}});
 agent.event({type:'agent_end',isTerminal:true});await new Promise(r=>setImmediate(r));
 assert.equal(s.status,'idle');assert.equal(s.queuePaused,true);
 assert.match(store.messagesOf(s.id).at(-1).text,/本轮已中断/);
 assert.equal(store.messagesOf(s.id).some(m=>m.role==='assistant'&&!m.text&&!m.toolCalls.length),false);
 agent.dispose();
});
