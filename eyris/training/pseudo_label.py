#!/usr/bin/env python3
"""Fill in objects that the public datasets left unlabelled.

Open Images does not box every object in a photo, and the pothole photos
only label road damage, so trees, poles, people and vehicles in them have no
box. Training on that would teach the model that those objects are
background. This script runs a large pretrained detector (the "teacher")
over every photo and adds its confident boxes wherever the dataset has no
box of that class already.

Only the training photos are touched. The validation photos keep their
human-made labels, so the accuracy measured on them is not influenced by the
teacher.

Run it after build_dataset.py and before training:
    python pseudo_label.py --data /content/eyris_data
Check the merge logic without a GPU or any model:
    python pseudo_label.py --self-test
"""
import argparse
import json
import os
import sys
from collections import Counter

from build_dataset import CLASSES, OPEN_IMAGES_CLASSES, yolo_line

# Text prompt for the open-vocabulary teacher -> EYRIS class. Potholes are
# left to the hand-labelled RDD2022 boxes: no general teacher finds them well.
WORLD_PROMPTS = {
    'person': 'person', 'car': 'car', 'motorcycle': 'motorcycle',
    'bicycle': 'bicycle', 'truck': 'truck', 'bus': 'bus', 'tree': 'tree',
    'utility pole': 'pole', 'electric pole': 'pole', 'street light': 'pole',
    'traffic sign': 'traffic sign', 'chair': 'chair', 'table': 'table',
    'door': 'door', 'stairs': 'stairs', 'bed': 'bed', 'sofa': 'sofa',
    'bottle': 'bottle', 'trash can': 'dustbin', 'backpack': 'bag',
    'handbag': 'bag', 'suitcase': 'bag', 'laptop': 'laptop',
}


def iou(a, b):
    """Intersection over union of two (x_min, y_min, x_max, y_max) boxes."""
    width = min(a[2], b[2]) - max(a[0], b[0])
    height = min(a[3], b[3]) - max(a[1], b[1])
    if width <= 0 or height <= 0:
        return 0.0
    overlap = width * height
    return overlap / ((a[2] - a[0]) * (a[3] - a[1])
                      + (b[2] - b[0]) * (b[3] - b[1]) - overlap)


def covered(inner, outer):
    """Share of inner's area that lies inside outer."""
    width = min(inner[2], outer[2]) - max(inner[0], outer[0])
    height = min(inner[3], outer[3]) - max(inner[1], outer[1])
    area = (inner[2] - inner[0]) * (inner[3] - inner[1])
    if width <= 0 or height <= 0 or area <= 0:
        return 0.0
    return width * height / area


def read_labels(path):
    """[(class_name, (x_min, y_min, x_max, y_max))] from a YOLO label file."""
    boxes = []
    if not os.path.exists(path):
        return boxes
    with open(path) as handle:
        for line in handle:
            parts = line.split()
            if len(parts) != 5:
                continue
            cx, cy, w, h = map(float, parts[1:])
            boxes.append((CLASSES[int(parts[0])],
                          (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)))
    return boxes


def merge(existing, predictions, max_iou=0.45, max_covered=0.8):
    """Predictions worth adding: (class_name, box) pairs not already labelled.

    A prediction is dropped when a box of the same class already overlaps it
    or mostly contains it, so existing human labels always win.
    predictions: [(class_name, box, confidence)], any order.
    """
    kept = list(existing)
    added = []
    for name, box, _ in sorted(predictions, key=lambda p: -p[2]):
        if box[2] - box[0] <= 0.004 or box[3] - box[1] <= 0.004:
            continue
        duplicate = any(
            other_name == name and (iou(box, other) > max_iou
                                    or covered(box, other) > max_covered
                                    or covered(other, box) > max_covered)
            for other_name, other in kept)
        if not duplicate:
            kept.append((name, box))
            added.append((name, box))
    return added


def load_teacher(kind):
    """Returns (model, {teacher class id: EYRIS class name})."""
    from ultralytics import YOLO
    if kind == 'world':
        try:
            model = YOLO('yolov8x-worldv2.pt')
            prompts = list(WORLD_PROMPTS)
            model.set_classes(prompts)
            return model, {i: WORLD_PROMPTS[p] for i, p in enumerate(prompts)}
        except Exception as error:  # noqa: BLE001 - fall back to a plain model
            print(f'[teacher] open-vocabulary model unavailable ({error}); '
                  'using the Open Images model instead')
    model = YOLO('yolov8x-oiv7.pt')
    mapping = {index: OPEN_IMAGES_CLASSES[name]
               for index, name in model.names.items()
               if name in OPEN_IMAGES_CLASSES}
    return model, mapping


def drop_unreadable(image_dir, label_dir, images):
    """Remove photos that cannot be opened (a failed download), with their labels."""
    from PIL import Image
    good = []
    for name in images:
        path = os.path.join(image_dir, name)
        try:
            with Image.open(path) as image:
                image.load()   # decodes fully, so truncated files fail here
            good.append(name)
        except Exception:  # noqa: BLE001 - any unreadable file is dropped
            os.remove(path)
            label = os.path.join(label_dir, os.path.splitext(name)[0] + '.txt')
            if os.path.exists(label):
                os.remove(label)
            print(f'  removed unreadable photo {name}')
    return good


def run(data, kind, confidence, batch, subsets=('train',), prefixes=()):
    model, class_map = load_teacher(kind)
    totals = Counter()
    for subset in subsets:
        image_dir = os.path.join(data, 'images', subset)
        label_dir = os.path.join(data, 'labels', subset)
        images = sorted(name for name in os.listdir(image_dir)
                        if name.lower().endswith(('.jpg', '.jpeg', '.png')))
        images = drop_unreadable(image_dir, label_dir, images)
        if prefixes:
            images = [name for name in images if name.startswith(tuple(prefixes))]
        print(f'[pseudo-label] {subset}: {len(images)} photos')
        for start in range(0, len(images), batch):
            chunk = images[start:start + batch]
            results = model.predict(
                [os.path.join(image_dir, name) for name in chunk],
                conf=confidence, imgsz=640, verbose=False)
            for name, result in zip(chunk, results):
                predictions = []
                for box, cls, conf in zip(result.boxes.xyxyn.tolist(),
                                          result.boxes.cls.tolist(),
                                          result.boxes.conf.tolist()):
                    target = class_map.get(int(cls))
                    if target:
                        predictions.append((target, tuple(box), conf))
                label_path = os.path.join(
                    label_dir, os.path.splitext(name)[0] + '.txt')
                added = merge(read_labels(label_path), predictions)
                lines = [yolo_line(n, *b) for n, b in added]
                lines = [line for line in lines if line]
                if lines:
                    with open(label_path, 'a') as handle:
                        handle.write('\n'.join(lines) + '\n')
                    totals.update(n for n, _ in added)
            if (start // batch) % 100 == 0:
                print(f'  {min(start + batch, len(images))}/{len(images)}')
    with open(os.path.join(data, 'pseudo_labels.json'), 'w') as handle:
        json.dump(dict(totals), handle, indent=2)
    print('\nboxes added per class:')
    for name in CLASSES:
        print(f'  {name:<14}{totals[name]:>8}')


def self_test():
    person = ('person', (.10, .10, .30, .80))
    existing = [person]
    predictions = [
        ('person', (.11, .12, .31, .79), .9),   # same person: dropped
        ('person', (.15, .20, .25, .50), .8),   # part of that person: dropped
        ('person', (.60, .10, .80, .80), .7),   # a second person: added
        ('tree', (.10, .10, .30, .80), .6),     # other class, same place: added
        ('pole', (.50, .50, .50, .90), .9),     # zero width: dropped
        ('person', (.61, .11, .79, .79), .5),   # duplicate of the added one
    ]
    added = merge(existing, predictions)
    assert [name for name, _ in added] == ['person', 'tree'], added
    assert added[0][1] == (.60, .10, .80, .80)
    assert abs(iou((0, 0, 1, 1), (0, 0, .5, 1)) - .5) < 1e-9
    assert iou((0, 0, .2, .2), (.5, .5, 1, 1)) == 0
    assert abs(covered((0, 0, .5, .5), (0, 0, 1, 1)) - 1) < 1e-9
    assert set(WORLD_PROMPTS.values()) == set(CLASSES) - {'pothole'}
    assert set(OPEN_IMAGES_CLASSES.values()) == set(CLASSES) - {'pothole'}
    name, box = added[0]
    line = yolo_line(name, *box)
    assert line == f"{CLASSES.index('person')} 0.700000 0.450000 0.200000 0.700000", line
    print('self-test passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--data', help='dataset folder made by build_dataset.py')
    parser.add_argument('--teacher', default='world', choices=('world', 'oiv7'))
    parser.add_argument('--confidence', type=float, default=0.4)
    parser.add_argument('--batch', type=int, default=32)
    parser.add_argument('--prefix', default='',
                        help='only photos whose file name starts with one of '
                             'these comma-separated prefixes (to continue an '
                             'interrupted run)')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.data:
        parser.error('--data is required')
    prefixes = [p for p in args.prefix.split(',') if p]
    return run(args.data, args.teacher, args.confidence, args.batch,
               prefixes=prefixes)


if __name__ == '__main__':
    sys.exit(main())
