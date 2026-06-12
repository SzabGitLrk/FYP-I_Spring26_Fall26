import cv2
import numpy as np
import mediapipe as mp
from keras.models import Sequential
from keras.layers import LSTM, Dense, Dropout, Masking, BatchNormalization, Input

# 1. The exact 30-word dictionary
TARGET_WORDS = [
    'sick', 'owie', 'bad', 'better', 'sleep', 'awake', 
    'food', 'drink', 'hungry', 'bath', 'bed', 'room', 
    'callonphone', 'wait', 'stay', 'go', 'find', 'have',
    'please', 'thankyou', 'yes', 'no', 'listen', 'look', 
    'hear', 'time', 'night', 'yesterday', 'person', 'brother'
]

# 2. Build the empty brain (Bypasses the version clash!)
print("🧠 Building Empty AI Brain...")
model = Sequential([Input(shape=(60, 258))])
model.add(Masking(mask_value=0.0))

model.add(LSTM(128, return_sequences=True, activation='tanh'))
model.add(BatchNormalization())
model.add(Dropout(0.3))

model.add(LSTM(256, return_sequences=True, activation='tanh'))
model.add(BatchNormalization())
model.add(Dropout(0.3))

model.add(LSTM(128, return_sequences=False, activation='tanh'))
model.add(BatchNormalization())
model.add(Dropout(0.3))

model.add(Dense(128, activation='relu'))
model.add(Dense(len(TARGET_WORDS), activation='softmax'))

# 3. Inject the trained memories directly
print("💉 Injecting Trained Memories...")
model.load_weights('fyp_30_word_kaggle_model.keras')

# 4. Setup MediaPipe
mp_holistic = mp.solutions.holistic
mp_drawing = mp.solutions.drawing_utils

def extract_keypoints(results):
    if results.pose_landmarks:
        pose = np.array([[res.x, res.y, res.z, 1.0] for res in results.pose_landmarks.landmark]).flatten()
    else:
        pose = np.zeros(33 * 4)
        
    if results.left_hand_landmarks:
        lh = np.array([[res.x, res.y, res.z] for res in results.left_hand_landmarks.landmark]).flatten()
    else:
        lh = np.zeros(21 * 3)
        
    if results.right_hand_landmarks:
        rh = np.array([[res.x, res.y, res.z] for res in results.right_hand_landmarks.landmark]).flatten()
    else:
        rh = np.zeros(21 * 3)
        
    return np.concatenate([pose, lh, rh])

# 5. Start the Webcam
cap = cv2.VideoCapture(0)
sequence = []
current_word = "Waiting..."

print("🎥 Starting Webcam... Press 'q' to quit.")

with mp_holistic.Holistic(min_detection_confidence=0.5, min_tracking_confidence=0.5) as holistic:
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret: break

        frame = cv2.flip(frame, 1)
        image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image.flags.writeable = False
        results = holistic.process(image)
        image.flags.writeable = True
        image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)
        
       # Draw the Face, Shoulders, and Body (Pose)
        mp_drawing.draw_landmarks(image, results.pose_landmarks, mp_holistic.POSE_CONNECTIONS)
        
        # Draw the Hands
        mp_drawing.draw_landmarks(image, results.left_hand_landmarks, mp_holistic.HAND_CONNECTIONS)
        mp_drawing.draw_landmarks(image, results.right_hand_landmarks, mp_holistic.HAND_CONNECTIONS)
        
        keypoints = extract_keypoints(results)
        sequence.append(keypoints)
        sequence = sequence[-60:]
        

# If we have 60 frames, make a prediction
        if len(sequence) == 60:
            if results.left_hand_landmarks or results.right_hand_landmarks:
                res = model.predict(np.expand_dims(sequence, axis=0), verbose=0)[0]
                
                if res[np.argmax(res)] > 0.75:
                    current_word = TARGET_WORDS[np.argmax(res)]
                    # THE FIX: Flush the memory so it doesn't get stuck on one word!
                    sequence = [] 
            else:
                current_word = "Waiting..."
                sequence = [] # Flush memory when hands are down too
        
        cv2.rectangle(image, (0,0), (640, 60), (245, 117, 16), -1)
        cv2.putText(image, current_word.upper(), (15, 45), 
                    cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 255, 255), 2, cv2.LINE_AA)
        
        cv2.imshow('FYP Bidirectional AI Communicator', image)

        if cv2.waitKey(10) & 0xFF == ord('q'):
            break

cap.release()
cv2.destroyAllWindows()