#!/usr/bin/env python3
"""Run the app's detection pipeline in Python on labelled photos, using the
very .tflite files the app ships, to choose thresholds and report accuracy.

    python app_sim.py collect            # run the models, cache every box
    python app_sim.py pick               # print thresholds per model and label
    python app_sim.py report             # accuracy of the app as configured
    python app_sim.py show <photo>...    # what the app would say for photos

The steps mirror lib/services/yolo_detection_service.dart: the frame is
shrunk to 384 px on its long side, letterboxed into each model's square
input, every candidate takes its best class, classes the app does not
report are dropped, then per-label thresholds, scene rules and merging.
"""
import json
import os
import pickle
import sys
from collections import defaultdict

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

APP = r'D:\F_L_W\Wajiha\eyris_app'
MODELS = os.path.join(APP, 'assets', 'models')
WORK = r'D:\dev\eyris_work'
CACHE = os.path.join(WORK, 'sim')
FRAME_LONG_SIDE = 384
FLOOR = 0.05

# --- keep in step with lib/services/detection_models.dart -------------------
CONFIG = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'app_models.json')))
INDOOR = {'Bed', 'Sofa', 'Table', 'Chair', 'Laptop', 'AC', 'Fan'}


def load_models(tags=None):
    from ai_edge_litert.interpreter import Interpreter
    models = []
    for spec in CONFIG['models']:
        if tags and spec['tag'] not in tags:
            continue
        path = os.path.join(MODELS, spec['file'])
        if not os.path.exists(path):
            print('missing', path)
            continue
        # SIM_THREADS: fewer threads each when several collects run side by side.
        it = Interpreter(model_path=path, num_threads=int(os.environ.get('SIM_THREADS', 8)))
        it.allocate_tensors()
        i, o = it.get_input_details()[0], it.get_output_details()[0]
        names = [l.strip().lower() for l in open(os.path.join(MODELS, spec['labels'])) if l.strip()]
        shape = list(i['shape'])
        channels_first = shape[1] == 3 and shape[3] != 3
        size = shape[3] if channels_first else shape[2]
        out_shape = list(o['shape'])
        assert 4 + len(names) in out_shape[1:], (spec['file'], out_shape, len(names))
        models.append(dict(spec=spec, it=it, i=i, o=o, names=names, size=size,
                           channels_first=channels_first,
                           attributes_first=out_shape[1] == 4 + len(names)))
    return models


def esp32_frame(image, seed=0):
    """The same view as the ESP32 camera would deliver it. The firmware
    (firmware/ESP32S3_EYE_Camera_HCSR04_UDP) streams VGA JPEGs at quality 12
    from an OV2640: fewer pixels, a softer lens, sensor noise and visible
    compression. This is an imitation made from an ordinary photo, a little
    harsher than the real camera in good light; it is not a real ESP32 frame.
    """
    import io
    from PIL import ImageFilter
    long_side, short_side = max(image.size), min(image.size)
    scale = min(1.0, 640 / long_side, 480 / short_side)
    if scale < 1.0:
        image = image.resize((max(1, round(image.width * scale)),
                              max(1, round(image.height * scale))), Image.BILINEAR)
    image = image.filter(ImageFilter.GaussianBlur(0.6))
    pixels = np.asarray(image, dtype=np.float32)
    # Less contrast and saturation than a phone, plus sensor noise.
    grey = pixels.mean(axis=2, keepdims=True)
    pixels = grey + (pixels - grey) * 0.85
    pixels = (pixels - 128) * 0.92 + 128
    pixels += np.random.default_rng(seed).normal(0, 4.0, pixels.shape)
    image = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
    buffer = io.BytesIO()
    image.save(buffer, 'JPEG', quality=50)
    return Image.open(io.BytesIO(buffer.getvalue())).convert('RGB')


# Cameras the app can be fed from. Cache files of anything but the phone
# carry the camera's name: ade_heldout_scene@esp32.pkl.
CAMERAS = {'phone': None, 'esp32': esp32_frame}


def cache_name(set_name, tag, camera='phone'):
    return f'{set_name}_{tag}' + ('' if camera == 'phone' else f'@{camera}') + '.pkl'


def frame_for_models(image):
    """The downscaled copy of the camera frame that the app hands to the models."""
    scale = min(1.0, FRAME_LONG_SIDE / max(image.size))
    if scale < 1.0:
        image = image.resize((max(1, round(image.width * scale)),
                              max(1, round(image.height * scale))), Image.BILINEAR)
    return image


def letterbox(image, size):
    scale = min(size / image.width, size / image.height)
    w, h = max(1, round(image.width * scale)), max(1, round(image.height * scale))
    pad_x, pad_y = (size - w) // 2, (size - h) // 2
    canvas = np.full((size, size, 3), 114 / 255, dtype=np.float32)
    canvas[pad_y:pad_y + h, pad_x:pad_x + w] = np.asarray(
        image.resize((w, h), Image.BILINEAR), dtype=np.float32) / 255
    return canvas, scale, pad_x, pad_y


def iou(a, b):
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    return w * h / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - w * h)


def run_model(model, small):
    """All boxes of one model as (score, model class name, box in 0..1 of the frame)."""
    size = model['size']
    canvas, scale, pad_x, pad_y = letterbox(small, size)
    x = canvas.transpose(2, 0, 1) if model['channels_first'] else canvas
    it = model['it']
    it.set_tensor(model['i']['index'], x[None])
    it.invoke()
    out = it.get_tensor(model['o']['index'])[0]
    if not model['attributes_first']:
        out = out.T
    boxes = out[:4].copy()
    if np.abs(boxes).max() <= 1.5:
        boxes *= size
    spec = model['spec']
    passes = [out[4:]]
    if spec.get('listed_only'):
        # Open-vocabulary model: every prompt is scored on its own, so only
        # the prompts the app uses take part (DetectorSpec.listedOnly), and
        # the "solo" labels get a pass of their own (DetectorSpec.soloLabels).
        wide = spec['names_wide']
        solo = np.array([wide.get(n) in spec.get('solo', []) for n in model['names']])
        keep = np.array([n in wide for n in model['names']]) & ~solo
        passes = [np.where(keep[:, None], out[4:], 0.0)]
        if solo.any():
            passes.append(np.where(solo[:, None], out[4:], 0.0))
    found = []
    for scores in passes:
        cls = scores.argmax(0)
        best = scores.max(0)
        for k in np.where(best > FLOOR)[0]:
            cx, cy, w, h = (float(v) for v in boxes[:, k])
            x1 = min(max((cx - w / 2 - pad_x) / scale, 0), small.width) / small.width
            y1 = min(max((cy - h / 2 - pad_y) / scale, 0), small.height) / small.height
            x2 = min(max((cx + w / 2 - pad_x) / scale, 0), small.width) / small.width
            y2 = min(max((cy + h / 2 - pad_y) / scale, 0), small.height) / small.height
            if (x2 - x1) * small.width <= 1 or (y2 - y1) * small.height <= 1:
                continue
            found.append((float(best[k]), model['names'][cls[k]], (x1, y1, x2, y2)))
    return found


def to_labels(found, spec):
    """Model names -> app labels, duplicates of a label removed (IoU > 0.5)."""
    names = spec['names_wide']
    mapped = [(s, names[n], b) for s, n, b in found if n in names]
    mapped.sort(key=lambda d: -d[0])
    kept = []
    for s, label, b in mapped:
        if not any(l == label and iou(b, o) > 0.5 for _, l, o in kept):
            kept.append((s, label, b))
    return kept


def scene_rules(dets):
    """applySceneRules in the app; boxes are fractions of the frame."""
    strong_indoor = any(l in INDOOR and s >= 0.60 for s, l, _ in dets)
    kept = []
    for s, label, (x1, y1, x2, y2) in dets:
        area, cy = (x2 - x1) * (y2 - y1), (y1 + y2) / 2
        if label == 'Pothole':
            if strong_indoor or area > 0.30 or (y2 - y1) > 0.60 or cy < 0.50:
                continue
        elif label == 'Speed breaker':
            # width/height compared in pixels of a 3:4 portrait frame is close
            # enough to the fraction test for photos; use fractions here.
            if strong_indoor or cy < 0.45 or (x2 - x1) < (y2 - y1) or area > 0.20:
                continue
            if (y2 - y1) > 0.35:
                continue
        elif label == 'Footpath':
            if strong_indoor or y2 < 0.55:
                continue
        elif label == 'Wall':
            if area < 0.30 or x1 > 0.40 or x2 < 0.60:
                continue
        kept.append((s, label, (x1, y1, x2, y2)))
    return kept


BACKING_IOU = 0.4     # confirmAcrossModels in the app


def app_detections(per_model, max_per_label=3, limit=12):
    """Thresholds + agreement between models + rules + merge: what the app
    shows for one frame."""
    candidates = []
    for index, (spec, found) in enumerate(per_model):
        count = defaultdict(int)
        allowed = set(spec['names'].values())
        backed = spec.get('backed', {})
        for s, label, b in found:      # already label-mapped and NMS'd, best first
            if label not in allowed:
                continue
            # A label with only a "backed" confidence is never reported on
            # this model's word alone (DetectorSpec.thresholdFor).
            alone = spec['thresholds'].get(
                label, float('inf') if label in backed else spec.get('default', 0.35))
            if s < min(alone, backed.get(label, alone)):
                continue
            if count[label] >= max_per_label:
                continue
            count[label] += 1
            candidates.append((s, label, b, index, s >= alone))
    dets = [(s, label, b) for s, label, b, index, sure in candidates
            if sure or any(l == label and i != index and iou(b, o) >= BACKING_IOU
                           for _, l, o, i, _ in candidates)]
    dets = scene_rules(dets)
    dets.sort(key=lambda d: -d[0])
    kept = []
    for s, label, b in dets:
        if len(kept) >= limit:
            break
        if not any(l == label and iou(b, o) > 0.5 for _, l, o in kept):
            kept.append((s, label, b))
    return kept


# --- test sets ---------------------------------------------------------------
OI_TO_LABEL = {
    'person': 'Person', 'car': 'Car', 'motorcycle': 'Bike', 'bicycle': 'Bike',
    'truck': 'Truck', 'bus': 'Bus', 'pothole': 'Pothole', 'tree': 'Tree',
    'pole': 'Pole', 'traffic sign': 'Traffic sign', 'chair': 'Chair', 'table': 'Table',
    'door': 'Door', 'stairs': 'Stairs', 'bed': 'Bed', 'sofa': 'Sofa', 'bottle': 'Bottle',
    'dustbin': 'Dustbin', 'bag': 'Backpack', 'laptop': 'Laptop',
}
ADE_TO_LABEL = {
    'person': 'Person', 'car': 'Car', 'motorcycle': 'Bike', 'bicycle': 'Bike',
    'truck': 'Truck', 'bus': 'Bus', 'tree': 'Tree', 'pole': 'Pole',
    'traffic sign': 'Traffic sign', 'chair': 'Chair', 'table': 'Table', 'door': 'Door',
    'stairs': 'Stairs', 'wall': 'Wall', 'bed': 'Bed', 'sofa': 'Sofa', 'bottle': 'Bottle',
    'dustbin': 'Dustbin', 'bag': 'Backpack', 'laptop': 'Laptop', 'footpath': 'Footpath',
    'standing ac': 'AC', 'fan': 'Fan',
}


def ade_set(only_file=None):
    """(name, path, truth {label: [boxes]}, ignore {label: [boxes]}, scored=None)."""
    from bench_ade import ADE_TO_CLASS, ALSO_IGNORE
    keep = None
    if only_file:
        keep = {os.path.basename(l.strip()) for l in open(only_file) if l.strip()}
    items = []
    root = os.path.join(WORK, 'ade', 'val')
    for line in open(os.path.join(root, 'objects.jsonl'), encoding='utf8'):
        r = json.loads(line)
        if keep is not None and r['file'] not in keep:
            continue
        w, h = r['width'], r['height']
        truth, ignore = defaultdict(list), defaultdict(list)
        for name, x1, y1, x2, y2, _ in r['objects']:
            box = (x1 / w, y1 / h, x2 / w, y2 / h)
            target = ADE_TO_CLASS.get(name)
            if target and target.startswith('~'):
                label = ADE_TO_LABEL.get(target[1:])
                if label:
                    ignore[label].append(box)
            elif target and target in ADE_TO_LABEL:
                truth[ADE_TO_LABEL[target]].append(box)
            for cls, names in ALSO_IGNORE.items():
                if name in names and cls in ADE_TO_LABEL:
                    ignore[ADE_TO_LABEL[cls]].append(box)
        items.append((r['file'], os.path.join(root, 'images', r['file']), dict(truth), dict(ignore), None))
    return items


def oi_set():
    from build_dataset import CLASSES
    from evaluate import scored_classes
    from pseudo_label import read_labels
    data = os.path.join(WORK, 'data')
    image_dir, label_dir = os.path.join(data, 'images', 'val'), os.path.join(data, 'labels', 'val')
    images = sorted(n for n in os.listdir(image_dir) if n.endswith('.jpg'))
    present, absent, skipped = scored_classes(data, {n[3:-4] for n in images if n.startswith('oi_')})
    items = []
    for name in images:
        rows = read_labels(os.path.join(label_dir, name[:-4] + '.txt'))
        if name.startswith('oi_'):
            iid = name[3:-4]
            scored = ({c for c, _ in rows} | (absent[iid] - present[iid])) - skipped[iid]
        else:
            scored = {'pothole'}
        truth = defaultdict(list)
        for c, box in rows:
            if c in scored:
                truth[OI_TO_LABEL[c]].append(tuple(box))
        # 'Bike' is scored only when both of its classes were checked or boxed.
        labels = {OI_TO_LABEL[c] for c in scored}
        items.append((name, os.path.join(image_dir, name), dict(truth), {}, labels))
    return items


def inside(a, b):
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    return w * h / max((a[2] - a[0]) * (a[3] - a[1]), 1e-9)


def score(dets, truth, ignore, scored):
    """[(label, confidence, correct)] for one photo; skips what cannot be judged."""
    unmatched = {l: list(b) for l, b in truth.items()}
    rows = []
    for s, label, box in sorted(dets, key=lambda d: -d[0]):
        if scored is not None and label not in scored:
            continue
        cands = unmatched.get(label, [])
        overlaps = [iou(box, o) for o in cands]
        if overlaps and max(overlaps) >= 0.5:
            cands.pop(int(np.argmax(overlaps)))
            rows.append((label, s, True))
            continue
        if any(iou(box, o) >= 0.5 for o in truth.get(label, [])):
            continue
        if any(iou(box, o) >= 0.4 or inside(box, o) >= 0.8 for o in ignore.get(label, [])):
            continue
        if label in ('Wall', 'Footpath', 'Stairs', 'Tree') and any(
                inside(box, o) >= 0.8 for o in truth.get(label, [])):
            continue
        rows.append((label, s, False))
    return rows


def collect(tags=None):
    """Run the models over every test photo. One cache file per set and model,
    so a model that is replaced can be collected again on its own.
    SIM_CAMERA=esp32 feeds the models imitation ESP32 frames instead."""
    os.makedirs(CACHE, exist_ok=True)
    camera = os.environ.get('SIM_CAMERA', 'phone')
    through = CAMERAS[camera]
    models = load_models(tags)
    sets = {
        'ade_heldout': ade_set(os.path.join(WORK, 'scene', 'test.txt')),
        'ade_all': ade_set(),
        'oi_val': oi_set(),
    }
    only = os.environ.get('SIM_SETS')
    if only:
        sets = {k: v for k, v in sets.items() if k in only.split(',')}
    seen = {}
    for set_name, items in sets.items():
        out = {m['spec']['tag']: {} for m in models}
        for n, (name, path, *_rest) in enumerate(items):
            if path not in seen:
                photo = Image.open(path).convert('RGB')
                if through:
                    photo = through(photo, seed=len(seen))
                small = frame_for_models(photo)
                seen[path] = {m['spec']['tag']: to_labels(run_model(m, small), m['spec'])
                              for m in models}
            for tag, found in seen[path].items():
                out[tag][name] = found
            if n % 200 == 0:
                print(f'  {set_name} {n}/{len(items)}', flush=True)
        for tag, data in out.items():
            pickle.dump(data, open(os.path.join(CACHE, cache_name(set_name, tag, camera)), 'wb'))
    print('collected', camera, [m['spec']['tag'] for m in models])


def load_raw(set_name, tag, camera='phone'):
    path = os.path.join(CACHE, cache_name(set_name, tag, camera))
    return pickle.load(open(path, 'rb')) if os.path.exists(path) else {}

def curves(set_name, items, tag):
    raw = load_raw(set_name, tag)
    hits, totals = defaultdict(list), defaultdict(int)
    for name, _path, truth, ignore, scored in items:
        for label, boxes in truth.items():
            totals[label] += len(boxes)
        for label, s, ok in score(raw.get(name, []), truth, ignore, scored):
            hits[label].append((s, ok))
    return hits, totals


def pr_at(hits, total, threshold):
    tp = sum(1 for s, ok in hits if ok and s >= threshold)
    fp = sum(1 for s, ok in hits if not ok and s >= threshold)
    return (tp / (tp + fp) if tp + fp else float('nan')), (tp / total if total else float('nan')), tp, fp


def average_precision(hits, total):
    if not total:
        return float('nan')
    found = sorted(hits, reverse=True)
    correct = np.array([ok for _, ok in found], dtype=float)
    tp, fp = np.cumsum(correct), np.cumsum(1 - correct)
    rec = np.concatenate(([0.0], tp / total, [1.0]))
    prec = np.concatenate(([1.0], tp / np.maximum(tp + fp, 1e-9), [0.0]))
    prec = np.maximum.accumulate(prec[::-1])[::-1]
    steps = np.where(rec[1:] != rec[:-1])[0]
    return float(np.sum((rec[steps + 1] - rec[steps]) * prec[steps + 1]))


def pick(target_precision=0.80, min_threshold=0.15):
    """Per model and label: AP on each test set and the lowest threshold that
    keeps precision at or above the target on every set where it is scored."""
    sets = {'ade_heldout': ade_set(os.path.join(WORK, 'scene', 'test.txt')),
            'ade_all': ade_set(), 'oi_val': oi_set()}
    result = {}
    for spec in CONFIG['models']:
        tag = spec['tag']
        # The scene model was trained on most ADE photos: judge it only on
        # the held-out ones. The other models never saw ADE.
        use = ['ade_heldout', 'oi_val'] if tag in ('scene', 'world') else ['ade_all', 'oi_val']
        data = {s: curves(s, sets[s], tag) for s in use}
        print(f"\n[{tag}]  label: per set AP50 (objects), then threshold -> precision/recall per set")
        result[tag] = {}
        for label in sorted(set(spec['names_wide'].values())):
            cells, usable = [], []
            for s in use:
                hits, totals = data[s]
                if totals[label] >= 15:
                    usable.append(s)
                cells.append(f"{s} {average_precision(hits[label], totals[label]):4.0%} ({totals[label]})")
            best = None
            for threshold in np.arange(min_threshold, 0.86, 0.01):
                ok = True
                for s in usable:
                    hits, totals = data[s]
                    p, r, tp, fp = pr_at(hits[label], totals[label], threshold)
                    if tp + fp >= 5 and p < target_precision:
                        ok = False
                if ok:
                    best = round(float(threshold), 2)
                    break
            at = []
            for s in use:
                hits, totals = data[s]
                p, r, tp, fp = pr_at(hits[label], totals[label], best if best is not None else 0.5)
                at.append(f"{p:4.0%}/{r:4.0%}")
            result[tag][label] = dict(threshold=best, ap={s: average_precision(*[data[s][0][label], data[s][1][label]]) for s in use},
                                      objects={s: data[s][1][label] for s in use})
            print(f"  {label:14s} " + ' | '.join(cells) + f" || thr {best} -> " + ' | '.join(at))
    json.dump(result, open(os.path.join(CACHE, 'pick.json'), 'w'), indent=1)


def report():
    sets = {'ade_heldout': ade_set(os.path.join(WORK, 'scene', 'test.txt')), 'oi_val': oi_set()}
    specs = {s['tag']: s for s in CONFIG['models']}
    rows = {}
    for set_name, items in sets.items():
        raw = {tag: load_raw(set_name, tag) for tag in specs}
        hits, totals, photos = defaultdict(list), defaultdict(int), defaultdict(int)
        false_alarm_photos = 0
        for name, _path, truth, ignore, scored in items:
            dets = app_detections([(specs[tag], raw[tag].get(name, [])) for tag in specs])
            for label, boxes in truth.items():
                totals[label] += len(boxes)
                photos[label] += 1
            judged = score(dets, truth, ignore, scored)
            for label, s, ok in judged:
                hits[label].append((s, ok))
            false_alarm_photos += any(not ok for _, _, ok in judged)
        rows[set_name] = (hits, totals, photos, len(items), false_alarm_photos)
    labels = CONFIG['labels']
    print(f"{'label':14s} | " + ' | '.join(f"{s}: objects precision recall" for s in sets))
    out = {}
    for label in labels:
        cells = []
        out[label] = {}
        for set_name in sets:
            hits, totals, photos, _, _ = rows[set_name]
            tp = sum(1 for _, ok in hits[label] if ok)
            fp = sum(1 for _, ok in hits[label] if not ok)
            p = tp / (tp + fp) if tp + fp else float('nan')
            r = tp / totals[label] if totals[label] else float('nan')
            cells.append(f"{totals[label]:5d}  {p:6.0%}  {r:6.0%}")
            out[label][set_name] = dict(objects=totals[label], precision=p, recall=r, tp=tp, fp=fp)
        print(f'{label:14s} | ' + ' | '.join(cells))
    for set_name in sets:
        _, _, _, n, bad = rows[set_name]
        print(f'{set_name}: {n} photos, {bad} with at least one wrong detection ({bad / n:.0%})')
        out['_' + set_name] = dict(photos=n, photos_with_false_alarm=bad)
    json.dump(out, open(os.path.join(CACHE, 'report.json'), 'w'), indent=1)


def show(paths):
    models = load_models()
    specs = {s['tag']: s for s in CONFIG['models']}
    for path in paths:
        small = frame_for_models(Image.open(path).convert('RGB'))
        per_model = [(m['spec'], to_labels(run_model(m, small), m['spec'])) for m in models]
        dets = app_detections(per_model)
        print(os.path.basename(path), '->',
              ', '.join(f'{l} {s:.2f}' for s, l, _ in dets) or 'nothing')
        for spec, found in per_model:
            top = ', '.join(f'{l} {s:.2f}' for s, l, _ in found[:5])
            print(f"     {spec['tag']:8s} best: {top}")


if __name__ == '__main__':
    step = sys.argv[1]
    if step == 'collect':
        collect(sys.argv[2:])
    elif step == 'pick':
        pick(*(float(v) for v in sys.argv[2:]))
    elif step == 'report':
        report()
    else:
        show(sys.argv[2:])
