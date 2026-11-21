"""Gems for the viewer: socket groups from a PoB XML, trade queries per gem.

Trade names come from tools/viewer/data/trade_gems.json (the trade site's /api/trade/data/items gem list):
supports get their " Support" name, transfigured gems their discriminator, and skills that
aren't tradeable gems (granted by items, e.g. Herald of the Hive) are left out automatically.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
TRADE_GEMS = json.load(open(os.path.join(HERE, 'data', 'trade_gems.json')))
_BY_TEXT = {e['text']: e for e in TRADE_GEMS if e.get('text')}
_TYPES = {e['type'] for e in TRADE_GEMS}
SLOT_PT = {'Body Armour': 'Peito', 'Weapon 1': 'Arma', 'Weapon 2': 'Offhand', 'Helmet': 'Elmo', 'Boots': 'Botas', 'Gloves': 'Luvas',
           'Ring 1': 'Anel 1', 'Ring 2': 'Anel 2', 'Amulet': 'Amuleto', 'Belt': 'Cinto'}


def trade_type(name):
    """Trade 'type' for a PoB gem name, or None when it isn't a tradeable gem."""
    if name in _BY_TEXT:
        e = _BY_TEXT[name]
        return {'option': e['type'], 'discriminator': e['disc']} if e.get('disc') else e['type']
    if name + ' Support' in _TYPES:
        return name + ' Support'
    if name in _TYPES:
        return name
    return None


def is_support(name):
    return isinstance(trade_type(name), str) and trade_type(name).endswith(' Support')


def icon_name(name):
    t = trade_type(name)
    return t if isinstance(t, str) else name


def groups(xml_path):
    x = open(xml_path).read()
    out = []
    for m in re.finditer(r'<Skill ([^>]*)>(.*?)</Skill>', x, re.S):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        if (a.get('slot') or '').endswith('Swap'):
            continue
        gems = [dict(re.findall(r'(\w+)="([^"]*)"', g)) for g in re.findall(r'<Gem ([^>]*)/?>', m.group(2))]
        gems = [dict(name=g['nameSpec'], level=int(g.get('level', 1)), quality=int(g.get('quality', 0)))
                for g in gems if g.get('nameSpec') and trade_type(g['nameSpec'])]
        if gems:
            out.append(dict(slot=a.get('slot'), label=SLOT_PT.get(a.get('slot'), a.get('slot') or ''), gems=gems))
    return out


def query(name, level, quality):
    f = {}
    if level > 1:
        f['gem_level'] = {'min': level}
    if quality > 0:
        f['quality'] = {'min': min(quality, 20)}
    return {'status': {'option': 'securable'}, 'type': trade_type(name), 'stats': [{'type': 'and', 'filters': []}],
            'filters': {'misc_filters': {'filters': f}}}


def variants(g):
    """(label, level, quality) searches: PoB's exact level, plus a cheaper 20/x when PoB uses a corrupted 21."""
    out = [(f"{g['level']}/{g['quality']}", g['level'], g['quality'])]
    if g['level'] == 21:
        q = 20 if g['quality'] else 0
        out.append((f'20/{q}', 20, q))
    return out


def price_queries(xml_path):
    """[{key, q}] for every gem search — feed to the browser price fetch (see README)."""
    return [dict(key=f"{g['name']} {lab}", q=query(g['name'], l, q))
            for gr in groups(xml_path) for g in gr['gems'] for lab, l, q in variants(g)]
