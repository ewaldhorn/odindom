#!/usr/bin/env bash
# Builds every OdinDOM example to WASM.
#
# Usage: ./build.sh [target-dir]
#   target-dir defaults to each example's own directory.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

FLAGS=(-target:js_wasm32 -o:size -no-entry-point)

build_example() {
	local dir="$1"
	local name
	name="$(basename "$dir")"
	echo "==> building $name"
	odin build "$dir" -out:"$dir/$name.wasm" "${FLAGS[@]}"
}

for dir in examples/*/ docs/; do
	dir="${dir%/}"
	if compgen -G "$dir/*.odin" > /dev/null; then
		build_example "$dir"
	fi
done

# docs/ must be self-contained for GitHub Pages, which only serves that one directory and
# can't reach the sibling web/ dir examples/ still load via a relative "../web/odindom.js".
cp web/odindom.js docs/odindom.js

echo
echo "Done. Serve the repo root with any static file server and open e.g.:"
echo "  examples/click-rect/index.html"
echo "  examples/canvas-cmd/index.html"
echo "  docs/index.html"
