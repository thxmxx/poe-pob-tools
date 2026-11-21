"""Example build spec for tools/viewer/build_viewer.py.

Copy to builds/<name>/spec.py, put the inputs in builds/<name>/inputs/, edit, then run:
    tools/viewer/build_viewer.py builds/<name>

Inputs this example expects (see CLAUDE.md "Viewer workflow" for how to get each one):
    inputs/base_90.xml, inputs/base_100.xml  PoB XML of the target build (tree trimmed per stage with pob_trim.sh)
    inputs/owned.json                         {"<PoB slot>": "<raw item text>"} for items the player already has
    inputs/ninja_chars.json                   poe.ninja character dump of similar builds (icons)
"""
import json, os
from viewer_lib import trade_id, unique_q, ref_items

HERE = os.path.dirname(os.path.abspath(__file__))
IN = os.path.join(HERE, 'inputs')

TITLE = 'My Build'                 # page <title>: short and specific
HEADING = 'My Build Name'
SKILL = 'Ethereal Knives'          # exact PoB gem name of the main skill
CHAR = 'CharacterName'
LEAGUE = 'Standard'
REFERENCE = ''                     # optional: the reference build/player you follow
TRADE = f'https://www.pathofexile.com/trade/search/{LEAGUE}/'
GEM_XML = os.path.join(IN, 'base_100.xml')
NINJA_CHARS = os.path.join(IN, 'ninja_chars.json')
DEFAULT_STAGE = 'now'

REF = ref_items(os.path.join(IN, 'base_100.xml'))   # target build's items: REF['Boots'], REF['Jewel 61834'], ...
OWN = json.load(open(os.path.join(IN, 'owned.json')))

NOTES = [
    'Rares are simulated at the <b>minimum of their trade search</b>; a better roll gives a bit more.',
]

ITEMS = {
    # already owned (no price, no trade link)
    'weapon': dict(owned=True, raw=OWN['Weapon 1'], icon='The Golden Charlatan'),
    # unique to buy: raw from the target build, trade link with the rolls that matter
    'boots_unique': dict(raw=REF['Boots'], icon='Sundance', price=0.1, roll='<b>Rarity ≥55%</b>.',
                         links=[('≥55% rarity', TRADE + trade_id(unique_q('Sundance', [
                             {'id': 'pseudo.pseudo_increased_rarity', 'value': {'min': 55}}])))]),
    # rare to buy: modelled at the search minimum
    'boots_rare': dict(name='Boots — Tailwind', icon='Fugitive Boots', price=3,
                       roll='<b>Tailwind on crit</b> + movement speed ≥25%.',
                       links=[('Tailwind + MS', TRADE + trade_id({
                           'status': {'option': 'securable'},
                           'stats': [{'type': 'and', 'filters': [
                               {'id': 'explicit.stat_1085545682', 'value': []},
                               {'id': 'pseudo.pseudo_increased_movement_speed', 'value': {'min': 25}}]}],
                           'filters': {'type_filters': {'filters': {'category': {'option': 'armour.boots'}, 'rarity': {'option': 'nonunique'}}}}}))],
                       raw="Rarity: RARE\nTailwind Boots\nFugitive Boots\n25% increased Movement Speed\nYou have Tailwind if you have dealt a Critical Strike Recently"),
}

SLOTS = [  # (PoB slot, label, group); jewel sockets as 'Jewel <passive node id>'
    ('Weapon 1', 'Weapon', 'gear'), ('Helmet', 'Helmet', 'gear'), ('Body Armour', 'Body', 'gear'), ('Gloves', 'Gloves', 'gear'),
    ('Boots', 'Boots', 'gear'), ('Amulet', 'Amulet', 'gear'), ('Ring 1', 'Ring 1', 'gear'), ('Ring 2', 'Ring 2', 'gear'), ('Belt', 'Belt', 'gear'),
    ('Flask 1', 'Flask 1', 'flask'), ('Flask 2', 'Flask 2', 'flask'), ('Flask 3', 'Flask 3', 'flask'), ('Flask 4', 'Flask 4', 'flask'), ('Flask 5', 'Flask 5', 'flask'),
]

CHOICES = {'Boots': ['boots_unique', 'boots_rare']}  # per-slot variations, first = default

NOW = {'Weapon 1': 'weapon'}                 # slots not listed are emptied
LATER = dict(NOW, **{'Boots': '*'})          # '*' = the player picks from CHOICES on the page

STAGES = [
    dict(id='now', label='Now', level=90, base='base_90.xml', slots=NOW, desc='Only what you already own.'),
    dict(id='later', label='Later', level=100, base='base_100.xml', slots=LATER, desc='Boots added; full tree.'),
]
