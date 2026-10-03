import {readdir, readFile, stat} from 'node:fs/promises';
import {dirname, resolve, relative, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const excluded = new Set(['.git', '.dart_tool', '.idea', '.tmp', '.tmp_dart_local',
  'node_modules', 'build', 'coverage', '.gradle', 'Pods', 'ephemeral', '.symlinks']);
const markdown = [];
async function collect(directory) {
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory() && !excluded.has(entry.name)) await collect(path);
    else if (entry.isFile() && entry.name.endsWith('.md')) markdown.push(path);
  }
}
await collect(root);
const failures = [];
let checked = 0;
for (const path of markdown) {
  const body = await readFile(path, 'utf8');
  for (const match of body.matchAll(/!?\[[^\]\n]*\]\(([^)\n]+)\)/g)) {
    const target = match[1].trim().replace(/^<|>$/g, '').split(/\s+["']/)[0];
    if (!target || /^(?:https?:|mailto:|tel:|#)/i.test(target)) continue;
    const local = decodeURIComponent(target.split('#')[0]);
    if (!local) continue;
    const resolved = resolve(dirname(path), local);
    if (resolved !== root && !resolved.startsWith(root + sep)) {
      failures.push(relative(root, path) + ': link escapes repository: ' + target);
      continue;
    }
    try { await stat(resolved); checked++; }
    catch { failures.push(relative(root, path) + ': missing target: ' + target); }
  }
  if (/file:\/\/\//i.test(body)) failures.push(relative(root, path) + ': machine-specific file link');
}
if (failures.length) {
  failures.forEach(message => console.error(message));
  process.exitCode = 1;
} else {
  console.log('Documentation check passed: ' + markdown.length + ' Markdown files, ' + checked + ' local links.');
}
