"""
BridgeSign AI — Sign-to-Text Server (HTTP POST)

Receives webcam frames from the frontend via HTTP POST,
runs MediaPipe hand tracking + ML model (via real_time_translator.py),
and returns predictions as JSON.

HOW TO START:
  cd backend
  pip install flask opencv-python numpy
  python server.py

  Then open http://localhost:8000 in your browser,
  switch to Sign -> Text mode, and click Record.
"""

import base64, sys, os, json

# Make fyp_env/ importable (contains real_time_translator.py + model)
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'fyp_env'))

from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import numpy as np
from real_time_translator import predict_frame

app = Flask(__name__)
CORS(app)

@app.route('/predict', methods=['POST'])
def predict():
    """
    POST /predict  { "frame": "data:image/jpeg;base64,..." }
    Returns        { "text": "A", "confidence": 0.95, "alternatives": [...] }
    """
    try:
        data = request.get_json(force=True)
        raw = data.get('frame', '')
        if not raw:
            return jsonify({'text': 'NO_FRAME', 'confidence': 0.0, 'alternatives': []})

        # Decode base64 -> numpy (OpenCV BGR)
        header, encoded = raw.split(',', 1)
        img_bytes = base64.b64decode(encoded)
        np_arr = np.frombuffer(img_bytes, dtype=np.uint8)
        frame_bgr = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if frame_bgr is None:
            return jsonify({'text': 'BAD_FRAME', 'confidence': 0.0, 'alternatives': []})

        text, confidence, alternatives = predict_frame(frame_bgr)

        return jsonify({
            'text': text,
            'confidence': confidence,
            'alternatives': alternatives,
        })

    except Exception as e:
        print(f'[Server] Predict error: {e}', flush=True)
        import traceback
        traceback.print_exc()
        return jsonify({'text': 'ERROR', 'confidence': 0.0, 'alternatives': []})


@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'})


if __name__ == '__main__':
    print('=' * 55, flush=True)
    print('  BridgeSign AI - Sign-to-Text Server (HTTP)', flush=True)
    print('  Endpoint : http://localhost:5002/predict', flush=True)
    print('  Model    : fyp_env/alphabet_classifier.pkl', flush=True)
    print('  Ctrl+C to stop', flush=True)
    print('=' * 55, flush=True)
    app.run(host='0.0.0.0', port=5002, debug=False)