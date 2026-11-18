#!/usr/bin/env python3
"""Contact sheets for checking photos and boxes by eye.

    python contact_sheet.py [--labels <dir>] <out.jpg> <cols> <cell px> <image> [<image> ...]

For each image a YOLO label file is looked for in <dir>, or next to it
(images/x.jpg -> labels/x.txt or labels/txt/x.txt, or x.txt beside it);
its boxes are drawn in red with the class id, or with the confidence when
the file has a sixth column (drafts). Each cell is numbered so a photo can
be named back from the sheet. A single argument ending in .lst is read as a
list of images, one per line.
"""
import os
import sys

from PIL import Image, ImageDraw

LABELS = None


def label_file(path):
    stem = os.path.splitext(path)[0]
    folder, name = os.path.split(stem)
    parent = os.path.dirname(folder)
    for cand in ((os.path.join(LABELS, name + '.txt'),) if LABELS else ()) + (
                 os.path.join(parent, 'labels', name + '.txt'),
                 os.path.join(parent, 'labels', 'txt', name + '.txt'),
                 stem + '.txt'):
        if os.path.exists(cand):
            return cand
    return None


def main():
    global LABELS
    args = sys.argv[1:]
    if args[0] == '--labels':
        LABELS, args = args[1], args[2:]
    out, cols, cell = args[0], int(args[1]), int(args[2])
    paths = args[3:]
    if len(paths) == 1 and paths[0].endswith('.lst'):
        paths = [l.strip() for l in open(paths[0], encoding='utf-8-sig') if l.strip()]
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cell, rows * cell), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for k, path in enumerate(paths):
        im = Image.open(path).convert('RGB')
        scale = min(cell / im.width, cell / im.height)
        w, h = max(1, int(im.width * scale)), max(1, int(im.height * scale))
        x0, y0 = (k % cols) * cell + (cell - w) // 2, (k // cols) * cell + (cell - h) // 2
        sheet.paste(im.resize((w, h)), (x0, y0))
        lab = label_file(path)
        if lab:
            for line in open(lab):
                p = line.split()
                if len(p) < 5:
                    continue
                c, cx, cy, bw, bh = p[0], *map(float, p[1:5])
                box = (x0 + (cx - bw / 2) * w, y0 + (cy - bh / 2) * h,
                       x0 + (cx + bw / 2) * w, y0 + (cy + bh / 2) * h)
                draw.rectangle(box, outline=(255, 0, 0), width=2)
                draw.text((box[0] + 2, box[1] + 1), p[5][:4] if len(p) > 5 else c,
                          fill=(255, 255, 0))
        draw.rectangle((x0, y0, x0 + 22, y0 + 12), fill=(0, 0, 0))
        draw.text((x0 + 2, y0), str(k), fill=(255, 255, 255))
    sheet.save(out, quality=88)


if __name__ == '__main__':
    main()
