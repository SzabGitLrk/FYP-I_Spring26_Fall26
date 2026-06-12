import cv2
import mediapipe as mp
import numpy as np
import os
import pandas as pd

# 1. Setup Paths
# Pointing to your current folder structure
TRAIN_DIR = os.path.join('datasets', 'ASL_Alphabet', 'asl_alphabet_train')
OUTPUT_DIR = os.path.join('extracted_data', 'ASL_Alphabet')
OUTPUT_FILE = os.path.join(OUTPUT_DIR, 'alphabet_landmarks.csv')

# Create the output folder if it doesn't exist
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 2. Initialize MediaPipe Hands
mp_hands = mp.solutions.hands
# static_image_mode=True is the correct setting for photo-based datasets
hands = mp_hands.Hands(static_image_mode=True, min_detection_confidence=0.5)

print("🚀 Starting BridgeSign AI: Alphabet Feature Extraction...")

# 3. Data Collection Containers
all_data = []

# LIMIT: Set this to a high number (like 800 or 1000) for the final run.
# Using 3000 images per letter can make the CSV huge and slow to train.
IMAGES_PER_LETTER_LIMIT = 800 

# 4. The Extraction Loop
# os.listdir(TRAIN_DIR) will find folders A, B, C, Nothing, Space, etc.
for letter_folder in sorted(os.listdir(TRAIN_DIR)):
    letter_path = os.path.join(TRAIN_DIR, letter_folder)
    
    if not os.path.isdir(letter_path):
        continue 
        
    print(f"📂 Processing: {letter_folder}")
    
    images_in_folder = os.listdir(letter_path)
    count = 0
    
    for img_name in images_in_folder:
        if count >= IMAGES_PER_LETTER_LIMIT:
            break
            
        img_path = os.path.join(letter_path, img_name)
        image = cv2.imread(img_path)
        
        if image is None:
            continue
            
        # Convert BGR to RGB for MediaPipe
        img_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        results = hands.process(img_rgb)
        
        # If landmarks are found, extract the coordinates
        if results.multi_hand_landmarks:
            # We only need the first hand detected in the photo
            hand_landmarks = results.multi_hand_landmarks[0]
            
            # Extract 21 landmarks (x, y, z) = 63 total values
            keypoints = []
            for lm in hand_landmarks.landmark:
                keypoints.extend([lm.x, lm.y, lm.z])
            
            # Append the coordinates + the label (the folder name)
            keypoints.append(letter_folder)
            all_data.append(keypoints)
            count += 1

    print(f"✅ Extracted {count} samples for '{letter_folder}'")

# 5. Save to CSV
# Create column names: x0, y0, z0 ... x20, y20, z20, label
columns = []
for i in range(21):
    columns.extend([f'x{i}', f'y{i}', f'z{i}'])
columns.append('label')

df = pd.DataFrame(all_data, columns=columns)
df.to_csv(OUTPUT_FILE, index=False)

print(f"\n🎉 Extraction Complete!")
print(f"📊 Total Samples: {len(all_data)}")
print(f"📁 Data saved to: {OUTPUT_FILE}")

hands.close()