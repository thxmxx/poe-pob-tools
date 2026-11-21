"""Helpers shared by build specs (builds/<name>/spec.py) and the viewer generator."""
import base64, gzip, html, json, re


def trade_id(q):
    """Trade search ids are the gzip+base64url of the query JSON (mtime=0 keeps them stable)."""
    raw = gzip.compress(json.dumps(q, separators=(",", ":")).encode(), mtime=0)
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')


def unique_q(name, stats=()):
    """Unique item search: securable, Foulborn: No, optional stat filters."""
    return {'status': {'option': 'securable'}, 'name': name,
            'stats': [{'type': 'and', 'filters': list(stats)}],
            'filters': {'misc_filters': {'filters': {'mutated': {'option': 'false'}}}}}


def ref_items(xml_path):
    """Raw item texts of a PoB XML, keyed by slot name and 'Jewel <nodeId>'."""
    x = open(xml_path).read()
    items = {}
    for m in re.finditer(r'<Item id="(\d+)"[^>]*>(.*?)</Item>', x, re.S):
        t = html.unescape(m.group(2))
        items[m.group(1)] = '\n'.join(l.strip() for l in t.split('\n') if l.strip() and not l.strip().startswith('<'))
    ref = {}
    for m in re.finditer(r'<Slot ([^>]*)/>', x):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        if a.get('itemId', '0') != '0':
            ref[a['name']] = items[a['itemId']]
    for m in re.finditer(r'<Socket itemId="(\d+)" nodeId="(\d+)"/>', x):
        ref['Jewel ' + m.group(2)] = items[m.group(1)]
    return ref


HEADER = re.compile(r'^(Unique ID|Item Level|LevelReq|Quality|Sockets|Radius|Limited to|Requires Class|Implicits|Evasion|Energy Shield|Armour|\w+BasePercentile|Catalyst|CatalystQuality|Has \d Abyssal|.* Item$|Prefix|Suffix)')
SHOW = ('Quality', 'Radius', 'Limited to', 'Requires Class')


def parse_item(lines):
    """PoB raw text lines -> props / implicits / explicits (crafted/fractured flags) / flags, for the tooltip."""
    props, imps, exps, flags, n_imp = [], [], [], [], 0
    body = lines[3:] if len(lines) > 2 and not HEADER.match(lines[2]) else lines[2:]
    i = 0
    while i < len(body) and HEADER.match(body[i]):
        l = body[i]
        k, _, v = l.partition(':')
        if k == 'Implicits':
            n_imp = int(v)
        elif k in SHOW:
            props.append([k, v.strip()])
        elif l.endswith(' Item') and ':' not in l:
            flags.append(l)
        i += 1
    for j, l in enumerate(body[i:]):
        if l in ('Corrupted', 'Fractured Item', 'Mirrored', 'Split'):
            flags.append(l)
            continue
        m = re.match(r'^\{(\w+)\}(.*)', l)
        kind, txt = (m.group(1), m.group(2)) if m else ('', l)
        if kind == 'vestigial':
            kind = ''
        dst = imps if j < n_imp else exps
        if txt in ('Passage', 'Historic'):  # PoB variant/flavour tags
            continue
        if txt[:1].islower() and dst:  # wrapped continuation of the previous mod
            dst[-1][0] += ' ' + txt
            continue
        dst.append([txt, kind])
    return dict(props=props, implicits=imps, explicits=exps, flags=flags)
