// PRD-2.3 §19.6 port check, page side: renders the 60 new items with the
// approved JavaScript (design/skins_v23) into build/skins_port/js_<t>.png.
// Usage (from flappy_spikes/): node tool/skins_port/render_js.mjs [t] [playwright index.mjs]
import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const t = process.argv[2] || '1.3';
const extra = process.env.EXTRA || '';
const pw = process.argv[3] || '/home/killerhis/.local/share/mise/installs/npm-playwright/1.63.0/node_modules/.mise/playwright@1.63.0/node_modules/playwright/index.mjs';
const { chromium } = await import(pw);
// The workspace design folder (outside git): the first ancestor that has
// design/skins_v23, or $DESIGN.
let design = process.env.DESIGN;
for (let d = here; !design && d !== '/'; d = dirname(d)) {
  if (existsSync(resolve(d, 'design/skins_v23/parts/hats.js'))) design = resolve(d, 'design');
}
const b = await chromium.launch({ executablePath: '/usr/bin/chromium', args: ['--allow-file-access-from-files'] });
const p = await b.newPage({ deviceScaleFactor: 1 });
const errs = []; p.on('pageerror', e => errs.push(String(e))); p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
await p.goto('file://' + resolve(here, 'harness.html') + '?design=' + encodeURIComponent(design) + '&t=' + t + extra);
await p.waitForFunction(() => window.__ready, null, { timeout: 20000 });
const url = await p.evaluate(() => window.__png);
mkdirSync('build/skins_port', { recursive: true });
writeFileSync(process.env.OUT || `build/skins_port/js_${t}.png`, Buffer.from(url.split(',')[1], 'base64'));
console.log(errs.length ? 'ERRORS:\n' + errs.join('\n') : 'ok', `build/skins_port/js_${t}.png`);
await b.close();
