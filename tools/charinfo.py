#!/usr/bin/env python3
"""Full dump of one character snapshot ({items, passives} from get-items + get-passive-skills).
Usage: charinfo.py SNAP.json
Shows gear with real link groups, gem level/quality, flasks, jewels, keystones/notables,
masteries WITH runegraft/tattoo overrides (skill_overrides), and allocated cluster nodes."""
import json, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
TREE = json.load(open(os.path.join(HERE, 'data', 'tree.json')))['nodes']


def load(f):
    d = json.loads(open(f).read().strip())
    return json.loads(d) if isinstance(d, str) else d


def t(m):
    return m if isinstance(m, str) else (m.get('description') or '')


def prop(g, name):
    return next((p['values'][0][0] for p in g.get('properties', []) if p['name'] == name and p.get('values')), '')


def item(i):
    print(f"== {i['inventoryId']}{'#'+str(i.get('x')) if i['inventoryId'].startswith('Flask') else ''}: "
          f"{(i.get('name', '') + ' ' + i['typeLine']).strip()}{'  [corrupted]' if i.get('corrupted') else ''}")
    for k in ('enchantMods', 'implicitMods', 'fracturedMods', 'explicitMods', 'craftedMods', 'mutatedMods'):
        for m in i.get(k, []):
            print(f"    {k[:5]:5s} {t(m)}")
    socks, gems = i.get('sockets', []), i.get('socketedItems', [])
    if gems:
        groups = defaultdict(list)
        for g in gems:
            grp = socks[g['socket']]['group'] if g.get('socket') is not None and g['socket'] < len(socks) else '?'
            groups[grp].append(f"{g['typeLine']} {prop(g, 'Level')}/{prop(g, 'Quality') or '0%'}".replace(' (Max)', ''))
        for grp, gs in groups.items():
            print(f"    link{grp}: " + ' + '.join(gs))
        empty = len(socks) - len(gems)
        if empty > 0:
            print(f"    ({empty} empty socket(s))")


def main(f):
    D = load(f)
    if 'items' not in D:  # {name: {items, passives}} wrapper
        D = next(v for v in D.values() if isinstance(v, dict) and 'items' in v)
    c, P = D['items']['character'], D['passives']
    print(f"# {c['name']} lvl {c['level']} {c['class']}  nodes={len(P['hashes'])}")
    for i in D['items']['items']:
        if i['inventoryId'] not in ('MainInventory', 'ExpandedMainInventory'):
            item(i)
    print('## jewels (x = jewelSlots index)')
    for j in P.get('items', []):
        print(f"-- x={j.get('x')} ", end='')
        item(j)
    ov = P.get('skill_overrides') or {}
    print('## keystones / notables / ascendancy')
    ks = [TREE[str(h)]['name'] for h in P['hashes'] if TREE.get(str(h), {}).get('isKeystone')]
    nt = [TREE[str(h)]['name'] for h in P['hashes'] if TREE.get(str(h), {}).get('isNotable') and not TREE[str(h)].get('ascendancyName')]
    asc = [TREE[str(h)]['name'] for h in P['hashes'] if TREE.get(str(h), {}).get('ascendancyName')]
    print('  keystones:', ks)
    print('  notables :', sorted(nt))
    print('  ascend   :', asc)
    print('## masteries (runegraft overrides win)')
    for h, e in (P.get('mastery_effects') or {}).items():
        n = TREE.get(str(h), {})
        orig = next((me['stats'] for me in n.get('masteryEffects', []) if str(me['effect']) == str(e)), [])
        if str(h) in ov:
            print(f"  {h} {n.get('name')}: RUNEGRAFT {ov[str(h)]['name']} -> {ov[str(h)]['stats']}  (base effect {orig} is REPLACED)")
        else:
            print(f"  {h} {n.get('name')}: {orig}")
    for h, o in ov.items():
        if not TREE.get(str(h), {}).get('isMastery'):
            print(f"  override on non-mastery {h} {TREE.get(str(h), {}).get('name')}: {o.get('name')} {o.get('stats')}")
    print('## allocated cluster nodes')
    ex = set(map(str, P.get('hashes_ex', [])))
    for k, v in (P.get('jewel_data') or {}).items():
        for h, n in ((v.get('subgraph') or {}).get('nodes') or {}).items():
            if h in ex:
                print(f"  [x={k}] {n.get('name')}: {n.get('stats', [])}")
    for k in ('alternate_ascendancy', 'bandit_choice', 'pantheon_major', 'pantheon_minor'):
        if k in P:
            print(f"  {k}: {P[k]}")


if __name__ == '__main__':
    main(sys.argv[1])
