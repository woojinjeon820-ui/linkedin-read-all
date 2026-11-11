#!/usr/bin/env bash
# LinkedIn Read-All installer / updater (macOS and Linux; on Windows it runs install.ps1).
#
#   curl -fsSL https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.sh | bash
#
# Downloads the latest release and unpacks it to ~/LinkedIn-Read-All.
#
# In Aside (macOS), it then loads the extension itself through the `aside` command-line tool:
# Developer mode on, load the folder, or reload it on an update. Nothing to click.
# In other browsers it copies the folder path to your clipboard and opens the Extensions page.
# Browsers only allow one-click installs from their web stores, so the last step is yours there:
# Developer mode on -> Load unpacked -> paste the path.
#
# Re-run it any time to update. The last line is LNRA_RESULT=<value>:
#   loaded | reloaded | other-copy | manual | failed (same meanings as install.ps1)
#
# Options (environment variables):
#   LNRA_DIR=/path       install somewhere else (default: ~/LinkedIn-Read-All)
#   LNRA_BROWSER=name    aside | chrome | edge | brave | arc | chromium (default: auto-detect)
#   LNRA_NO_AUTOMATE=1   don't load it into Aside automatically
#   LNRA_NO_OPEN=1       don't open the browser
#   LNRA_NO_CLIPBOARD=1  don't touch the clipboard
set -euo pipefail

REPO="woojinjeon820-ui/linkedin-read-all"
DEST="${LNRA_DIR:-$HOME/LinkedIn-Read-All}"
NAME="LinkedIn Read-All"

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; printf '\nLNRA_RESULT=failed\n'; exit 1; }

# --- 0. On Windows (Git Bash, MSYS, Cygwin, WSL), hand over to install.ps1 -----------------
# It installs into the Windows user folder and also does the browser clicks itself.
win_shell=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) win_shell=1 ;;
  Linux) grep -qi microsoft /proc/version 2>/dev/null && command -v powershell.exe >/dev/null 2>&1 && win_shell=1 ;;
esac
if [ -n "$win_shell" ]; then
  if [ -n "${LNRA_DIR:-}" ]; then
    if command -v cygpath >/dev/null 2>&1; then LNRA_DIR=$(cygpath -w "$LNRA_DIR")
    elif command -v wslpath >/dev/null 2>&1; then LNRA_DIR=$(wslpath -w "$LNRA_DIR"); fi
    export LNRA_DIR
  fi
  # WSL only passes variables listed in WSLENV through to Windows programs.
  export WSLENV="${WSLENV:+$WSLENV:}LNRA_DIR:LNRA_BROWSER:LNRA_NO_AUTOMATE:LNRA_NO_OPEN:LNRA_NO_CLIPBOARD:LNRA_USER_DATA_DIR:LNRA_DEBUG"
  say "Windows detected: running the Windows installer (install.ps1)..."
  # Run from a checkout (bash install.sh)? Use the install.ps1 next to it. Piped from curl? Fetch it.
  here=""
  [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] && here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  if [ -n "$here" ] && [ -f "$here/install.ps1" ]; then
    ps1="$here/install.ps1"
    if command -v cygpath >/dev/null 2>&1; then ps1=$(cygpath -w "$ps1"); elif command -v wslpath >/dev/null 2>&1; then ps1=$(wslpath -w "$ps1"); fi
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1"
  fi
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "irm 'https://raw.githubusercontent.com/$REPO/main/install.ps1' | iex"
fi

for cmd in curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed."
done

# --- Aside automation (macOS) ----------------------------------------------------------------
# The `aside` CLI runs Playwright-style scripts inside the Aside browser. On chrome://extensions
# that page's own API (chrome.developerPrivate) can turn on Developer mode, reload an extension,
# and load a folder once it's dropped on the page, which we simulate with a drag event.
aside_cli=""
if [ "$(uname -s)" = Darwin ] && [ -z "${LNRA_NO_AUTOMATE:-}" ] && [ -z "${LNRA_NO_OPEN:-}" ] &&
   { [ -z "${LNRA_BROWSER:-}" ] || [ "${LNRA_BROWSER:-}" = aside ]; } && pgrep -xq Aside 2>/dev/null; then
  if command -v aside >/dev/null 2>&1; then aside_cli=$(command -v aside)
  elif [ -x "$HOME/.local/bin/aside" ]; then aside_cli="$HOME/.local/bin/aside"; fi
fi

js_str() { local v=${1//\\/\\\\}; v=${v//\"/\\\"}; printf '"%s"' "$v"; }
pretty() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# aside_run <query|install>: prints LNRA_COPY=<path> lines (query) or LNRA_ASIDE=<outcome> (install).
aside_run() {
  local js
  js='const MODE = '"$(js_str "$1")"', DEST = '"$(js_str "$DEST")"', DEST_PRETTY = '"$(js_str "$(pretty "$DEST")")"';
const pg = await openTab("chrome://extensions/");
await sleep(1200);
const ev = async (expression) => {
  const r = await pg._sendToTarget("Runtime.evaluate", { expression, userGesture: true, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error((r.exceptionDetails.exception && r.exceptionDetails.exception.description) || r.exceptionDetails.text);
  return r.result.value;
};
const copies = async () => JSON.parse(await ev(`new Promise(r => chrome.developerPrivate.getExtensionsInfo({ includeDisabled: true, includeTerminated: true }, l => r(JSON.stringify(l.filter(e => e.name === "LinkedIn Read-All").map(e => ({ id: e.id, path: e.prettifiedPath || "", loc: e.location }))))))`));
const isMine = c => c.path === DEST || c.path === DEST_PRETTY;
let out = "";
try {
  const list = await copies();
  if (MODE === "query") {
    for (const c of list) if (c.loc === "UNPACKED") console.log("LNRA_COPY=" + c.path);
    out = "queried";
  } else {
    await ev(`new Promise(r => chrome.developerPrivate.updateProfileConfiguration({ inDeveloperMode: true }, () => r(true)))`);
    const mine = list.find(isMine);
    if (mine) {
      await ev(`new Promise(r => chrome.developerPrivate.reload(${JSON.stringify(mine.id)}, { failQuietly: true }, () => r(true)))`);
      out = "reloaded";
    } else if (list.some(c => c.loc === "UNPACKED")) {
      out = "other-copy";
    } else {
      await ev(`(() => { window.__lnra = null; document.addEventListener("drop", e => { const it = e.dataTransfer && e.dataTransfer.items[0]; const en = it && it.webkitGetAsEntry && it.webkitGetAsEntry(); if (en && en.isDirectory) { e.stopImmediatePropagation(); e.preventDefault(); chrome.developerPrivate.loadDirectory(en, id => { window.__lnra = { id, err: chrome.runtime.lastError ? chrome.runtime.lastError.message : null }; }); } }, true); return true; })()`);
      const data = { items: [], files: [DEST], dragOperationsMask: 1 };
      for (const type of ["dragEnter", "dragOver", "drop"]) { await pg._sendToTarget("Input.dispatchDragEvent", { type, x: 400, y: 300, data }); await sleep(250); }
      let ok = false;
      for (let i = 0; i < 20 && !ok; i++) { await sleep(500); ok = (await copies()).some(isMine); }
      out = ok ? "loaded" : "failed: " + (await ev("JSON.stringify(window.__lnra)"));
    }
  }
} catch (e) { out = "failed: " + e.message; }
console.log("LNRA_ASIDE=" + out);
await closeTab(pg);'
  # The CLI has its own 120 s limit; keep ours shorter so a stuck Aside can't hang the install.
  perl -e 'alarm(shift); exec(@ARGV)' 90 "$aside_cli" repl "$js" 2>&1 || true
}

# Already loaded by hand from another folder (say, an unzipped download)? Update that copy in
# place so Aside keeps the same extension and its read / unread state. Never a git checkout:
# that's someone developing the extension.
if [ -n "$aside_cli" ] && [ -z "${LNRA_DIR:-}" ]; then
  while IFS= read -r line; do
    p=${line#LNRA_COPY=}; case "$p" in "~"/*) p="$HOME${p#\~}" ;; esac
    [ "$p" = "$DEST" ] && break
    if grep -q "\"name\": *\"$NAME\"" "$p/manifest.json" 2>/dev/null &&
       ! git -C "$p" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      say "$NAME is already loaded in Aside from $p. Updating that copy."
      DEST="$p"
      break
    fi
  done < <(aside_run query | grep '^LNRA_COPY=' || true)
fi

# --- 1. Find the latest release zip -------------------------------------------------------
say "Finding the latest release of $NAME..."
api="https://api.github.com/repos/$REPO/releases/latest"
zip_url=$(curl -fsSL "$api" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/') ||
  die "couldn't reach GitHub ($api)."
[ -n "$zip_url" ] || die "no .zip found in the latest release of $REPO."
version=$(printf '%s' "$zip_url" | sed -n 's/.*-\([0-9][0-9.]*\)\.zip$/\1/p')

# --- 2. Download and unpack into a temp dir, check it's really the extension -------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$zip_url" -o "$tmp/ext.zip" || die "download failed: $zip_url"
unzip -q "$tmp/ext.zip" -d "$tmp/ext" || die "the downloaded file isn't a valid zip."
grep -q "\"name\": *\"$NAME\"" "$tmp/ext/manifest.json" 2>/dev/null || die "the download doesn't look like $NAME."

# --- 3. Install, replacing only a previous copy of this extension -------------------------
if [ -e "$DEST" ]; then
  if grep -q "\"name\": *\"$NAME\"" "$DEST/manifest.json" 2>/dev/null; then
    action="Updated"
  else
    die "$DEST already exists and isn't $NAME. Move it, or set LNRA_DIR to another folder."
  fi
else
  action="Installed"
fi
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST.new"
mv "$tmp/ext" "$DEST.new"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
say "$action $NAME ${version:+v$version }in: $DEST"

# --- 3b. Aside: load or reload it, no clicks -------------------------------------------------
if [ -n "$aside_cli" ]; then
  say "Loading it into Aside..."
  outcome=$(aside_run install | sed -n 's/^LNRA_ASIDE=//p' | tail -1)
  case "$outcome" in
    loaded)
      say "Loaded $NAME into Aside."
      say "Open https://www.linkedin.com/notifications/ - a dark bar with \"Mark all as read\" appears at the bottom."
      say ""; say "LNRA_RESULT=loaded"; exit 0 ;;
    reloaded)
      say "$NAME was already loaded from $DEST. Updated it${version:+ to v$version} and reloaded it."
      say "Refresh any open LinkedIn tabs to pick up the new version."
      say ""; say "LNRA_RESULT=reloaded"; exit 0 ;;
    other-copy)
      say "Aside already has a copy of $NAME loaded from a different folder (a git checkout, or one this"
      say "installer can't update). Two copies conflict, so nothing was loaded. To use this install instead,"
      say "remove the old one on chrome://extensions in Aside, then run this installer again."
      say ""; say "LNRA_RESULT=other-copy"; exit 0 ;;
    *)
      [ -n "$outcome" ] || outcome="no answer from the aside command"
      say "Couldn't load it into Aside automatically ($outcome). Falling back to the manual steps." ;;
  esac
fi

# --- 4. Clipboard ---------------------------------------------------------------------------
copied=""
if [ -z "${LNRA_NO_CLIPBOARD:-}" ]; then
  for c in pbcopy wl-copy "xclip -selection clipboard" "xsel --clipboard --input"; do
    if command -v "${c%% *}" >/dev/null 2>&1 && printf '%s' "$DEST" | $c 2>/dev/null; then
      copied=1
      break
    fi
  done
fi

# --- 5. Open the browser's Extensions page --------------------------------------------------
os=$(uname -s)
mac_app() { # browser key -> macOS app name
  case "$1" in
    aside) echo "Aside" ;; chrome) echo "Google Chrome" ;; edge) echo "Microsoft Edge" ;;
    brave) echo "Brave Browser" ;; arc) echo "Arc" ;; chromium) echo "Chromium" ;; *) echo "" ;;
  esac
}
linux_bin() { # browser key -> Linux executables to try
  case "$1" in
    chrome) echo "google-chrome google-chrome-stable" ;; edge) echo "microsoft-edge microsoft-edge-stable" ;;
    brave) echo "brave-browser brave" ;; chromium) echo "chromium chromium-browser" ;; *) echo "" ;;
  esac
}
installed() {
  if [ "$os" = Darwin ]; then
    local app; app=$(mac_app "$1")
    [ -n "$app" ] && { [ -d "/Applications/$app.app" ] || [ -d "$HOME/Applications/$app.app" ]; }
  else
    local b; for b in $(linux_bin "$1"); do command -v "$b" >/dev/null 2>&1 && return 0; done; return 1
  fi
}
running() {
  if [ "$os" = Darwin ]; then pgrep -xq "$(mac_app "$1")" 2>/dev/null
  else local b; for b in $(linux_bin "$1"); do pgrep -x "$b" >/dev/null 2>&1 && return 0; done; return 1; fi
}

browser="${LNRA_BROWSER:-}"
if [ -z "$browser" ]; then
  # Prefer a browser that's already open, then any installed one.
  for b in aside chrome edge brave arc chromium; do installed "$b" && running "$b" && { browser=$b; break; }; done
  [ -n "$browser" ] || for b in chrome aside edge brave arc chromium; do installed "$b" && { browser=$b; break; }; done
fi

ext_page="chrome://extensions/"
[ "$browser" = edge ] && ext_page="edge://extensions/"
[ "$browser" = brave ] && ext_page="brave://extensions/"

opened=""
if [ -z "${LNRA_NO_OPEN:-}" ] && [ -n "$browser" ]; then
  if [ "$os" = Darwin ]; then
    open -a "$(mac_app "$browser")" "$ext_page" 2>/dev/null && opened=1
  else
    for b in $(linux_bin "$browser"); do
      command -v "$b" >/dev/null 2>&1 && { ("$b" "$ext_page" >/dev/null 2>&1 &) ; opened=1; break; }
    done
  fi
fi

# --- 6. The one manual step ----------------------------------------------------------------
if [ -n "$copied" ]; then path_hint="the path (it's on your clipboard)"; else path_hint="$DEST"; fi
if [ "$os" = Darwin ]; then
  pick="press Cmd+Shift+G, paste $path_hint, press Enter, then Select"
else
  pick="choose $path_hint"
fi
# Some browsers ignore chrome:// links opened from outside, so always name the address too.
if [ -n "$opened" ]; then where="the Extensions page we opened (if it didn't open, type $ext_page in the address bar)"
elif [ -n "$browser" ]; then where="$ext_page in $( [ "$os" = Darwin ] && mac_app "$browser" || echo "$browser")"
else where="$ext_page in your Chromium browser (Chrome, Aside, Edge, Brave, Arc)"; fi
say ""
if [ "$action" = Updated ]; then
  say "If it's already loaded: on $where, press the reload icon on the $NAME card. Done."
  say "First time loading it? Follow the steps below."
fi
say "To finish, on $where:"
say "  1. Turn on Developer mode (top right)"
say "  2. Click Load unpacked and $pick"
say "  3. Open https://www.linkedin.com/notifications/ (the bar appears at the bottom)"
say ""
say "LNRA_RESULT=manual"
