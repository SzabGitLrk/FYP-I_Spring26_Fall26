#!/usr/bin/env python3
"""Build the open-vocabulary helper model (YOLO-World) for the app.

Step 1 (needs the CLIP text encoder; run from the app folder so
weights/clip/ViT-B-32.pt is found):
    python export_world.py prompts --weights yolov8s-worldv2.pt --prompts prompts_v2.json --out D:/dev/eyris_work/world

Step 2 (needs onnx2tf + tensorflow):
    python export_world.py tflite --out D:/dev/eyris_work/world --imgsz 320

The prompts are baked into the model, one output class per prompt, in the
order of the prompts file. labels_world.txt lists them in that order.
"""
import argparse
import json
import os
import shutil
import sys

import numpy as np


def prompts_step(args):
    from ultralytics import YOLO
    prompts = list(json.load(open(args.prompts)))
    model = YOLO(args.weights)
    model.set_classes(prompts)
    os.makedirs(args.out, exist_ok=True)
    model.save(os.path.join(args.out, 'eyris_world.pt'))
    with open(os.path.join(args.out, 'labels_world.txt'), 'w') as handle:
        handle.write('\n'.join(prompts) + '\n')
    print(len(prompts), 'prompts saved')


def tflite_step(args):
    import onnx2tf
    import torch
    from PIL import Image
    from ultralytics import YOLO

    size = args.imgsz
    weights = os.path.join(args.out, 'eyris_world.pt')
    labels = [l.strip() for l in open(os.path.join(args.out, 'labels_world.txt')) if l.strip()]
    model = YOLO(weights)
    assert [model.names[i] for i in range(len(model.names))] == labels

    photos = sorted(os.listdir(args.photos))[::max(1, len(os.listdir(args.photos)) // 20)][:20]
    sample = 'calibration_image_sample_data_20x128x128x3_float32.npy'
    if not os.path.exists(sample):
        np.save(sample, np.stack([
            np.asarray(Image.open(os.path.join(args.photos, n)).convert('RGB').resize((128, 128)),
                       dtype=np.float32) / 255 for n in photos]))

    onnx_path = model.export(format='onnx', imgsz=size, simplify=True)
    saved = os.path.join(args.out, 'saved_model')
    onnx2tf.convert(input_onnx_file_path=onnx_path, output_folder_path=saved,
                    not_use_onnxsim=True, verbosity='error',
                    output_signaturedefs=True, enable_batchmatmul_unfold=True)
    stem = os.path.splitext(os.path.basename(onnx_path))[0]
    tflite = os.path.join(args.out, 'eyris_world.tflite')
    shutil.copy(os.path.join(saved, f'{stem}_float32.tflite'), tflite)

    from ai_edge_litert.interpreter import Interpreter
    interpreter = Interpreter(model_path=tflite, num_threads=4)
    interpreter.allocate_tensors()
    i, o = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    print('tflite input', i['shape'], 'output', o['shape'], f'{os.path.getsize(tflite) / 1e6:.1f} MB')
    assert list(i['shape']) == [1, size, size, 3], i['shape']
    assert o['shape'][1] == 4 + len(labels), o['shape']

    network = YOLO(weights).model.float().eval()
    worst_score = worst_box = 0.0
    for name in photos:
        image = Image.open(os.path.join(args.photos, name)).convert('RGB').resize((size, size))
        x = np.asarray(image, dtype=np.float32) / 255
        interpreter.set_tensor(i['index'], x[None])
        interpreter.invoke()
        converted = interpreter.get_tensor(o['index'])[0].copy()
        if np.abs(converted[:4]).max() <= 1.5:
            converted[:4] *= size
        with torch.no_grad():
            original = network(torch.from_numpy(x).permute(2, 0, 1)[None])
        original = (original[0] if isinstance(original, (list, tuple)) else original)[0].numpy()
        confident = original[4:].max(axis=0) >= 0.05
        worst_score = max(worst_score, float(np.abs(converted[4:] - original[4:]).max()))
        if confident.any():
            worst_box = max(worst_box, float(np.abs(converted[:4, confident] - original[:4, confident]).max()))
    print(f'compared {len(photos)} photos with PyTorch: largest score difference '
          f'{worst_score:.4f}, largest box difference {worst_box:.2f} px')
    assert worst_score < 0.02 and worst_box < 2.0, 'converted model differs from PyTorch'


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('step', choices=['prompts', 'tflite'])
    parser.add_argument('--weights')
    parser.add_argument('--prompts')
    parser.add_argument('--out', required=True)
    parser.add_argument('--imgsz', type=int, default=320)
    parser.add_argument('--photos', default=r'D:\dev\eyris_work\ade\val\images')
    args = parser.parse_args()
    (prompts_step if args.step == 'prompts' else tflite_step)(args)


if __name__ == '__main__':
    sys.exit(main())
