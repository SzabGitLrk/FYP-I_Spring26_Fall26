#!/usr/bin/env python3
"""Draft open-drain boxes on frames of the client's videos.

    python client_drafts.py <weights.pt> <out dir> <every n-th frame> <video> [<video> ...]

Writes <out dir>/images/<video>_<frame>.jpg and <out dir>/drafts/<same>.txt
(YOLO rows with a sixth column, the confidence; only the open drain class).
The client films the phone running EYRIS, so a frame shows the camera
preview on the phone's screen and, around it, the real scene.
"""
import os
import sys

import cv2


def main():
    weights, out, step = sys.argv[1], sys.argv[2], int(sys.argv[3])
    from ultralytics import YOLO
    model = YOLO(weights)
    drain = [k for k, v in model.names.items() if v == 'open drain'][0]
    os.makedirs(f'{out}/images', exist_ok=True)
    os.makedirs(f'{out}/drafts', exist_ok=True)
    for video in sys.argv[4:]:
        stem = os.path.splitext(os.path.basename(video))[0][-11:].replace(' ', '').replace('.', '')
        cap = cv2.VideoCapture(video)
        i = kept = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if i % step == 0:
                name = f'v{stem}_{i:04d}'
                cv2.imwrite(f'{out}/images/{name}.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 92])
                r = model.predict(frame, imgsz=640, conf=0.05, verbose=False)[0]
                rows = [(*b, s) for c, s, b in zip(r.boxes.cls.tolist(), r.boxes.conf.tolist(),
                                                    r.boxes.xywhn.tolist()) if int(c) == drain]
                with open(f'{out}/drafts/{name}.txt', 'w') as f:
                    for cx, cy, w, h, s in rows:
                        f.write(f'3 {cx:.5f} {cy:.5f} {w:.5f} {h:.5f} {s:.3f}\n')
                kept += any(s >= 0.25 for *_, s in rows)
            i += 1
        print(f'{os.path.basename(video)}: {i} frames, drafted every {step}th, '
              f'{kept} with a box >= 0.25')


if __name__ == '__main__':
    main()
