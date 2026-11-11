#!/usr/bin/env bash
# End-to-end test of the installed extension on the real LinkedIn notifications page,
# driven through the Aside browser CLI (https://aside.com).
#
# Usage: tests/live/run-aside.sh <extension-id>
#   Find the id on chrome://extensions (Developer mode on) under "LinkedIn Read-All".
#
# Requires: Aside running, signed in to LinkedIn, extension loaded unpacked.
# WARNING: clears the extension's local read/unread state before running.
# It only closes the tabs it opens itself.
set -euo pipefail
id="${1:?usage: $0 <extension-id>}"
here="$(cd "$(dirname "$0")" && pwd)"
aside repl "$(sed "s/__EXT_ID__/$id/" "$here/e2e.repl.js")" | grep -E '^(PASS|FAIL|INFO|TOTAL)'
