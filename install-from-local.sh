#!/usr/bin/env bash

set -euo pipefail

mkdir -p ~/.local/bin
cp jai/jai.sh ~/.local/bin/jai
cp jai/jai-cursorhooks.sh ~/.local/bin/jai-cursorhooks
cp sekey/sekey.sh ~/.local/bin/sekey
chmod +x ~/.local/bin/jai ~/.local/bin/jai-cursorhooks ~/.local/bin/sekey
echo "Optional Cursor integration:"
echo "  jai install-cursorhooks [directory]   # writes .cursor/hooks.json (directory defaults to ~)"

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not found. jai-cursorhooks JSON parsing needs jq."
  echo "Install jq, then run: jai install-cursorhooks"
fi