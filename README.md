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

Paste this into **Claude Code** or **Codex**:

```text
Install https://github.com/woojinjeon820-ui/linkedin-read-all: run `curl -fsSL https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.sh | bash` (Windows PowerShell: `irm https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.ps1 | iex`), then tell me what it printed.
```

The installer does the whole job: download, load into the browser, or reload on an update. In **Aside on macOS** and in **Chrome, Edge, Brave and Aside on Windows** that includes the browser clicks, so there is nothing left for you. In other browsers on macOS and Linux it opens the Extensions page and copies the folder path, and you do the last two clicks (the agent tells you which).

**Approvals:** Claude Code in auto mode runs it without asking. Codex runs commands in a sandbox with no network access, so it asks you once to run the installer outside the sandbox. Approve that, or start Codex with `codex --sandbox danger-full-access` to skip the question.

### Do it yourself

**macOS / Linux, one command** (Chrome, Aside, Edge, Brave, Arc):

```bash
curl -fsSL https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.sh | bash
```

The script downloads the latest release to `~/LinkedIn-Read-All`.

- **Aside on macOS:** if Aside is open, the script loads the extension itself through Aside's `aside` command-line tool. It turns on Developer mode and loads the folder, or reloads it on an update. Nothing to click.
- **Other browsers:** it copies the folder path to your clipboard and opens the Extensions page. Then turn on **Developer mode** (top right), click **Load unpacked**, press `Cmd+Shift+G`, paste (`Cmd+V`), press Enter, then **Select**. Browsers only allow one-click installs from their web stores, so this part is by hand.

Then open <https://www.linkedin.com/notifications/>. The bar appears at the bottom. To **update**, run the same command again: in Aside it reloads the extension for you; elsewhere press the reload icon on the extension's card. [Read the script](install.sh) before running it if you like. It only writes to `~/LinkedIn-Read-All`, or updates the folder Aside already loads the extension from.

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
- LinkedIn's own "new" markers go away too: the light-blue card background and the small blue dot in the left margin. LinkedIn normally keeps both until you click each card. When the extension marks a card read, it repaints the card in LinkedIn's normal colour and hides the dot, and marking it unread brings both back. Once a dot has been seen, its style signature is remembered so that dots on re-rendered cards (reload, filter switch, scrolling, coming back to the page) are hidden the instant they appear. LinkedIn already counts every notification as seen once you open the page, so this only changes what you see.
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
| `extension/src/early.js` | Runs at `document_start`: applies the learned "new"-dot selectors before LinkedIn paints, so hidden dots never flash. |
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
