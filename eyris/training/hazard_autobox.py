#!/usr/bin/env python3
"""First-draft boxes for web photos of one hazard class, to be checked by eye.

    python hazard_autobox.py ac  D:/dev/eyris_work/hazard/web_ac  D:/dev/eyris_work/hazard/draft_ac
    python hazard_autobox.py drain <images> <out>
    python hazard_autobox.py yolo <weights.pt> <class id> <images> <out>

"ac" and "drain" use YOLO-World (run from the app folder so
weights/clip/ViT-B-32.pt is found) with the class prompts competing against
look-alikes (fridge, door, cabinet... / manhole cover, grate, puddle...).
"yolo" uses a model trained on the labelled sets to draft boxes for the web
photos of the same class. Each image gets a YOLO txt with a sixth column,
the confidence; the review step keeps, fixes or drops them.
"""
import os
import sys

AC_PROMPTS = ['floor standing air conditioner', 'air conditioner', 'portable air conditioner',
              'tower air conditioner']
LOOK_ALIKES = ['refrigerator', 'door', 'window', 'wardrobe', 'cabinet', 'person', 'sofa',
               'air cooler', 'water dispenser', 'television', 'table', 'chair', 'bed', 'curtain',
               'pillar', 'loudspeaker', 'washing machine', 'heater']
DRAIN_PROMPTS = ['open manhole', 'uncovered manhole', 'open drain', 'hole in the ground',
                 'open sewer']
DRAIN_LOOK_ALIKES = ['manhole cover', 'drain grate', 'puddle', 'shadow', 'person', 'car',
                     'motorcycle', 'brick', 'door', 'wall']


def write(out, name, rows):
    with open(os.path.join(out, os.path.splitext(name)[0] + '.txt'), 'w') as f:
        for c, cx, cy, w, h, s in rows:
            f.write(f'{c} {cx:.5f} {cy:.5f} {w:.5f} {h:.5f} {s:.3f}\n')


def run(model, images, out, keep, conf):
    os.makedirs(out, exist_ok=True)
    names = sorted(n for n in os.listdir(images) if n.lower().endswith('.jpg'))
    for k in range(0, len(names), 16):
        batch = [os.path.join(images, n) for n in names[k:k + 16]]
        for name, r in zip(names[k:k + 16], model.predict(batch, conf=conf, imgsz=640,
                                                            verbose=False, iou=0.5,
                                                            agnostic_nms=True)):
            rows = []
            for c, s, b in zip(r.boxes.cls.tolist(), r.boxes.conf.tolist(), r.boxes.xywhn.tolist()):
                if int(c) in keep:
                    rows.append((0, *b, s))
            write(out, name, rows)
    print(len(names), 'photos drafted into', out)


def main():
    from ultralytics import YOLO
    if sys.argv[1] == 'ac':
        model = YOLO('yolov8s-worldv2.pt')
        model.set_classes(AC_PROMPTS + LOOK_ALIKES)
        run(model, sys.argv[2], sys.argv[3], set(range(len(AC_PROMPTS))), 0.08)
    elif sys.argv[1] == 'drain':
        model = YOLO('yolov8s-worldv2.pt')
        model.set_classes(DRAIN_PROMPTS + DRAIN_LOOK_ALIKES)
        run(model, sys.argv[2], sys.argv[3], set(range(len(DRAIN_PROMPTS))), 0.05)
    else:
        weights, cls, images, out = sys.argv[2:6]
        run(YOLO(weights), images, out, {int(cls)}, 0.15)


if __name__ == '__main__':
    main()
