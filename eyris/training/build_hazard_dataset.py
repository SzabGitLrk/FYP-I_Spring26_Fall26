#!/usr/bin/env python3
"""Build the training set of the "hazard" model: pothole, speed breaker,
standing AC and open drain, the objects the other models could not find
reliably.

    python build_hazard_dataset.py            # writes D:/dev/eyris_work/hazard/ds

Sources (all on the development PC):
  - Potholes: RDD2022 photos already used by the road model (its split is
    kept, so the road model's test photos stay test photos here), plus the
    Roboflow "potholes-detection-d4rma" set (CC BY 4.0, via Hugging Face
    Ryukijano/Pothole-detection-Yolov8).
  - Speed breakers: SBP-YOLO speed bump set (github.com/chuanqi1997/SBP-YOLO).
  - Standing ACs: Objects365 photos fetched by objects365_ac.py and
    Wikimedia Commons photos, every box checked by eye (hazard/ac_review.json,
    written by hazard/ac_decisions.py). Objects365 photos whose ACs are all
    wall, window or outdoor units are kept as photos without a standing AC.
  - Open drains (open manholes, missing or broken drain slabs, open drain
    channels): the "open manhole" class of the Kaggle set
    sabidrahman/pothole-cracks-and-openmanhole (fetched with remote_zip.py),
    and the Uncovered and Broken folders of the Bangladesh manhole set
    (Mendeley Data 10.17632/7zzcmv2wz7.1, CC BY 4.0, mendeley_manholes.py),
    whose photos carry no boxes: drain_boxes.py proposes them and every one
    was checked by eye (hazard/drain_review.json).
  - Open drains in the client's own videos (2026-10-15): frames written by
    client_drafts.py, boxes read off box_sheets.py grids
    (hazard/client_review.json). Training only; the client's first video
    (5.51.55 PM) is kept for testing.
  - More open manholes, with closed ones as photos without an open drain,
    from three Kaggle sets with boxes: amandapriyashantha/manhole-detection-
    dataset (Roboflow, CC BY 4.0), cubeai/manhole-for-yolov8 and
    deeppratap/manhole-detection (Roboflow, CC BY 4.0). Their own split is
    kept (valid and test are our test) and one copy per original is used.
  - Closed manholes, square covers and grates from the same Bangladesh set,
    as photos without an open drain: a covered drain is safe to walk on.
  - The ESP32 camera's view of rooms, cut out of the client's screen
    recording 249.mp4 by screen_frames.py: photos without any hazard (the
    old model saw a speed breaker in a laptop keyboard there). The last
    fifth of the recording is test.
  - Photos with none of the four: ADE20K rooms and streets, so that a road,
    a zebra crossing, a fridge or a wardrobe is learned as "nothing". ADE
    photos with any air conditioner are left out, because standing units are
    not told apart from wall units there.

A photo goes to test when a hash of its name says so; copies of one photo
(Roboflow's "<base>_jpg.rf.<hash>") share the hash of the base. The
Bangladesh set holds several brightness and blur variants of each shot
under different names, so there near-identical photos share one hash.
"""
import hashlib
import json
import os
import random
import shutil

import numpy as np

WORK = 'D:/dev/eyris_work'
H = f'{WORK}/hazard'
OUT = f'{H}/ds'
CLASSES = ['pothole', 'speed breaker', 'standing ac', 'open drain']
ADE_AC, ADE_ROAD, ADE_FOOTPATH = 21, 27, 20
ADE_INDOOR = {14, 15, 10, 24, 28, 29}   # bed, sofa, table, ceiling, cabinet, curtain
AC_REPEAT = 4
DRAIN_REPEAT = 3
OI_NEGATIVES = 2000
KAGGLE = f'{H}/kaggle_om/dataset/dataset'
MENDELEY = f'{H}/mendeley_bd'
# Square_Manhole_(119): a broken frame, maybe open; neither safe nor sure.
MENDELEY_UNSURE = {'Square_Manhole_(119).jpg'}
ESP32_ROOMS_TEST_FROM = 3250   # video frame; 249.mp4 has 4061


def test_share(name, share):
    base = os.path.basename(name).split('.rf.')[0].split('_jpg')[0]
    return int(hashlib.md5(base.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF < share


def photo_groups(paths, bits=12):
    """Path -> the first path of its group of near-identical photos (a
    difference hash differing in at most `bits` of 64)."""
    from PIL import Image
    hashes = []
    for p in paths:
        g = np.asarray(Image.open(p).convert('L').resize((9, 8), Image.BILINEAR), dtype=np.int16)
        hashes.append((g[:, 1:] > g[:, :-1]).flatten())
    parent = list(range(len(paths)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(paths)):
        for j in range(i):
            if int((hashes[i] != hashes[j]).sum()) <= bits:
                parent[find(i)] = find(j)
    return {p: paths[find(i)] for i, p in enumerate(paths)}


def read(path):
    if not os.path.exists(path):
        return []
    return [l.split() for l in open(path) if l.strip()]


def yolo_box(row):
    """[class, cx, cy, w, h] from a box row, or from a polygon row."""
    if len(row) <= 6:
        return row[:5]
    xs, ys = list(map(float, row[1::2])), list(map(float, row[2::2]))
    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
    return [row[0], (x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1]


def manhole_sets():
    """(image, open drain rows, split, prefix) from the Kaggle manhole sets
    with boxes. Amanda's "improperly closed" covers are mostly shut and a
    few gape, so photos with one are left out."""
    sets = [(f'{H}/kaggle_amanda/manhole_detection.v1i.yolov11', {'2'}, {'1'}, 'oma_'),
            (f'{H}/kaggle_cube', {'1'}, set(), 'omc_'),
            (f'{H}/kaggle_deep', {'1'}, set(), 'omd_')]
    for root, open_ids, unsure_ids, prefix in sets:
        for split in ('train', 'valid', 'test'):
            seen = set()
            for n in sorted(os.listdir(f'{root}/{split}/labels')):
                base = n.split('.rf.')[0]
                image = f'{root}/{split}/images/{n[:-4]}.jpg'
                if base in seen or not os.path.exists(image):
                    continue
                seen.add(base)
                rows = [yolo_box(r) for r in read(f'{root}/{split}/labels/{n}')]
                if {r[0] for r in rows} & unsure_ids:
                    continue
                yield (image, [[3] + r[1:5] for r in rows if r[0] in open_ids],
                       'train' if split == 'train' else 'test', prefix)


def put(split, image, rows, prefix):
    name = prefix + os.path.basename(image)
    if not name.lower().endswith('.jpg'):
        name = os.path.splitext(name)[0] + '.jpg'
    dst = f'{OUT}/images/{split}/{name}'
    if image.lower().endswith('.jpg'):
        try:
            os.link(image, dst)
        except OSError:
            shutil.copy(image, dst)
    else:
        from PIL import Image
        Image.open(image).convert('RGB').save(dst, quality=92)
    with open(f'{OUT}/labels/{split}/{name[:-4]}.txt', 'w') as f:
        for c, cx, cy, w, h in rows:
            f.write(f'{c} {float(cx):.6f} {float(cy):.6f} {float(w):.6f} {float(h):.6f}\n')
    return split


def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    for s in ('train', 'test'):
        os.makedirs(f'{OUT}/images/{s}')
        os.makedirs(f'{OUT}/labels/{s}')
    count = {}

    def add(split, kind, image, rows, prefix):
        put(split, image, rows, prefix)
        count[(kind, split)] = count.get((kind, split), 0) + 1

    # Potholes, RDD: keep the road model's split.
    for split, dst in (('train', 'train'), ('val', 'test')):
        d = f'{WORK}/data'
        for n in sorted(os.listdir(f'{d}/images/{split}')):
            if not n.startswith('rdd_'):
                continue
            rows = [[0] + r[1:5] for r in read(f'{d}/labels/{split}/{n[:-4]}.txt') if r[0] == '6']
            if rows:
                add(dst, 'pothole', f'{d}/images/{split}/{n}', rows, '')
    # Potholes, Roboflow set: its own test split is ours.
    for split in ('train', 'valid', 'test'):
        d = f'{H}/ryu/{split}'
        for n in sorted(os.listdir(f'{d}/images')):
            rows = [[0] + r[1:5] for r in read(f'{d}/labels/{n[:-4]}.txt')]
            add('test' if split == 'test' else 'train', 'pothole', f'{d}/images/{n}', rows, 'rf_')
    # Speed breakers.
    d = f'{H}/sbp'
    for n in sorted(os.listdir(f'{d}/images')):
        lab = f'{d}/labels/{n[:-4]}.txt'
        if not n.endswith('.jpg') or not os.path.exists(lab):
            continue
        rows = [[1] + r[1:5] for r in read(lab) if r[0] == '1']
        add('test' if test_share(n, 0.15) else 'train', 'speed breaker', f'{d}/images/{n}', rows, 'sb_')
    # Standing ACs, checked by eye (ac_decisions.py). There are few, so each
    # training photo is used AC_REPEAT times.
    review = json.load(open(f'{H}/ac_review.json'))
    positives = [(p, [[2] + r for r in rows], 'acw_') for p, rows in review['commons'].items()]
    positives += [(f'{H}/o365/images/{n}', [r[:5] for r in read(f'{H}/o365/labels/{n[:-4]}.txt')],
                   'aco_') for n in review['o365_keep']]
    for path, rows, prefix in sorted(positives):
        if test_share(path, 0.25):
            add('test', 'standing ac', path, rows, prefix)
        else:
            for k in range(AC_REPEAT):
                add('train', 'standing ac', path, rows, f'{prefix}{k}_')
    # Objects365 photos whose ACs are all on walls, windows or outside.
    for n in review['o365_negative']:
        add('test' if test_share(n, 0.2) else 'train', 'wall ac', f'{H}/o365/images/{n}', [], 'acn_')
    # Open drains, Kaggle (class 2 there): the open manhole class folder,
    # plus the few originals that are only in its train folder. Its
    # "_aug_" copies are left out; training makes its own variants.
    drains = {}
    for n in sorted(os.listdir(f'{KAGGLE}/classes/open_manhole/images')):
        rows = read(f'{KAGGLE}/classes/open_manhole/labels/txt/{n[:-4]}.txt')
        drains[n] = (f'{KAGGLE}/classes/open_manhole/images/{n}', rows)
    for n in sorted(os.listdir(f'{KAGGLE}/train/images')):
        if n not in drains:
            drains[n] = (f'{KAGGLE}/train/images/{n}', read(f'{KAGGLE}/train/labels/{n[:-4]}.txt'))
    for n, (path, rows) in sorted(drains.items()):
        rows = [[3] + r[1:5] for r in rows if r[0] == '2']
        if not rows:
            continue
        if test_share(n, 0.2):
            add('test', 'open drain', path, rows, 'omk_')
        else:
            for k in range(DRAIN_REPEAT):
                add('train', 'open drain', path, rows, f'omk{k}_')
    for path, rows, split, prefix in manhole_sets():
        if not rows:
            add(split, 'closed drain', path, [], prefix)
        elif split == 'test':
            add(split, 'open drain', path, rows, prefix)
        else:
            for k in range(DRAIN_REPEAT):
                add(split, 'open drain', path, rows, f'{prefix}{k}_')
    # Bangladesh set: open drains boxed by drain_boxes.py and checked by eye,
    # and closed covers and grates as photos without one.
    drain_review = f'{H}/drain_review.json'
    boxed = json.load(open(drain_review)) if os.path.exists(drain_review) else {}
    closed = [f'{MENDELEY}/{folder}/{n}' for folder in ('Good_Manhole', 'Square_Manhole')
              for n in sorted(os.listdir(f'{MENDELEY}/{folder}'))
              if n.endswith('.jpg') and n not in MENDELEY_UNSURE]
    opened = sorted(boxed.get('boxes', {}))
    unopened = sorted(boxed.get('no_drain', []))
    groups = photo_groups(opened + closed + unopened)
    for path in opened:
        rows = [[3] + r for r in boxed['boxes'][path]]
        if test_share(groups[path], 0.25):
            add('test', 'open drain', path, rows, 'omb_')
        else:
            for k in range(DRAIN_REPEAT):
                add('train', 'open drain', path, rows, f'omb{k}_')
    for path in closed + unopened:
        add('test' if test_share(groups[path], 0.25) else 'train', 'closed drain', path, [], 'omn_')
    # ESP32 frames of rooms (one every 25 video frames, about a second
    # apart), twice each: they are few and exactly where the false alarms were.
    rooms = f'{H}/client_249/crops'
    for n in sorted(os.listdir(rooms)) if os.path.isdir(rooms) else []:
        if int(n.rsplit('_', 1)[1][:-4]) >= ESP32_ROOMS_TEST_FROM:
            add('test', 'esp32 room', f'{rooms}/{n}', [], '')
        else:
            for k in range(2):
                add('train', 'esp32 room', f'{rooms}/{n}', [], f'r{k}_')
    # The client's videos: few frames of few places, so each is used
    # DRAIN_REPEAT times, like the other small drain sets.
    client = f'{H}/client_review.json'
    for n, corners in sorted(json.load(open(client))['corners10'].items()) if os.path.exists(client) else []:
        rows = [[3, (x1 + x2) / 20, (y1 + y2) / 20, (x2 - x1) / 10, (y2 - y1) / 10]
                for x1, y1, x2, y2 in corners]
        for k in range(DRAIN_REPEAT):
            add('train', 'client drain', f'{H}/client_frames/images/{n}', rows, f'cl{k}_')
    # Nothing-of-the-four photos from ADE20K.
    street, indoor = [], []
    lists = [l.strip() for f in ('train.txt', 'test.txt') for l in open(f'{WORK}/scene/{f}') if l.strip()]
    for image in lists:
        lab = image.replace('/images/', '/labels/')[:-4] + '.txt'
        classes = {int(r[0]) for r in read(lab)}
        if ADE_AC in classes:
            continue
        if classes & {ADE_ROAD, ADE_FOOTPATH}:
            street.append(image)
        elif classes & ADE_INDOOR:
            indoor.append(image)
    rng = random.Random(7)
    rng.shuffle(street)
    rng.shuffle(indoor)
    for kind, pool, n_train, n_test in (('street', street, 1500, 300), ('indoor', indoor, 1500, 300)):
        for i, image in enumerate(pool[:n_train + n_test]):
            add('train' if i < n_train else 'test', kind, image, [], 'neg_')
    # Everyday Open Images photos from the road model's training half:
    # dustbins, bottles, bags, vehicles, road markings. Without them a tall
    # dustbin in the middle of a photo was taken for a standing AC. (Their
    # test half is the false-alarm check in hazard_eval.py.)
    oi = sorted(n for n in os.listdir(f'{WORK}/data/images/train') if n.startswith('oi_'))
    rng.shuffle(oi)
    for n in oi[:OI_NEGATIVES]:
        add('train', 'everyday', f'{WORK}/data/images/train/{n}', [], '')
    with open(f'{OUT}/data.yaml', 'w') as f:
        f.write(f'path: {OUT}\ntrain: images/train\nval: images/test\nnames:\n')
        for i, c in enumerate(CLASSES):
            f.write(f'  {i}: {c}\n')
    for k in sorted(count):
        print(k, count[k])


if __name__ == '__main__':
    main()
