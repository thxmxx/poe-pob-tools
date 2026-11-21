#!/usr/bin/env python3
"""Run headless PoB on variants of a character snapshot and compare.
Usage: pob_variants.py SNAP.json CONFIG.json VARIANTS.py [variant ...]   (no variant names = all)
Each variant edits a copy of the snapshot (items/gems) and/or the config (customMods, conditions).
VARIANTS.py is executed here and registers variants with the helpers in scope, e.g.:

    @variant('gem21', 'Main skill 21/20 corrupted', '~2 div')
    def _(s, c): set_gem(s, 'Divine Retribution', level=21, corrupted=True)

    @variant('mastery', 'Custom mod from a mastery', '1 point')
    def _(s, c): add_mods(c, '+1% to Critical Strike Multiplier per 10 Maximum Energy Shield on Shield')

Set MAINSKILL to pick the main skill."""
import copy, json, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))


def load(f):
    d = json.loads(open(f).read().strip())
    return json.loads(d) if isinstance(d, str) else d


def items(s):
    return s['items']['items']


def find_item(s, inv, x=None):
    pool = items(s) + s['passives'].get('items', [])
    return next(i for i in pool if i['inventoryId'] == inv and (x is None or i.get('x') == x))


def set_gem(s, name, level=None, quality=None, corrupted=None):
    for i in items(s):
        for g in i.get('socketedItems', []):
            if g['typeLine'] == name:
                props = g.setdefault('properties', [])
                for key, val in (('Level', level), ('Quality', quality)):
                    if val is None:
                        continue
                    p = next((p for p in props if p['name'] == key), None)
                    txt = f"+{val}%" if key == 'Quality' else str(val)
                    if p:
                        p['values'] = [[txt, 0]]
                    else:
                        props.append({'name': key, 'values': [[txt, 0]], 'displayMode': 0})
                if corrupted is not None:
                    g['corrupted'] = corrupted
                return
    raise KeyError(name)


def replace_mod(item, old_sub, new):
    for k in ('explicitMods', 'implicitMods', 'craftedMods'):
        for n, m in enumerate(item.get(k, [])):
            if old_sub in (m if isinstance(m, str) else m.get('description', '')):
                item[k][n] = new
                return
    raise KeyError(old_sub)


def swap_item(s, inv, x, name, typeline, frame, explicit, implicit=()):
    it = find_item(s, inv, x)
    it.update({'name': name, 'typeLine': typeline, 'baseType': typeline, 'frameType': frame,
               'explicitMods': list(explicit), 'implicitMods': list(implicit), 'craftedMods': [],
               'enchantMods': [], 'fracturedMods': [], 'mutatedMods': [], 'corrupted': False})


def add_mods(cfg, *lines):
    cfg['customMods'] = '\n'.join(filter(None, [cfg.get('customMods', '')] + list(lines)))


# ---- variants: (description, cost note, fn(snap, cfg)) -------------------------------------
V = {}
def variant(key, desc, cost):
    def deco(fn):
        V[key] = (desc, cost, fn); return fn
    return deco


KEYS = ['Life', 'CombinedDPS', 'AverageHit', 'CritChance', 'LifeCost', 'TotalEHP', 'ChaosResist', 'ColdResist']


def run(snap, cfg):
    with tempfile.TemporaryDirectory() as td:
        sp, cp = os.path.join(td, 's.json'), os.path.join(td, 'c.json')
        json.dump(snap, open(sp, 'w')); json.dump(cfg, open(cp, 'w'))
        out = subprocess.run([os.path.join(HERE, "pob.sh"), sp, cp] + ([os.environ["MAINSKILL"]] if os.environ.get("MAINSKILL") else []), capture_output=True, text=True).stdout
    return json.loads(out[out.index('\n{') + 1:])['stats']


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    snap, cfg = load(sys.argv[1]), load(sys.argv[2])
    exec(compile(open(sys.argv[3]).read(), sys.argv[3], 'exec'), globals())  # registers variants via @variant
    keys = sys.argv[4:] or list(V)
    jobs = {'base': (snap, cfg)}
    for k in keys:
        s, c = copy.deepcopy(snap), copy.deepcopy(cfg)
        V[k][2](s, c)
        jobs[k] = (s, c)
    with ThreadPoolExecutor(8) as ex:
        res = dict(zip(jobs, ex.map(lambda j: run(*j), jobs.values())))
    b = res['base']
    print(f"{'variant':16s} {'DPS':>9s} {'dDPS%':>7s} {'Life':>7s} {'dLife':>6s} {'EHP':>8s} {'chaos':>5s} {'cold':>5s}  cost / desc")
    for k, r in res.items():
        dd = (r['CombinedDPS'] / b['CombinedDPS'] - 1) * 100
        desc, cost = (V[k][0], V[k][1]) if k in V else ('baseline', '')
        print(f"{k:16s} {r['CombinedDPS']/1e3:8.0f}k {dd:+6.1f}% {r['Life']:7.0f} {r['Life']-b['Life']:+6.0f} "
              f"{r.get('TotalEHP', 0)/1e3:7.0f}k {r['ChaosResist']:5.0f} {r['ColdResist']:5.0f}  {cost} | {desc}")


if __name__ == '__main__':
    main()
