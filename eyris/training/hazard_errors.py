#!/usr/bin/env python3
"""Where the hazard model's wrong detections come from, per label and kind
of test photo, at the given confidences (after hazard_eval.py collect).

    python hazard_errors.py 0.55 0.35 0.7
"""
import pickle
import sys
from collections import Counter

import hazard_eval as h

thresholds = dict(zip(h.LABELS, (float(v) for v in sys.argv[1:4])))
truth = {n: t for n, _, t in h.test_items()}
for camera in ('phone', 'esp32'):
    raw = pickle.load(open(f'{h.CACHE}/hazard_{camera}.pkl', 'rb'))
    wrong = Counter()
    for name, entry in raw.items():
        dets = [d for d in h.rules(entry) if d[0] >= thresholds[d[1]]]
        for label, s, ok in h.judge(dets, truth[name]):
            if not ok:
                kind = name.split('_')[0] if not name.startswith('neg_') else name[:8]
                wrong[(label, kind)] += 1
    print(camera, sorted(wrong.items(), key=lambda kv: -kv[1]))
