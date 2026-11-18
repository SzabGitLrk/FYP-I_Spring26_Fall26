#!/usr/bin/env python3
"""How often a weak "open drain" box shows up, with and without a drain.

    python drain_caution.py [camera]        # phone (default) or esp32

Reads the detections that hazard_eval.py collect stored for the test photos
(D:/dev/eyris_work/sim/hazard_<camera>.pkl). For each confidence it prints
the share of photos holding an open drain where a box of at least that
confidence lies on the drain, and the share of photos without one where
any open-drain box of that confidence appears. The app uses a confidence
below the reporting one only to hold back "Path clear" (it says "Path
unclear, move slowly" instead); this table is how that value was chosen.
"""
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from app_sim import inside, iou  # noqa: E402
from hazard_eval import CACHE, test_items  # noqa: E402


def main():
    camera = sys.argv[1] if len(sys.argv) > 1 else 'phone'
    raw = pickle.load(open(f'{CACHE}/hazard_{camera}.pkl', 'rb'))
    with_drain, without = [], []
    for name, _path, truth in test_items():
        dets = [(s, b) for s, label, b in raw.get(name, ((1, 1), []))[1] if label == 'Open drain']
        drains = truth.get('Open drain', [])
        if drains:
            on = [s for s, b in dets if any(iou(b, t) >= 0.3 or inside(b, t) >= 0.7 for t in drains)]
            with_drain.append(max(on, default=0.0))
        else:
            without.append((max((s for s, _ in dets), default=0.0), name))
    print(f'{camera}: {len(with_drain)} photos with an open drain, {len(without)} without')
    for t in (0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60):
        found = sum(s >= t for s in with_drain)
        false = [n for s, n in without if s >= t]
        print(f'  {t:.2f}: drain seen on {found / len(with_drain):.0%} of drain photos, '
              f'a box on {len(false) / len(without):.1%} of photos without ({len(false)})')
    worst = sorted(without, reverse=True)[:15]
    print('  strongest boxes on photos without a drain:', [(n, round(s, 2)) for s, n in worst])
    # Found, per source of the drain photos. omb_ are the Bangladesh photos:
    # broken slabs and open chambers like the client's.
    by_source = {}
    names = [n for n, _p, t in test_items() if t.get('Open drain')]
    for n, s in zip(names, with_drain):
        by_source.setdefault(n.split('_')[0].rstrip('0123456789'), []).append(s)
    for source, scores in sorted(by_source.items()):
        print(f'  {source}: {len(scores)} photos, found at 0.25 / 0.40 / 0.50: ' + ' / '.join(
            f'{sum(s >= t for s in scores)}' for t in (0.25, 0.40, 0.50)))


if __name__ == '__main__':
    main()
