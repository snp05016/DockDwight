#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"
./scripts/build_app.sh
pkill -x DockDwight 2>/dev/null || true
rm -rf /Applications/DockDwight.app
cp -R DockDwight.app /Applications/DockDwight.app
/Applications/DockDwight.app/Contents/MacOS/DockDwight --enable-login
open /Applications/DockDwight.app
echo "DockDwight installed. Control+Option+D toggles him."

