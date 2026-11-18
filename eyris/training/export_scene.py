#!/usr/bin/env python3
"""Convert the trained scene model to the TFLite file the app loads, check it
against PyTorch, and save one real output as a fixture for the app's tests.

    python export_scene.py --weights runs/scene_b/weights/best.pt --out D:/dev/eyris_work/scene_export

PyTorch -> ONNX -> TFLite (float32, input [1, 384, 384, 3], raw output
[1, 4 + classes, 3024]). Needs ultralytics, onnx, onnxslim, onnx2tf,
tensorflow, tf_keras, ai-edge-litert.
"""
import argparse
import json
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image

SIZE = 384
THRESHOLD = 0.30


def half_up(value):
    """Round like Dart's num.round()."""
    return int(math.floor(value + 0.5))


def letterbox(image):
    scale = min(SIZE / image.width, SIZE / image.height)
    width, height = max(1, half_up(image.width * scale)), max(1, half_up(image.height * scale))
    pad_x, pad_y = (SIZE - width) // 2, (SIZE - height) // 2
    canvas = np.full((SIZE, SIZE, 3), 114 / 255, dtype=np.float32)
    canvas[pad_y:pad_y + height, pad_x:pad_x + width] = np.asarray(
        image.resize((width, height), Image.BILINEAR), dtype=np.float32) / 255
    return canvas, scale, pad_x, pad_y


def reference_detections(output, labels, scale, pad_x, pad_y, width, height):
    """The app's rules (decodeRawYolo + labelDetections) in numpy, every class
    reported under its own name at one threshold."""
    scores = output[4:]
    class_ids, best = scores.argmax(axis=0), scores.max(axis=0)
    found = []
    for index in np.where(best >= THRESHOLD)[0]:
        cx, cy, w, h = (float(v) for v in output[:4, index])
        x1 = min(max((cx - w / 2 - pad_x) / scale, 0), width)
        y1 = min(max((cy - h / 2 - pad_y) / scale, 0), height)
        x2 = min(max((cx + w / 2 - pad_x) / scale, 0), width)
        y2 = min(max((cy + h / 2 - pad_y) / scale, 0), height)
        if x2 - x1 <= 2 or y2 - y1 <= 2:
            continue
        found.append((float(best[index]), labels[class_ids[index]], (x1, y1, x2, y2)))
    found.sort(key=lambda item: -item[0])
    kept, per_label = [], {}
    for confidence, label, box in found:
        def overlap(other):
            w = min(box[2], other[2]) - max(box[0], other[0])
            h = min(box[3], other[3]) - max(box[1], other[1])
            if w <= 0 or h <= 0:
                return 0.0
            return w * h / ((box[2] - box[0]) * (box[3] - box[1])
                            + (other[2] - other[0]) * (other[3] - other[1]) - w * h)
        if per_label.get(label, 0) >= 3:
            continue
        if any(label == l and overlap(b) > 0.5 for _, l, b in kept):
            continue
        kept.append((confidence, label, box))
        per_label[label] = per_label.get(label, 0) + 1
    return kept


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--weights', required=True)
    parser.add_argument('--photos', default=r'D:\dev\eyris_work\scene\test.txt')
    parser.add_argument('--out', required=True)
    parser.add_argument('--fixture', help='folder for the app test fixture')
    parser.add_argument('--check', type=int, default=30)
    parser.add_argument('--size', type=int, default=384, help='square model input in pixels')
    parser.add_argument('--name', default='scene', help='files are named eyris_<name>.tflite / labels_<name>.txt')
    args = parser.parse_args()
    global SIZE
    SIZE = args.size

    import torch
    from ultralytics import YOLO

    os.makedirs(args.out, exist_ok=True)
    model = YOLO(args.weights)
    labels = [model.names[i] for i in range(len(model.names))]
    photos = [l.strip() for l in open(args.photos) if l.strip()]

    sample = 'calibration_image_sample_data_20x128x128x3_float32.npy'
    if not os.path.exists(sample):
        np.save(sample, np.stack([
            np.asarray(Image.open(p).convert('RGB').resize((128, 128)), dtype=np.float32) / 255
            for p in photos[::max(1, len(photos) // 20)][:20]]))

    import onnx2tf
    onnx_path = model.export(format='onnx', imgsz=SIZE, simplify=True)
    saved = os.path.join(args.out, 'saved_model')
    onnx2tf.convert(input_onnx_file_path=onnx_path, output_folder_path=saved,
                    not_use_onnxsim=True, verbosity='error',
                    output_signaturedefs=True, enable_batchmatmul_unfold=True)
    stem = os.path.splitext(os.path.basename(onnx_path))[0]
    tflite = os.path.join(args.out, f'eyris_{args.name}.tflite')
    shutil.copy(os.path.join(saved, f'{stem}_float32.tflite'), tflite)
    with open(os.path.join(args.out, f'labels_{args.name}.txt'), 'w') as handle:
        handle.write('\n'.join(labels) + '\n')

    from ai_edge_litert.interpreter import Interpreter
    interpreter = Interpreter(model_path=tflite, num_threads=4)
    interpreter.allocate_tensors()
    i, o = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    print('tflite input', i['shape'], 'output', o['shape'], f'{os.path.getsize(tflite) / 1e6:.1f} MB')
    assert list(i['shape']) == [1, SIZE, SIZE, 3]
    assert o['shape'][1] == 4 + len(labels), o['shape']

    network = YOLO(args.weights).model.float().eval()
    worst_score = worst_box = 0.0
    same = total = 0
    fixture = None
    for path in photos[::max(1, len(photos) // args.check)][:args.check]:
        image = Image.open(path).convert('RGB')
        canvas, scale, pad_x, pad_y = letterbox(image)
        interpreter.set_tensor(i['index'], canvas[None])
        interpreter.invoke()
        raw = interpreter.get_tensor(o['index'])[0]
        converted = raw.copy()
        if np.abs(converted[:4]).max() <= 1.5:
            converted[:4] *= SIZE
        with torch.no_grad():
            original = network(torch.from_numpy(canvas).permute(2, 0, 1)[None])
        original = (original[0] if isinstance(original, (list, tuple)) else original)[0].numpy()
        confident = original[4:].max(axis=0) >= 0.05
        worst_score = max(worst_score, float(np.abs(converted[4:] - original[4:]).max()))
        if confident.any():
            worst_box = max(worst_box, float(np.abs(
                converted[:4, confident] - original[:4, confident]).max()))
        a = reference_detections(converted, labels, scale, pad_x, pad_y, image.width, image.height)
        b = reference_detections(original, labels, scale, pad_x, pad_y, image.width, image.height)
        total += 1
        same += [l for _, l, _ in a] == [l for _, l, _ in b]
        if fixture is None or len({l for _, l, _ in a}) > len({l for _, l, _ in fixture[1]}):
            fixture = (os.path.basename(path), a, raw.copy(), image.size)

    print(f'compared {total} photos with PyTorch: largest score difference {worst_score:.4f}, '
          f'largest box difference {worst_box:.2f} px, identical detections on {same}/{total}')
    assert worst_score < 0.02 and worst_box < 2.0, 'converted model differs from PyTorch'

    if args.fixture and fixture:
        name, detections, output, (width, height) = fixture
        os.makedirs(args.fixture, exist_ok=True)
        output.astype('<f4').tofile(os.path.join(args.fixture, f'{args.name}_model_output.f32'))
        with open(os.path.join(args.fixture, f'{args.name}_model_output.json'), 'w') as handle:
            json.dump({
                'photo': name, 'shape': [1, *output.shape], 'inputSize': SIZE,
                'sourceWidth': width, 'sourceHeight': height, 'labels': labels,
                'threshold': THRESHOLD,
                'expected': [{'label': label, 'confidence': round(confidence, 6),
                              'box': [round(v, 3) for v in box]}
                             for confidence, label, box in detections],
            }, handle, indent=1)
        print(f'fixture: {name}, {len(detections)} detections:',
              ', '.join(f'{label} {confidence:.2f}' for confidence, label, _ in detections))


if __name__ == '__main__':
    sys.exit(main())
