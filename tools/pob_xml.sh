#!/usr/bin/env bash
# Headless PoB calc on a PoB XML (e.g. a decoded guide PoB), choosing tree spec / item set / skill set by title prefix.
# Usage: tools/pob_xml.sh BUILD.xml SPEC_PREFIX ITEMSET_PREFIX SKILLSET_PREFIX "Main Skill"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
XML="$(realpath "$1")"
cd "$HERE/vendor/PathOfBuilding/src"
export LUA_PATH="$HERE/pobshim/?.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;;"
exec luajit "$HERE/pob_xml.lua" "$XML" "$2" "$3" "$4" "$5"
