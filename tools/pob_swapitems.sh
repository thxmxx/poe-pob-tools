#!/usr/bin/env bash
# Swap items in a PoB XML with raw item texts.
# Usage: tools/pob_swapitems.sh BUILD.xml ITEMS.json OUT.xml(absolute) "Main Skill" [LEVEL]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
XML="$(realpath "$1")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_swapitems.lua" "$XML" "$(realpath "$2")" "$3" "$4" "${5:-}"
