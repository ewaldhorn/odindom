#!/bin/bash
# run.sh — Build every example + demo, then start the dev server.
#
# Matches the run.sh convention used by ../godom and ../zigdom (build, then
# serve on :9000 with http-server -c-1 to disable caching of the .wasm).
# Unlike those repos there is no single docs/ output — OdinDOM ships two
# separate runnable apps (examples/click-rect and demo), so the whole repo
# root is served instead of one docs/ directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building WASM ..."
./build.sh

echo "==> Starting dev server on http://localhost:9000 ..."
echo "    examples/click-rect: http://localhost:9000/examples/click-rect/index.html"
echo "    demo:                http://localhost:9000/demo/index.html"
npx http-server . -p 9000 -c-1
