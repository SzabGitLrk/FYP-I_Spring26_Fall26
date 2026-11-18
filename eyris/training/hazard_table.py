#!/usr/bin/env python3
"""Right / wrong / found per label and confidence, through both cameras,
and the AC detections one by one (after hazard_eval.py collect).

    python hazard_table.py [--old-photos] [label ...]

--old-photos leaves out the drain and manhole-cover photos added in 1.0.6
(names starting with "om"), so the figures can be set against the 1.0.5
report, which was measured without them.
"""
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hazard_eval import CACHE, LABELS, at, curves, judge, rules, test_items  # noqa: E402

STEPS = [0.15, 0.25, 0.35, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80]


def main():
    args = sys.argv[1:]
    old = '--old-photos' in args
    labels = [a for a in args if not a.startswith('--')] or LABELS
    names = {n for n, _p, _t in test_items() if not (old and n.startswith('om'))}
    data = {camera: curves(camera, names) for camera in ('phone', 'esp32')}
    for label in labels:
        print(f'{label}' + (' (photos of 1.0.5 only)' if old else ''))
        for t in STEPS:
            cells = []
            for camera, (hits, totals) in data.items():
                tp, fp, p, r = at(hits[label], totals[label], t)
                cells.append(f'{camera} {tp:4d} right {fp:3d} wrong {p:6.1%} found {r:5.1%}')
            print(f'  {t:.2f}: ' + ' | '.join(cells))
    if 'AC' in labels:
        raw = pickle.load(open(f'{CACHE}/hazard_phone.pkl', 'rb'))
        truth = {n: t for n, _p, t in test_items()}
        print('AC detections from 0.40, phone:')
        for name, entry in raw.items():
            if name not in names:
                continue
            for s, label, box in rules(entry):
                if label == 'AC' and s >= 0.4:
                    ok = judge([(s, label, box)], truth[name])[0][2]
                    print(f"  {name} {s:.2f} {'right' if ok else 'WRONG'} "
                          f"{[round(float(v), 2) for v in box]}")


if __name__ == '__main__':
    main()
