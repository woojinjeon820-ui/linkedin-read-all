#!/usr/bin/env bash
# Zip the extension for a GitHub release or the Chrome Web Store: dist/linkedin-read-all-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(node -p "require('./extension/manifest.json').version")
mkdir -p dist
out="dist/linkedin-read-all-$version.zip"
rm -f "$out"
(cd extension && zip -qr "../$out" . -x '.*')
echo "$out"
