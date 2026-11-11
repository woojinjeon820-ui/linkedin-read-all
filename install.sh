#!/usr/bin/env bash
# LinkedIn Read-All installer / updater (macOS and Linux; on Windows it runs install.ps1).
#
#   curl -fsSL https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.sh | bash
#
# Downloads the latest release, unpacks it to ~/LinkedIn-Read-All, copies that path to
# your clipboard, and opens your browser's Extensions page. Browsers only allow
# one-click installs from their web stores, so the last step is yours:
# Developer mode on -> Load unpacked -> paste the path.
#
# Re-run it any time to update, then press the reload icon on the extension's card.
#
# Options (environment variables):
#   LNRA_DIR=/path       install somewhere else (default: ~/LinkedIn-Read-All)
#   LNRA_BROWSER=name    aside | chrome | edge | brave | arc | chromium (default: auto-detect)
#   LNRA_NO_OPEN=1       don't open the browser
#   LNRA_NO_CLIPBOARD=1  don't touch the clipboard
set -euo pipefail

REPO="woojinjeon820-ui/linkedin-read-all"
DEST="${LNRA_DIR:-$HOME/LinkedIn-Read-All}"
NAME="LinkedIn Read-All"

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

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
  export WSLENV="${WSLENV:+$WSLENV:}LNRA_DIR:LNRA_BROWSER:LNRA_NO_AUTOMATE:LNRA_NO_OPEN:LNRA_NO_CLIPBOARD"
  say "Windows detected: running the Windows installer (install.ps1)..."
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "irm 'https://raw.githubusercontent.com/$REPO/main/install.ps1' | iex"
fi

for cmd in curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed."
done

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
