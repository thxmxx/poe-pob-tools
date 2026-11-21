#!/usr/bin/env python3
"""Build a precomputed PoB progression viewer for one build folder.

Usage: tools/viewer/build_viewer.py builds/<name> [--items-only] [--no-upload]

Reads builds/<name>/spec.py (see builds/charlatan/spec.py and tools/viewer/README.md) and writes
builds/<name>/site/{index.html,data.json,icons/}:
  - every stage x combination of per-slot variants is run through headless PoB
    (tools/pob_swapitems.sh), giving DPS/EHP/life/res, and the resulting XML is uploaded
    to pobb.in (cached by content hash in inputs/pobb_cache.json);
  - item and gem icons are downloaded from the poe.ninja character dump (spec.NINJA_CHARS),
    with inputs/icon_overrides.json for bases that only appear there with unique art;
  - gem trade links come from tools/viewer/gems.py, prices from inputs/gem_prices.json.
--items-only reuses the PoB results already in site/data.json (texts/links/prices only).
"""
import base64, hashlib, importlib.util, itertools, json, os, re, subprocess, sys, tempfile, time, urllib.request, zlib
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from viewer_lib import trade_id, parse_item  # noqa: E402
import gems as G  # noqa: E402

UNIQUE_FRAMES = {3, 9, 10}  # unique, relic/foil variants: their art isn't the base's art


def load_spec(build_dir):
    p = importlib.util.spec_from_file_location('spec', os.path.join(build_dir, 'spec.py'))
    m = importlib.util.module_from_spec(p)
    p.loader.exec_module(m)
    return m


def combos(stage, choices):
    dims = [s for s, v in stage['slots'].items() if v == '*']
    for picks in itertools.product(*[choices[d] for d in dims]):
        yield dict(zip(dims, picks))


def combo_key(pick):
    return '|'.join(f'{k}={pick[k]}' for k in sorted(pick))


def run_one(S, stage, pick):
    slots = {}
    for sid, _, _ in S.SLOTS:
        key = stage['slots'].get(sid)
        if key == '*':
            key = pick[sid]
        slots[sid] = S.ITEMS[key]['raw'] if key else ''
    tmp = tempfile.mkdtemp(prefix='viewer_')
    ip, xp = os.path.join(tmp, 'items.json'), os.path.join(tmp, 'out.xml')
    json.dump(slots, open(ip, 'w'))
    p = subprocess.run([os.path.join(ROOT, 'tools', 'pob_swapitems.sh'), os.path.join(S.IN, stage['base']), ip, xp, S.SKILL, str(stage['level'])],
                       capture_output=True, text=True, timeout=300)
    t = '\n' + p.stdout
    if p.returncode or '\n{' not in t:
        raise RuntimeError(f"{stage['id']} {pick}: {p.stderr[-2000:]}")
    return json.loads(t[t.rindex('\n{'):])['stats'], open(xp).read()


def upload(xml, cache, enabled):
    h = hashlib.sha1(xml.encode()).hexdigest()
    if h in cache or not enabled:
        return cache.get(h)
    body = base64.urlsafe_b64encode(zlib.compress(xml.encode(), 9))
    req = urllib.request.Request('https://pobb.in/pob/', data=body, method='POST', headers={'Content-Type': 'text/plain', 'User-Agent': 'pob-tools'})
    cache[h] = 'https://pobb.in/' + urllib.request.urlopen(req, timeout=60).read().decode().strip()
    time.sleep(0.5)
    return cache[h]


def icon_getter(S, out_dir):
    s = json.load(open(S.NINJA_CHARS))
    s = json.loads(s) if isinstance(s, str) else s
    acc = {}

    def walk(o):
        if isinstance(o, dict):
            if 'icon' in o and 'typeLine' in o:
                if o.get('name'):
                    acc.setdefault(o['name'], o['icon'])
                if o.get('frameType') not in UNIQUE_FRAMES:
                    acc.setdefault(o.get('baseType') or o['typeLine'], o['icon'])
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(s)
    ov = os.path.join(S.IN, 'icon_overrides.json')
    if os.path.exists(ov):
        acc.update(json.load(open(ov)))
    os.makedirs(os.path.join(out_dir, 'icons'), exist_ok=True)

    def get(name):
        url = acc.get(name)
        if not url:
            print('no icon for', name, '(add it to inputs/icon_overrides.json)', file=sys.stderr)
            return None
        fn = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-') + '.png'
        path = os.path.join(out_dir, 'icons', fn)
        stamp = path + '.src'
        if not os.path.exists(path) or (os.path.exists(stamp) and open(stamp).read() != url) or not os.path.exists(stamp):
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            open(path, 'wb').write(urllib.request.urlopen(req, timeout=30).read())
            open(stamp, 'w').write(url)
        return 'icons/' + fn
    return get


def item_data(S, get_icon):
    items = {}
    for k, it in S.ITEMS.items():
        lines = [l for l in (it.get('raw') or '').split('\n') if l.strip()]
        name = it.get('name') or (lines[1] if len(lines) > 1 else k)
        base = lines[2] if len(lines) > 2 and not lines[2].startswith(('Implicits', 'Sockets', 'Unique ID')) else ''
        rarity = lines[0].split(':')[1].strip().lower() if lines else 'rare'
        items[k] = dict(name=name, base=base, rarity='unique' if rarity == 'unique' else 'rare', icon=get_icon(it['icon']), owned=bool(it.get('owned')),
                        price=it.get('price', 0), roll=it.get('roll', ''), links=[list(x) for x in it.get('links', [])], **parse_item(lines))
    return items


def skill_data(S, get_icon):
    gp_path = os.path.join(S.IN, 'gem_prices.json')
    gp = json.load(open(gp_path)) if os.path.exists(gp_path) else {'rate': None, 'date': None, 'prices': {}}
    skills = []
    for gr in G.groups(S.GEM_XML):
        gl = [dict(name=g['name'], level=g['level'], quality=g['quality'], support=G.is_support(g['name']), icon=get_icon(G.icon_name(g['name'])),
                   links=[[lab, S.TRADE + trade_id(G.query(g['name'], l, q)), gp['prices'].get(f"{g['name']} {lab}")] for lab, l, q in G.variants(g)])
              for g in gr['gems']]
        skills.append(dict(slot=gr['slot'], label=gr['label'], gems=gl))
    return skills, gp


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        sys.exit(__doc__)
    build_dir = os.path.abspath(args[0])
    S = load_spec(build_dir)
    out_dir = os.path.join(build_dir, 'site')
    os.makedirs(out_dir, exist_ok=True)
    items_only = '--items-only' in sys.argv
    cache_p = os.path.join(S.IN, 'pobb_cache.json')
    cache = json.load(open(cache_p)) if os.path.exists(cache_p) else {}

    if items_only:
        results = json.load(open(os.path.join(out_dir, 'data.json')))['results']
    else:
        jobs = [(st, pick) for st in S.STAGES for pick in combos(st, S.CHOICES)]
        print(f'{len(jobs)} PoB runs', file=sys.stderr)
        with ThreadPoolExecutor(4) as ex:
            outs = list(ex.map(lambda j: run_one(S, *j), jobs))
        results = {st['id']: {} for st in S.STAGES}
        for (st, pick), (stats, xml) in zip(jobs, outs):
            stats['pobb'] = upload(xml, cache, '--no-upload' not in sys.argv)
            results[st['id']][combo_key(pick)] = stats
            print(st['id'], combo_key(pick), round(stats['dps'] / 1e6, 2), 'M', round(stats['ehp']), stats['pobb'], file=sys.stderr)
        json.dump(cache, open(cache_p, 'w'), indent=1)

    get_icon = icon_getter(S, out_dir)
    skills, gp = skill_data(S, get_icon)
    data = dict(title=S.TITLE, heading=S.HEADING, skill=S.SKILL, char=S.CHAR, reference=S.REFERENCE, notes=S.NOTES,
                defaultStage=getattr(S, 'DEFAULT_STAGE', S.STAGES[0]['id']), updated=time.strftime('%d/%m/%Y %H:%M'),
                gemRate=gp['rate'], gemDate=gp['date'], skills=skills,
                slots=[dict(id=s, label=l, group=g) for s, l, g in S.SLOTS], choices=S.CHOICES,
                stages=[dict(id=s['id'], label=s['label'], level=s['level'], desc=s['desc'], slots=s['slots']) for s in S.STAGES],
                items=item_data(S, get_icon), results=results)
    json.dump(data, open(os.path.join(out_dir, 'data.json'), 'w'), ensure_ascii=False, separators=(',', ':'))
    page = open(os.path.join(HERE, 'template.html')).read().replace('__TITLE__', S.TITLE).replace('__HEADING__', S.HEADING)
    open(os.path.join(out_dir, 'index.html'), 'w').write(page)
    print('wrote', out_dir, file=sys.stderr)


if __name__ == '__main__':
    main()
