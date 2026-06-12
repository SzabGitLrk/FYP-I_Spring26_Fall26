import cv2
import mediapipe as mp
import numpy as np
import json
import os

# 1. Setup the Paths
JSON_PATH = os.path.join('datasets', 'WLASL', 'WLASL_v0.3.json')
VIDEO_DIR = os.path.join('datasets', 'WLASL', 'videos')
OUTPUT_DIR = os.path.join('extracted_data', 'WLASL')

# Create the output folder if it doesn't exist
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 2. Initialize MediaPipe Holistic
mp_holistic = mp.solutions.holistic

# 3. Helper Function to Extract and Flatten Coordinates
def extract_keypoints(results):
    # Pose: 33 landmarks * 4 values (x,y,z,visibility) = 132 values
    pose = np.array([[res.x, res.y, res.z, res.visibility] for res in results.pose_landmarks.landmark]).flatten() if results.pose_landmarks else np.zeros(33*4)
    # Left Hand: 21 landmarks * 3 values (x,y,z) = 63 values
    lh = np.array([[res.x, res.y, res.z] for res in results.left_hand_landmarks.landmark]).flatten() if results.left_hand_landmarks else np.zeros(21*3)
    # Right Hand: 21 landmarks * 3 values (x,y,z) = 63 values
    rh = np.array([[res.x, res.y, res.z] for res in results.right_hand_landmarks.landmark]).flatten() if results.right_hand_landmarks else np.zeros(21*3)
    
    # Combine all into one massive 1D array per frame (258 total values)
    return np.concatenate([pose, lh, rh])

# 4. Load the WLASL JSON Data
print("Loading WLASL JSON file...")
with open(JSON_PATH, 'r') as f:
    WLASL_DATA = json.load(f)

print("Starting Feature Extraction (Test Batch of 3 Words)...\n")

# 5. The Extraction Loop
TEST_LIMIT = 3
words_processed = 0

with mp_holistic.Holistic(min_detection_confidence=0.5, min_tracking_confidence=0.5) as holistic:
    for entry in WLASL_DATA:
        if words_processed >= TEST_LIMIT:
            break
            
        word = entry['gloss']
        print(f"--- Processing Word: {word.upper()} ---")
        
        # Create a specific folder for this word
        word_dir = os.path.join(OUTPUT_DIR, word)
        os.makedirs(word_dir, exist_ok=True)
        
        for instance in entry['instances']:
            video_id = instance['video_id']
            video_path = os.path.join(VIDEO_DIR, f"{video_id}.mp4")
            
            # Check if you actually downloaded this specific video
            if not os.path.exists(video_path):
                print(f"Skipping {video_id}.mp4 (File not found in videos folder)")
                continue
                
            print(f"Extracting frames from video: {video_id}.mp4")
            cap = cv2.VideoCapture(video_path)
            video_sequence_data = []
            
            while cap.isOpened():
                success, frame = cap.read()
                if not success:
                    break # Reached the end of the video
                
                # Convert color and process the frame with MediaPipe
                image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                results = holistic.process(image)
                
                # Extract the math coordinates and save to our sequence list
                keypoints = extract_keypoints(results)
                video_sequence_data.append(keypoints)
                
            cap.release()
            
            # 6. Save the math array to your hard drive
            if len(video_sequence_data) > 0:
                npy_path = os.path.join(word_dir, str(video_id))
                np.save(npy_path, video_sequence_data)
                
        words_processed += 1

print("\n✅ Test Extraction Complete!")
print(f"Check the '{OUTPUT_DIR}' folder to see your AI data!")