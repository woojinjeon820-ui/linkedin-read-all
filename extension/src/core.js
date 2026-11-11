/*
 * Pure state logic for LinkedIn Read-All. No DOM, no chrome.* APIs, so it can be
 * unit-tested in Node and shared by the content script and the popup.
 *
 * Why local state: LinkedIn's notification menu offers no per-item "mark as read"
 * or "mark as unread", and it clears its own unread styling as soon as the page is
 * opened. So the extension keeps its own read / unread / kept state per notification.
 *
 * Data shape (persisted in chrome.storage.local under STORAGE_KEY):
 *   { v: 1, baseline: boolean, items: { [key]: { s: 'u' | 'r', k: 0 | 1, t: firstSeenMs } } }
 *   s = state (unread / read), k = kept (user explicitly kept or flagged it unread).
 */
(function (root) {
  'use strict';

  const STORAGE_KEY = 'lnra';
  const MAX_AGE_MS = 120 * 24 * 60 * 60 * 1000; // forget entries after ~4 months
  const MAX_ITEMS = 5000;

  // Query params that identify *what* a notification points at. Everything else
  // (trk, f_TPR timestamps, tracking ids) varies between loads and is dropped.
  const KEEP_PARAMS = ['keywords', 'geoId', 'notificationType', 'groupBy', 'title', 'currentJobId'];

  // Coarse kind of notification, so "X reacted to your post" and "Y commented on
  // your post" (same link) get different keys. Order matters: first match wins.
  const KINDS = [
    ['react', /reacted|liked|celebrat|loves? |found .* (insightful|funny)|support/i],
    ['comment', /comment|replied|reply/i],
    ['mention', /mention|tagged/i],
    ['repost', /repost|shared|reshar/i],
    ['view', /viewed your|search(es)? appear|appeared in/i],
    ['job', /opportunit|job|hiring|applicant/i],
    ['connect', /connect|invitation|accepted/i],
    ['milestone', /birthday|anniversar|congratulat|new position|started a/i],
    ['post', /new from|posted|published|was live|is live|event/i],
  ];

  function emptyData() {
    return { v: 1, baseline: false, items: {} };
  }

  function normalizeHref(href) {
    if (!href) return '';
    try {
      const u = new URL(href, 'https://www.linkedin.com');
      const params = new URLSearchParams();
      for (const k of KEEP_PARAMS) {
        if (u.searchParams.has(k)) params.set(k, u.searchParams.get(k));
      }
      params.sort();
      const path = u.pathname.replace(/\/+$/, '') || '/';
      const qs = params.toString();
      return u.host + path + (qs ? '?' + qs : '');
    } catch (_e) {
      return String(href);
    }
  }

  function kindOf(text) {
    const t = String(text || '');
    for (const [kind, re] of KINDS) if (re.test(t)) return kind;
    return 'other';
  }

  function cardKey(href, headline) {
    return normalizeHref(href) + '#' + kindOf(headline);
  }

  function clone(data) {
    return JSON.parse(JSON.stringify(data || emptyData()));
  }

  function sanitize(raw) {
    if (!raw || typeof raw !== 'object' || !raw.items) return emptyData();
    return { v: 1, baseline: !!raw.baseline, items: { ...raw.items } };
  }

  /*
   * Register the keys currently on the page (in DOM order, newest first).
   * Unknown keys become unread if we have no baseline yet (fresh install) or if
   * they sit above every known card (i.e. they are newer). Unknown keys that load
   * *below* a known card are older items surfaced by scrolling: once the user has
   * done "mark all as read" (baseline), those default to read so old history does
   * not reappear as unread.
   * Returns { data, added } where added = number of new keys.
   */
  function register(data, keysInOrder, now) {
    const out = clone(data);
    let seenKnown = false;
    let added = 0;
    for (const key of keysInOrder) {
      const entry = out.items[key];
      if (entry) {
        seenKnown = true;
        continue;
      }
      const unread = !out.baseline || !seenKnown;
      out.items[key] = { s: unread ? 'u' : 'r', k: 0, t: now };
      added++;
    }
    return { data: out, added };
  }

  function setState(data, keys, state, kept) {
    const out = clone(data);
    for (const key of keys) {
      const prev = out.items[key] || { t: Date.now() };
      out.items[key] = { s: state, k: kept ? 1 : 0, t: prev.t };
    }
    return out;
  }

  function markRead(data, keys) {
    return setState(data, keys, 'r', false);
  }

  // Marking unread by hand is an explicit "keep this flagged" signal.
  function markUnread(data, keys, kept = true) {
    return setState(data, keys, 'u', kept);
  }

  /*
   * Mark every stored notification read, except `exceptKeys`, which stay unread
   * and are flagged as kept. Sets the baseline so older history loads as read.
   */
  function markAllReadExcept(data, exceptKeys) {
    const keep = new Set(exceptKeys || []);
    const out = clone(data);
    for (const [key, entry] of Object.entries(out.items)) {
      out.items[key] = keep.has(key) ? { s: 'u', k: 1, t: entry.t } : { s: 'r', k: 0, t: entry.t };
    }
    for (const key of keep) {
      if (!out.items[key]) out.items[key] = { s: 'u', k: 1, t: Date.now() };
    }
    out.baseline = true;
    return out;
  }

  function markAllRead(data) {
    return markAllReadExcept(data, []);
  }

  function markAllUnread(data, keys) {
    // "All" = everything currently loaded on the page (keys); not kept.
    return setState(data, keys, 'u', false);
  }

  function isUnread(data, key) {
    const e = data.items[key];
    return !!e && e.s === 'u';
  }

  function isKept(data, key) {
    const e = data.items[key];
    return !!e && e.s === 'u' && e.k === 1;
  }

  function unreadCount(data) {
    let n = 0;
    for (const e of Object.values(data.items)) if (e.s === 'u') n++;
    return n;
  }

  function prune(data, now, keepKeys) {
    const out = clone(data);
    const keep = new Set(keepKeys || []);
    for (const [key, e] of Object.entries(out.items)) {
      // Never drop kept/unread items or ones on screen.
      if (!keep.has(key) && e.s === 'r' && now - (e.t || 0) > MAX_AGE_MS) delete out.items[key];
    }
    const keys = Object.keys(out.items);
    if (keys.length > MAX_ITEMS) {
      keys
        .filter((k) => !keep.has(k) && out.items[k].s === 'r')
        .sort((a, b) => (out.items[a].t || 0) - (out.items[b].t || 0))
        .slice(0, keys.length - MAX_ITEMS)
        .forEach((k) => delete out.items[k]);
    }
    return out;
  }

  /* Select keys between two keys (inclusive) in the given order. For Shift+click. */
  function rangeBetween(order, fromKey, toKey) {
    const a = order.indexOf(fromKey);
    const b = order.indexOf(toKey);
    if (a < 0 || b < 0) return [toKey];
    const [lo, hi] = a < b ? [a, b] : [b, a];
    return order.slice(lo, hi + 1);
  }

  const api = {
    STORAGE_KEY,
    emptyData,
    sanitize,
    normalizeHref,
    kindOf,
    cardKey,
    register,
    markRead,
    markUnread,
    markAllRead,
    markAllReadExcept,
    markAllUnread,
    isUnread,
    isKept,
    unreadCount,
    prune,
    rangeBetween,
    clone,
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LNRA = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
