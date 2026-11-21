# poe-pob-tools

Headless [Path of Building](https://github.com/PathOfBuildingCommunity/PathOfBuilding) (PoE 1) scripts: calculate a character or a PoB build from the command line, compare item and gem swaps, trim a tree to a level, value passives and masteries, and generate a static progression page with trade links (the "viewer").

Everything runs on stock LuaJIT against an unmodified PoB checkout (git submodule at `tools/vendor/PathOfBuilding`).

## Setup

```sh
git clone --recurse-submodules https://github.com/thxmxx/poe-pob-tools
cd poe-pob-tools
sudo apt install luajit            # or your distro's luajit 2.1
tools/gen_timeless.py              # decompress timeless jewel tables (~450 MB, gitignored)
```

The scripts deal with two gaps between stock LuaJIT and PoB's own runtime:

- PoB's bundled LuaJIT accepts compound assignment (`a += b`, `s ..= t`). Each `pob_*.lua` rewrites those lines while loading PoB's files.
- Headless PoB has no `Inflate()`, so timeless jewel data is read from `tools/data/timeless/*.bin` (made by `gen_timeless.py`).

## Inputs

- **Character snapshot** (`SNAP.json`): `{"items": <get-items>, "passives": <get-passive-skills>}` from `https://www.pathofexile.com/character-window/get-items?accountName=...&realm=pc&character=...` and `.../get-passive-skills?...`, fetched from a logged-in browser session.
- **PoB XML**: decode a pobb.in / PoB export code (base64url + zlib) to XML.
- **Config JSON**: PoB ConfigOptions variable names, e.g. `{"_flasks": true, "conditionLowLife": true, "usePowerCharges": true}`. `_flasks` ticks every flask as active.

## Scripts

| Script | What it does |
|---|---|
| `pob.sh SNAP.json [CONFIG.json\|-] [MAIN_SKILL]` | Calculate a character snapshot. Prints stats, life breakdown, reservations, all numeric outputs (JSON). `EXPORT_XML=out.xml` also saves the PoB XML. |
| `pob_variants.py SNAP.json CONFIG.json [variant ...]` | Run variants of a snapshot (item/gem/config edits) and compare. |
| `pob_xml.sh BUILD.xml SPEC ITEMSET SKILLSET MAIN_SKILL` | Calculate a PoB XML, choosing tree spec / item set / skill set by title prefix. |
| `pob_swapitems.sh BUILD.xml ITEMS.json OUT.xml "Main Skill" [LEVEL]` | Put raw item texts into slots (`{"Boots": "<raw item>", "Jewel 61834": "", ...}`; `""` empties a slot), activate flasks, recalc, save the XML. |
| `pob_trim.sh BUILD.xml LEVEL OUT.xml "Main Skill"` | Trim a tree to the points available at LEVEL, removing the least valuable leaves first. `KEEP_OVERRIDES=1` keeps runegraft/tattoo nodes. |
| `pob_nextnode.sh BUILD.xml "Main Skill"` | Value of every unallocated node reachable with one point. |
| `pob_plan.sh BUILD.xml PLAN.json OUT.xml` | Plan passive allocations on a PoB XML and save the result. |
| `pob_mastery.sh BUILD.xml "Main Skill"` | DPS/EHP delta of every mastery effect choice. |
| `pob_dmgtaken.sh BUILD.xml "Main Skill"` | Dump damage-taken modifiers by type. |
| `pob_srcdump.sh BUILD.xml "Main Skill"` | Dump where each modifier comes from. |
| `charinfo.py SNAP.json` | Readable dump of a snapshot (gear, gems, passives). |
| `chardiff.py OLD.json NEW.json` / `track.py OLD NEW` | Diff two snapshots (gear, gems, passives). |
| `gen_timeless.py` | Generate `data/timeless/*.bin` from PoB's timeless jewel data. |

Raw item text is PoB's format (the text you get from "Copy" in PoB or Ctrl+C in game). Timeless jewels need a `Radius: Large` line or PoB ignores their radius.

## Viewer: a precomputed build progression page

`tools/viewer/` builds a static page (pobb.in-like): paper doll with item icons and game-style tooltips, progression stages, per-slot variations with DPS/EHP deltas, trade links with the important rolls, gem links with trade per level/quality, and a pobb.in link for every stage × variation combination. All numbers are precomputed with headless PoB, so the page needs no server.

```sh
tools/viewer/build_viewer.py builds/<name>             # PoB runs + pobb.in uploads + icons
tools/viewer/build_viewer.py builds/<name> --items-only  # texts/links/prices only, reuse PoB results
# output: builds/<name>/site/{index.html,data.json,icons/}
```

A build folder has:

```
builds/<name>/
  spec.py                 # everything build-specific (see below)
  inputs/
    base_<level>.xml      # PoB XML per stage tree (pob_trim.sh to make lower-level trees)
    ninja_chars.json      # poe.ninja character dump of similar builds -> item/gem icons
    icon_overrides.json   # {"Topaz Ring": "<icon url>"} for bases only seen with unique art
    gem_prices.json       # {"rate": <chaos per div>, "date": "...", "prices": {"<gem> <lvl>/<q>": div}}
    pobb_cache.json       # xml sha1 -> pobb.in url (written by the generator)
  site/                   # generated
```

`spec.py` defines:

- page info: `TITLE`, `HEADING`, `SKILL` (PoB main skill), `CHAR`, `LEAGUE`, `REFERENCE`, `TRADE`, `NOTES` (HTML strings), `DEFAULT_STAGE`;
- paths: `IN`, `GEM_XML` (socket groups for the skills section), `NINJA_CHARS`;
- `ITEMS`: `{key: dict(raw=<PoB item text>, icon=<unique name or base type>, owned=bool, price=div, roll=html, links=[(label, trade_url)], name=optional)}`;
- `SLOTS`: `[(pob_slot, label, 'gear'|'flask'|'jewel')]`, jewels as `'Jewel <nodeId>'`;
- `CHOICES`: `{slot: [item keys]}`, the variations (first = default);
- `STAGES`: `[dict(id, label, level, base='base_91.xml', desc, slots={slot: item_key | '*'})]`, where `'*'` = pick from `CHOICES`.

`viewer_lib.py` has helpers for specs: `trade_id(query)` builds a trade search URL id offline (ids are gzip+base64url of the query JSON), `unique_q(name, stats)` builds a unique search (securable, Foulborn: No), and `ref_items(xml)` gets raw item texts from a PoB XML by slot.

Gem prices come from the trade API through a logged-in browser. `gems.price_queries(xml)` lists the queries; POST each to `/api/trade/search/<league>`, fetch the cheapest results, and write `gem_prices.json`. `data/trade_gems.json` is the trade site's gem list (`/api/trade/data/items`), used for support names, transfigured gem discriminators and to skip item-granted skills.

## License

MIT for the scripts here. Path of Building is MIT (its own repo). Item art and game data belong to Grinding Gear Games.
