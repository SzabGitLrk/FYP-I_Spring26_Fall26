#!/usr/bin/env python3
"""Frames from the client's videos, for training and for checking by eye.

    python video_frames.py <video> <out dir> <every n-th frame> [sheet.jpg]

Writes <out dir>/<video stem>_<frame>.jpg and, with a sheet path, a numbered
contact sheet of the frames written.
"""
import os
import sys

import cv2


def main():
    video, out, step = sys.argv[1], sys.argv[2], int(sys.argv[3])
    sheet = sys.argv[4] if len(sys.argv) > 4 else None
    os.makedirs(out, exist_ok=True)
    stem = os.path.splitext(os.path.basename(video))[0].replace(' ', '_').replace('.', '-')
    cap = cv2.VideoCapture(video)
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    written, i = [], 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if i % step == 0:
            path = os.path.join(out, f'{stem}_{i:04d}.jpg')
            cv2.imwrite(path, frame, [cv2.IMWRITE_JPEG_QUALITY, 92])
            written.append(path)
        i += 1
    h, w = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)), int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    print(f'{os.path.basename(video)}: {i} frames ({n} listed), {fps:.1f} fps, {w}x{h}, wrote {len(written)}')
    if sheet and written:
        sys.argv = ['contact_sheet.py', sheet, '6', '200', *written]
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import contact_sheet
        contact_sheet.main()


if __name__ == '__main__':
    main()
