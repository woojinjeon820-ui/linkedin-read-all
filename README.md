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
Do the whole install yourself. Only hand me a step if you truly can't do it.

1. Find out which browser I use: Chrome, Aside, Edge, Brave or Arc. Prefer the one that's
   open; ask me if you can't tell. Its extensions page is chrome://extensions
   (Aside and Arc too), edge://extensions in Edge, brave://extensions in Brave.
2. Read the installer for my OS in that repo, then run it. Run it in a normal shell that can
   reach the internet and my desktop. If your sandbox blocks that, ask me to approve running
   it outside the sandbox. Don't download or unzip anything by hand.
   - Windows, from PowerShell, cmd or Git Bash (the script is install.ps1):
     powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.ps1 | iex"
   - macOS / Linux (the script is install.sh):
     curl -fsSL https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.sh | bash
   On Windows the script also does the browser clicks itself (Developer mode, Load unpacked,
   the folder picker, or Reload on an update). Tell me not to touch the mouse or keyboard
   while it runs. Its last line is LNRA_RESULT=<value>:
   - loaded or reloaded: done, go to step 4.
   - other-copy: an older copy from another folder is loaded. Tell me, and offer to remove
     it (only with my OK), then run the installer again.
   - manual: the files are installed; the output says which browser step is left. Do step 3.
   - failed: tell me the error.
3. Only if the browser step is left (always on macOS / Linux): if the extensions page
   already lists "LinkedIn Read-All", don't load another copy (two copies conflict). Press
   the reload icon on its card instead. Otherwise, if you can control my browser, do the
   clicks yourself: turn on Developer mode, click "Load unpacked", and pick the folder the
   installer printed. The folder picker is a system dialog many agents can't operate. If
   you can't, ask me to do just that part (macOS: Cmd+Shift+G, Cmd+V, Enter, Select;
   Windows: Ctrl+V into the Folder box, Select Folder) and wait. If you can't control the
   browser at all, walk me through each click and wait for me after each one.
4. Check that "LinkedIn Read-All" is listed and turned on. Then open
   https://www.linkedin.com/notifications/ (I may need to sign in) and confirm a dark bar
   with "Mark all as read" appears at the bottom of the page. If you check the page's code
   rather than a screenshot, the bar is inside the shadow root of the #lnra-host element,
   so a plain text search of the page won't find it. If you can't see my browser, ask me
   whether the bar is there.

Don't change, disable or remove other extensions or browser settings. Don't close my
tabs; you may close tabs you opened yourself. Tell me what you did and anything that
didn't work.
```

The agent runs the installer. On Windows the installer also does the browser clicks itself through Windows UI Automation. On macOS and Linux the agent does the clicks if it can control your browser, and otherwise walks you through them.

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

**Windows, one command** (Chrome, Edge, Brave, Aside). Paste it into PowerShell, cmd or Git Bash:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.ps1 | iex"
```

It downloads the latest release to `%USERPROFILE%\LinkedIn-Read-All` and opens your browser's Extensions page. Then it turns on Developer mode, clicks **Load unpacked** and fills in the folder picker for you, so keep your hands off the mouse for a few seconds. Run it again to update: it replaces the files and presses the extension's **Reload** button. If a click can't be automated (for example, a non-English browser, or a work policy that blocks Developer mode), it tells you which step is left and puts the folder path on your clipboard. [Read the script](install.ps1) first if you like. It only writes to `%USERPROFILE%\LinkedIn-Read-All`, and it only reads your browser profile to see whether the extension is already loaded.

**By hand:** download `linkedin-read-all-<version>.zip` from the [latest release](../../releases/latest), unzip it, open `chrome://extensions` (`edge://extensions` in Edge), turn on Developer mode, click **Load unpacked**, and choose the unzipped folder.

To change the keyboard shortcut, go to `chrome://extensions/shortcuts`.

## How it works (and why)

LinkedIn's notification menu has no per-item "mark as read" or "mark as unread", and LinkedIn clears its own unread styling as soon as you open the page. So the extension keeps its **own** read / unread / kept state for each notification, stored only in your browser (`chrome.storage.local`). Unread items get a blue tint and dot; items you kept unread get an amber tint and a flag.

- A notification counts as read once you open it, or when you use a bulk action.
- LinkedIn's own light-blue "new" background goes away too. LinkedIn normally keeps that highlight until you click each card. When the extension marks a card read, it repaints the card in LinkedIn's normal colour, and marking it unread brings the highlight back. LinkedIn already counts every notification as seen once you open the page, so this only changes what you see.
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
