#!/usr/bin/env python3
"""Train the EYRIS scene model (YOLOv8s) on the set made by build_scene_dataset.py.

    python train_scene.py --data D:/dev/eyris_work/scene --name scene_a --epochs 60

Starts from Ultralytics' Open Images weights, which already know doors,
stairs and furniture, and trains at 416 px (the app runs it at 384 px).
"""
import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--data', required=True)
    parser.add_argument('--init', default=r'D:\dev\eyris_work\training\yolov8s-oiv7.pt')
    parser.add_argument('--epochs', type=int, default=60)
    parser.add_argument('--batch', type=int, default=32)
    parser.add_argument('--imgsz', type=int, default=416)
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--project', default=r'D:\dev\eyris_work\runs')
    parser.add_argument('--name', default='scene')
    parser.add_argument('--cache', action='store_true', help='keep decoded photos in RAM')
    args = parser.parse_args()

    from ultralytics import YOLO
    YOLO(args.init).train(
        data=os.path.join(args.data, 'data.yaml'), imgsz=args.imgsz,
        epochs=args.epochs, batch=args.batch, workers=args.workers,
        patience=20, cache=args.cache, optimizer='AdamW', lr0=0.001, cos_lr=True,
        warmup_epochs=2, close_mosaic=8, plots=False,
        project=args.project, name=args.name, exist_ok=True)


if __name__ == '__main__':   # required on Windows: data loading uses subprocesses
    sys.exit(main())
