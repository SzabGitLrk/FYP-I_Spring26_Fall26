#!/usr/bin/env python3
"""Open-drain boxes for the Bangladesh manhole photos, which come without
any: drafts by hazard_autobox.py, decisions by eye.

    python drain_boxes.py sheets <draft dir>[,<draft dir>...] <out prefix>
    python drain_boxes.py apply <decisions.json>

"sheets" draws on every photo of Uncovered_Manhole and Broken_Manhole the
best draft box of each draft folder (red: first folder, blue: second), in
numbered contact sheets of 48, and writes <out prefix>.lst with the photo
order. "apply" turns decisions into hazard/drain_review.json, the file
build_hazard_dataset.py reads. Decisions, by sheet number:

    {"list": "<out prefix>.lst",
     "red": [..], "blue": [..],          # that draft box is right
     "boxes": {"12": [[cx, cy, w, h], ..]},  # drawn by hand, 0..1
     "corners10": {"12": [[x1, y1, x2, y2], ..]},  # read off box_sheets.py grids
     "no_drain": [..],                   # no open drain in the photo
     "drop": [..]}                       # unclear: left out

"apply" also takes the list written by box_sheets.py (one photo per group
of near-identical shots); then only those photos are used.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

H = 'D:/dev/eyris_work/hazard'
FOLDERS = ['Uncovered_Manhole', 'Broken_Manhole']
COLOURS = [(255, 0, 0), (0, 160, 255)]


def photos():
    return [f'{H}/mendeley_bd/{folder}/{n}' for folder in FOLDERS
            for n in sorted(os.listdir(f'{H}/mendeley_bd/{folder}')) if n.endswith('.jpg')]


def best(draft_dir, path):
    lab = os.path.join(draft_dir, os.path.splitext(os.path.basename(path))[0] + '.txt')
    rows = [list(map(float, l.split()[1:6])) for l in open(lab) if l.strip()] if os.path.exists(lab) else []
    return max(rows, key=lambda r: r[4]) if rows else None


def sheets(drafts, prefix, cols=8, cell=200):
    paths = photos()
    with open(prefix + '.lst', 'w') as f:
        f.write('\n'.join(paths) + '\n')
    for start in range(0, len(paths), 48):
        chunk = paths[start:start + 48]
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new('RGB', (cols * cell, rows * cell), (40, 40, 40))
        draw = ImageDraw.Draw(sheet)
        for k, path in enumerate(chunk):
            im = Image.open(path).convert('RGB')
            scale = min(cell / im.width, cell / im.height)
            w, h = max(1, int(im.width * scale)), max(1, int(im.height * scale))
            x0, y0 = (k % cols) * cell + (cell - w) // 2, (k // cols) * cell + (cell - h) // 2
            sheet.paste(im.resize((w, h)), (x0, y0))
            for d, colour in zip(drafts, COLOURS):
                b = best(d, path)
                if b is None:
                    continue
                cx, cy, bw, bh, s = b
                box = (x0 + (cx - bw / 2) * w, y0 + (cy - bh / 2) * h,
                       x0 + (cx + bw / 2) * w, y0 + (cy + bh / 2) * h)
                draw.rectangle(box, outline=colour, width=2)
                draw.text((box[0] + 2, box[1] + 1), f'{s:.2f}', fill=colour)
            draw.rectangle((x0, y0, x0 + 26, y0 + 12), fill=(0, 0, 0))
            draw.text((x0 + 2, y0), str(start + k), fill=(255, 255, 255))
        sheet.save(f'{prefix}_{start // 48}.jpg', quality=88)
    print(len(paths), 'photos in', (len(paths) + 47) // 48, 'sheets')


def apply(decisions_file):
    d = json.load(open(decisions_file))
    paths = [l.strip() for l in open(d['list']) if l.strip()]
    drafts = d['drafts']
    boxes, no_drain = {}, []
    for colour, folder in zip(('red', 'blue'), drafts):
        for k in d.get(colour, []):
            cx, cy, w, h, _ = best(folder, paths[k])
            boxes.setdefault(paths[k], []).append([round(v, 5) for v in (cx, cy, w, h)])
    for k, rows in d.get('boxes', {}).items():
        boxes.setdefault(paths[int(k)], []).extend(rows)
    for k, rows in d.get('corners10', {}).items():
        for x1, y1, x2, y2 in rows:
            boxes.setdefault(paths[int(k)], []).append(
                [round(v, 5) for v in ((x1 + x2) / 20, (y1 + y2) / 20, (x2 - x1) / 10, (y2 - y1) / 10)])
    for k in d.get('no_drain', []):
        no_drain.append(paths[k])
    decided = set(boxes) | set(no_drain) | {paths[k] for k in d.get('drop', [])}
    missing = [k for k, p in enumerate(paths) if p not in decided]
    if missing:
        print('no decision for', missing)
    json.dump({'boxes': boxes, 'no_drain': no_drain}, open(f'{H}/drain_review.json', 'w'), indent=1)
    print(len(boxes), 'photos with open drains,', len(no_drain), 'without,',
          len(d.get('drop', [])), 'left out')


if __name__ == '__main__':
    if sys.argv[1] == 'sheets':
        sheets(sys.argv[2].split(','), sys.argv[3])
    else:
        apply(sys.argv[2])
