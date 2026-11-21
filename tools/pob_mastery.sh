#!/usr/bin/env bash
# Value (DPS/EHP delta) of every mastery effect choice on a PoB XML build.
# Usage: tools/pob_mastery.sh BUILD.xml "Main Skill"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
XML="$(realpath "$1")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_mastery.lua" "$XML" "$2"
