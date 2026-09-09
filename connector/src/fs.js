// 目录浏览（用于选择工作目录）：只列目录、跳过隐藏项，可新建文件夹。需要设备 Token。
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { expandHome } from './files.js';

export function listDirectories(input) {
  const target = path.resolve(expandHome(input || os.homedir()));
  const st = fs.statSync(target);
  if (!st.isDirectory()) throw Object.assign(new Error('不是目录'), { status: 400 });
  const entries = fs.readdirSync(target, { withFileTypes: true })
    .filter((e) => e.isDirectory() && !e.name.startsWith('.') && e.name !== 'node_modules')
    .map((e) => ({ name: e.name, path: path.join(target, e.name) }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const parent = path.dirname(target);
  return { path: target, parent: parent === target ? null : parent, home: os.homedir(), entries };
}

export function makeDirectory(parent, name) {
  if (!name || /[\/\\]/.test(name) || name.startsWith('.')) throw Object.assign(new Error('文件夹名不合法'), { status: 400 });
  const target = path.join(path.resolve(expandHome(parent)), name);
  fs.mkdirSync(target, { recursive: false });
  return { path: target };
}
