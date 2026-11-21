#!/usr/bin/env python3
"""Generate tools/data/timeless/<Name>.bin from PoB's Data/TimelessJewelData/<Name>.zip(.partN).

Headless PoB has no Inflate(), so the pob_*.lua scripts read these pre-decompressed tables instead.
Run once after cloning (and after updating the PoB submodule): tools/gen_timeless.py
"""
import glob, os, re, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'vendor', 'PathOfBuilding', 'src', 'Data', 'TimelessJewelData')
OUT = os.path.join(HERE, 'data', 'timeless')
os.makedirs(OUT, exist_ok=True)
names = sorted({re.sub(r'\.zip(\.part\d+)?$', '', os.path.basename(p)) for p in glob.glob(os.path.join(SRC, '*.zip*'))})
for name in names:
    parts = sorted(glob.glob(os.path.join(SRC, name + '.zip.part*')), key=lambda p: int(p.rsplit('part', 1)[1])) or [os.path.join(SRC, name + '.zip')]
    raw = b''.join(open(p, 'rb').read() for p in parts)
    open(os.path.join(OUT, name + '.bin'), 'wb').write(zlib.decompress(raw))
    print(name, len(raw), '->', os.path.getsize(os.path.join(OUT, name + '.bin')))
