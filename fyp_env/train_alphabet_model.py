import pandas as pd
import numpy as np
import pickle
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

# 1. Load the dataset
DATA_PATH = 'extracted_data/ASL_Alphabet/alphabet_landmarks.csv'
MODEL_SAVE_PATH = 'alphabet_classifier.pkl'

print("📂 Loading dataset...")
df = pd.read_csv(DATA_PATH)

# 2. Split Data (Features and Labels)
# X = everything except the 'label' column
# y = only the 'label' column
X = df.drop('label', axis=1)
y = df['label']

# 3. Train/Test Split (80% training, 20% testing)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

print(f"🧠 Training the Random Forest Brain on {len(X_train)} samples...")

# 4. Initialize and Train Model
# n_estimators=100 means we are using 100 "Decision Trees" to vote on the result
model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train, y_train)

# 5. Evaluation
y_pred = model.predict(X_test)
accuracy = accuracy_score(y_test, y_pred)

print("\n📊 --- Model Performance ---")
print(f"Overall Accuracy: {accuracy * 100:.2f}%")
print("\nDetailed Report:")
print(classification_report(y_test, y_pred))

# 6. Save the Model
with open(MODEL_SAVE_PATH, 'wb') as f:
    pickle.dump(model, f)

print(f"\n✅ Success! Model saved as: {MODEL_SAVE_PATH}")