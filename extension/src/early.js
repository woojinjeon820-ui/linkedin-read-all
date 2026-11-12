/*
 * LinkedIn Read-All: runs at document_start, before LinkedIn paints anything.
 *
 * Its one job is to make sure LinkedIn's own blue "new" dot never shows on a card the
 * extension has marked read, not even for a frame. content.js (document_idle) finds the
 * dot by colour and size and remembers its tag + class signature; this script puts those
 * learned selectors into a <style> as early as possible on every load, and flags <html>
 * while the page is /notifications so the rules only apply there. Shares the isolated
 * world with content.js, which uses the globalThis.__lnraDot API below.
 */
(function () {
  'use strict';

  if (globalThis.__lnraDot) return;

  const DOT_SEL_KEY = 'lnraDotSel'; // chrome.storage.local: learned dot selectors, newest first
  const PAGE_ATTR = 'data-lnra-notifications'; // on <html> while on /notifications
  const DOT_SHOW_ATTR = 'data-lnra-native-dot-show'; // on the dot of a card we show as unread
  const STYLE_ID = 'lnra-dot-style';
  const MAX_DOT_SELECTORS = 8;

  const storage = chrome.storage && chrome.storage.local;
  let selectors = [];
  let style = null;

  function isNotificationsPath(pathname) {
    return /^\/notifications\/?$/.test(pathname) || globalThis.__lnraForcePage === true;
  }

  function syncPageAttr(pathname) {
    const html = document.documentElement;
    if (!html) return;
    if (isNotificationsPath(pathname)) html.setAttribute(PAGE_ATTR, '');
    else html.removeAttribute(PAGE_ATTR);
  }

  function cssFor(list) {
    return list
      .map((s) => `html[${PAGE_ATTR}] main ${s}:not([${DOT_SHOW_ATTR}]) { visibility: hidden !important; }`)
      .join('\n');
  }

  function apply() {
    if (!style) {
      style = document.getElementById(STYLE_ID);
      if (!style) {
        style = document.createElement('style');
        style.id = STYLE_ID;
        style.setAttribute('data-lnra-ui', '');
      }
    }
    const css = cssFor(selectors);
    if (style.textContent !== css) style.textContent = css;
    const parent = document.head || document.documentElement;
    if (!style.isConnected && parent) parent.appendChild(style);
  }

  function sanitize(list) {
    return Array.isArray(list) ? list.filter((s) => typeof s === 'string' && s).slice(0, MAX_DOT_SELECTORS) : [];
  }

  const api = {
    PAGE_ATTR,
    DOT_SHOW_ATTR,
    get: () => selectors.slice(),
    set(list) {
      selectors = sanitize(list);
      apply();
    },
    // Remember a selector (newest first), apply it now and persist it for the next load.
    learn(sel) {
      if (!sel || selectors.includes(sel)) return;
      selectors = [sel, ...selectors].slice(0, MAX_DOT_SELECTORS);
      apply();
      try {
        storage.set({ [DOT_SEL_KEY]: selectors });
      } catch (_e) {
        /* extension reloaded */
      }
    },
    syncPageAttr,
  };
  globalThis.__lnraDot = api;

  syncPageAttr(location.pathname);
  if (!document.documentElement) {
    document.addEventListener('readystatechange', () => syncPageAttr(location.pathname), { once: true });
  }
  try {
    // Fires before a same-document navigation commits, so the flag is right before LinkedIn paints.
    if (globalThis.navigation && typeof navigation.addEventListener === 'function') {
      navigation.addEventListener('navigate', (e) => {
        try {
          syncPageAttr(new URL(e.destination.url).pathname);
        } catch (_e) {
          /* ignore */
        }
      });
    }
  } catch (_e) {
    /* ignore */
  }

  try {
    storage.get(DOT_SEL_KEY, (res) => api.set(res && res[DOT_SEL_KEY]));
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area === 'local' && changes[DOT_SEL_KEY]) api.set(changes[DOT_SEL_KEY].newValue);
    });
  } catch (_e) {
    /* no storage: nothing learned yet */
  }
})();
