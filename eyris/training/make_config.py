#!/usr/bin/env python3
"""Write app_models.json: for each model the app ships, which of its classes
map to which spoken label. "names_wide" lists everything a model could
report (used to compare models); "names", "thresholds" and "backed" are what
the app actually uses and are filled in by tune_precision.py --write.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LABEL = {
    'person': 'Person', 'car': 'Car', 'motorcycle': 'Bike', 'bicycle': 'Bike',
    'truck': 'Truck', 'bus': 'Bus', 'tree': 'Tree', 'pole': 'Pole',
    'traffic sign': 'Traffic sign', 'traffic light': 'Traffic sign', 'chair': 'Chair',
    'table': 'Table', 'door': 'Door', 'stairs': 'Stairs', 'wall': 'Wall', 'bed': 'Bed',
    'sofa': 'Sofa', 'bottle': 'Bottle', 'dustbin': 'Dustbin', 'bag': 'Backpack',
    'laptop': 'Laptop', 'speed breaker': 'Speed breaker', 'footpath': 'Footpath',
    'standing ac': 'AC', 'air conditioner': 'AC', 'fan': 'Fan',
}
LABELS = ['Person', 'Car', 'Bike', 'Truck', 'Bus', 'Pothole', 'Tree', 'Pole', 'Traffic sign',
          'Chair', 'Table', 'Door', 'Stairs', 'Wall', 'Bed', 'Sofa', 'Bottle', 'Dustbin',
          'Backpack', 'Laptop', 'Speed breaker', 'Footpath', 'AC', 'Fan']

prompts = json.load(open(os.path.join(HERE, 'prompts_v2.json')))
# The footpath prompts are left out: the scene model reports footpaths, and
# these prompts out-score "road hump" on every stretch of road.
world_wide = {p: LABEL[c] for p, c in prompts.items()
              if c in LABEL and c != 'footpath'}

from build_scene_dataset import CLASSES  # noqa: E402
scene_wide = {c: LABEL[c] for c in CLASSES if c in LABEL}

ROAD_CLASSES = [l.strip() for l in open(r'D:\dev\eyris_work\road_export\labels_road.txt') if l.strip()]

path = os.path.join(HERE, 'app_models.json')
old = json.load(open(path)) if os.path.exists(path) else {'models': []}
previous = {m['tag']: m for m in old['models']}


def model(tag, file, labels, wide, default):
    kept = previous.get(tag, {})
    return {'tag': tag, 'file': file, 'labels': labels, 'names_wide': wide,
            'listed_only': tag == 'world',
            'solo': ['Speed breaker'] if tag == 'world' else [],
            'names': kept.get('names', wide), 'thresholds': kept.get('thresholds', {}),
            'backed': kept.get('backed', {}), 'default': kept.get('default', default)}


config = {'labels': LABELS, 'models': [
    model('scene', 'eyris_scene.tflite', 'labels_scene.txt', scene_wide, 0.35),
    model('world', 'eyris_world.tflite', 'labels_world.txt', world_wide, 0.35),
    model('road', 'eyris_road.tflite', 'labels_road.txt',
          {**{c: LABEL[c] for c in ROAD_CLASSES if c in LABEL}, 'pothole': 'Pothole'}, 0.35),
]}
json.dump(config, open(path, 'w'), indent=1)
print('wrote', path)
