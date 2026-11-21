#!/usr/bin/env bash
# Value of every unallocated node reachable with one point.
# Usage: tools/pob_nextnode.sh BUILD.xml "Main Skill"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
XML="$(realpath "$1")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_nextnode.lua" "$XML" "$2"
