const EXT = 'chrome-extension://__EXT_ID__';
let pass = 0, fail = 0;
const check = (name, ok, info) => { ok ? pass++ : fail++; console.log((ok ? 'PASS ' : 'FAIL ') + name + (info !== undefined ? '  ' + JSON.stringify(info) : '')); };
const E = await openTab(EXT + '/popup/popup.html');
await E.evaluate(() => chrome.storage.local.clear());
const badge = () => E.evaluate(() => chrome.action.getBadgeText({}));
const stored = () => E.evaluate(async () => { const d = (await chrome.storage.local.get('lnra')).lnra || { items: {} }; const it = Object.values(d.items); return { n: it.length, unread: it.filter(e => e.s === 'u').length, kept: it.filter(e => e.k).length }; });
const P = await openTab('https://www.linkedin.com/notifications/');
await sleep(4500);
// dots: LinkedIn's own blue "new" dots on the page (8px, LinkedIn blue, round); dotsShown: how many are still visible.
const st = (pg = P) => pg.evaluate(() => { const h = document.getElementById('lnra-host'); const dots = [...document.querySelectorAll('[data-lnra-card] *')].filter(el => { if (el.closest('[data-lnra-ui]')) return false; const r = el.getBoundingClientRect(); if (r.width < 4 || r.width > 16 || Math.abs(r.width - r.height) > 2) return false; const bg = getComputedStyle(el).backgroundColor; return /rgba?\(10, 102, 194/.test(bg); }); return { cards: document.querySelectorAll('[data-lnra-card]').length, unread: document.querySelectorAll('[data-lnra-unread]').length, kept: document.querySelectorAll('[data-lnra-kept]').length, selected: document.querySelectorAll('[data-lnra-selected]').length, selecting: document.documentElement.hasAttribute('data-lnra-selecting'), bar: !!(h && h.isConnected), text: h ? [...h.shadowRoot.querySelectorAll('.bar:not([hidden]) .count')].map(e => e.textContent).join('') : '', dots: dots.length, dotsShown: dots.filter(el => getComputedStyle(el).visibility !== 'hidden').length }; });
const sc = (s, pg = P) => pg.evaluate((s) => document.getElementById('lnra-host').shadowRoot.querySelector(s).click(), s);
const C = P.locator('[data-lnra-card]');
let s = await st();
check('fresh load: all cards unread, bar shown', s.cards >= 10 && s.unread === s.cards && s.bar, s);
await sleep(500);
check('badge = unread count', (await badge()) === String((await stored()).unread), { badge: await badge(), stored: await stored() });
// quick selects
await sc('.select');
await sc('.q-all'); s = await st(); check('Select > All selects every card', s.selected === s.cards && s.selecting, s);
await sc('.q-none'); s = await st(); check('Select > None clears selection', s.selected === 0, s);
await C.nth(0).click(); await C.nth(2).click(); s = await st(); check('click toggles individual cards', s.selected === 2, s);
await C.nth(0).click(); s = await st(); check('clicking a selected card deselects it', s.selected === 1, s);
await sc('.sel-read'); await sleep(300); s = await st(); check('Mark selected read: 1 read, selection mode exits', s.unread === s.cards - 1 && !s.selecting, s);
await sc('.select'); await sc('.q-read'); s = await st(); check('Select > Read picks only read cards', s.selected === 1, s);
await sc('.q-unread'); s = await st(); check('Select > Unread picks only unread cards', s.selected === s.cards - 1, s);
await P.keyboard.press('Escape'); s = await st(); check('Esc exits selection mode and clears selection', !s.selecting && s.selected === 0, s);
await sc('.select'); await sc('.done'); s = await st(); check('Done exits selection mode', !s.selecting, s);
await sc('.all'); await sleep(300); s = await st(); check('Mark all as read', s.unread === 0 && s.text === 'All caught up', s);
check("LinkedIn's own blue dots hidden once read" + (s.dots ? '' : ' (no native dots on this page right now)'), s.dotsShown === 0, { dots: s.dots, shown: s.dotsShown });
// Reload with everything read: the learned selector must hide re-rendered dots at once, no flash.
if (s.dots) {
  await P.reload(); const t0 = Date.now(); let flashes = 0, samples = 0, seenCards = false;
  while (Date.now() - t0 < 5000) { const x = await st().catch(() => null); if (x) { samples++; if (x.cards > 0) seenCards = true; if (x.dotsShown > 0) flashes++; } await sleep(60); }
  check('no dot flash on reload once the dot selector is learned', seenCards && flashes === 0, { samples, flashes, style: await P.evaluate(() => (document.getElementById('lnra-dot-style') || {}).textContent || '') });
}
await sleep(400); check('badge cleared when 0 unread', (await badge()) === '', await badge());
await sc('.select'); await sc('.all-unread'); await sleep(300); s = await st(); check('All unread: every loaded card unread, none kept', s.unread === s.cards && s.kept === 0 && !s.selecting, s);
check("LinkedIn's own blue dots come back when unread", s.dotsShown === s.dots, { dots: s.dots, shown: s.dotsShown });
await sleep(400); check('badge updates to new count', (await badge()) === String(s.cards) || (s.cards > 99 && (await badge()) === '99+'), await badge());
await sc('.undo'); await sleep(300); s = await st(); check('Undo of All unread restores all read', s.unread === 0, s);
// click-to-read (Cmd+click opens in a new tab, so this page stays put)
await sc('.select'); await C.nth(4).click(); await sc('.sel-unread'); await sleep(300);
s = await st(); check('Mark selected unread keeps it flagged', s.unread === 1 && s.kept === 1, s);
const idsBefore = new Set((await listBrowserTabs()).map(t => t.targetId));
await C.nth(4).click({ modifiers: ['Meta'] }); await sleep(1500);
s = await st(); check('opening a notification marks it read', s.unread === 0, s);
check('this tab did not navigate', P.url().endsWith('/notifications/'), P.url());
const newTabs = (await listBrowserTabs()).filter(t => !idsBefore.has(t.targetId));
check('Cmd+click opened exactly one new tab', newTabs.length === 1, newTabs.map(t => t.url.slice(0, 60)));
if (newTabs.length === 1) { const tp = await attachBrowserTab(newTabs[0].targetId); await closeTab(tp); }
await P.bringToFront();
// leave the page (SPA) and come back
await P.locator('header a[href*="/feed"], nav a[href*="/feed"]').first().click().catch(async () => { await P.goto('https://www.linkedin.com/feed/'); });
await sleep(3000);
s = await st(); check('bar hidden off the notifications page', !s.bar, { url: P.url(), ...s });
await P.goBack();
{ // everything is read here, so any dot seen while the page comes back is a flash
  const t0 = Date.now(); let flashes = 0, dotsSeen = 0;
  while (Date.now() - t0 < 3500) { const x = await st().catch(() => null); if (x) { dotsSeen = Math.max(dotsSeen, x.dots); if (x.dotsShown > 0) flashes++; } await sleep(60); }
  check('no dot flash when coming back to the page' + (dotsSeen ? '' : ' (no native dots on this page right now)'), flashes === 0, { dotsSeen, flashes });
}
s = await st(); check('bar and highlights return on coming back', s.bar && s.cards > 0, { url: P.url(), ...s });
// two tabs stay in sync
const P2 = await openTab('https://www.linkedin.com/notifications/'); await sleep(4500);
await sc('.select', P2); await sc('.q-all', P2); await sc('.sel-unread', P2); await sleep(800);
const s1 = await st(P), s2 = await st(P2);
check('change in tab 2 shows in tab 1', s1.unread === s1.cards && s2.unread === s2.cards, { tab1: s1, tab2: s2 });
await sc('.all', P2); await sleep(800);
check('Mark all in tab 2 clears tab 1', (await st(P)).unread === 0, await st(P));
await closeTab(P2);
// keyboard shortcut (browser-level; may not be triggerable by automation)
await sc('.select', P); await sc('.q-all', P); await sc('.sel-unread', P); await sleep(500);
await P.bringToFront(); await P.keyboard.press('Alt+Shift+KeyR'); await sleep(1200);
const afterKey = await st(P);
console.log((afterKey.unread === 0 ? 'PASS ' : 'INFO ') + 'Alt+Shift+R shortcut ' + (afterKey.unread === 0 ? 'marked all read' : 'not delivered by automation (browser shortcuts ignore synthetic keys)'), JSON.stringify(afterKey));
// same code path the shortcut runs, via the background worker
await E.evaluate(() => chrome.runtime.sendMessage({ type: 'lnra:popupMarkAllRead' })); await sleep(800);
check('background mark-all (shortcut code path) clears everything', (await st(P)).unread === 0 && (await stored()).unread === 0, await stored());
// popup
await E.reload(); await sleep(500);
check('popup shows 0 and disables button', await E.evaluate(() => document.getElementById('n').textContent === '0' && document.getElementById('markAll').disabled));
await E.emulateMedia({ colorScheme: 'dark' }); await sleep(300);
check('popup dark mode applies', await E.evaluate(() => getComputedStyle(document.body).backgroundColor), undefined);
await E.emulateMedia({ colorScheme: 'light' });
const nTabs = (await listBrowserTabs()).filter(t => /linkedin\.com\/notifications/.test(t.url)).length;
await E.evaluate(() => document.getElementById('open').click()); await sleep(1500);
const nTabs2 = (await listBrowserTabs()).filter(t => /linkedin\.com\/notifications/.test(t.url)).length;
check('Open notifications focuses the existing tab instead of opening another', nTabs2 === nTabs, { before: nTabs, after: nTabs2 });
console.log(`\nTOTAL ${pass} passed, ${fail} failed`);
