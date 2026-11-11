# LinkedIn Read-All

A Chrome extension (Manifest V3) that adds what LinkedIn is missing on its Notifications page:

- **Mark all as read** in one click (bottom bar, toolbar popup, or `Alt+Shift+R`)
- **Select mode** for bulk actions: Read all *except* selected (keep a few flagged), Mark selected read, Mark selected unread, All unread
- Click / Shift+click range selection, quick-select (All, None, Unread, Read), Esc to exit
- **Undo** for 10 seconds after any bulk action
- Unread count on the toolbar badge

Works in Google Chrome, Aside, and other Chromium browsers (Edge, Brave, Arc).

## Install

### Let an AI agent do it

Paste this into **Claude Code** (or Claude with computer use or Claude in Chrome) or **Codex**:

```text
Install the "LinkedIn Read-All" browser extension for me from
https://github.com/woojinjeon820-ui/linkedin-read-all

1. Find out which browser I use: Chrome, Aside, Edge, Brave or Arc. Prefer the one that's
   running; ask me if you can't tell. Its extensions page is chrome://extensions
   (Aside and Arc too), edge://extensions in Edge, brave://extensions in Brave.
2. If you can see that page, check whether "LinkedIn Read-All" is already listed. If it is,
   don't load another copy (two copies conflict). Tell me its version, and its folder if
   the Details page shows it (don't guess). If it's older than the latest release, run
   step 3 to update, then press the reload icon on its card. Then skip to step 5.
3. Read install.sh in that repo, then run it (it puts the install path on my clipboard):
   curl -fsSL https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.sh | bash
   On Windows: get the .zip asset of the latest release from
   https://api.github.com/repos/woojinjeon820-ui/linkedin-read-all/releases/latest
   and extract it to %USERPROFILE%\LinkedIn-Read-All.
4. Browsers don't let scripts load extensions, so this part takes clicks. If you can control
   my browser, do them yourself: on the extensions page turn on Developer mode, click
   "Load unpacked", and pick the LinkedIn-Read-All folder from step 3. The folder picker is
   a system dialog many agents can't operate. If you can't, ask me to do just that part
   (on macOS: Cmd+Shift+G, Cmd+V, Enter, Select) and wait. If you can't control the browser
   at all, walk me through each click and wait for me after each one.
5. Check that "LinkedIn Read-All" is listed and turned on. Then open
   https://www.linkedin.com/notifications/ (I may need to sign in) and confirm a dark bar
   with "Mark all as read" appears at the bottom of the page. If you check the page's code
   rather than a screenshot, the bar is inside the shadow root of the #lnra-host element,
   so a plain text search of the page won't find it.

Don't change, disable or remove other extensions or browser settings. Don't close my
tabs; you may close tabs you opened yourself. Tell me what you did and anything that
didn't work.
```

The agent runs the installer and, if it can control your browser, does the clicks too. If it can't, it walks you through them.

### Do it yourself

**macOS / Linux, one command** (Chrome, Aside, Edge, Brave, Arc):

```bash
curl -fsSL https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.sh | bash
```

The script downloads the latest release to `~/LinkedIn-Read-All`, copies that path to your clipboard, and opens your browser's Extensions page. Then:

1. Turn on **Developer mode** (top right).
2. Click **Load unpacked**, press `Cmd+Shift+G`, paste (`Cmd+V`), press Enter, then **Select**.
3. Open <https://www.linkedin.com/notifications/>. The bar appears at the bottom.

That last part has to be done by hand: browsers only allow one-click installs from their web stores. To **update**, run the same command again, then press the reload icon on the extension's card. [Read the script](install.sh) before running it if you like. It only writes to `~/LinkedIn-Read-All`.

**Windows, or by hand:** download `linkedin-read-all-<version>.zip` from the [latest release](../../releases/latest), unzip it, open `chrome://extensions` (`edge://extensions` in Edge), turn on Developer mode, click **Load unpacked**, and choose the unzipped folder.

To change the keyboard shortcut, go to `chrome://extensions/shortcuts`.

## How it works (and why)

LinkedIn's notification menu has no per-item "mark as read" or "mark as unread", and LinkedIn clears its own unread styling as soon as you open the page. So the extension keeps its **own** read / unread / kept state for each notification, stored only in your browser (`chrome.storage.local`). Unread items get a blue tint and dot; items you kept unread get an amber tint and a flag.

- A notification counts as read once you open it, or when you use a bulk action.
- After your first "Mark all as read", older notifications that load as you scroll come in as read. Only new ones at the top come in as unread.
- Each notification is identified by its link plus its kind (reaction, comment, job alert, and so on). If LinkedIn rolls new reactions into a notification you already read, it stays read.
- It makes **no network requests** and changes nothing on LinkedIn's servers. It only reads the page and adds its own styling.

## Develop

After you edit the code, press the reload icon on the extension card (loaded from `extension/`), then refresh the LinkedIn tab.

```bash
npm test                       # unit tests for the state logic (Node 18+)
npm run package                # zip the extension into dist/
git tag v0.1.2 && git push --tags  # CI tests, packages and publishes the release (tag must match manifest version)
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
