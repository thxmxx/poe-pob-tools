#!/usr/bin/env python3
"""Compare build snapshots. Usage: track.py OLD_SNAP NEW_SNAP
Snapshots are {"me": {items, passives}, "ref": {items, passives}} as saved by the
browser fetch of /character-window/get-items + get-passive-skills."""
import json, re, sys, os

TREE = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'tree.json')))['nodes']

def load(f):
    d = json.loads(open(f).read().strip())
    return json.loads(d) if isinstance(d, str) else d

def t(m):
    return m if isinstance(m, str) else (m.get('description') or '')

def name(h):
    n = TREE.get(str(h), {})
    return (n.get('name') or str(h)) + ('*' if n.get('isNotable') or n.get('isKeystone') else '') + (f" [asc:{n['ascendancyName']}]" if n.get('ascendancyName') else '')

def gear(D):
    out = {}
    for i in D['items']['items']:
        inv = i['inventoryId']
        if inv in ('MainInventory', 'ExpandedMainInventory'):
            continue
        k = inv + (f"#{i.get('x')}" if inv.startswith('Flask') else '')
        mods = [t(m) for kk in ('implicitMods', 'explicitMods', 'craftedMods', 'fracturedMods', 'enchantMods') for m in i.get(kk, [])]
        gems = [f"{g['typeLine']} {next((p['values'][0][0] for p in g.get('properties', []) if p['name'] == 'Level'), '')}".strip() for g in i.get('socketedItems', [])]
        out[k] = (f"{i.get('name', '')} {i['typeLine']}".strip(), mods, gems)
    for j in D['passives'].get('items', []):
        out[f"Jewel:{j.get('name')}"] = (f"{j.get('name')} {j['typeLine']}", [t(m) for m in j.get('explicitMods', [])], [])
    return out

PAT = {
    'flat_str': r'^\+(\d+) to (?:Strength|all Attributes)(?: and \w+)?$|^\+(\d+) to Strength and \w+$',
    'inc_str': r'^(\d+)% increased (?:Strength|Attributes)$',
    'spell_inc': r'^(\d+)% increased Spell Damage$',
    'atk_spd': r'^(\d+)% increased Attack Speed(?: with (?:Maces or Sceptres|One Handed Melee Weapons)| while holding a Shield)?$',
    'crit_inc': r'^(\d+)% increased (?:Global |Melee )?Critical Strike Chance$',
    'crit_multi': r'^\+(\d+)% to (?:Global |Melee )?Critical Strike Multiplier(?: with One Handed Melee Weapons)?$',
    'life_flat': r'^\+(\d+) to maximum Life$',
    'life_inc': r'^(\d+)% increased maximum Life$',
}

import math
G, C = None, None
def _pos(h):
    n = TREE[str(h)]; g = G[str(n['group'])]; r = C['orbitRadii'][n['orbit']]; k = C['skillsPerOrbit'][n['orbit']]
    a = 2 * math.pi * n['orbitIndex'] / k  # uniform-angle approximation
    return g['x'] + r * math.sin(a), g['y'] - r * math.cos(a)

def lethal_pride(P):
    """Lethal Pride: +2 Str on attribute travel nodes, +4 Str on other small nodes in radius (approx)."""
    global G, C
    if G is None:
        full = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'tree.json')))
        G, C = full['groups'], full['constants']
    out = []
    for j in P.get('items', []):
        if j['typeLine'] != 'Timeless Jewel' or j.get('name') != 'Lethal Pride':
            continue
        slots = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'tree.json')))['jewelSlots']
        sx, sy = _pos(slots[j['x']])
        for h in P['hashes']:
            n = TREE.get(str(h), {})
            if 'group' not in n or n.get('isNotable') or n.get('isKeystone') or n.get('ascendancyName') or n.get('isJewelSocket') or n.get('isMastery'):
                continue
            x, y = _pos(h)
            if math.hypot(x - sx, y - sy) <= 1800:
                travel = any(re.match(r'^\+\d+ to (Strength|Dexterity|Intelligence)$', m) for m in n.get('stats', []))
                out.append(f"+{2 if travel else 4} to Strength")
    return out

def stats(D):
    mods = []
    for i in D['items']['items']:
        inv = i['inventoryId']
        if inv in ('MainInventory', 'ExpandedMainInventory') or inv.startswith('Flask'):
            continue
        ms = [t(m) for k in ('implicitMods', 'explicitMods', 'craftedMods', 'fracturedMods') for m in i.get(k, [])]
        if inv == 'Weapon':  # local weapon mods don't count globally (except Str)
            ms = [m for m in ms if 'increased' not in m or 'Strength' in m]
        mods += ms
    for j in D['passives'].get('items', []):
        mods += [t(m) for m in j.get('explicitMods', [])]
    P = D['passives']
    for h in P['hashes']:
        mods += TREE.get(str(h), {}).get('stats', [])
    ov = P.get('skill_overrides') or {}  # runegrafts/tattoos replace the node's stats
    for h in list(P['hashes']):
        if str(h) in ov and not TREE.get(str(h), {}).get('isMastery'):
            mods += ov[str(h)].get('stats', [])
            for st in TREE.get(str(h), {}).get('stats', []):
                if st in mods: mods.remove(st)
    for h, e in (P.get('mastery_effects') or {}).items():  # chosen mastery effects (unless runegrafted)
        if str(h) in ov:
            mods += ov[str(h)].get('stats', []); continue
        mods += next((me['stats'] for me in TREE.get(str(h), {}).get('masteryEffects', []) if str(me['effect']) == str(e)), [])
    ex = set(map(str, P.get('hashes_ex', [])))  # allocated cluster-jewel nodes
    for v in (P.get('jewel_data') or {}).values():
        for h, n in ((v.get('subgraph') or {}).get('nodes') or {}).items():
            if h in ex:
                mods += n.get('stats', [])
    mods += lethal_pride(P)
    acc = {k: 0 for k in PAT}
    res = {'Fire': 0, 'Cold': 0, 'Lightning': 0, 'Chaos': 0}
    for m in mods:
        for k, p in PAT.items():
            x = re.match(p, m)
            if x:
                acc[k] += int(next(g for g in x.groups() if g))
        x = re.match(r'^([+-]\d+)% to (.+?) Resistances?$', m)
        if x:
            ks = ['Fire', 'Cold', 'Lightning'] if 'all Elemental' in x[2] else [k for k in res if k in x[2]]
            for k in ks:
                res[k] += int(x[1])
    s = (32 + acc['flat_str']) * (1 + acc['inc_str'] / 100)
    iw = '50288' in map(str, D['passives']['hashes'])
    k = 0.3 if any('instead grants 3%' in m for m in mods) else 0.2
    c = D['items']['character']
    return {
        'lvl': c['level'], 'nodes': len(D['passives']['hashes']), 'jewels': len(D['passives'].get('items', [])),
        'str': round(s), 'ironwill_atk%': round(s * k * 1.5) if iw else 0, 'spell%': acc['spell_inc'],
        'atk_spd%': acc['atk_spd'], 'crit_inc%': acc['crit_inc'], 'crit_multi': acc['crit_multi'],
        'life_flat': acc['life_flat'], 'life_inc%': acc['life_inc'], 'res(sum)': res,
    }

def diff(label, a, b):
    ga, gb = gear(a), gear(b)
    ch = [k for k in sorted(set(ga) | set(gb)) if ga.get(k) != gb.get(k)]
    ha, hb = set(a['passives']['hashes']), set(b['passives']['hashes'])
    print(f"### {label} changes")
    if not ch and ha == hb:
        print("  (nothing changed)")
    for k in ch:
        print(f"  {k}:\n    old: {ga.get(k)}\n    new: {gb.get(k)}")
    if ha != hb:
        print(f"  tree +{sorted(name(h) for h in hb - ha)}  -{sorted(name(h) for h in ha - hb)}")

if __name__ == '__main__':
    old, new = load(sys.argv[1]), load(sys.argv[2])
    diff('ME', old['me'], new['me'])
    diff('REF', old['ref'], new['ref'])
    sm, sr = stats(new['me']), stats(new['ref'])
    print('### stats (me | ref)')
    print('  NOTE: str/atk_spd/etc are ESTIMATES (no Lethal Pride notable bonuses, no buffs/auras). Trust in-game C panel; jewel x indices >= tree sockets may be cluster sockets.')
    for k in sm:
        print(f"  {k:14s} {sm[k]} | {sr[k]}")
    hm, hr = set(new['me']['passives']['hashes']), set(new['ref']['passives']['hashes'])
    print(f"### tree vs ref: ref has, I lack {sorted(name(h) for h in hr - hm)} | I have, ref lacks {sorted(name(h) for h in hm - hr)}")
