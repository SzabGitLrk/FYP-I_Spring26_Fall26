#!/usr/bin/env python3
"""False alarms per 100 photos for labels that have no labelled examples in
ADE20K (pothole, speed breaker): every such detection there is a mistake.
Position rules of the app are applied; the indoor rule is not.

    python fp_rates.py
"""
import app_sim

for tag, label in (('pothole', 'Pothole'), ('road', 'Pothole'), ('world', 'Speed breaker')):
    raw = app_sim.load_raw('ade_all', tag)
    if not raw:
        continue
    cells = []
    for threshold in (0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.60):
        photos = 0
        for found in raw.values():
            dets = [(s, l, b) for s, l, b in found if l == label and s >= threshold]
            photos += bool(app_sim.scene_rules(dets))
        cells.append(f'{threshold:.2f}: {100 * photos / len(raw):4.1f}')
    print(f'{tag:8s} {label:14s} photos with a false alarm per 100 -> ' + ' | '.join(cells))
