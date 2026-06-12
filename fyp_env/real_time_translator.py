import cv2
import mediapipe as mp
import pandas as pd
import pickle
import socket
import warnings
import os

warnings.filterwarnings("ignore")

# ═════════════════════════════════════════════════════════════════════════
# REUSABLE FUNCTION — called by backend/server.py for WebSocket inference
# ═════════════════════════════════════════════════════════════════════════
_HANDS = None
_MODEL = None
_LANDMARK_COLS = [f'{axis}{i}' for i in range(21) for axis in ['x', 'y', 'z']]

def predict_frame(frame_bgr):
    """
    frame_bgr : numpy array (H, W, 3) in BGR order (OpenCV format)

    Returns  (text: str, confidence: float, alternatives: list[dict])
    """
    global _HANDS, _MODEL

    if _HANDS is None:
        mp_hands = mp.solutions.hands
        _HANDS = mp_hands.Hands(
            static_image_mode=False,
            max_num_hands=1,
            min_detection_confidence=0.7,
            min_tracking_confidence=0.5,
        )

    if _MODEL is None:
        model_path = os.path.join(os.path.dirname(__file__), 'alphabet_classifier.pkl')
        try:
            with open(model_path, 'rb') as f:
                _MODEL = pickle.load(f)
        except Exception as e:
            print(f"⚠️ Model not found at {model_path}: {e}")
            return ("NO_MODEL", 0.0, [])

    frame = cv2.flip(frame_bgr, 1)
    img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = _HANDS.process(img_rgb)

    if not results.multi_hand_landmarks:
        return ("NOTHING", 0.0, [])

    hand = results.multi_hand_landmarks[0]
    keypoints = []
    for lm in hand.landmark:
        keypoints.extend([lm.x, lm.y, lm.z])

    df = pd.DataFrame([keypoints], columns=_LANDMARK_COLS)
    prediction = _MODEL.predict(df)[0]

    try:
        proba = _MODEL.predict_proba(df)[0]
        confidence = float(max(proba))
        classes = _MODEL.classes_
        top3 = sorted(zip(classes, proba), key=lambda x: -x[1])[:3]
        alternatives = [{'word': str(c), 'confidence': float(p)} for c, p in top3]
    except Exception:
        confidence = 1.0
        alternatives = [{'word': str(prediction), 'confidence': 1.0}]

    return (str(prediction), confidence, alternatives)


# ═════════════════════════════════════════════════════════════════════════
# ORIGINAL SCRIPT — only runs when executed directly (not on import)
# ═════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':

    # ==========================================
    # 1. DUAL-PORT NETWORKING SETUP
    # ==========================================
    UDP_IP = "127.0.0.1"
    TEXT_PORT = 5052   # Channel for letters/words
    VIDEO_PORT = 5053  # Channel for webcam frames

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f"📡 Dual-Bridge Active: Text on {TEXT_PORT} | Video on {VIDEO_PORT}")

    # ==========================================
    # 2. LOAD AI MODEL & MEDIAPIPE
    # ==========================================
    try:
        with open('alphabet_classifier.pkl', 'rb') as f:
            model = pickle.load(f)
    except Exception as e:
        print(f"❌ Model missing: {e}"); exit()

    mp_hands = mp.solutions.hands
    mp_drawing = mp.solutions.drawing_utils
    hands = mp_hands.Hands(min_detection_confidence=0.7, min_tracking_confidence=0.5)

    # ==========================================
    # 3. HEADLESS CAPTURE LOOP
    # ==========================================
    cap = cv2.VideoCapture(0)
    previous_prediction = ""
    frames_locked = 0
    REQUIRED_FRAMES = 3

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret: break
        
        frame = cv2.flip(frame, 1)
        
        # --- AI MODEL PROCESSING ---
        img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = hands.process(img_rgb)
        current_prediction = "NOTHING"
        
        if results.multi_hand_landmarks:
            hand_landmarks = results.multi_hand_landmarks[0]
            mp_drawing.draw_landmarks(frame, hand_landmarks, mp_hands.HAND_CONNECTIONS)
                
            keypoints = []
            for lm in hand_landmarks.landmark:
                keypoints.extend([lm.x, lm.y, lm.z])
                    
            columns = [f'{axis}{i}' for i in range(21) for axis in ['x', 'y', 'z']]
            df = pd.DataFrame([keypoints], columns=columns)
            current_prediction = model.predict(df)[0]
        
        # --- SEND TRANSLATED TEXT ---
        if current_prediction == previous_prediction:
            frames_locked += 1
        else:
            frames_locked = 0
            previous_prediction = current_prediction
            
        if frames_locked >= REQUIRED_FRAMES:
            try: sock.sendto(str.encode(current_prediction), (UDP_IP, TEXT_PORT))
            except: pass
            frames_locked = 0

        # --- NEW: COMPRESS & STREAM WEBCAM FRAMES TO UNITY ---
        try:
            small_frame = cv2.resize(frame, (400, 300))
            _, encoded_img = cv2.imencode('.jpg', small_frame, [int(cv2.IMWRITE_JPEG_QUALITY), 40])
            sock.sendto(encoded_img.tobytes(), (UDP_IP, VIDEO_PORT))
        except Exception as e:
            pass

    cap.release()