const L = globalThis.LNRA;
const NOTIFICATIONS_URL = 'https://www.linkedin.com/notifications/';

async function refresh() {
  const res = await chrome.storage.local.get(L.STORAGE_KEY);
  const n = L.unreadCount(L.sanitize(res[L.STORAGE_KEY]));
  document.getElementById('n').textContent = n;
  document.getElementById('label').textContent = n === 1 ? 'unread notification' : 'unread notifications';
  document.getElementById('markAll').disabled = n === 0;
}

document.getElementById('markAll').addEventListener('click', async () => {
  await chrome.runtime.sendMessage({ type: 'lnra:popupMarkAllRead' });
  refresh();
});

document.getElementById('open').addEventListener('click', async () => {
  const [existing] = await chrome.tabs.query({ url: NOTIFICATIONS_URL + '*' });
  if (existing) {
    await chrome.tabs.update(existing.id, { active: true });
    await chrome.windows.update(existing.windowId, { focused: true });
  } else {
    await chrome.tabs.create({ url: NOTIFICATIONS_URL });
  }
  window.close();
});

chrome.commands.getAll((cmds) => {
  const c = cmds.find((x) => x.name === 'mark-all-read');
  if (c && c.shortcut) document.getElementById('shortcut').textContent = c.shortcut;
});

chrome.storage.onChanged.addListener(refresh);
refresh();
