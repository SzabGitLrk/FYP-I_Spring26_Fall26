# 🚀 Quick Start Guide - Dual Sense AI

## 📋 Prerequisites
- Python 3.8+
- Git
- Virtual Environment (venv or conda)
- Webcam
- Optional: Azure Cognitive Services account

## ⚡ 5-Minute Setup

### Step 1: Clone & Setup Environment
```bash
# Navigate to project
cd c:\Users\A.J\ Computer's\Desktop\Dual_Sense_AI

# Activate virtual environment
./fyp_env/Scripts/activate

# Or create new one if needed
python -m venv fyp_env
./fyp_env/Scripts/activate
```

### Step 2: Install Dependencies
```bash
# Install or update packages
pip install --upgrade pip
pip install -r backend/requirements.txt
```

### Step 3: Configure Environment
```bash
# Copy example configuration
copy .env.example .env

# Edit .env file with your settings (optional for local dev)
# Most defaults work for local development
```

### Step 4: Run Backend Server
```bash
cd backend
python app.py

# Server will start on http://localhost:5000
# Health check: curl http://localhost:5000/api/health
```

### Step 5: Run Frontend (New Terminal)
```bash
cd WebApp
python -m http.server 8000

# Access at http://localhost:8000
```

### Step 6: Test Real-time Recognition
```bash
# New terminal - Run real-time sign recognition
cd fyp_env
python real_time_translator.py

# Or run text-to-sign pipeline
python text_to_sign_pipeline.py
```

---

## 🧪 Testing the System

### Test 1: Backend Health
```bash
curl http://localhost:5000/api/health
# Expected: {"status": "healthy", "timestamp": "..."}
```

### Test 2: Text to ASL
```bash
curl -X POST http://localhost:5000/api/translate/text-to-asl \
  -H "Content-Type: application/json" \
  -d '{"text": "hello world"}'
```

### Test 3: Sign Recognition (Webcam)
```bash
python fyp_env/hand_tracker.py
# Shows live hand skeleton tracking
```

### Test 4: Full Pipeline
```bash
# In one terminal: Backend
python backend/app.py

# In another terminal: Real-time recognition
python fyp_env/real_time_translator.py

# Open browser: http://localhost:8000
# Perform hand gestures to see predictions
```

---

## 🎯 Common Issues & Solutions

### Issue 1: Module Not Found
```bash
# Solution: Ensure virtual environment is activated
# Windows:
./fyp_env/Scripts/activate

# Linux/Mac:
source fyp_env/bin/activate

# Then install requirements
pip install -r backend/requirements.txt
```

### Issue 2: MediaPipe Not Detecting Hand
```bash
# Solution: Check webcam
python fyp_env/test_webcam.py

# Check lighting - needs good lighting
# Position hand in view
# Try calibration script
python fyp_env/hand_tracker.py
```

### Issue 3: CUDA/GPU Not Found
```bash
# Solution: Use CPU (slower but works)
# In config.py, set:
os.environ['CUDA_VISIBLE_DEVICES'] = '-1'

# Or install CUDA support
pip install tensorflow-gpu
```

### Issue 4: Port Already in Use
```bash
# Solution: Use different port
# For backend:
python backend/app.py --port 5001

# For frontend:
python -m http.server 8001
```

### Issue 5: API Connection Refused
```bash
# Check backend is running
curl http://localhost:5000/api/health

# Check frontend is pointing to correct API
# Edit WebApp/services/api.js baseURL
```

---

## 📁 Project Structure

```
Dual_Sense_AI/
├── app.py                          # Main real-time recognition
├── text_to_asl.py                  # Text-to-sign converter
├── IMPLEMENTATION_GUIDE.md         # This guide!
│
├── backend/                        # 🆕 Flask REST API
│   ├── app.py
│   ├── config.py
│   ├── requirements.txt
│   ├── wsgi.py
│   ├── models/
│   │   ├── loader.py
│   │   ├── inference.py
│   │   └── ensemble.py
│   ├── services/
│   │   ├── speech_service.py       # Azure Speech integration
│   │   ├── cache_service.py
│   │   └── text_to_asl_service.py
│   ├── routes/
│   │   ├── prediction_routes.py
│   │   ├── translation_routes.py
│   │   └── speech_routes.py
│   ├── database/
│   │   ├── models.py
│   │   └── migrations/
│   ├── middleware/
│   │   ├── rate_limiter.py
│   │   └── error_handler.py
│   ├── monitoring/
│   │   ├── metrics.py
│   │   └── logger.py
│   └── tests/
│       ├── test_api.py
│       ├── test_models.py
│       └── test_integration.py
│
├── fyp_env/                        # Python virtual environment
│   ├── real_time_translator.py
│   ├── hand_tracker.py
│   ├── train_alphabet_model.py
│   ├── alphabet_classifier.pkl
│   ├── datasets/
│   ├── extracted_data/
│   └── models/
│
├── WebApp/                         # Frontend (HTML/JS/CSS)
│   ├── app.js                      # Main Three.js application
│   ├── index.html
│   ├── style.css
│   ├── services/
│   │   ├── api.js                  # REST API client
│   │   └── rtc_stream.js           # WebRTC streaming
│   └── assets/
│
└── docker/                         # 🆕 Containerization
    ├── Dockerfile
    ├── docker-compose.yml
    └── nginx.conf
```

---

## 🚀 Next Steps

### Immediate (This Week)
1. ✅ Get real-time hand tracking working
2. ✅ Verify sign recognition accuracy
3. ✅ Test text-to-ASL animation pipeline
4. ✅ Set up backend API server

### Short Term (Next 2 Weeks)
1. ✅ Integrate Azure Speech Service
2. ✅ Implement REST API wrapper
3. ✅ Add rate limiting & caching
4. ✅ Create comprehensive tests

### Medium Term (Weeks 3-4)
1. ✅ Optimize models for accuracy
2. ✅ Implement monitoring & logging
3. ✅ Set up CI/CD pipeline
4. ✅ Docker containerization

### Production (Weeks 5+)
1. ✅ Security hardening
2. ✅ Load testing
3. ✅ Database integration
4. ✅ Cloud deployment

---

## 📞 Debugging Tips

### Enable Verbose Logging
```python
# In backend/config.py
LOG_LEVEL = 'DEBUG'  # Shows detailed execution trace
```

### Profile Performance
```bash
# Use cProfile to find bottlenecks
python -m cProfile -s cumtime backend/app.py
```

### Check Dependencies
```bash
# List all installed packages
pip list

# Check for conflicts
pip check

# Upgrade all packages
pip install --upgrade -r requirements.txt
```

### Monitor GPU/CPU
```bash
# Windows Task Manager
taskmgr

# Or use Python monitoring
pip install gpustat
gpustat  # Check GPU usage
```

---

## 🎓 Learning Resources

### MediaPipe
- Documentation: https://developers.google.com/mediapipe
- Hand Tracking: https://google.github.io/mediapipe/solutions/hands

### Sign Language Datasets
- WLASL: https://dxli94.github.io/WLASL/
- ASL Alphabet: https://www.kaggle.com/grassknoted/asl-alphabet

### Three.js 3D Animation
- Docs: https://threejs.org/docs/
- FBX Loader: https://threejs.org/examples/#webgl_loader_fbx

### Flask REST API
- Flask Docs: https://flask.palletsprojects.com/
- RESTful Best Practices: https://restfulapi.net/

---

## 💡 Pro Tips

1. **GPU Acceleration**: If you have NVIDIA GPU, install CUDA for 10-20x faster inference
2. **Batch Processing**: Process multiple frames at once for better GPU utilization
3. **Caching**: Cache model predictions for duplicate inputs
4. **Profiling**: Use PyCharm or VSCode profiler to identify bottlenecks
5. **Testing**: Write tests early - saves debugging time later
6. **Documentation**: Keep API docs updated as you add features
7. **Version Control**: Commit often with clear messages

---

## ✅ Checklist Before Submission

- [ ] All models load without errors
- [ ] Real-time recognition works at 30+ FPS
- [ ] Text-to-ASL animation plays smoothly
- [ ] Speech integration works (if implemented)
- [ ] Error handling covers all edge cases
- [ ] Code has >80% test coverage
- [ ] Performance meets SLAs (<100ms latency)
- [ ] Documentation is comprehensive
- [ ] Docker deployment works
- [ ] Security vulnerabilities scanned

---

## 📧 Support

For issues or questions:
1. Check the IMPLEMENTATION_GUIDE.md for detailed info
2. Review error logs in logs/ directory
3. Check VS Code for syntax errors
4. Use browser developer console for frontend errors
5. Enable DEBUG mode for detailed traces

Good luck! 🎉

