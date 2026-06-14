from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import torch
from transformers import pipeline, AutoImageProcessor, AutoModelForImageClassification
from PIL import Image
import io
import cv2
import tempfile
import os
import numpy as np

app = FastAPI()

# Allow CORS for the frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

device = 0 if torch.cuda.is_available() else -1
device_torch = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# ──────────────────────────────────────────────────────────────
# IMAGE MODEL: Using a pre-trained ViT-based deepfake detector
# Model: Organika/sdxl-detector (Highly accurate for AI vs Real)
# ──────────────────────────────────────────────────────────────
print("[INFO] Loading image detection model (Organika/sdxl-detector)...")
IMAGE_MODEL_NAME = "Organika/sdxl-detector"

try:
    image_processor = AutoImageProcessor.from_pretrained(IMAGE_MODEL_NAME)
    image_model = AutoModelForImageClassification.from_pretrained(IMAGE_MODEL_NAME)
    image_model = image_model.to(device_torch)
    image_model.eval()
    IMAGE_MODEL_LOADED = True
    print("[SUCCESS] Image detection model loaded successfully!")
except Exception as e:
    IMAGE_MODEL_LOADED = False
    print(f"[ERROR] Error loading image model: {e}")

# ──────────────────────────────────────────────────────────────
# VIDEO MODEL: We use the same image model frame-by-frame
# Extract N frames from a video, classify each, aggregate results
# This is more robust than a custom CNN-LSTM with limited training data
# ──────────────────────────────────────────────────────────────
print("[SUCCESS] Video detection will use frame-level analysis with the image model.")


@app.post("/predict/image")
async def predict_image(file: UploadFile = File(...)):
    if not IMAGE_MODEL_LOADED:
        return {"prediction": "Error", "confidence": "Model not loaded"}

    contents = await file.read()
    image = Image.open(io.BytesIO(contents)).convert('RGB')

    # Process with the pre-trained model
    inputs = image_processor(images=image, return_tensors="pt").to(device_torch)

    with torch.no_grad():
        outputs = image_model(**inputs)
        probs = torch.nn.functional.softmax(outputs.logits, dim=-1)

    # Map model labels to our labels
    predicted_class_idx = probs.argmax(-1).item()
    label = image_model.config.id2label[predicted_class_idx]
    confidence = probs[0][predicted_class_idx].item() * 100

    # Normalize labels (different models may use different label names)
    label_lower = label.lower()
    if "fake" in label_lower or "ai" in label_lower or "synthetic" in label_lower or "generated" in label_lower or "artificial" in label_lower:
        prediction = "Fake"
    elif "real" in label_lower or "authentic" in label_lower or "human" in label_lower:
        prediction = "Real"
    else:
        prediction = label  # Fallback to raw label

    return {"prediction": prediction, "confidence": f"{confidence:.2f}%"}


@app.post("/predict/video")
async def predict_video(file: UploadFile = File(...)):
    if not IMAGE_MODEL_LOADED:
        return {"prediction": "Error", "confidence": "Model not loaded"}

    # Save video temporarily
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
    temp_file.write(await file.read())
    temp_file.close()

    try:
        cap = cv2.VideoCapture(temp_file.name)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

        if total_frames == 0:
            cap.release()
            os.unlink(temp_file.name)
            return {"prediction": "Error", "confidence": "Could not read video"}

        # Sample N frames evenly from the video
        num_samples = min(16, total_frames)
        step = max(1, total_frames // num_samples)
        frame_indices = [i * step for i in range(num_samples)]

        fake_scores = []
        real_scores = []

        for idx in frame_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ret, frame = cap.read()
            if not ret:
                continue

            # Convert BGR to RGB and then to PIL
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            pil_frame = Image.fromarray(frame_rgb)

            # Run through the image model
            inputs = image_processor(images=pil_frame, return_tensors="pt").to(device_torch)
            with torch.no_grad():
                outputs = image_model(**inputs)
                probs = torch.nn.functional.softmax(outputs.logits, dim=-1)

            # Gather per-frame scores
            for i, label_id in enumerate(range(probs.shape[1])):
                label = image_model.config.id2label[label_id].lower()
                score = probs[0][label_id].item()
                if "fake" in label or "ai" in label or "synthetic" in label or "generated" in label or "artificial" in label:
                    fake_scores.append(score)
                elif "real" in label or "authentic" in label or "human" in label:
                    real_scores.append(score)

        cap.release()
        os.unlink(temp_file.name)

        if not fake_scores and not real_scores:
            return {"prediction": "Error", "confidence": "Could not analyze frames"}

        # Aggregate: average scores across all frames
        avg_fake = np.mean(fake_scores) if fake_scores else 0
        avg_real = np.mean(real_scores) if real_scores else 0

        if avg_fake > avg_real:
            prediction = "Fake"
            confidence = avg_fake * 100
        else:
            prediction = "Real"
            confidence = avg_real * 100

        return {
            "prediction": prediction,
            "confidence": f"{confidence:.2f}%",
            "frames_analyzed": len(frame_indices),
        }

    except Exception as e:
        os.unlink(temp_file.name)
        return {"prediction": "Error", "confidence": f"Analysis failed: {str(e)}"}


if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=True)
