#!/usr/bin/env python3
"""Build the EYRIS "scene" training set (YOLO format) from ADE20K photos
unpacked by ade_extract.py.

    python build_scene_dataset.py --source D:/dev/eyris_work/ade/val --holdout 0.15 \
        --source D:/dev/eyris_work/ade/train0 --out D:/dev/eyris_work/scene

ADE20K labels every object in every photo, so the model also learns what is
NOT a table: floors, ceilings, windows, railings and cabinets are classes of
their own. The app never reports those; they exist so that a ceiling is
recognised as a ceiling.

A share of the first source (--holdout) is kept out of training and written
to test.txt; accuracy is measured on those photos only.
"""
import argparse
import hashlib
import json
import os
from collections import Counter

# Index == class id in the trained model (labels_scene.txt in the app).
CLASSES = [
    'person', 'car', 'motorcycle', 'bicycle', 'truck', 'bus', 'tree', 'pole',
    'traffic light', 'chair', 'table', 'door', 'stairs', 'wall', 'bed', 'sofa',
    'bottle', 'dustbin', 'bag', 'laptop', 'footpath', 'air conditioner', 'fan',
    # Surroundings: learned so they are not mistaken for the classes above.
    'floor', 'ceiling', 'window', 'railing', 'road', 'cabinet', 'curtain',
    'signboard', 'building', 'plant', 'column', 'fence',
]

ADE_NAMES = {
    'person, individual, someone, somebody, mortal, soul': 'person',
    'car, auto, automobile, machine, motorcar': 'car', 'van': 'car',
    'minibike, motorbike': 'motorcycle',
    'bicycle, bike, wheel, cycle': 'bicycle',
    'truck, motortruck': 'truck',
    'bus, autobus, coach, charabanc, double-decker, jitney, motorbus, motorcoach, omnibus, passenger vehicle': 'bus',
    'tree': 'tree', 'palm, palm tree': 'tree',
    'pole': 'pole', 'streetlight, street lamp': 'pole',
    'traffic light, traffic signal, stoplight': 'traffic light',
    'chair': 'chair', 'armchair': 'chair', 'swivel chair': 'chair',
    'chair desk': 'chair', 'deck chair, beach chair': 'chair', 'stool': 'chair',
    'table': 'table', 'desk': 'table', 'coffee table, cocktail table': 'table',
    'console table, console': 'table',
    'door': 'door', 'double door': 'door', 'screen door, screen': 'door',
    'stairs, steps': 'stairs', 'stairway, staircase': 'stairs', 'step, stair': 'stairs',
    'wall': 'wall',
    'bed': 'bed',
    'sofa, couch, lounge': 'sofa',
    'bottle': 'bottle',
    'ashcan, trash can, garbage can, wastebin, ash bin, ash-bin, ashbin, dustbin, trash barrel, trash bin': 'dustbin',
    'bag': 'bag', 'bag, handbag, pocketbook, purse': 'bag',
    'backpack, back pack, knapsack, packsack, rucksack, haversack': 'bag',
    'bag, traveling bag, travelling bag, grip, suitcase': 'bag',
    'laptop, laptop computer': 'laptop',
    'sidewalk, pavement': 'footpath',
    'air conditioner, air conditioning': 'air conditioner',
    'fan': 'fan',
    'floor, flooring': 'floor',
    'ceiling': 'ceiling',
    'windowpane, window': 'window',
    'railing, rail': 'railing',
    'bannister, banister, balustrade, balusters, handrail': 'railing',
    'road, route': 'road',
    'cabinet': 'cabinet', 'wardrobe, closet, press': 'cabinet', 'shelf': 'cabinet',
    'curtain, drape, drapery, mantle, pall': 'curtain',
    'signboard, sign': 'signboard',
    'building, edifice': 'building',
    'plant, flora, plant life': 'plant',
    'column, pillar': 'column',
    'fence, fencing': 'fence',
}
MIN_SIDE = 0.012   # of the photo: smaller boxes cannot be seen at 384 px


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--source', action='append', required=True)
    parser.add_argument('--holdout', type=float, default=0.15)
    parser.add_argument('--out', required=True)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    index = {name: i for i, name in enumerate(CLASSES)}
    train, test = [], []
    counts = Counter()
    for number, source in enumerate(args.source):
        image_dir = os.path.join(source, 'images')
        label_dir = os.path.join(source, 'labels')
        os.makedirs(label_dir, exist_ok=True)
        with open(os.path.join(source, 'objects.jsonl'), encoding='utf8') as handle:
            for line in handle:
                record = json.loads(line)
                width, height = record['width'], record['height']
                rows = []
                for name, x1, y1, x2, y2, _ in record['objects']:
                    target = ADE_NAMES.get(name)
                    if target is None:
                        continue
                    w, h = (x2 - x1) / width, (y2 - y1) / height
                    if w < MIN_SIDE or h < MIN_SIDE:
                        continue
                    rows.append(f'{index[target]} {(x1 + x2) / 2 / width:.6f} '
                                f'{(y1 + y2) / 2 / height:.6f} {w:.6f} {h:.6f}')
                    counts[target] += 1
                stem = os.path.splitext(record['file'])[0]
                with open(os.path.join(label_dir, stem + '.txt'), 'w') as out:
                    out.write('\n'.join(rows) + ('\n' if rows else ''))
                path = os.path.join(image_dir, record['file']).replace('\\', '/')
                digest = int(hashlib.md5(record['file'].encode()).hexdigest(), 16)
                held = number == 0 and (digest % 1000) / 1000 < args.holdout
                (test if held else train).append(path)

    for name, paths in (('train', train), ('test', test)):
        with open(os.path.join(args.out, name + '.txt'), 'w') as handle:
            handle.write('\n'.join(paths) + '\n')
    with open(os.path.join(args.out, 'data.yaml'), 'w') as handle:
        handle.write(f"path: {args.out.replace(chr(92), '/')}\ntrain: train.txt\nval: test.txt\nnames:\n")
        for i, name in enumerate(CLASSES):
            handle.write(f'  {i}: {name}\n')
    print(f'{len(train)} training photos, {len(test)} held out')
    print(', '.join(f'{name} {counts[name]}' for name in CLASSES))


if __name__ == '__main__':
    main()
