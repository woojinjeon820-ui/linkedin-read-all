/*
 * LinkedIn Read-All: content script for www.linkedin.com.
 *
 * Finds notification cards on /notifications, keeps a local read / unread / kept
 * state for each (see core.js for why), highlights unread ones, and adds a floating
 * bar with "Mark all as read" and a selection mode for bulk read / unread.
 *
 * All LinkedIn-specific DOM assumptions live in SELECTORS so a markup change is a
 * one-place fix.
 */
(function () {
  'use strict';

  const L = globalThis.LNRA;
  if (!L || globalThis.__lnraLoaded) return;
  globalThis.__lnraLoaded = true;

  const SELECTORS = {
    // Every notification card has exactly one of these "More options" buttons.
    // LinkedIn's class names are hashed, so we anchor on the accessible label.
    menuButtonLabels: [
      'More options',
      'Weitere Optionen',
      'Plus d’options',
      "Plus d'options",
      'Más opciones',
      'Mais opções',
      'Altre opzioni',
      'Meer opties',
      '더보기',
      'その他のオプション',
      '更多选项',
    ],
    feedRoot: ['main [aria-label="Primary content"]', 'main'],
  };

  const UNDO_MS = 10000;

  // ---------- state ----------
  let data = L.emptyData();
  let loaded = false;
  let selecting = false;
  const selected = new Set();
  let lastClickedKey = null;
  let order = []; // keys on the page, newest first
  let cardsByKey = new Map();
  let undo = null; // { data, timer }

  const storage = chrome.storage && chrome.storage.local;

  function load() {
    return new Promise((resolve) => {
      try {
        storage.get(L.STORAGE_KEY, (res) => {
          data = L.sanitize(res && res[L.STORAGE_KEY]);
          loaded = true;
          resolve();
        });
      } catch (_e) {
        loaded = true;
        resolve();
      }
    });
  }

  function save(next) {
    data = next;
    try {
      storage.set({ [L.STORAGE_KEY]: data });
    } catch (_e) {
      /* extension reloaded; page needs a refresh */
    }
    render();
  }

  try {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local' || !changes[L.STORAGE_KEY]) return;
      const nv = changes[L.STORAGE_KEY].newValue;
      if (JSON.stringify(nv) === JSON.stringify(data)) return;
      data = L.sanitize(nv);
      render();
    });
  } catch (_e) {
    /* ignore */
  }

  // Tiny element builder: h('span', { class: 'x' }, ['text' | Node, ...]).
  function h(tag, attrs, children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) if (v !== undefined) el.setAttribute(k, v);
    for (const c of [].concat(children ?? [])) el.append(c);
    return el;
  }

  // ---------- DOM discovery ----------
  function isNotificationsPage() {
    // __lnraForcePage lets the offline fixture test run on a non-LinkedIn URL.
    return /^\/notifications\/?$/.test(location.pathname) || globalThis.__lnraForcePage === true;
  }

  function feedRoot() {
    for (const sel of SELECTORS.feedRoot) {
      const el = document.querySelector(sel);
      if (el) return el;
    }
    return null;
  }

  function menuButtons(root) {
    const labels = new Set(SELECTORS.menuButtonLabels);
    return [...root.querySelectorAll('button[aria-label]')].filter(
      (b) => labels.has(b.getAttribute('aria-label')) && !b.closest('[data-lnra-ui]')
    );
  }

  /*
   * A card = the highest ancestor of a menu button that contains no other menu
   * button. Counting menu buttons per ancestor makes this O(cards x depth).
   */
  function findCards(root) {
    const buttons = menuButtons(root);
    const counts = new Map();
    for (const b of buttons) {
      for (let el = b.parentElement; el && el !== root; el = el.parentElement) {
        counts.set(el, (counts.get(el) || 0) + 1);
      }
    }
    const cards = [];
    for (const b of buttons) {
      let card = b;
      while (card.parentElement && card.parentElement !== root && counts.get(card.parentElement) === 1) {
        card = card.parentElement;
      }
      if (card !== b) cards.push(card);
    }
    return cards;
  }

  function describeCard(card) {
    const links = [...card.querySelectorAll('a[href]')].filter((a) => !a.closest('[data-lnra-ui]'));
    // The last link is LinkedIn's full-card link; its text is the headline.
    const main = links[links.length - 1];
    const href = main ? main.getAttribute('href') : '';
    const headline = (main && (main.getAttribute('aria-label') || main.textContent)) || card.textContent || '';
    return { href, headline: headline.replace(/\s+/g, ' ').trim() };
  }

  // ---------- scan + render ----------
  let scanQueued = false;
  function queueScan() {
    if (scanQueued) return;
    scanQueued = true;
    setTimeout(() => {
      scanQueued = false;
      scan();
    }, 150);
  }

  function scan() {
    if (!loaded) return;
    if (!isNotificationsPage()) {
      if (selecting) setSelecting(false);
      bar.hide();
      order = [];
      cardsByKey = new Map();
      return;
    }
    const root = feedRoot();
    if (!root) return;
    const cards = findCards(root);
    const nextOrder = [];
    const nextMap = new Map();
    const dupes = new Map();
    for (const card of cards) {
      const { href, headline } = describeCard(card);
      if (!href) continue;
      let key = L.cardKey(href, headline);
      const n = (dupes.get(key) || 0) + 1;
      dupes.set(key, n);
      if (n > 1) key += '~' + n;
      if (card.dataset.lnraKey !== key) card.dataset.lnraKey = key;
      if (!card.hasAttribute('data-lnra-card')) card.setAttribute('data-lnra-card', '');
      nextOrder.push(key);
      nextMap.set(key, card);
    }
    order = nextOrder;
    cardsByKey = nextMap;
    for (const k of [...selected]) if (!cardsByKey.has(k)) selected.delete(k);

    const { data: registered, added } = L.register(data, order, Date.now());
    if (added > 0) save(L.prune(registered, Date.now(), order));
    else render();
  }

  function setAttr(el, name, on) {
    if (on && el.getAttribute(name) !== '1') el.setAttribute(name, '1');
    else if (!on && el.hasAttribute(name)) el.removeAttribute(name);
  }

  function render() {
    if (!isNotificationsPage()) return;
    for (const [key, card] of cardsByKey) {
      setAttr(card, 'data-lnra-unread', L.isUnread(data, key));
      setAttr(card, 'data-lnra-kept', L.isKept(data, key));
      setAttr(card, 'data-lnra-selected', selecting && selected.has(key));
      let mark = card.querySelector(':scope > .lnra-mark');
      if (!mark) {
        mark = h('span', { class: 'lnra-mark', 'data-lnra-ui': '', 'aria-hidden': 'true' }, [
          h('span', { class: 'lnra-box' }),
          h('span', { class: 'lnra-dot' }),
          h('span', { class: 'lnra-flag', title: 'Kept unread' }, '⚑'),
        ]);
        card.appendChild(mark);
      }
    }
    bar.update();
  }

  // ---------- actions ----------
  function apply(next, message) {
    const before = data;
    save(next);
    showUndo(before, message);
  }

  function loadedUnreadKeys() {
    return order.filter((k) => L.isUnread(data, k));
  }

  const actions = {
    markAllRead() {
      const n = L.unreadCount(data);
      apply(L.markAllRead(data), n ? `Marked ${n} as read` : 'All caught up');
    },
    markAllReadExceptSelected() {
      const keep = [...selected];
      const n = L.unreadCount(data) - keep.filter((k) => L.isUnread(data, k)).length;
      apply(L.markAllReadExcept(data, keep), `Marked ${Math.max(n, 0)} as read, kept ${keep.length}`);
      setSelecting(false);
    },
    markSelectedRead() {
      const keys = [...selected];
      apply(L.markRead(data, keys), `Marked ${keys.length} as read`);
      setSelecting(false);
    },
    markSelectedUnread() {
      const keys = [...selected];
      apply(L.markUnread(data, keys, true), `Kept ${keys.length} as unread`);
      setSelecting(false);
    },
    markAllUnread() {
      apply(L.markAllUnread(data, order), `Marked ${order.length} as unread`);
      setSelecting(false);
    },
  };

  function selectWhere(pred) {
    selected.clear();
    for (const k of order) if (pred(k)) selected.add(k);
    render();
  }

  function setSelecting(on) {
    selecting = on;
    if (!on) selected.clear();
    lastClickedKey = null;
    if (on) document.documentElement.setAttribute('data-lnra-selecting', '');
    else document.documentElement.removeAttribute('data-lnra-selecting');
    render();
  }

  function toggleSelect(key, shift) {
    if (shift && lastClickedKey) {
      const range = L.rangeBetween(order, lastClickedKey, key);
      const on = !selected.has(key);
      for (const k of range) on ? selected.add(k) : selected.delete(k);
    } else if (selected.has(key)) selected.delete(key);
    else selected.add(key);
    lastClickedKey = key;
    render();
  }

  function showUndo(before, message) {
    if (undo) clearTimeout(undo.timer);
    undo = {
      data: before,
      timer: setTimeout(() => {
        undo = null;
        bar.update();
      }, UNDO_MS),
    };
    bar.toast(message, !!undo);
  }

  function doUndo() {
    if (!undo) return;
    clearTimeout(undo.timer);
    const prev = undo.data;
    undo = null;
    save(prev);
    bar.toast('Undone', false);
  }

  // ---------- events ----------
  function onClick(e) {
    const t = e.target;
    if (!(t instanceof Element) || t.closest('[data-lnra-ui="bar"]')) return;
    const card = t.closest('[data-lnra-card]');
    if (!card || !card.dataset.lnraKey) return;
    const key = card.dataset.lnraKey;
    if (selecting) {
      // In selection mode a click anywhere on a card toggles it; nothing navigates.
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      if (e.type === 'click') toggleSelect(key, e.shiftKey);
      return;
    }
    // Opening a notification marks it read, like any inbox.
    if (t.closest('a[href]') && L.isUnread(data, key)) save(L.markRead(data, [key]));
  }
  document.addEventListener('click', onClick, true);
  document.addEventListener('auxclick', onClick, true);
  // Swallow presses too, so LinkedIn's own handlers don't fire in selection mode.
  document.addEventListener(
    'mousedown',
    (e) => {
      if (selecting && e.target instanceof Element && e.target.closest('[data-lnra-card]') && !e.target.closest('[data-lnra-ui="bar"]')) {
        e.preventDefault();
      }
    },
    true
  );
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && selecting) setSelecting(false);
  });

  chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
    if (!msg || typeof msg.type !== 'string') return;
    if (msg.type === 'lnra:markAllRead') {
      if (isNotificationsPage()) actions.markAllRead();
      else save(L.markAllRead(data));
      reply({ ok: true, unread: L.unreadCount(data) });
    } else if (msg.type === 'lnra:status') {
      reply({ ok: true, onPage: isNotificationsPage(), unread: L.unreadCount(data), loaded: order.length });
    }
  });

  // ---------- floating bar (shadow DOM so LinkedIn's CSS can't touch it) ----------
  const bar = (() => {
    let host = null;
    let els = null;
    let toastTimer = null;

    const css = `
      :host { all: initial; }
      .wrap { position: fixed; left: 50%; bottom: 20px; transform: translateX(-50%); z-index: 2147483000;
        display: flex; flex-direction: column; align-items: center; gap: 8px;
        font: 14px/1.3 -apple-system, system-ui, "Segoe UI", Roboto, sans-serif; max-width: calc(100vw - 32px); }
      .bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 6px;
        padding: 8px 10px; border-radius: 999px; background: #1d2226; color: #fff;
        box-shadow: 0 6px 24px rgba(0,0,0,.28); }
      .count { padding: 0 8px 0 6px; font-weight: 600; white-space: nowrap; display: flex; align-items: center; gap: 6px; }
      .count i { width: 8px; height: 8px; border-radius: 50%; background: #70b5f9; display: inline-block; }
      .sep { width: 1px; height: 20px; background: rgba(255,255,255,.18); margin: 0 2px; }
      .lbl { color: rgba(255,255,255,.6); font-size: 12px; padding-left: 4px; }
      button { font: inherit; border: 0; border-radius: 999px; padding: 6px 12px; cursor: pointer;
        background: rgba(255,255,255,.1); color: #fff; white-space: nowrap; }
      button:hover { background: rgba(255,255,255,.2); }
      button:focus-visible { outline: 2px solid #70b5f9; outline-offset: 2px; }
      button.primary { background: #0a66c2; font-weight: 600; }
      button.primary:hover { background: #004182; }
      button.link { background: none; padding: 6px 6px; color: #70b5f9; }
      button.link:hover { text-decoration: underline; background: none; }
      button:disabled { opacity: .4; cursor: default; }
      .toast { display: none; align-items: center; gap: 12px; padding: 8px 8px 8px 16px; border-radius: 10px;
        background: #1d2226; color: #fff; box-shadow: 0 6px 24px rgba(0,0,0,.28); }
      .toast.on { display: flex; }
      [hidden] { display: none !important; }
    `;

    function build() {
      host = document.createElement('div');
      host.id = 'lnra-host';
      host.setAttribute('data-lnra-ui', 'bar');
      const shadow = host.attachShadow({ mode: 'open' });
      // Constructable stylesheet: not subject to the page's Content-Security-Policy.
      try {
        const sheet = new CSSStyleSheet();
        sheet.replaceSync(css);
        shadow.adoptedStyleSheets = [sheet];
      } catch (_e) {
        const style = document.createElement('style');
        style.textContent = css;
        shadow.appendChild(style);
      }
      // Built with createElement (no innerHTML) so Trusted Types policies can't block it.
      const btn = (cls, text, title) => h('button', { class: cls, type: 'button', title }, text);
      shadow.appendChild(
        h('div', { class: 'wrap', role: 'region', 'aria-label': 'LinkedIn Read-All' }, [
          h('div', { class: 'toast', role: 'status', 'aria-live': 'polite' }, [h('span', { class: 'msg' }), btn('link undo', 'Undo')]),
          h('div', { class: 'bar normal' }, [
            h('span', { class: 'count' }, [h('i'), h('span', { class: 'n' }, '0 unread')]),
            btn('primary all', 'Mark all as read'),
            btn('select', 'Select', 'Pick notifications to read or keep unread'),
          ]),
          h('div', { class: 'bar selecting', hidden: '' }, [
            h('span', { class: 'count' }, [h('span', { class: 'ns' }, '0 selected')]),
            h('span', { class: 'lbl' }, 'Select:'),
            btn('link q-all', 'All'),
            btn('link q-none', 'None'),
            btn('link q-unread', 'Unread'),
            btn('link q-read', 'Read'),
            h('span', { class: 'sep' }),
            btn('primary except', 'Read all except selected', 'Mark everything read; selected stay unread and flagged'),
            btn('sel-read', 'Mark read'),
            btn('sel-unread', 'Mark unread', 'Keep selected unread and flagged'),
            btn('all-unread', 'All unread'),
            h('span', { class: 'sep' }),
            btn('done', 'Done'),
          ]),
        ])
      );
      const $ = (s) => shadow.querySelector(s);
      els = {
        normal: $('.normal'),
        selecting: $('.selecting'),
        n: $('.n'),
        ns: $('.ns'),
        all: $('.all'),
        except: $('.except'),
        selRead: $('.sel-read'),
        selUnread: $('.sel-unread'),
        toast: $('.toast'),
        msg: $('.msg'),
        undo: $('.undo'),
      };
      $('.all').addEventListener('click', () => actions.markAllRead());
      $('.select').addEventListener('click', () => setSelecting(true));
      $('.done').addEventListener('click', () => setSelecting(false));
      $('.except').addEventListener('click', () => actions.markAllReadExceptSelected());
      $('.sel-read').addEventListener('click', () => actions.markSelectedRead());
      $('.sel-unread').addEventListener('click', () => actions.markSelectedUnread());
      $('.all-unread').addEventListener('click', () => actions.markAllUnread());
      $('.q-all').addEventListener('click', () => selectWhere(() => true));
      $('.q-none').addEventListener('click', () => selectWhere(() => false));
      $('.q-unread').addEventListener('click', () => selectWhere((k) => L.isUnread(data, k)));
      $('.q-read').addEventListener('click', () => selectWhere((k) => !L.isUnread(data, k)));
      $('.undo').addEventListener('click', () => doUndo());
    }

    function ensure() {
      if (!host) build();
      if (!host.isConnected) (document.body || document.documentElement).appendChild(host);
    }

    return {
      hide() {
        if (host) host.remove();
      },
      update() {
        if (!isNotificationsPage() || !order.length) return this.hide();
        ensure();
        const n = L.unreadCount(data);
        els.n.textContent = n === 0 ? 'All caught up' : `${n} unread`;
        els.all.disabled = n === 0;
        els.normal.hidden = selecting;
        els.selecting.hidden = !selecting;
        els.ns.textContent = `${selected.size} selected`;
        els.except.disabled = false;
        els.selRead.disabled = selected.size === 0;
        els.selUnread.disabled = selected.size === 0;
        if (!undo) els.undo.hidden = true;
      },
      toast(message, canUndo) {
        ensure();
        els.msg.textContent = message;
        els.undo.hidden = !canUndo;
        els.toast.classList.add('on');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => els.toast.classList.remove('on'), canUndo ? UNDO_MS : 2500);
      },
    };
  })();

  // ---------- boot ----------
  const observer = new MutationObserver(queueScan);
  load().then(() => {
    observer.observe(document.documentElement, { childList: true, subtree: true });
    scan();
  });
  // LinkedIn is a single-page app: catch route changes that don't touch the DOM much.
  let lastPath = location.pathname;
  setInterval(() => {
    if (location.pathname !== lastPath) {
      lastPath = location.pathname;
      queueScan();
    }
  }, 500);

  // Exposed for debugging and automated checks.
  globalThis.__lnra = { scan, actions, getData: () => data, getOrder: () => order.slice(), setSelecting, toggleSelect, selected };
})();
