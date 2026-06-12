import pandas as pd
import pickle
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import warnings

# Silence warnings for a clean terminal
warnings.filterwarnings("ignore")

print("\n🚀 BridgeSign AI: Neural Fusion & Training Started...")
print("="*50)

# --- 1. Load the Datasets ---
# NOTE: Make sure this path points to your Kaggle CSV!
KAGGLE_CSV_PATH = 'extracted_data/ASL_Alphabet/alphabet_landmarks.csv' 
CUSTOM_CSV_PATH = 'final_cleaned_data.csv' # Your perfect dataset

print("📂 Loading datasets...")
try:
    kaggle_df = pd.read_csv(KAGGLE_CSV_PATH)
    print(f"   -> Kaggle Base Data: {len(kaggle_df)} rows")
except Exception as e:
    print(f"❌ Error loading Kaggle data. Check path: {KAGGLE_CSV_PATH}")
    exit()

try:
    custom_df = pd.read_csv(CUSTOM_CSV_PATH)
    print(f"   -> Custom Webcam Data: {len(custom_df)} rows")
except Exception as e:
    print(f"❌ Error loading Custom data: {e}")
    exit()

# --- 2. Combine the Data ---
combined_df = pd.concat([kaggle_df, custom_df], ignore_index=True)
print(f"🧬 Combined Dataset Size: {len(combined_df)} rows")

# --- 3. Prepare for Training ---
X = combined_df.drop('label', axis=1)
y = combined_df['label']

print("\n🧠 Shuffling data and splitting into Train/Test sets...")
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

print(f"⚙️ Training the Random Forest Brain on {len(X_train)} samples. This may take a minute...")

# --- 4. Train the Model ---
model = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1) # n_jobs=-1 uses all CPU cores for speed
model.fit(X_train, y_train)

# --- 5. Evaluate ---
y_pred = model.predict(X_test)
accuracy = accuracy_score(y_test, y_pred)

print("\n📊 --- New Model Performance ---")
print(f"Real-World Accuracy Score: {accuracy * 100:.2f}%")

# --- 6. Save the Upgraded Brain ---
with open('alphabet_classifier.pkl', 'wb') as f:
    pickle.dump(model, f)

print("="*50)
print("✅ Success! Upgraded model saved as: 'alphabet_classifier.pkl'")
print("🔥 The AI has now learned exactly what your hands look like.")