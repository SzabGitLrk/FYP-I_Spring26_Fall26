#!/usr/bin/env python3
"""Unpack ADE20K parquet files (Hugging Face 1aurent/ADE20K) into photos plus
one line of boxes per photo.

    python ade_extract.py <parquet> [<parquet> ...] --out D:/dev/eyris_work/ade/val

ADE20K labels every object in every photo, so unlike Open Images it can
measure false alarms, and it has walls, floors, doors, stairs and sidewalks.
Each line of objects.jsonl is {"file", "width", "height", "objects": [[name, x1, y1, x2, y2], ...]}
with pixel boxes taken from the outline of each whole object (parts of objects,
such as a car door or a cabinet door, are skipped).
"""
import argparse
import io
import json
import os

import duckdb
from PIL import Image

MAX_SIDE = 640


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('parquet', nargs='+')
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    image_dir = os.path.join(args.out, 'images')
    os.makedirs(image_dir, exist_ok=True)
    count = 0
    with open(os.path.join(args.out, 'objects.jsonl'), 'a', encoding='utf8') as lines:
        for path in args.parquet:
            con = duckdb.connect()
            total = con.execute('SELECT count(*) FROM read_parquet(?)', [path]).fetchone()[0]
            for offset in range(0, total, 50):
                rows = con.execute(
                    'SELECT filename, image, objects FROM read_parquet(?) LIMIT 50 OFFSET ?',
                    [path, offset]).fetchall()
                for filename, image, objects in rows:
                    name = os.path.splitext(os.path.basename(filename))[0] + '.jpg'
                    photo = Image.open(io.BytesIO(image['bytes'])).convert('RGB')
                    width, height = photo.size
                    scale = min(1.0, MAX_SIDE / max(width, height))
                    if scale < 1.0:
                        photo = photo.resize((round(width * scale), round(height * scale)),
                                             Image.BILINEAR)
                    photo.save(os.path.join(image_dir, name), quality=90)
                    boxes = []
                    for item in objects:
                        xs, ys = item['polygon']['x'], item['polygon']['y']
                        if item['parts']['part_level'] != 0 or len(xs) < 3:
                            continue
                        x1, x2 = min(xs) * scale, max(xs) * scale
                        y1, y2 = min(ys) * scale, max(ys) * scale
                        if x2 - x1 < 2 or y2 - y1 < 2:
                            continue
                        boxes.append([item['name'], round(x1, 1), round(y1, 1),
                                      round(x2, 1), round(y2, 1), bool(item['occluded'])])
                    lines.write(json.dumps({'file': name, 'width': photo.width,
                                            'height': photo.height, 'objects': boxes}) + '\n')
                    count += 1
                print(f'  {count} photos', flush=True)
            con.close()
    print('done', count)


if __name__ == '__main__':
    main()
