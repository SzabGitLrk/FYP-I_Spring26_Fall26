#!/usr/bin/env python3
"""Score a detector on ADE20K validation photos (2,000 indoor and street scenes
in which every object is labelled, so false alarms are counted properly).

    python bench_ade.py --weights yolov8s-worldv2.pt --kind world --prompts prompts.json --imgsz 320 --squash --tag name
    python bench_ade.py --weights best.pt --kind custom --imgsz 320 --squash --tag name

Writes <out>/<tag>.json with, per class, every detection's confidence and
whether it was right; pick_thresholds.py turns those into app thresholds.
"""
import argparse
import json
import os
from collections import defaultdict

import numpy as np
from PIL import Image

ADE = r'D:\dev\eyris_work\ade\val'

# ADE20K object name -> EYRIS class. '~class' marks look-alikes: a detection of
# that class on such an object is neither counted as right nor as wrong.
ADE_TO_CLASS = {
    'person, individual, someone, somebody, mortal, soul': 'person',
    'car, auto, automobile, machine, motorcar': 'car',
    'van': 'car',
    'bus, autobus, coach, charabanc, double-decker, jitney, motorbus, motorcoach, omnibus, passenger vehicle': 'bus',
    'truck, motortruck': 'truck',
    'bicycle, bike, wheel, cycle': 'bicycle',
    'minibike, motorbike': 'motorcycle',
    'tree': 'tree', 'palm, palm tree': 'tree',
    'pole': 'pole', 'streetlight, street lamp': 'pole',
    'traffic light, traffic signal, stoplight': 'traffic sign',
    'signboard, sign': '~traffic sign',
    'chair': 'chair', 'armchair': 'chair', 'swivel chair': 'chair', 'chair desk': 'chair',
    'deck chair, beach chair': 'chair',
    'table': 'table', 'desk': 'table', 'coffee table, cocktail table': 'table',
    'console table, console': 'table', 'pool table, billiard table, snooker table': 'table',
    'door': 'door', 'double door': 'door', 'screen door, screen': 'door',
    'stairs, steps': 'stairs', 'stairway, staircase': 'stairs', 'step, stair': 'stairs',
    'escalator, moving staircase, moving stairway': '~stairs',
    'wall': 'wall',
    'bed': 'bed',
    'sofa, couch, lounge': 'sofa',
    'bottle': 'bottle',
    'ashcan, trash can, garbage can, wastebin, ash bin, ash-bin, ashbin, dustbin, trash barrel, trash bin': 'dustbin',
    'bag': 'bag', 'bag, handbag, pocketbook, purse': 'bag',
    'backpack, back pack, knapsack, packsack, rucksack, haversack': 'bag',
    'bag, traveling bag, travelling bag, grip, suitcase': 'bag',
    'laptop, laptop computer': 'laptop',
    'computer, computing machine, computing device, data processor, electronic computer, information processing system': '~laptop',
    'sidewalk, pavement': 'footpath', 'path': '~footpath',
    'air conditioner, air conditioning': 'standing ac',
    'fan': 'fan',
}
# Look-alikes across classes that should not be punished as false alarms.
ALSO_IGNORE = {
    'sofa': {'armchair'}, 'chair': {'sofa, couch, lounge', 'stool', 'bench', 'seat'},
    'table': {'counter', 'countertop', 'kitchen island', 'cabinet'},
    'door': {'doorframe, doorcase', 'gate', 'elevator door', 'shower door', 'garage door'},
    'pole': {'column, pillar', 'post'}, 'tree': {'plant, flora, plant life', 'bush', 'trees'},
    'wall': {'fence, fencing', 'building, edifice', 'partition, divider'},
    'footpath': {'road, route', 'floor, flooring', 'curb, curbing, kerb', 'earth, ground'},
    'stairs': {'bannister, banister, balustrade, balusters, handrail', 'railing, rail'},
    'bag': {'box', 'basket'}, 'truck': {'van'}, 'car': {'truck, motortruck'},
}
CLASSES = ['person', 'car', 'motorcycle', 'bicycle', 'truck', 'bus', 'tree', 'pole',
           'traffic sign', 'chair', 'table', 'door', 'stairs', 'wall', 'bed', 'sofa',
           'bottle', 'dustbin', 'bag', 'laptop', 'footpath', 'standing ac', 'fan',
           'speed breaker', 'pothole']
# What the Oct 6 20-class model calls its classes -> the names used here.
CUSTOM_NAMES = {'air conditioner': 'standing ac'}


def iou(a, b):
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    return w * h / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - w * h)


def inside(a, b):
    """Share of box a that lies inside box b."""
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    return w * h / max((a[2] - a[0]) * (a[3] - a[1]), 1e-9)


def nms(found, limit=0.5):
    found.sort(key=lambda d: -d[0])
    kept = []
    for conf, name, box in found:
        if not any(n == name and iou(box, b) > limit for _, n, b in kept):
            kept.append((conf, name, box))
    return kept


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--weights', required=True)
    ap.add_argument('--kind', required=True, choices=['custom', 'world'])
    ap.add_argument('--prompts')
    ap.add_argument('--imgsz', type=int, default=320)
    ap.add_argument('--squash', action='store_true')
    ap.add_argument('--tag', required=True)
    ap.add_argument('--out', default=r'D:\dev\eyris_work\bench')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--only', help='text file listing the photos to score (held-out set)')
    args = ap.parse_args()

    from ultralytics import YOLO
    model = YOLO(args.weights)
    if args.kind == 'world':
        prompts = json.load(open(args.prompts))
        model.set_classes(list(prompts))
        to_class = dict(enumerate(prompts.values()))
    else:
        to_class = {i: CUSTOM_NAMES.get(n, n) for i, n in model.names.items()}

    records = [json.loads(line) for line in open(os.path.join(ADE, 'objects.jsonl'), encoding='utf8')]
    if args.only:
        keep = {os.path.basename(line.strip()) for line in open(args.only) if line.strip()}
        records = [r for r in records if r['file'] in keep]
    if args.limit:
        records = records[:args.limit]
    hits = {c: [] for c in CLASSES}
    totals = dict.fromkeys(CLASSES, 0)
    batch = 16
    for start in range(0, len(records), batch):
        chunk = records[start:start + batch]
        paths = [os.path.join(ADE, 'images', r['file']) for r in chunk]
        if args.squash:
            sources = [np.asarray(Image.open(p).convert('RGB').resize(
                (args.imgsz, args.imgsz), Image.BILINEAR))[:, :, ::-1] for p in paths]
        else:
            sources = paths
        results = model.predict(sources, conf=0.02, iou=0.6, imgsz=args.imgsz,
                                verbose=False, max_det=300)
        for record, result in zip(chunk, results):
            w, h = record['width'], record['height']
            truth, ignore = defaultdict(list), defaultdict(list)
            for name, x1, y1, x2, y2, _ in record['objects']:
                box = (x1 / w, y1 / h, x2 / w, y2 / h)
                target = ADE_TO_CLASS.get(name)
                if target and target.startswith('~'):
                    ignore[target[1:]].append(box)
                elif target:
                    truth[target].append(box)
                for cls, names in ALSO_IGNORE.items():
                    if name in names:
                        ignore[cls].append(box)
            for cls, boxes in truth.items():
                totals[cls] += len(boxes)
            unmatched = {c: list(b) for c, b in truth.items()}
            found = []
            for box, cid, conf in zip(result.boxes.xyxyn.cpu().numpy(),
                                      result.boxes.cls.cpu().numpy().astype(int),
                                      result.boxes.conf.cpu().numpy()):
                cls = to_class.get(int(cid))
                if cls in hits:
                    found.append((float(conf), cls, tuple(float(v) for v in box)))
            for conf, cls, box in nms(found):
                cands = unmatched.get(cls, [])
                overlaps = [iou(box, other) for other in cands]
                if overlaps and max(overlaps) >= 0.5:
                    cands.pop(int(np.argmax(overlaps)))
                    hits[cls].append((conf, True))
                    continue
                # A second box on an object already found, a box on a look-alike,
                # or a part of a large labelled region is not a false alarm.
                if any(iou(box, b) >= 0.5 for b in truth.get(cls, [])):
                    continue
                if any(iou(box, b) >= 0.4 or inside(box, b) >= 0.8 for b in ignore.get(cls, [])):
                    continue
                if cls in ('wall', 'footpath', 'stairs', 'tree') and any(
                        inside(box, b) >= 0.8 for b in truth.get(cls, [])):
                    continue
                hits[cls].append((conf, False))
        if (start // batch) % 25 == 0:
            print(f'  {min(start + batch, len(records))}/{len(records)}', flush=True)

    photos = len(records)
    print(f"\n{args.tag}: {os.path.basename(args.weights)} imgsz={args.imgsz}"
          f"{' squash' if args.squash else ''} on {photos} ADE20K photos")
    print(f"{'class':13s} {'obj':>5s} {'AP50':>5s} | " + ' | '.join(
        f'P / R @{t:.2f}' for t in (0.10, 0.20, 0.30)) + ' | thr P>=.80 -> R')
    rows = {}
    for cls in CLASSES:
        found = sorted(hits[cls], reverse=True)
        correct = np.array([k for _, k in found], dtype=float)
        conf = np.array([s for s, _ in found])
        tp, fp = np.cumsum(correct), np.cumsum(1 - correct)
        total = totals[cls]
        rec = tp / max(total, 1)
        prec = tp / np.maximum(tp + fp, 1e-9)
        if total:
            r = np.concatenate(([0.0], rec, [1.0]))
            p = np.concatenate(([1.0], prec, [0.0]))
            p = np.maximum.accumulate(p[::-1])[::-1]
            steps = np.where(r[1:] != r[:-1])[0]
            ap50 = float(np.sum((r[steps + 1] - r[steps]) * p[steps + 1]))
        else:
            ap50 = float('nan')
        cells = []
        for t in (0.10, 0.20, 0.30):
            m = conf >= t
            a, b = correct[m].sum(), (1 - correct[m]).sum()
            cells.append(f"{(a / (a + b) if a + b else float('nan')):4.0%}/{(a / total if total else 0):4.0%}")
        pick, pick_r = None, 0.0
        for k in range(len(found)):
            if prec[k] >= 0.80 and tp[k] >= 3 and rec[k] > pick_r:
                pick, pick_r = float(conf[k]), float(rec[k])
        rows[cls] = {'objects': total, 'ap50': ap50, 'photos': photos,
                     'curve': [(float(s), bool(k)) for s, k in found]}
        print(f'{cls:13s} {total:5d} {ap50:5.0%} | ' + ' | '.join(cells)
              + f" | {('%.2f' % pick) if pick else ' -- '} -> {pick_r:4.0%}")
    scored = [r['ap50'] for r in rows.values() if r['objects'] >= 20]
    print(f'mean AP50 over classes with 20+ objects: {np.mean(scored):.1%}')
    os.makedirs(args.out, exist_ok=True)
    json.dump(rows, open(os.path.join(args.out, args.tag + '.json'), 'w'))


if __name__ == '__main__':
    main()
