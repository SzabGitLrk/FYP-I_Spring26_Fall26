#!/usr/bin/env python3
"""Camera frames out of a screen recording of the EYRIS camera screen.

    python screen_frames.py <video> <out dir> <every n-th frame> <x1> <y1> <x2> <y2>

The client recorded the app's screen while it ran on the ESP32 camera
(249.mp4, 2026-10-15, indoors). The camera preview sits at a fixed place on
the screen; (x1, y1, x2, y2) is that place in video pixels. The frames are
used as photos without any hazard: they are the ESP32's view of rooms,
where the old hazard model saw a speed breaker in a laptop keyboard.
"""
import os
import sys

import cv2


def main():
    video, out, step = sys.argv[1], sys.argv[2], int(sys.argv[3])
    x1, y1, x2, y2 = map(int, sys.argv[4:8])
    os.makedirs(out, exist_ok=True)
    stem = os.path.splitext(os.path.basename(video))[0]
    cap = cv2.VideoCapture(video)
    i = written = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if i % step == 0:
            cv2.imwrite(os.path.join(out, f's{stem}_{i:05d}.jpg'), frame[y1:y2, x1:x2],
                        [cv2.IMWRITE_JPEG_QUALITY, 92])
            written += 1
        i += 1
    print(f'{video}: {i} frames, wrote {written} crops to {out}')


if __name__ == '__main__':
    main()
