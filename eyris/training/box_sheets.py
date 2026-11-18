#!/usr/bin/env python3
"""Sheets for drawing boxes by eye: four photos per sheet, each with a grid
every tenth of its width and height (labelled 0..10), so a box can be read
off as x1 y1 x2 y2 in tenths. A draft box (sixth column = confidence) found
in <drafts> is drawn in red.

    python box_sheets.py <list file> <out prefix> [drafts dir]

The list file holds one image path per line; sheet k shows photos 4k..4k+3,
numbered by their line in the list.
"""
import os
import sys

from PIL import Image, ImageDraw

CELL = 460
PAD = 18


def main():
    paths = [l.strip() for l in open(sys.argv[1], encoding='utf-8-sig') if l.strip()]
    prefix = sys.argv[2]
    drafts = sys.argv[3] if len(sys.argv) > 3 else None
    for start in range(0, len(paths), 4):
        sheet = Image.new('RGB', (2 * (CELL + 2 * PAD), 2 * (CELL + 2 * PAD)), (30, 30, 30))
        draw = ImageDraw.Draw(sheet)
        for k, path in enumerate(paths[start:start + 4]):
            im = Image.open(path).convert('RGB')
            scale = min(CELL / im.width, CELL / im.height)
            w, h = int(im.width * scale), int(im.height * scale)
            x0 = (k % 2) * (CELL + 2 * PAD) + PAD
            y0 = (k // 2) * (CELL + 2 * PAD) + PAD
            sheet.paste(im.resize((w, h)), (x0, y0))
            for t in range(11):
                gx, gy = x0 + w * t / 10, y0 + h * t / 10
                colour = (0, 255, 255) if t % 5 == 0 else (255, 255, 0)
                draw.line((gx, y0, gx, y0 + h), fill=colour, width=1)
                draw.line((x0, gy, x0 + w, gy), fill=colour, width=1)
                draw.text((gx - 3, y0 - 14), str(t), fill=(255, 255, 255))
                draw.text((x0 - 14, gy - 5), str(t), fill=(255, 255, 255))
            if drafts:
                lab = os.path.join(drafts, os.path.splitext(os.path.basename(path))[0] + '.txt')
                if os.path.exists(lab):
                    rows = [list(map(float, l.split()[1:6])) for l in open(lab) if l.strip()]
                    rows = [r for r in rows if r[4] >= 0.10]
                    if rows:
                        cx, cy, bw, bh, s = max(rows, key=lambda r: r[4])
                        draw.rectangle((x0 + (cx - bw / 2) * w, y0 + (cy - bh / 2) * h,
                                        x0 + (cx + bw / 2) * w, y0 + (cy + bh / 2) * h),
                                       outline=(255, 0, 0), width=3)
                        draw.text((x0 + (cx - bw / 2) * w + 3, y0 + (cy - bh / 2) * h + 2),
                                  f'{s:.2f}', fill=(255, 0, 0))
            draw.rectangle((x0 + w - 40, y0 + h - 16, x0 + w, y0 + h), fill=(0, 0, 0))
            draw.text((x0 + w - 36, y0 + h - 15), f'#{start + k}', fill=(255, 255, 255))
        sheet.save(f'{prefix}_{start // 4:02d}.jpg', quality=90)
    print(len(paths), 'photos on', (len(paths) + 3) // 4, 'sheets')


if __name__ == '__main__':
    main()
