/* LinkedIn Read-All — service worker: toolbar badge + keyboard shortcut. */
importScripts('core.js');

const L = globalThis.LNRA;
const NOTIFICATIONS_URL = 'https://www.linkedin.com/notifications/';

async function getData() {
  const res = await chrome.storage.local.get(L.STORAGE_KEY);
  return L.sanitize(res[L.STORAGE_KEY]);
}

async function updateBadge() {
  const n = L.unreadCount(await getData());
  await chrome.action.setBadgeBackgroundColor({ color: '#0a66c2' });
  await chrome.action.setBadgeText({ text: n === 0 ? '' : n > 99 ? '99+' : String(n) });
}

/* Mark all read: through the page if a notifications tab is active (so loaded
   cards register first and the undo toast shows), else directly in storage. */
async function markAllRead() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab && tab.url && tab.url.startsWith(NOTIFICATIONS_URL)) {
    try {
      await chrome.tabs.sendMessage(tab.id, { type: 'lnra:markAllRead' });
      return;
    } catch (_e) {
      /* content script not ready; fall through */
    }
  }
  const data = await getData();
  await chrome.storage.local.set({ [L.STORAGE_KEY]: L.markAllRead(data) });
}

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes[L.STORAGE_KEY]) updateBadge();
});
chrome.runtime.onInstalled.addListener(updateBadge);
chrome.runtime.onStartup.addListener(updateBadge);

chrome.commands.onCommand.addListener((command) => {
  if (command === 'mark-all-read') markAllRead();
});

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (msg && msg.type === 'lnra:popupMarkAllRead') {
    markAllRead().then(() => reply({ ok: true }));
    return true;
  }
});
