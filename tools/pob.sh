#!/usr/bin/env bash
# Headless PoB calc. Usage: tools/pob.sh SNAP.json [CONFIG.json|-] [MAIN_SKILL]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SNAP="$(realpath "$1")"; CFG="${2:--}"; [ "$CFG" != "-" ] && CFG="$(realpath "$CFG")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_calc.lua" "$SNAP" "$CFG" "${3:-}"
