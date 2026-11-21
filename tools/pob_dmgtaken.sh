#!/usr/bin/env bash
# Dump the damage-taken modifiers (by type) of a PoB XML build.
# Usage: tools/pob_dmgtaken.sh BUILD.xml "Main Skill"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
XML="$(realpath "$1")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_dmgtaken.lua" "$XML" "$2"
