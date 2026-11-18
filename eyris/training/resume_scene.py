#!/usr/bin/env python3
"""Continue a scene training run that was stopped early, from its last.pt.

    python resume_scene.py D:/dev/eyris_work/runs/scene_c/weights/last.pt

The run keeps its own settings (epochs, learning-rate schedule, folder).
"""
import sys


def main():
    from ultralytics import YOLO
    YOLO(sys.argv[1]).train(resume=True)


if __name__ == '__main__':   # required on Windows: data loading uses subprocesses
    sys.exit(main())
