# CLAUDE.md — working in poe-pob-tools

This repo lets Claude analyse Path of Exile 1 characters and builds with headless Path of Building (PoB), compare purchases, and publish a build progression page. The person you're helping is a player. Talk in their language and in game terms (DPS, EHP, resists, div/chaos), and keep script internals out of the conversation unless they ask.

## First-time setup (check before anything else)

```sh
git submodule update --init          # PoB checkout at tools/vendor/PathOfBuilding
luajit -v                            # needs LuaJIT 2.1 (apt install luajit)
ls tools/data/timeless/*.bin || tools/gen_timeless.py   # timeless jewel tables, ~450 MB, gitignored
```

Quick sanity test: decode any PoB code to XML and run `tools/pob_xml.sh BUILD.xml "" "" "" "<Main Skill>"`. It should print JSON with `CombinedDPS` and `TotalEHP`.

## Getting the player's data

Ask for the account name (`Name#1234`), the character name and the league. Keep account names, character names, emails and stash contents out of anything committed to this repo or sent to third-party services. Player data goes in `builds/` and `snapshots/`, which are gitignored.

- **Character snapshot**: needs a browser logged into pathofexile.com (e.g. the Playwright MCP). From a page on that domain, `fetch` and save `{items, passives}` to `snapshots/<char>.json`:
  - `/character-window/get-items?accountName=<Name%231234>&realm=pc&character=<char>`
  - `/character-window/get-passive-skills?accountName=...&realm=pc&character=<char>`
  - `/character-window/get-characters?accountName=...&realm=pc` lists characters
  - `/character-window/get-stash-items?accountName=...&realm=pc&league=<league>&tabs=1&tabIndex=<n>` gets stash tabs. Use it to find items the player already owns but hasn't equipped.
  - On "Just a moment..." (Cloudflare), wait a few seconds and retry from the page.
- **Reference builds**: poe.ninja builds pages (`https://poe.ninja/poe1/builds/<league>?items=<Unique+Name>&class=<Ascendancy>`). The character API is `/api/protected/characters/poe1/builds/<version>/character?account=..&name=..&overview=<league>&type=0&timeMachine=`. Read `<version>` from the page's network requests. A dump of ~30 similar characters is the best evidence for "what do people actually use" and also gives item icons.
- **PoB codes**: pobb.in / PoB export codes are base64url(zlib(xml)). Upload with `POST https://pobb.in/pob/`, body = base64url(zlib(xml)); the response is the id.

## Rules that matter (learned the hard way)

1. **Fetch a fresh snapshot before every analysis or buying advice.** Players change gear constantly, and stale data leads to wrong advice.
2. **Never tell them to buy what they already have.** Check equipped items and stash first. Show every suggestion as a delta against the item currently in that slot, using `pob_swapitems.sh` or `pob_variants.py`.
3. **PoB numbers are estimates. Label them as such and verify before claiming.** PoB doesn't model everything:
   - returning projectiles (Nimis);
   - Wine of the Prophet buffs;
   - some uniques' conditional effects.
   When PoB can't answer, use poe.ninja usage data and say which source you used.
4. **Calculate the way they play**: flasks on (`{"_flasks": true}` in the config) and the bandit/pantheon they really use. The snapshot doesn't include the bandit.
5. **Trade links**:
   - always `status: securable`;
   - uniques also need **Foulborn: No** (`filters.misc_filters.filters.mutated.option = "false"`), or prices come from the mutated versions;
   - filter the rolls that matter (e.g. Cinderswallow with Malediction, Watcher's Eye mods, Impossible Escape keystone);
   - test which rolls matter in PoB first and say which don't.
6. **Trade search ids are gzip+base64url of the query JSON** (`viewer_lib.trade_id`). Build links offline and verify by decoding. When unsure, open one in the browser once.
7. **Prices**: use the median of the 3 cheapest listings, convert with the current chaos/div rate (trade exchange API), and say the date.

## PoB gotchas

- Create items from raw text with `new("Item"):Item(raw)`. Timeless jewels need a `Radius: Large` line or their radius is ignored.
- `pob_swapitems.sh`: `""` empties a slot. Jewel sockets are named `Jewel <passive node id>`. Find the ids in the XML's `<Socket nodeId=...>` entries.
- Removing a jewel like Impossible Escape or a cluster deallocates the nodes that depended on it. Adding it back doesn't reallocate them, so always swap from the original XML.
- `pob_trim.sh` removes the least valuable leaf nodes to fit a level. `KEEP_OVERRIDES=1` keeps runegraft/tattoo nodes.
- If two configurations give identical DPS to the last digit, check why (node counts, item really applied) before reporting.

## Typical tasks

- **"How is my character doing / what should I upgrade?"**: fresh snapshot → `pob.sh SNAP.json CONFIG.json "<Main Skill>"` → compare with reference builds → `pob_variants.py` for candidate swaps → trade links for the winners.
- **"Plan my next build"**: get the reference PoB (poe.ninja or a guide) → swap in what the player owns (`pob_swapitems.sh`) → list what's missing with trade links and prices → build the viewer.
- **"Which is better, X or Y?"**: run both in PoB and give the delta. Also give the poe.ninja usage split when PoB can't model the difference.

## Viewer workflow (progression page)

The viewer is a static page with an inventory paper doll, game-style tooltips, stages, per-slot variations with DPS/EHP deltas, trade links, gem links and a pobb.in link per combination. It's precomputed, so no server is needed.

1. `mkdir -p builds/<name>/inputs && cp tools/viewer/example_spec.py builds/<name>/spec.py`
2. Inputs:
   - `base_<level>.xml`: the reference PoB per stage, trimmed with `pob_trim.sh` for lower levels;
   - `owned.json`: the player's items as raw PoB text, per slot;
   - `ninja_chars.json`: poe.ninja dump, for icons;
   - `icon_overrides.json`: bases whose only art in the dump is unique art. Get a rare's icon from the trade API.
3. Edit `spec.py`: `ITEMS`, `SLOTS`, `CHOICES`, `STAGES`, `NOTES`. Model rares at the minimum of their trade search.
4. Gem prices: `python3 -c "import sys; sys.path.insert(0,'tools/viewer'); import gems, json; print(json.dumps(gems.price_queries('builds/<name>/inputs/base_<level>.xml')))"`. Run the queries through the logged-in browser (POST `/api/trade/search/<league>` with `{query, sort:{price:'asc'}}`, then `/api/trade/fetch/<ids>?query=<id>`, ~5 s apart to respect rate limits), then write `inputs/gem_prices.json`.
5. `tools/viewer/build_viewer.py builds/<name>` (`--items-only` to refresh texts/links without PoB runs).
6. Serve: `cd builds/<name>/site && python3 -m http.server 8765`. Phone on the same Wi-Fi: `http://<LAN IP>:8765/`. Outside the home network: `cloudflared tunnel --url http://localhost:8765` (quick tunnel; never edit the user's existing named tunnels). The page also works as a hosted artifact: publish `index.html` with `data.json` and `icons/*`.

The page's UI strings are in Portuguese (pt-BR) in `tools/viewer/template.html`; translate them if the player prefers another language.
