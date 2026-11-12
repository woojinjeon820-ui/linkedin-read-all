/*
 * Builds an Aside REPL script that injects the extension (with an in-memory chrome.storage
 * shim) into a page and clicks through every flow. Used against the offline fixture:
 *   B64=$(base64 < tests/fixture/notifications.html | tr -d '\\n')
 *   node tests/live/build-fixture-harness.js extension "data:text/html;base64,$B64" force > /tmp/h.js
 *   aside repl "$(cat /tmp/h.js)"
 */
const fs = require('fs'), path = require('path');
const ext = process.argv[2]; const URL_ = process.argv[3]; const FORCE = process.argv[4] === 'force';
const shim = `(() => { if (globalThis.chrome && chrome.storage && chrome.storage.local && chrome.runtime && chrome.runtime.id) return;
  const mem = {}; const ls = [];
  globalThis.chrome = Object.assign(globalThis.chrome || {}, {
    storage: { local: { get(k, cb) { const out = {}; for (const key of [].concat(k)) out[key] = mem[key]; cb(out); }, set(o) { const ch = {}; for (const k in o) { ch[k] = {oldValue: mem[k], newValue: JSON.parse(JSON.stringify(o[k]))}; mem[k] = ch[k].newValue; } ls.forEach(f => f(ch, 'local')); } },
      onChanged: { addListener(f) { ls.push(f); } } },
    runtime: { onMessage: { addListener() {} }, sendMessage() {} } }); })();`;
const code = shim + fs.readFileSync(path.join(ext, 'src/early.js'), 'utf8') + fs.readFileSync(path.join(ext, 'src/core.js'), 'utf8') + fs.readFileSync(path.join(ext, 'src/content.js'), 'utf8');
const css = fs.readFileSync(path.join(ext, 'src/content.css'), 'utf8');
const cssInject = `(() => { const s = new CSSStyleSheet(); s.replaceSync(${JSON.stringify(css)}); document.adoptedStyleSheets = [...document.adoptedStyleSheets, s]; })();`;
const repl = `
const P = await openTab(${JSON.stringify(URL_)});
await sleep(3000);
console.log('pwd', typeof pwd === 'function' ? pwd() : pwd, P.url().slice(0, 60));
if (${FORCE}) await P.evaluate(() => { window.__lnraForcePage = true; });
await P.evaluate(${JSON.stringify(cssInject)});
await P.evaluate(${JSON.stringify(code)});
await sleep(1500);
const stat = () => P.evaluate(() => { const d = __lnra.getData(); const o = __lnra.getOrder(); return { loaded: o.length, unread: o.filter(k => d.items[k] && d.items[k].s === 'u').length, kept: o.filter(k => d.items[k] && d.items[k].k === 1).length, cards: document.querySelectorAll('[data-lnra-card]').length, marks: document.querySelectorAll('.lnra-mark').length, bar: !!document.getElementById('lnra-host'), selected: __lnra.selected.size, barText: document.getElementById('lnra-host') && [...document.getElementById('lnra-host').shadowRoot.querySelectorAll('.bar:not([hidden]) .count, .toast.on .msg')].map(e => e.textContent).join(' / ') }; });
const shadowClick = (sel) => P.evaluate((s) => document.getElementById('lnra-host').shadowRoot.querySelector(s).click(), sel);
await fs.mkdir('./artifacts', { recursive: true });
console.log('1 initial', JSON.stringify(await stat()));
console.log('sample keys', JSON.stringify(await P.evaluate(() => __lnra.getOrder().slice(0, 6))));
await P.screenshot({ path: './artifacts/1-initial.png' });
const cardsL = P.locator('[data-lnra-card]');
if (${FORCE}) { await cardsL.nth(7).click(); console.log('1b normal click marks read', JSON.stringify(await stat()), 'nav:', await P.evaluate(() => window.__navigatedTo)); await P.evaluate(() => { window.__navigatedTo = undefined; }); }
await shadowClick('.select');
const cardsL_ignore = P.locator('[data-lnra-card]');
await cardsL.nth(1).click();
await cardsL.nth(3).click({ modifiers: ['Shift'] });
console.log('2 selected 1..3 via real clicks', JSON.stringify(await stat()), 'nav (should be undefined):', await P.evaluate(() => window.__navigatedTo));
await P.screenshot({ path: './artifacts/2-selecting.png' });
await shadowClick('.except');
await sleep(300);
console.log('3 read all except selected', JSON.stringify(await stat()));
await P.screenshot({ path: './artifacts/3-except.png' });
await shadowClick('.undo');
await sleep(300);
console.log('4 undo', JSON.stringify(await stat()));
await shadowClick('.all');
await sleep(300);
console.log('5 mark all read', JSON.stringify(await stat()));
await shadowClick('.select');
await cardsL.nth(0).click();
await shadowClick('.sel-unread');
await sleep(300);
console.log('6 mark one unread', JSON.stringify(await stat()));
await shadowClick('.select');
await shadowClick('.q-all');
console.log('7 quick-select all', JSON.stringify(await stat()));
await shadowClick('.all-unread');
await sleep(300);
console.log('8 all unread', JSON.stringify(await stat()));
await P.keyboard.press('Escape');
await P.locator('main').evaluate(m => m.scrollTo(0, m.scrollHeight));
await sleep(2500);
console.log('9 after scroll (lazy-load)', JSON.stringify(await stat()));
await P.evaluate(() => document.querySelector('main').scrollTo(0, 0));
await P.screenshot({ path: './artifacts/4-final.png' });
`;
process.stdout.write(repl);
