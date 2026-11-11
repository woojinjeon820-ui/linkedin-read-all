# LinkedIn Read-All

A Chrome extension (Manifest V3) that adds what LinkedIn is missing on its Notifications page:

- **Mark all as read** in one click (bottom bar, toolbar popup, or `Alt+Shift+R`)
- **Select mode** for bulk actions: Read all *except* selected (keep a few flagged), Mark selected read, Mark selected unread, All unread
- Click / Shift+click range selection, quick-select (All, None, Unread, Read), Esc to exit
- **Undo** for 10 seconds after any bulk action
- Unread count on the toolbar badge

Works in Google Chrome, Aside, and other Chromium browsers (Edge, Brave, Arc).

## How it works (and why)

LinkedIn's notification menu has no per-item "mark as read" or "mark as unread", and LinkedIn clears its own unread styling as soon as you open the page. So the extension keeps its **own** read / unread / kept state for each notification, stored only in your browser (`chrome.storage.local`). Unread items get a blue tint and dot; items you kept unread get an amber tint and a flag.

- A notification counts as read once you open it, or when you use a bulk action.
- After your first "Mark all as read", older notifications that load as you scroll come in as read. Only new ones at the top come in as unread.
- Each notification is identified by its link plus its kind (reaction, comment, job alert, and so on). If LinkedIn rolls new reactions into a notification you already read, it stays read.
- It makes **no network requests** and changes nothing on LinkedIn's servers. It only reads the page and adds its own styling.

## Install

Download `linkedin-read-all-<version>.zip` from the [latest release](../../releases/latest) and unzip it, or clone this repo and use its `extension/` folder.

### Chrome
1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and choose the unzipped folder (or `extension/` in this repo).
4. Open <https://www.linkedin.com/notifications/>. The bar appears at the bottom.

### Aside
Aside is Chromium-based, so the steps are the same:
1. Open `chrome://extensions` in Aside (it shows as "Extensions").
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose the `extension/` folder.
4. Open <https://www.linkedin.com/notifications/>.

To change the shortcut: `chrome://extensions/shortcuts`.

After you edit the code, click the reload icon on the extension card, then refresh the LinkedIn tab.

## Develop

```bash
npm test                       # unit tests for the state logic (Node 18+)
npm run package                # zip the extension into dist/
python3 scripts/make_icons.py  # regenerate icons
```

### End-to-end tests (Aside)

`tests/live/run-aside.sh <extension-id>` drives the installed extension on the real LinkedIn notifications page through the [Aside](https://aside.com) browser CLI. It runs 28 checks covering every bar action, select mode, undo, click-to-read, the badge, the popup, page navigation, and two-tab sync. It clears the extension's local state first and only closes tabs it opens. Pressing the keyboard shortcut can't be automated (browsers ignore synthetic shortcut keys), so press it by hand once.

`tests/live/build-fixture-harness.js` runs the same flows against `tests/fixture/notifications.html` without a LinkedIn login.

| Path | What it does |
| --- | --- |
| `extension/src/core.js` | Pure state logic (keys, read/unread/kept, baseline, undo-safe). Shared by all parts and unit-tested. |
| `extension/src/content.js` | Finds cards on the page, highlights them, and runs the bottom bar and select mode. `SELECTORS` at the top holds every LinkedIn DOM assumption. |
| `extension/src/content.css` | Card highlight, flag, and checkbox styles. |
| `extension/src/background.js` | Toolbar badge and keyboard shortcut. |
| `extension/popup/` | Toolbar popup. |
| `tests/fixture/notifications.html` | Offline copy of LinkedIn's notifications page structure (recorded 2026-11-11), for manual and automated checks. |

**If LinkedIn changes its page:** cards are found by their "More options" button (`aria-label`); each card is the highest ancestor that contains exactly one such button. If the bar shows but cards don't highlight, check `SELECTORS.menuButtonLabels` first. Non-English UIs need their label added there.

## Privacy

No data leaves your browser. The extension makes no network requests and has no analytics. Its only permissions are `storage` and access to `www.linkedin.com`.

## License

[MIT](LICENSE). Not affiliated with or endorsed by LinkedIn.
