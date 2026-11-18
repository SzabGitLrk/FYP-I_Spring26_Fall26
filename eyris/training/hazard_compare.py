#!/usr/bin/env python3
"""Compare hazard models on the phone-camera test photos, the way the app
runs them, before choosing one.

    python hazard_compare.py collect <tag> <model.tflite> <labels.txt>
    python hazard_compare.py show <tag> [<tag> ...]

"collect" stores what the model finds in every test photo of hazard/ds (and
the Open Images photos hazard_eval.py adds) as sim/hazard_cmp_<tag>.pkl.
"show" prints, per label and for a few confidences, how many reported boxes
are right and how many objects are found.
"""
import os
import pickle
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from app_sim import iou, run_model  # noqa: E402
from hazard_eval import CACHE, LABELS, NAMES, at, frame, judge, rules, test_items  # noqa: E402

STEPS = (0.30, 0.40, 0.50, 0.60, 0.70)


def collect(tag, model_path, labels_path):
    from ai_edge_litert.interpreter import Interpreter
    it = Interpreter(model_path=model_path, num_threads=8)
    it.allocate_tensors()
    i, o = it.get_input_details()[0], it.get_output_details()[0]
    names = [l.strip().lower() for l in open(labels_path) if l.strip()]
    model = dict(spec={}, it=it, i=i, o=o, names=names, size=list(i['shape'])[2],
                 channels_first=False, attributes_first=list(o['shape'])[1] == 4 + len(names))
    out = {}
    for name, path, _ in test_items():
        photo = Image.open(path).convert('RGB')
        found = sorted(((s, NAMES[n], b) for s, n, b in run_model(model, frame(photo)) if n in NAMES),
                       key=lambda d: -d[0])
        kept = []   # as hazard_eval.collect: one box per object and label
        for s, label, b in found:
            if s >= 0.05 and not any(l == label and iou(b, o2) > 0.5 for _, l, o2 in kept):
                kept.append((s, label, b))
        out[name] = (photo.size, kept[:20])
    pickle.dump(out, open(f'{CACHE}/hazard_cmp_{tag}.pkl', 'wb'))
    print(tag, len(out), 'photos')


def show(tags):
    """A tag is the name given to collect, or the path of a phone-camera
    pickle written by hazard_eval.py collect."""
    items = test_items()
    for tag in tags:
        path = tag if tag.endswith('.pkl') else f'{CACHE}/hazard_cmp_{tag}.pkl'
        raw = pickle.load(open(path, 'rb'))
        hits, totals = {l: [] for l in LABELS}, {l: 0 for l in LABELS}
        for name, _path, truth in items:
            for label, boxes in truth.items():
                totals[label] += len(boxes)
            for label, s, ok in judge(rules(raw[name]), truth):
                hits[label].append((s, ok))
        print(f'== {tag}')
        for label in LABELS:
            cells = []
            for t in STEPS:
                tp, fp, p, r = at(hits[label], totals[label], t)
                cells.append(f'{t:.2f}: {tp}/{tp + fp} right, found {r:.0%}')
            print(f'  {label:14s} ' + ' | '.join(cells))


if __name__ == '__main__':
    if sys.argv[1] == 'collect':
        collect(*sys.argv[2:5])
    else:
        show(sys.argv[2:])
