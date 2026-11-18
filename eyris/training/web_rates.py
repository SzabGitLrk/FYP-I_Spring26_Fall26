#!/usr/bin/env python3
"""How often each model reports a label on photos known to show it.

    python web_rates.py D:/dev/eyris_work/web/speed_breaker "Speed breaker" [more labels]

The photos come from a keyword search, so some do not actually show the
object: the figures are a rough lower bound, not a recall measurement.
"""
import os
import pickle
import sys

from PIL import Image

import app_sim

folder, labels = sys.argv[1], sys.argv[2:]
cache = os.path.join(app_sim.CACHE, 'web_' + os.path.basename(folder.rstrip('/\\')) + '.pkl')
if os.path.exists(cache):
    raw = pickle.load(open(cache, 'rb'))
else:
    raw = {}
models = None
names = sorted(n for n in os.listdir(folder) if n.lower().endswith('.jpg'))
for name in names:
    if name in raw:
        continue
    models = models or app_sim.load_models()
    try:
        small = app_sim.frame_for_models(Image.open(os.path.join(folder, name)).convert('RGB'))
    except Exception:  # noqa: BLE001
        continue
    raw[name] = {m['spec']['tag']: app_sim.to_labels(app_sim.run_model(m, small), m['spec'])
                 for m in models}
pickle.dump(raw, open(cache, 'wb'))

print(f'{len(raw)} photos in {folder}')
tags = sorted({t for per in raw.values() for t in per})
for label in labels:
    for tag in tags:
        cells = []
        for threshold in (0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50):
            hit = 0
            for per in raw.values():
                dets = [(s, l, b) for s, l, b in per.get(tag, []) if l == label and s >= threshold]
                hit += bool(app_sim.scene_rules(dets))
            cells.append(f'{threshold:.2f}: {100 * hit / max(len(raw), 1):3.0f}%')
        if any(not c.endswith('  0%') for c in cells):
            print(f'  {label:14s} {tag:8s} ' + ' | '.join(cells))
