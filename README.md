# Signly AI

An accessible communication system for bridging sign language and spoken language through real-time hand tracking, machine learning, and 3D avatar animation.

## Features

- **Sign-to-Text**: Real-time sign language recognition using webcam + MediaPipe hand tracking + LSTM/Random Forest models
- **Text-to-Sign**: Converts text into 3D avatar animations (ASL signs via FBX animation files)
- **Alphabet Recognition**: Letter-by-letter ASL finger spelling using a Random Forest classifier
- **30-Word Recognition**: LSTM-based model for common sign language phrases
- **3D Avatar**: Three.js powered avatar that displays sign language animations
- **Web Dashboard**: Interactive UI for switching between modes, viewing predictions, and managing sessions

## Architecture

```
Dual_Sense_AI/
├── backend/               Flask REST API + Prediction Server
│   ├── app.py             Main Flask application (port 5001)
│   ├── server.py          Sign-to-text prediction server (port 5002)
│   ├── config.py          Configuration
│   ├── models/loader.py   Model loading (LSTM + Random Forest)
│   ├── routes/            API route handlers
│   ├── database/          SQLAlchemy models
│   └── requirements.txt   Python dependencies
├── WebApp/                Frontend (Three.js 3D Avatar + UI)
│   ├── index.html         Main page
│   ├── app.js             3D avatar engine
│   ├── api-client.js      API communication layer
│   ├── ui-manager.js      UI state management
│   ├── assets/            FBX animation files + avatar
│   └── lib/               Third-party libraries
├── fyp_env/               ML training & research scripts
│   ├── alphabet_classifier.pkl   Trained Random Forest model
│   ├── real_time_translator.py   Core prediction logic
│   └── train_*.py                Training pipeline scripts
├── fyp_30_word_kaggle_model.keras   LSTM sign language model
├── serve-offline.py        One-command launcher
├── start_backend.ps1       PowerShell launcher
└── .env.example            Environment configuration template
```

## Tech Stack

- **Backend**: Python, Flask, Flask-SQLAlchemy, Flask-Limiter
- **ML**: TensorFlow/Keras (LSTM), scikit-learn (Random Forest), MediaPipe (hand tracking)
- **Frontend**: HTML/CSS/JS, Three.js (3D rendering), Socket.IO
- **Data**: OpenCV (webcam capture), NumPy, Pandas

## Quick Start

### Prerequisites
- Python 3.8+
- Webcam

### Setup

```bash
# Create and activate virtual environment
python -m venv venv
.\venv\Scripts\activate

# Install dependencies
pip install -r backend/requirements.txt

# Configure environment (optional for local dev)
copy .env.example .env
```

### Run

```bash
# Option 1: One-command launcher
python serve-offline.py

# Option 2: PowerShell launcher (starts both servers)
.\start_backend.ps1

# Then open http://localhost:8000 in your browser
```

The backend starts two servers:
- **Flask API** on port 5001 (REST endpoints)
- **Prediction Server** on port 5002 (real-time frame processing)

### Manual Start

```bash
# Terminal 1 - Backend API
python backend/app.py

# Terminal 2 - Prediction Server
python backend/server.py

# Terminal 3 - Frontend
cd WebApp
python -m http.server 8000
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/predict/alphabet` | Alphabet sign prediction |
| POST | `/api/predict/sign` | 30-word sign prediction |
| POST | `/api/translate/text-to-asl` | Text to sign animation |
| POST | `/api/translate/asl-to-text` | Sign to text translation |
| POST | `/api/speech/recognize` | Speech recognition |
| POST | `/api/speech/synthesize` | Speech synthesis |

## Models

- **Alphabet Model**: Random Forest classifier (26 ASL letters, 63 keypoint features via MediaPipe)
- **Sign Model**: LSTM neural network (30 word classes, sequence of 30 frames with 21 landmarks each)
