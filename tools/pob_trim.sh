#!/usr/bin/env bash
# Trim a PoB tree to the points available at a level (drops least valuable leaves first).
# Usage: tools/pob_trim.sh BUILD.xml LEVEL OUT.xml(absolute) "Main Skill"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
XML="$(realpath "$1")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_trim.lua" "$XML" "$2" "$3" "$4"
