from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import numpy as np
from PIL import Image
import io
import pickle, torch
import torch.nn as nn
from torchvision import models, transforms
import os

# ── CONFIG ────────────────────────────────────────────────────────────────────

CLASS_LABELS = [
    "Blouse",               # 0
    "Dhoti Pants",          # 1
    "Dupattas",             # 2
    "Gowns",                # 3
    "Kurta (Men)",          # 4
    "Leggings & Salwars",   # 5
    "Lehenga",              # 6
    "Mojaris (Men)",        # 7
    "Mojaris (Women)",      # 8
    "Nehru Jackets",        # 9
    "Palazzos",             # 10
    "Petticoats",           # 11
    "Saree",                # 12
    "Sherwanis",            # 13
    "Women Kurta",          # 14
]
NUM_CLASSES = len(CLASS_LABELS)  # 15

MODEL_PATHS = {
    "resnet50":        "weights/best_resnet50_fixed.pth",
    "efficientnet_b0": "weights/best_efficientnet_model.pth",
}

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# ── PREPROCESSING ─────────────────────────────────────────────────────────────

preprocess = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std =[0.229, 0.224, 0.225]),
])

# ── MODEL LOADERS ─────────────────────────────────────────────────────────────

def load_resnet50(path: str) -> nn.Module:
    model = models.resnet50(weights=None)
    # Exact head architecture from the error message:
    # fc.0 Linear(2048→1024), fc.1 BN(1024),
    # fc.4 Linear(1024→512),  fc.5 BN(512),
    # fc.8 Linear(512→15)
    num_ftrs = model.fc.in_features  # 2048
    model.fc = nn.Sequential(
        nn.Linear(num_ftrs, 1024),   # fc.0
        nn.BatchNorm1d(1024),         # fc.1
        nn.ReLU(),                    # fc.2
        nn.Dropout(0.3),              # fc.3
        nn.Linear(1024, 512),         # fc.4
        nn.BatchNorm1d(512),          # fc.5
        nn.ReLU(),                    # fc.6
        nn.Dropout(0.3),              # fc.7
        nn.Linear(512, NUM_CLASSES)   # fc.8
    )
    state = torch.load(path, map_location=DEVICE)
    if isinstance(state, dict) and "model_state_dict" in state:
        state = state["model_state_dict"]
    model.load_state_dict(state)
    model.to(DEVICE)
    model.eval()
    return model


def load_efficientnet_pkl(path: str) -> nn.Module:
    model = models.efficientnet_b0(weights=None)
    model.classifier[1] = nn.Linear(1280, NUM_CLASSES)
    state = torch.load(path, map_location=DEVICE, weights_only=False)
    model.load_state_dict(state)
    model.to(DEVICE)
    model.eval()
    return model

# ── LOAD ALL MODELS AT STARTUP ────────────────────────────────────────────────

print("\nLoading FitFind models...")
MODELS = {}

for name, path in MODEL_PATHS.items():
    if not os.path.exists(path):
        print(f"  ⚠  {name}: file not found at '{path}' — skipping")
        continue
    try:
        if name == "resnet50":
            MODELS[name] = (load_resnet50(path), preprocess)
        elif name == "efficientnet_b0":
            MODELS[name] = (load_efficientnet_pkl(path), preprocess)
        print(f"  ✓  {name} loaded  ({path})")
    except Exception as e:
        print(f"  ✗  {name} FAILED: {e}")

if not MODELS:
    print("  WARNING: No models loaded — predictions will return dummy data.\n")
else:
    print(f"  Ready — {len(MODELS)}/{len(MODEL_PATHS)} models on {DEVICE}\n")

# ── FASTAPI APP ───────────────────────────────────────────────────────────────

app = FastAPI(
    title="FitFind Classification API",
    description="Ensemble: ResNet50 (.pth) + EfficientNet-B0 (.pkl)",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── INFERENCE ─────────────────────────────────────────────────────────────────

def predict_single(model: nn.Module, transform, image: Image.Image) -> np.ndarray:
    tensor = transform(image).unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        logits = model(tensor)
        probs  = torch.softmax(logits, dim=1).cpu().numpy()[0]
    return probs


def _make_breakdown(probs: np.ndarray) -> list:
    return sorted(
        [{"label": CLASS_LABELS[i], "confidence": float(round(float(probs[i]) * 100, 2))}
         for i in range(NUM_CLASSES)],
        key=lambda x: x["confidence"], reverse=True,
    )


def ensemble_predict(image: Image.Image) -> dict:
    if not MODELS:
        probs = np.random.dirichlet(np.ones(NUM_CLASSES))
        return {
            "top_class":   CLASS_LABELS[int(np.argmax(probs))],
            "confidence":  float(round(float(np.max(probs)) * 100, 2)),
            "breakdown":   _make_breakdown(probs),
            "models_used": ["dummy"],
        }

    all_probs = []
    per_model = {}
    for name, (model, transform) in MODELS.items():
        p = predict_single(model, transform, image)
        all_probs.append(p)
        per_model[name] = {
            "top_class":  CLASS_LABELS[int(np.argmax(p))],
            "confidence": float(round(float(np.max(p)) * 100, 2)),
        }

    probs = np.mean(all_probs, axis=0)

    return {
        "top_class":   CLASS_LABELS[int(np.argmax(probs))],
        "confidence":  float(round(float(np.max(probs)) * 100, 2)),
        "breakdown":   _make_breakdown(probs),
        "models_used": list(MODELS.keys()),
        "per_model":   per_model,
    }

# ── ROUTES ────────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return {
        "status":        "FitFind API running",
        "models_loaded": list(MODELS.keys()),
        "num_classes":   NUM_CLASSES,
        "classes":       CLASS_LABELS,
        "device":        str(DEVICE),
    }

@app.get("/health")
def health():
    return {"status": "ok", "models_ready": len(MODELS)}

@app.post("/classify")
async def classify(file: UploadFile = File(...)):
    if file.content_type not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported type '{file.content_type}'. Send JPEG, PNG, or WEBP."
        )
    try:
        contents = await file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")
    except Exception:
        raise HTTPException(status_code=400, detail="Could not decode image.")
    try:
        result = ensemble_predict(image)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")
    return JSONResponse(content=result)
