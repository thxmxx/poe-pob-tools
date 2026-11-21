#!/usr/bin/env python3
"""Diff two single-character snapshots ({items, passives}) or a {name:{items,passives}} wrapper.
Usage: chardiff.py OLD NEW [charname]"""
import json, sys, os
T = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'tree.json')))['nodes']
def L(f, name=None):
    d = json.loads(open(f).read().strip()); d = json.loads(d) if isinstance(d, str) else d
    if 'items' not in d: d = d[name]
    return d
t = lambda m: m if isinstance(m, str) else m.get('description', '')
def gear(D):
    o = {}
    for i in D['items']['items']:
        if i['inventoryId'] in ('MainInventory', 'ExpandedMainInventory'): continue
        k = i['inventoryId'] + (f"#{i.get('x')}" if i['inventoryId'].startswith('Flask') else '')
        o[k] = ((i.get('name', '') + ' ' + i['typeLine']).strip(),
                [t(m) for kk in ('implicitMods', 'explicitMods', 'craftedMods', 'fracturedMods', 'enchantMods') for m in i.get(kk, [])],
                [f"{g['typeLine']} {next((p['values'][0][0] for p in g.get('properties', []) if p['name'] == 'Level'), '')}" for g in i.get('socketedItems', [])])
    for j in D['passives'].get('items', []):
        o['Jewel:' + str(j.get('name')) + ':' + j['typeLine']] = (j['typeLine'], [t(m) for m in j.get('explicitMods', [])], [])
    return o
name = sys.argv[3] if len(sys.argv) > 3 else None
old, new = L(sys.argv[1], name), L(sys.argv[2], name)
a, b = gear(old), gear(new)
print('level', old['items']['character']['level'], '->', new['items']['character']['level'])
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k): print(k, '\n  old', a.get(k), '\n  new', b.get(k))
ha, hb = set(old['passives']['hashes']), set(new['passives']['hashes'])
nm = lambda h: T.get(str(h), {}).get('name', str(h))
print('tree +', [nm(h) for h in hb - ha], ' -', [nm(h) for h in ha - hb])
ex = set(map(str, new['passives'].get('hashes_ex', [])))
for v in (new['passives'].get('jewel_data') or {}).values():
    for h, n in ((v.get('subgraph') or {}).get('nodes') or {}).items():
        if h in ex: print('  cluster alloc', n.get('name'))
