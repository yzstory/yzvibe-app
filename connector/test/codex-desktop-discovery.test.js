import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { scanCodexSessions } from '../src/transcripts.js';

test('Desktop title index discovers large first messages and refreshes names without a rollout change', t => {
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'codex-desktop-'));
 t.after(()=>fs.rmSync(home,{recursive:true,force:true}));
 const dir=path.join(home,'sessions','2026','09','14');fs.mkdirSync(dir,{recursive:true});
 fs.writeFileSync(path.join(dir,'rollout-desktop.jsonl'),[
  {type:'session_meta',payload:{id:'desktop',cwd:home,source:'vscode'}},
  {type:'response_item',payload:{type:'message',role:'user',content:[{type:'input_text',text:'Analyze this screenshot'},{type:'input_image',image_url:'data:image/png;base64,'+'a'.repeat(2_000_000)}]}},
 ].map(JSON.stringify).join('\n'));
 const index=path.join(home,'session_index.jsonl');
 assert.equal(scanCodexSessions({codexHome:home}).length,0);
 fs.writeFileSync(index,JSON.stringify({id:'desktop',thread_name:'Desktop conversation'})+'\n');
 assert.equal(scanCodexSessions({codexHome:home})[0].title,'Desktop conversation');
 fs.appendFileSync(index,JSON.stringify({id:'desktop',thread_name:'Renamed on desktop'})+'\n{"id":');
 const sessions=scanCodexSessions({codexHome:home});
 assert.equal(sessions.length,1);assert.equal(sessions[0].title,'Renamed on desktop');
 assert.equal(sessions[0].agentSessionId,'desktop');
});
