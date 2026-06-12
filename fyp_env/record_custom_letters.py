import cv2
import mediapipe as mp
import pandas as pd
import os

# --- 1. SETTINGS ---
OUTPUT_FILE = "custom_webcam_data.csv"
FRAMES_TO_RECORD = 200  # About 6 seconds of data per letter

# MediaPipe Setup
mp_hands = mp.solutions.hands
mp_drawing = mp.solutions.drawing_utils
hands = mp_hands.Hands(min_detection_confidence=0.7, min_tracking_confidence=0.5)

print("\n🎥 BridgeSign AI: Continuous Data Recorder")
print("We will record letters one by one and save them automatically.")

# --- 2. CONTINUOUS LOOP ---
while True:
    # 1. Get input from the terminal
    print("\n" + "="*50)
    target_letter = input("👉 Enter the letter to record (or type 'EXIT' to finish): ").strip().upper()
    
    if target_letter == 'EXIT':
        print("\n✅ Recording session complete. All data is safely stored in the CSV!")
        break # Ends the entire script
        
    if target_letter == "":
        print("⚠️ You must enter a letter. Try again.")
        continue

    # 2. Open the camera for this specific letter
    cap = cv2.VideoCapture(0)
    data_collected = []
    is_recording = False
    frames_captured = 0
    
    print(f"\n🚀 Camera starting for '{target_letter}'...")
    print("👉 Press 'R' on the camera window to START recording.")
    print("👉 Press 'S' on the camera window to SKIP this letter.")
    
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret: break
        
        frame = cv2.flip(frame, 1)
        img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = hands.process(img_rgb)
        
        # UI Instructions on the camera feed
        if not is_recording:
            cv2.putText(frame, f"Hold '{target_letter}' & Press 'R' to Start", (10, 40), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)
            cv2.putText(frame, "Press 'S' to Skip", (10, 75), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 2)
        else:
            cv2.putText(frame, f"RECORDING '{target_letter}'... ({frames_captured}/{FRAMES_TO_RECORD})", 
                        (10, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
            cv2.putText(frame, "Wiggle your hand slightly!", (10, 80), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 127), 2)

        if results.multi_hand_landmarks:
            for hand_landmarks in results.multi_hand_landmarks:
                mp_drawing.draw_landmarks(frame, hand_landmarks, mp_hands.HAND_CONNECTIONS)
                
                # If we are in recording mode, extract the 63 coordinates
                if is_recording:
                    keypoints = []
                    for lm in hand_landmarks.landmark:
                        keypoints.extend([lm.x, lm.y, lm.z])
                    
                    keypoints.append(target_letter)
                    data_collected.append(keypoints)
                    frames_captured += 1
                    
            # Stop the inner loop automatically when we hit 200 frames
            if frames_captured >= FRAMES_TO_RECORD:
                break

        cv2.imshow('BridgeSign Custom Recorder', frame)

        # Keyboard controls for the camera window
        key = cv2.waitKey(1) & 0xFF
        if key == ord('s'): 
            print("\n⏭️ Skipped this letter.")
            break
        if key == ord('r') and not is_recording:
            print("\n🔴 RECORDING STARTED...")
            is_recording = True

    # 3. Close the camera window cleanly
    cap.release()
    cv2.destroyAllWindows()

    # 4. Save the data instantly (so you don't lose it if it crashes later)
    if frames_captured >= FRAMES_TO_RECORD:
        columns = []
        for i in range(21):
            columns.extend([f'x{i}', f'y{i}', f'z{i}'])
        columns.append('label')
        
        df_new = pd.DataFrame(data_collected, columns=columns)
        
        if os.path.exists(OUTPUT_FILE):
            df_new.to_csv(OUTPUT_FILE, mode='a', header=False, index=False)
        else:
            df_new.to_csv(OUTPUT_FILE, index=False)
            
        print(f"📁 SUCCESS: Saved {FRAMES_TO_RECORD} frames for '{target_letter}'!")