#!/usr/bin/env python3
"""Measure the hazard model the way the app runs it, through the phone camera
and through imitated ESP32 frames, and pick its confidences.

    python hazard_eval.py collect <model.tflite> <labels.txt>   # run once per model
    python hazard_eval.py pick [target]                         # thresholds + cross-check
    python hazard_eval.py report a b c d                        # pothole, speed breaker, AC, open drain

Test photos: the test half of hazard/ds (held out from training) plus the
Open Images photos of the road model's test set, which hold none of the
four objects and so measure false alarms in everyday scenes.

A detection is right when it overlaps a labelled object of its class
(IoU >= 0.3, or lies 70% inside it): for "speed breaker ahead" the exact
extent of the box does not matter. A second box on an object already found
is neither right nor wrong.
"""
import json
import os
import pickle
import sys
from collections import defaultdict

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from app_sim import esp32_frame, inside, iou, run_model  # noqa: E402

WORK = 'D:/dev/eyris_work'
DS = f'{WORK}/hazard/ds'
CACHE = f'{WORK}/sim'
NAMES = {'pothole': 'Pothole', 'speed breaker': 'Speed breaker', 'standing ac': 'AC',
         'open drain': 'Open drain'}
LABELS = list(NAMES.values())
FRAME_LONG_SIDE = 416   # the app decodes frames to its largest model input
INDOOR_HINT = None


def test_items():
    items = []
    for n in sorted(os.listdir(f'{DS}/images/test')):
        truth = defaultdict(list)
        lab = f'{DS}/labels/test/{n[:-4]}.txt'
        for line in open(lab):
            p = line.split()
            if len(p) >= 5:
                c, cx, cy, w, h = int(p[0]), *map(float, p[1:5])
                truth[LABELS[c]].append((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2))
        items.append((n, f'{DS}/images/test/{n}', dict(truth)))
    oi = f'{WORK}/data/images/val'
    for n in sorted(os.listdir(oi)):
        if n.startswith('oi_'):
            items.append((n, f'{oi}/{n}', {}))
    return items


def frame(photo):
    scale = min(1.0, FRAME_LONG_SIDE / max(photo.size))
    if scale < 1.0:
        photo = photo.resize((max(1, round(photo.width * scale)),
                              max(1, round(photo.height * scale))), Image.BILINEAR)
    return photo


def collect(model_path, labels_path):
    from ai_edge_litert.interpreter import Interpreter
    it = Interpreter(model_path=model_path, num_threads=8)
    it.allocate_tensors()
    i, o = it.get_input_details()[0], it.get_output_details()[0]
    names = [l.strip().lower() for l in open(labels_path) if l.strip()]
    shape = list(i['shape'])
    model = dict(spec={'names_wide': NAMES}, it=it, i=i, o=o, names=names, size=shape[2],
                 channels_first=False, attributes_first=list(o['shape'])[1] == 4 + len(names))
    items = test_items()
    for camera in ('phone', 'esp32'):
        out = {}
        for k, (name, path, _) in enumerate(items):
            photo = Image.open(path).convert('RGB')
            if camera == 'esp32':
                photo = esp32_frame(photo, seed=k)
            found = [(s, NAMES[n], b) for s, n, b in run_model(model, frame(photo)) if n in NAMES]
            found.sort(key=lambda d: -d[0])
            kept = []
            for s, label, b in found:
                if s < 0.05:
                    continue
                if not any(l == label and iou(b, o2) > 0.5 for _, l, o2 in kept):
                    kept.append((s, label, b))
            out[name] = (photo.size, kept[:20])
            if k % 500 == 0:
                print(camera, k, len(items), flush=True)
        pickle.dump(out, open(f'{CACHE}/hazard_{camera}.pkl', 'wb'))
    print('collected', len(items), 'photos')


def rules(entry):
    """applySceneRules for hazard-model boxes; shapes compared in pixels."""
    (width, height), dets = entry
    kept = []
    for s, label, (x1, y1, x2, y2) in dets:
        w, h = (x2 - x1) * width, (y2 - y1) * height
        if label == 'Speed breaker' and w < h:
            continue   # a strip across the road, never taller than wide
        if label == 'AC' and h < w:
            continue   # standing units are tall
        kept.append((s, label, (x1, y1, x2, y2)))
    return kept


def judge(dets, truth):
    rows = []
    found = {l: [False] * len(b) for l, b in truth.items()}
    for s, label, box in sorted(dets, key=lambda d: -d[0]):
        boxes = truth.get(label, [])
        hit = [k for k, t in enumerate(boxes) if iou(box, t) >= 0.3 or inside(box, t) >= 0.7]
        fresh = [k for k in hit if not found[label][k]]
        if fresh:
            found[label][fresh[0]] = True
            rows.append((label, s, True))
        elif hit:
            continue
        else:
            rows.append((label, s, False))
    return rows


def curves(camera, names=None):
    raw = pickle.load(open(f'{CACHE}/hazard_{camera}.pkl', 'rb'))
    hits, totals = defaultdict(list), defaultdict(int)
    for name, _path, truth in test_items():
        if names is not None and name not in names:
            continue
        for label, boxes in truth.items():
            totals[label] += len(boxes)
        for label, s, ok in judge(rules(raw.get(name, ((1, 1), []))), truth):
            hits[label].append((s, ok))
    return hits, totals


def at(hits, total, t):
    tp = sum(1 for s, ok in hits if ok and s >= t)
    fp = sum(1 for s, ok in hits if not ok and s >= t)
    return tp, fp, (tp / (tp + fp) if tp + fp else float('nan')), (tp / total if total else float('nan'))


def lowest(data, label, target):
    """Lowest confidence at which every camera keeps precision >= target,
    with the lower edge of a 1-sigma interval when there are few detections."""
    for t in np.arange(0.10, 0.96, 0.01):
        ok = True
        for hits, totals in data:
            tp, fp, p, _ = at(hits[label], totals[label], t)
            n = tp + fp
            if n == 0:
                continue
            margin = np.sqrt(max(p * (1 - p), 0.0225) / n)
            if p - margin < target and not (n >= 200 and p >= target):
                ok = False
        if ok:
            return round(float(t), 2)
    return None


def pick(target=0.90):
    items = test_items()
    names = [n for n, _, _ in items]
    half_a = {n for k, n in enumerate(names) if k % 2 == 0}
    half_b = set(names) - half_a
    full = [curves(c) for c in ('phone', 'esp32')]
    result = {}
    for label in LABELS:
        t = lowest(full, label, target)
        ta = lowest([curves(c, half_a) for c in ('phone', 'esp32')], label, target)
        print(f'\n{label}: threshold {t} (picked on half A alone: {ta})')
        for camera, (hits, totals) in zip(('phone', 'esp32'), full):
            if t is not None:
                tp, fp, p, r = at(hits[label], totals[label], t)
                print(f'  {camera:6s} all photos: {tp} right, {fp} wrong -> precision {p:.1%}, '
                      f'found {tp} of {totals[label]} ({r:.1%})')
            if ta is not None:
                hb, tb = curves(camera, half_b)
                tp, fp, p, r = at(hb[label], tb[label], ta)
                print(f'  {camera:6s} half B at {ta}: {tp} right, {fp} wrong -> precision {p:.1%}, '
                      f'found {r:.1%}')
        result[label] = t
    json.dump(result, open(f'{CACHE}/hazard_pick.json', 'w'), indent=1)
    print(result)


def report(thresholds):
    out = {}
    for camera in ('phone', 'esp32'):
        hits, totals = curves(camera)
        out[camera] = {}
        for label, t in zip(LABELS, thresholds):
            tp, fp, p, r = at(hits[label], totals[label], t)
            out[camera][label] = dict(threshold=t, right=tp, wrong=fp, objects=totals[label],
                                      precision=p, recall=r)
            print(f'{camera:6s} {label:14s} at {t:.2f}: {tp} right, {fp} wrong ({p:.1%}), '
                  f'found {tp} of {totals[label]} ({r:.1%})')
    json.dump(out, open(f'{CACHE}/hazard_report.json', 'w'), indent=1)


if __name__ == '__main__':
    if sys.argv[1] == 'collect':
        collect(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'pick':
        pick(*(float(v) for v in sys.argv[2:]))
    else:
        report([float(v) for v in sys.argv[2:2 + len(LABELS)]])
