#!/usr/bin/env bash
# Plan passive allocations on a PoB XML and save the result.
# Usage: tools/pob_plan.sh BUILD.xml PLAN.json OUT.xml(absolute)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
XML="$(realpath "$1")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_plan.lua" "$XML" "$(realpath "$2")" "$3"
