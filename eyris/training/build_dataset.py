#!/usr/bin/env python3
"""Build the EYRIS detection dataset (YOLO format) from public sources.

Sources
  * Open Images V7 (CC BY 4.0 annotations) for 19 of the 20 classes.
  * RDD2022 road-damage dataset (CC BY-SA 4.0), Hugging Face mirror
    dronefreak/RDD2022, for potholes.

"Wall" is deliberately not a class: a wall has no outline to put a box
around, so the app reports it from the distance sensor as an obstacle ahead.

Only the Python standard library is required. If Pillow is installed, large
photos are downscaled to save disk space and training time.

Example (Colab):
    python build_dataset.py --out /content/eyris_data --per-class 2500
Quick self-test with a handful of images:
    python build_dataset.py --out ./sample --per-class 3 --val-per-class 2 \
        --potholes 4 --oi-train-split validation
"""
import argparse
import csv
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

# Index in this list == class id in the trained model. The app maps these
# names to its spoken labels (see lib/services/yolo_detection_service.dart).
CLASSES = [
    'person', 'car', 'motorcycle', 'bicycle', 'truck', 'bus', 'pothole',
    'tree', 'pole', 'traffic sign', 'chair', 'table', 'door', 'stairs',
    'bed', 'sofa', 'bottle', 'dustbin', 'bag', 'laptop',
]

# Open Images display name -> EYRIS class.
OPEN_IMAGES_CLASSES = {
    'Person': 'person', 'Man': 'person', 'Woman': 'person', 'Boy': 'person',
    'Girl': 'person',
    'Car': 'car', 'Taxi': 'car', 'Van': 'car',
    'Motorcycle': 'motorcycle',
    'Bicycle': 'bicycle',
    'Truck': 'truck',
    'Bus': 'bus',
    'Tree': 'tree', 'Palm tree': 'tree',
    'Street light': 'pole',
    'Traffic sign': 'traffic sign', 'Stop sign': 'traffic sign',
    'Chair': 'chair',
    'Table': 'table', 'Coffee table': 'table', 'Desk': 'table',
    'Kitchen & dining room table': 'table',
    'Door': 'door',
    'Stairs': 'stairs',
    'Bed': 'bed',
    'Couch': 'sofa', 'Sofa bed': 'sofa', 'Loveseat': 'sofa',
    'Studio couch': 'sofa',
    'Bottle': 'bottle',
    'Waste container': 'dustbin',
    'Backpack': 'bag', 'Handbag': 'bag', 'Suitcase': 'bag', 'Briefcase': 'bag',
    'Laptop': 'laptop',
}

OI_CLASS_NAMES_URL = ('https://storage.googleapis.com/openimages/v7/'
                      'oidv7-class-descriptions-boxable.csv')
OI_BOXES_URL = {
    'train': ('https://storage.googleapis.com/openimages/v6/'
              'oidv6-train-annotations-bbox.csv'),
    'validation': ('https://storage.googleapis.com/openimages/v5/'
                   'validation-annotations-bbox.csv'),
    # 125,000 photos; a much smaller download than the 2 GB training list.
    'test': ('https://storage.googleapis.com/openimages/v5/'
             'test-annotations-bbox.csv'),
}
OI_IMAGE_URL = 'https://open-images-dataset.s3.amazonaws.com/{split}/{id}.jpg'

RDD_BASE = 'https://huggingface.co/datasets/dronefreak/RDD2022/resolve/main/data'
RDD_SHARDS = {'train': 9, 'valid': 2}
RDD_POTHOLE_CATEGORY = 3
# Aerial photos look nothing like what a pedestrian's camera sees.
RDD_SKIP_PREFIXES = ('China_Drone',)

# Training runs at 640 px, so larger photos only slow loading down.
MAX_IMAGE_SIDE = 640


def fetch(url, path=None, retries=5, timeout=120):
    """Download url. Returns bytes, or writes to path (skipping existing files)."""
    if path and os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    last = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'eyris-dataset/1.0'})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                if not path:
                    return response.read()
                part = path + '.part'
                with open(part, 'wb') as out:
                    while True:
                        block = response.read(1 << 20)
                        if not block:
                            break
                        out.write(block)
                os.replace(part, path)
                return path
        except urllib.error.HTTPError as error:
            if error.code in (403, 404):
                raise
            last = error
        except Exception as error:  # noqa: BLE001 - network errors are retried
            last = error
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f'download failed: {url}: {last}')


def shrink(path):
    """Downscale a large photo in place. Labels are normalized, so they stay valid."""
    try:
        from PIL import Image
    except ImportError:
        return
    try:
        with Image.open(path) as image:
            if max(image.size) <= MAX_IMAGE_SIDE:
                return
            image = image.convert('RGB')
            image.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
            image.save(path, 'JPEG', quality=90)
    except Exception as error:  # noqa: BLE001 - a bad photo must not stop the build
        print(f'  could not resize {os.path.basename(path)}: {error}')


def yolo_line(class_name, x_min, y_min, x_max, y_max):
    """One label line from normalized corner coordinates, or None if degenerate."""
    x_min, y_min = max(0.0, x_min), max(0.0, y_min)
    x_max, y_max = min(1.0, x_max), min(1.0, y_max)
    width, height = x_max - x_min, y_max - y_min
    if width <= 0.002 or height <= 0.002:
        return None
    return (f'{CLASSES.index(class_name)} {(x_min + x_max) / 2:.6f} '
            f'{(y_min + y_max) / 2:.6f} {width:.6f} {height:.6f}')


def choose_images(classes_per_image, per_class, seed):
    """Pick images so every class reaches per_class images, rarest class first.

    classes_per_image: {image_id: set of class names}. Common classes fill up
    by appearing alongside rare ones, which keeps the dataset balanced.
    """
    by_class = defaultdict(list)
    for image_id, names in classes_per_image.items():
        for name in names:
            by_class[name].append(image_id)
    rng = random.Random(seed)
    chosen, counts = set(), Counter()
    for name in sorted(by_class, key=lambda n: len(by_class[n])):
        candidates = sorted(by_class[name])
        rng.shuffle(candidates)
        for image_id in candidates:
            if counts[name] >= per_class:
                break
            if image_id in chosen:
                continue
            chosen.add(image_id)
            counts.update(classes_per_image[image_id])
    return chosen, counts


def open_images(split, subset, per_class, out, cache, seed, workers):
    """Add Open Images photos of the EYRIS classes to out/{images,labels}/subset."""
    print(f'[open images] {split} -> {subset}, up to {per_class} images per class')
    names = {}
    for row in csv.reader(fetch(OI_CLASS_NAMES_URL).decode('utf8').splitlines()):
        if len(row) >= 2:
            names[row[0]] = row[1]
    label_to_class = {label: OPEN_IMAGES_CLASSES[name]
                      for label, name in names.items() if name in OPEN_IMAGES_CLASSES}
    missing = set(OPEN_IMAGES_CLASSES) - set(names.values())
    if missing:
        raise SystemExit(f'Open Images no longer lists: {sorted(missing)}')

    boxes_csv = fetch(OI_BOXES_URL[split], os.path.join(cache, f'oi-{split}-bbox.csv'))

    def rows():
        with open(boxes_csv, newline='', encoding='utf8') as handle:
            reader = csv.reader(handle)
            header = next(reader)
            col = {name: header.index(name) for name in (
                'ImageID', 'LabelName', 'XMin', 'XMax', 'YMin', 'YMax',
                'IsGroupOf', 'IsDepiction')}
            for row in reader:
                name = label_to_class.get(row[col['LabelName']])
                # Group boxes cover a whole crowd and depictions are drawings
                # or statues; neither teaches the shape of a real object.
                if (name is None or row[col['IsGroupOf']] == '1'
                        or row[col['IsDepiction']] == '1'):
                    continue
                yield (row[col['ImageID']], name, float(row[col['XMin']]),
                       float(row[col['YMin']]), float(row[col['XMax']]),
                       float(row[col['YMax']]))

    classes_per_image = defaultdict(set)
    for image_id, name, *_ in rows():
        classes_per_image[image_id].add(name)
    chosen, _ = choose_images(classes_per_image, per_class, seed)
    del classes_per_image

    labels = defaultdict(list)
    for image_id, name, x_min, y_min, x_max, y_max in rows():
        if image_id in chosen:
            line = yolo_line(name, x_min, y_min, x_max, y_max)
            if line:
                labels[image_id].append(line)

    image_dir = os.path.join(out, 'images', subset)
    label_dir = os.path.join(out, 'labels', subset)
    os.makedirs(image_dir, exist_ok=True)
    os.makedirs(label_dir, exist_ok=True)

    def save(image_id):
        target = os.path.join(image_dir, f'oi_{image_id}.jpg')
        try:
            fetch(OI_IMAGE_URL.format(split=split, id=image_id), target)
        except Exception as error:  # noqa: BLE001 - skip photos that are gone
            return f'{image_id}: {error}'
        shrink(target)
        with open(os.path.join(label_dir, f'oi_{image_id}.txt'), 'w') as handle:
            handle.write('\n'.join(labels[image_id]) + '\n')
        return None

    todo = sorted(image_id for image_id in chosen if labels[image_id])
    failed = 0
    with ThreadPoolExecutor(workers) as pool:
        for done, error in enumerate(pool.map(save, todo), 1):
            failed += error is not None
            if done % 1000 == 0 or done == len(todo):
                print(f'  {done}/{len(todo)} photos ({failed} unavailable)')
    return len(todo) - failed


def potholes(out, limit, val_limit, seed, workers):
    """Add RDD2022 street photos containing potholes."""
    print(f'[rdd2022] up to {limit} training and {val_limit} validation pothole photos')
    total = 0
    for rdd_split, subset, cap in (('train', 'train', limit), ('valid', 'val', val_limit)):
        wanted = []
        for shard in range(RDD_SHARDS[rdd_split]):
            folder = f'{rdd_split}/shard_{shard:03d}'
            listing = fetch(f'{RDD_BASE}/images/{folder}/metadata.jsonl').decode('utf8')
            for line in listing.splitlines():
                if not line.strip():
                    continue
                entry = json.loads(line)
                name = entry['file_name']
                if (RDD_POTHOLE_CATEGORY in entry['objects']['categories']
                        and not name.startswith(RDD_SKIP_PREFIXES)):
                    wanted.append((folder, name))
        random.Random(seed).shuffle(wanted)
        wanted = wanted[:cap]

        image_dir = os.path.join(out, 'images', subset)
        label_dir = os.path.join(out, 'labels', subset)
        os.makedirs(image_dir, exist_ok=True)
        os.makedirs(label_dir, exist_ok=True)

        def save(item, image_dir=image_dir, label_dir=label_dir):
            folder, name = item
            stem = os.path.splitext(name)[0]
            try:
                source = fetch(f'{RDD_BASE}/labels/{folder}/{stem}.txt').decode('utf8')
                lines = []
                for row in source.splitlines():
                    parts = row.split()
                    if len(parts) == 5 and int(parts[0]) == RDD_POTHOLE_CATEGORY:
                        cx, cy, w, h = map(float, parts[1:])
                        line = yolo_line('pothole', cx - w / 2, cy - h / 2,
                                         cx + w / 2, cy + h / 2)
                        if line:
                            lines.append(line)
                if not lines:
                    return 'no pothole boxes'
                target = os.path.join(image_dir, f'rdd_{name}')
                fetch(f'{RDD_BASE}/images/{folder}/{name}', target)
                shrink(target)
                with open(os.path.join(label_dir, f'rdd_{stem}.txt'), 'w') as handle:
                    handle.write('\n'.join(lines) + '\n')
                return None
            except Exception as error:  # noqa: BLE001
                return f'{name}: {error}'

        with ThreadPoolExecutor(workers) as pool:
            results = list(pool.map(save, wanted))
        saved = sum(result is None for result in results)
        print(f'  {subset}: {saved}/{len(wanted)} pothole photos')
        total += saved
    return total


def tidy(out, subset):
    """After an interrupted run: drop partial downloads and photos without labels."""
    image_dir = os.path.join(out, 'images', subset)
    label_dir = os.path.join(out, 'labels', subset)
    removed = 0
    for name in os.listdir(image_dir):
        stem, extension = os.path.splitext(name)
        label = os.path.join(label_dir, stem + '.txt')
        if extension == '.part' or not os.path.exists(label):
            os.remove(os.path.join(image_dir, name))
            removed += 1
    print(f'[tidy] {subset}: removed {removed} incomplete files, '
          f'{len(os.listdir(image_dir))} photos kept')


def summarize(out):
    """Write data.yaml and print how many boxes each class has."""
    report = {}
    for subset in ('train', 'val'):
        counts, images = Counter(), 0
        label_dir = os.path.join(out, 'labels', subset)
        for name in os.listdir(label_dir) if os.path.isdir(label_dir) else []:
            images += 1
            with open(os.path.join(label_dir, name)) as handle:
                for line in handle:
                    if line.strip():
                        counts[CLASSES[int(line.split()[0])]] += 1
        report[subset] = (images, counts)

    with open(os.path.join(out, 'data.yaml'), 'w') as handle:
        handle.write(f'path: {os.path.abspath(out)}\n')
        handle.write('train: images/train\nval: images/val\n')
        handle.write('names:\n')
        for index, name in enumerate(CLASSES):
            handle.write(f'  {index}: {name}\n')

    print(f"\n{'class':<14}{'train boxes':>12}{'val boxes':>11}")
    for name in CLASSES:
        print(f"{name:<14}{report['train'][1][name]:>12}{report['val'][1][name]:>11}")
    print(f"{'photos':<14}{report['train'][0]:>12}{report['val'][0]:>11}")
    weak = [name for name in CLASSES if report['train'][1][name] < 300]
    if weak:
        print(f'\nNOTE: fewer than 300 training boxes for: {", ".join(weak)}. '
              'Expect weak detection for these until more photos are added.')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--out', required=True, help='dataset folder to create')
    parser.add_argument('--cache', help='folder for downloaded annotation files')
    parser.add_argument('--per-class', type=int, default=2500,
                        help='training photos to collect per class')
    parser.add_argument('--val-per-class', type=int, default=150)
    parser.add_argument('--potholes', type=int, default=3000,
                        help='training photos with potholes')
    parser.add_argument('--val-potholes', type=int, default=300)
    parser.add_argument('--oi-train-split', default='train',
                        choices=sorted(OI_BOXES_URL),
                        help='Open Images split to build the training set from')
    parser.add_argument('--keep-train', action='store_true',
                        help='keep the Open Images training photos already '
                             'downloaded by an interrupted run and add no more')
    parser.add_argument('--workers', type=int, default=32)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    cache = args.cache or os.path.join(args.out, '_cache')
    os.makedirs(cache, exist_ok=True)

    if args.keep_train:
        tidy(args.out, 'train')
    else:
        open_images(args.oi_train_split, 'train', args.per_class, args.out,
                    cache, args.seed, args.workers)
    if args.oi_train_split == 'validation':
        print('[open images] self-test: validation photos reused for val')
    # A different seed keeps validation photos distinct in the self-test too.
    open_images('validation', 'val', args.val_per_class, args.out, cache,
                args.seed + 1, args.workers)
    potholes(args.out, args.potholes, args.val_potholes, args.seed, args.workers)
    summarize(args.out)
    print(f'\nDataset ready: {os.path.join(os.path.abspath(args.out), "data.yaml")}')


if __name__ == '__main__':
    sys.exit(main())
