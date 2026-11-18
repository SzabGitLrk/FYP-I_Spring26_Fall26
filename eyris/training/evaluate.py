#!/usr/bin/env python3
"""Measure the trained model on the validation photos and save example pictures.

    python evaluate.py --data D:/eyris_data --weights runs/eyris20/weights/best.pt --out report

The validation photos keep their human-made labels (they are never touched by
pseudo_label.py), and none of them was used for training.

Open Images does not label every object in every photo. It records, per
photo, which classes a person checked. Following the Open Images evaluation
rules, a class is only scored on photos where it was checked: where it has
boxes, or where a person confirmed it is absent. Classes nobody checked on a
photo are skipped there, as are classes marked there as a crowd or a drawing.
Pothole photos (RDD2022) are scored for potholes only.

Writes accuracy.json, accuracy.md and a folder of pictures with the model's
detections drawn on them.
"""
import argparse
import csv
import json
import os
import sys
from collections import defaultdict

import numpy as np

from build_dataset import (CLASSES, OI_BOXES_URL, OI_CLASS_NAMES_URL,
                           OPEN_IMAGES_CLASSES, fetch)
from pseudo_label import iou, read_labels

OI_IMAGE_LABELS_URL = ('https://storage.googleapis.com/openimages/v5/'
                       'validation-annotations-human-imagelabels-boxable.csv')
APP_THRESHOLD = 0.30
NEW_CLASSES = ['pothole', 'tree', 'pole', 'traffic sign', 'door', 'stairs', 'dustbin']


def scored_classes(data, image_ids):
    """{image_id: set of classes that may be scored on that Open Images photo}."""
    cache = os.path.join(data, '_cache')
    os.makedirs(cache, exist_ok=True)
    names = dict(row[:2] for row in csv.reader(
        fetch(OI_CLASS_NAMES_URL).decode('utf8').splitlines()) if len(row) >= 2)
    to_class = {label: OPEN_IMAGES_CLASSES[name] for label, name in names.items()
                if name in OPEN_IMAGES_CLASSES}

    present, absent, skipped = defaultdict(set), defaultdict(set), defaultdict(set)
    path = fetch(OI_IMAGE_LABELS_URL, os.path.join(cache, 'oi-validation-imagelabels.csv'))
    with open(path, newline='', encoding='utf8') as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            name = to_class.get(row['LabelName'])
            if name and row['ImageID'] in image_ids:
                (present if row['Confidence'] == '1' else absent)[row['ImageID']].add(name)

    path = fetch(OI_BOXES_URL['validation'], os.path.join(cache, 'oi-validation-bbox.csv'))
    with open(path, newline='', encoding='utf8') as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            name = to_class.get(row['LabelName'])
            if (name and row['ImageID'] in image_ids
                    and (row['IsGroupOf'] == '1' or row['IsDepiction'] == '1')):
                skipped[row['ImageID']].add(name)
    return present, absent, skipped


def average_precision(recall, precision):
    """Area under the precision-recall curve (all-point interpolation)."""
    recall = np.concatenate(([0.0], recall, [1.0]))
    precision = np.concatenate(([1.0], precision, [0.0]))
    precision = np.maximum.accumulate(precision[::-1])[::-1]
    steps = np.where(recall[1:] != recall[:-1])[0]
    return float(np.sum((recall[steps + 1] - recall[steps]) * precision[steps + 1]))


def evaluate(data, weights, out, batch):
    from ultralytics import YOLO

    image_dir = os.path.join(data, 'images', 'val')
    label_dir = os.path.join(data, 'labels', 'val')
    images = sorted(name for name in os.listdir(image_dir) if name.endswith('.jpg'))
    oi_ids = {name[3:-4] for name in images if name.startswith('oi_')}
    present, absent, skipped = scored_classes(data, oi_ids)

    model = YOLO(weights)
    assert [model.names[i] for i in range(len(model.names))] == CLASSES, model.names

    # Per class: [(confidence, correct)] and the number of labelled objects.
    hits = {name: [] for name in CLASSES}
    totals = dict.fromkeys(CLASSES, 0)
    photos = dict.fromkeys(CLASSES, 0)
    best_example = {name: [] for name in CLASSES}   # (confidence, image)

    for start in range(0, len(images), batch):
        chunk = images[start:start + batch]
        results = model.predict([os.path.join(image_dir, name) for name in chunk],
                                conf=0.01, iou=0.6, imgsz=640, verbose=False)
        for name, result in zip(chunk, results):
            truth = read_labels(os.path.join(label_dir, name[:-4] + '.txt'))
            if name.startswith('oi_'):
                image_id = name[3:-4]
                boxed = {class_name for class_name, _ in truth}
                # Scored: classes with boxes, or confirmed absent; never
                # classes marked as a crowd or a drawing on this photo.
                scored = (boxed | (absent[image_id] - present[image_id])) - skipped[image_id]
            else:
                scored = {'pothole'}
            for class_name in scored:
                photos[class_name] += 1
            unmatched = defaultdict(list)
            for class_name, box in truth:
                if class_name in scored:
                    unmatched[class_name].append(box)
                    totals[class_name] += 1

            order = np.argsort(-result.boxes.conf.cpu().numpy())
            boxes = result.boxes.xyxyn.cpu().numpy()[order]
            classes = result.boxes.cls.cpu().numpy().astype(int)[order]
            confidences = result.boxes.conf.cpu().numpy()[order]
            for box, class_id, confidence in zip(boxes, classes, confidences):
                class_name = CLASSES[class_id]
                if class_name not in scored:
                    continue
                candidates = unmatched[class_name]
                overlaps = [iou(tuple(box), other) for other in candidates]
                correct = bool(overlaps) and max(overlaps) >= 0.5
                if correct:
                    candidates.pop(int(np.argmax(overlaps)))
                    best_example[class_name].append((float(confidence), name))
                hits[class_name].append((float(confidence), correct))
        if (start // batch) % 10 == 0:
            print(f'  {min(start + batch, len(images))}/{len(images)} photos')

    rows = []
    for class_name in CLASSES:
        found = sorted(hits[class_name], reverse=True)
        correct = np.array([c for _, c in found], dtype=float)
        confidence = np.array([s for s, _ in found])
        true_positives = np.cumsum(correct)
        false_positives = np.cumsum(1 - correct)
        total = totals[class_name]
        recall_curve = true_positives / max(total, 1)
        precision_curve = true_positives / np.maximum(true_positives + false_positives, 1e-9)
        ap50 = average_precision(recall_curve, precision_curve) if total else float('nan')
        at_app = confidence >= APP_THRESHOLD
        tp, fp = correct[at_app].sum(), (1 - correct[at_app]).sum()
        rows.append({
            'class': class_name,
            'photos': photos[class_name],
            'objects': total,
            'precision': float(tp / (tp + fp)) if tp + fp else float('nan'),
            'recall': float(tp / total) if total else float('nan'),
            'ap50': ap50,
        })

    scored_rows = [row for row in rows if row['objects']]
    summary = {
        'weights': os.path.abspath(weights),
        'validation_photos': len(images),
        'confidence_threshold': APP_THRESHOLD,
        'mean_ap50': float(np.mean([row['ap50'] for row in scored_rows])),
        'mean_precision': float(np.nanmean([row['precision'] for row in scored_rows])),
        'mean_recall': float(np.mean([row['recall'] for row in scored_rows])),
        'classes': rows,
    }
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'accuracy.json'), 'w') as handle:
        json.dump(summary, handle, indent=2)

    lines = ['| Class | Photos | Objects | Precision | Recall | AP50 |',
             '|---|---:|---:|---:|---:|---:|']
    for row in rows:
        lines.append(f"| {row['class']} | {row['photos']} | {row['objects']} | "
                     f"{row['precision']:.0%} | {row['recall']:.0%} | {row['ap50']:.0%} |")
    lines.append(f"| **All {len(scored_rows)} classes (mean)** | {len(images)} | "
                 f"{sum(row['objects'] for row in rows)} | {summary['mean_precision']:.0%} | "
                 f"{summary['mean_recall']:.0%} | {summary['mean_ap50']:.0%} |")
    with open(os.path.join(out, 'accuracy.md'), 'w') as handle:
        handle.write('\n'.join(lines) + '\n')
    print('\n'.join(lines))

    # Pictures: for each class, the photos where it was detected correctly
    # with the highest confidence, with every detection drawn.
    picture_dir = os.path.join(out, 'detections')
    os.makedirs(picture_dir, exist_ok=True)
    for class_name in CLASSES:
        chosen = []
        for _, name in sorted(best_example[class_name], reverse=True):
            if name not in chosen:
                chosen.append(name)
            if len(chosen) == (4 if class_name in NEW_CLASSES else 2):
                break
        for number, name in enumerate(chosen, 1):
            result = model.predict(os.path.join(image_dir, name), conf=APP_THRESHOLD,
                                   imgsz=640, verbose=False)[0]
            result.save(os.path.join(
                picture_dir, f"{class_name.replace(' ', '_')}_{number}.jpg"))
    print(f'pictures saved in {picture_dir}')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--data', required=True)
    parser.add_argument('--weights', required=True)
    parser.add_argument('--out', default='report')
    parser.add_argument('--batch', type=int, default=16)
    args = parser.parse_args()
    evaluate(args.data, args.weights, args.out, args.batch)


if __name__ == '__main__':
    sys.exit(main())
