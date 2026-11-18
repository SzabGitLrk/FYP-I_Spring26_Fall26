#!/usr/bin/env python3
"""Train the hazard model (pothole, speed breaker, standing AC).

    python train_hazard.py <run name> [epochs] [imgsz] [weights] [data loader workers]

Runs on the GPU environment (D:/dev/venv_gpu). The app feeds this model a
frame letterboxed to its input size, so training uses the same size. Keep
the data loader at 3 workers on the development PC: each worker loads its
own copy of torch (about 0.6 GB), and 8 of them ran its 16 GB out of memory.
"""
import sys

from ultralytics import YOLO

name = sys.argv[1]
epochs = int(sys.argv[2]) if len(sys.argv) > 2 else 60
imgsz = int(sys.argv[3]) if len(sys.argv) > 3 else 416
weights = sys.argv[4] if len(sys.argv) > 4 else 'D:/dev/eyris_work/training/yolov8s-oiv7.pt'
workers = int(sys.argv[5]) if len(sys.argv) > 5 else 3

if __name__ == '__main__':
    YOLO(weights).train(
        data='D:/dev/eyris_work/hazard/ds/data.yaml', epochs=epochs, imgsz=imgsz, batch=32,
        project='D:/dev/eyris_work/runs', name=name, exist_ok=True, workers=workers, patience=0,
        # Phone and ESP32 frames: colour casts, blur from motion, varied light.
        hsv_h=0.02, hsv_s=0.6, hsv_v=0.5, degrees=3, scale=0.5, translate=0.1,
        fliplr=0.5, mosaic=1.0, close_mosaic=10, cos_lr=True, plots=False)
