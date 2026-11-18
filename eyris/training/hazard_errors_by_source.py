#!/usr/bin/env python3
"""Where a label's wrong boxes come from, by source of the test photo.

    python hazard_errors_by_source.py <label> <threshold> [pickle]

The pickle defaults to D:/dev/eyris_work/sim/hazard_phone.pkl (written by
hazard_eval.py collect). Sources are the file-name prefixes given by
build_hazard_dataset.py: rdd/rf (potholes), sb (speed breakers), om*
(drains and manhole covers), neg (ADE20K), oi (Open Images), r (ESP32
rooms), ac* (ACs).
"""
import collections
import os
import pickle
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hazard_eval import CACHE, judge, rules, test_items  # noqa: E402


def source(name):
    return re.match(r'[a-z]+', name).group(0)


def main():
    label, t = sys.argv[1], float(sys.argv[2])
    path = sys.argv[3] if len(sys.argv) > 3 else f'{CACHE}/hazard_phone.pkl'
    raw = pickle.load(open(path, 'rb'))
    right, wrong, examples = collections.Counter(), collections.Counter(), collections.defaultdict(list)
    for name, _path, truth in test_items():
        for lab, s, ok in judge(rules(raw[name]), truth):
            if lab != label or s < t:
                continue
            src = source(name)
            if ok:
                right[src] += 1
            else:
                wrong[src] += 1
                examples[src].append((name, round(s, 2), sorted(truth)))
    print(f'{label} at {t} ({os.path.basename(path)}): {sum(right.values())} right, '
          f'{sum(wrong.values())} wrong')
    for src in sorted(set(right) | set(wrong)):
        print(f'  {src:6s} right {right[src]:4d}  wrong {wrong[src]:4d}  e.g. {examples[src][:3]}')


if __name__ == '__main__':
    main()
