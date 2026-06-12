# 🚀 Quick Reference - GUI Setup

## ⚡ 5-Minute Startup

```bash
# Terminal 1: Start Backend
cd backend
python app.py
# Server running on http://localhost:5000 ✅

# Terminal 2: Serve WebApp
cd WebApp
python -m http.server 8000
# Server running on http://localhost:8000 ✅

# Browser: Open WebApp
http://localhost:8000
# Status should show "Connected" ✅
```

## 📁 New Files Created

| File | Size | Purpose |
|------|------|---------|
| `WebApp/ui-manager.js` | 380 lines | UI state & interactions |
| `WebApp/api-client.js` | 380 lines | Backend communication |
| `WebApp/README.md` | 300+ lines | Complete docs |
| `WebApp/GUI_ENHANCEMENTS.md` | 200+ lines | Feature overview |
| `WEBAPP_SETUP_GUIDE.md` | 400+ lines | Setup instructions |
| `index.html` | 150 lines | Enhanced structure |
| `style.css` | 800 lines | Professional styling |

## 🎮 Basic Usage

### Text to Sign
```
1. Type "hello" in input box
2. Click Send button
3. Avatar signs "hello"
4. See confidence and alternatives
```

### Sign to Text
```
1. Click "Sign to Text" button
2. Enable camera
3. Perform sign gesture
4. System shows recognized text
```

## 🔑 Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Enter | Send text |
| Esc | Clear input |
| ? | Show help |
| S | Toggle speak mode |
| R | Toggle record mode |

## 🎨 Colors (Easy Customization)

```css
/* Edit style.css :root section */
--primary-color: #0078D7;        /* Main color */
--secondary-color: #50E6FF;      /* Accent */
--success-color: #107C10;        /* Green */
--error-color: #E81123;          /* Red */
--warning-color: #FFB900;        /* Yellow */
--bg-primary: #0F0F13;           /* Dark bg */
```

## 📱 Responsive Breakpoints

```
Desktop:  >1200px   (3-column layout)
Tablet:   768-1200px (collapsed sidebars)
Mobile:   <768px    (single column)
```

## 🧪 Testing Commands

```javascript
// In browser console:

// Check connection
console.log(window.apiClient.isConnected);

// Get health status
await window.apiClient.getHealth();

// Get model info
await window.apiClient.getModelStatus();

// Show toast
window.uiManager.showToast('Test message', 'info');

// Update metrics
window.uiManager.updateLatency(50);

// Switch mode
window.uiManager.switchMode('sign-to-text');
```

## 🐛 Common Issues

### "Backend unavailable"
```bash
curl http://localhost:5000/api/health
# If fails, restart backend: python app.py
```

### "API Client not found"
```bash
# Check script load order in index.html
# Should be: api-client.js → ui-manager.js → app.js
# Clear cache: Ctrl+Shift+Delete
```

### Low FPS
```javascript
// Check GPU acceleration
// DevTools → Settings → Enable Experiments
// Look for "GPU Rasterization"
```

## 📊 Performance Monitor

```
FPS Counter:    Ideally 60
Latency:        Should be <100ms
Confidence:     Shows as %
Memory:         <200MB (check Task Manager)
```

## 🔗 Quick Links

| Resource | URL |
|----------|-----|
| WebApp | `http://localhost:8000` |
| Backend API | `http://localhost:5000` |
| Health Check | `http://localhost:5000/api/health` |
| Documentation | `WebApp/README.md` |
| Setup Guide | `WEBAPP_SETUP_GUIDE.md` |
| Features | `WebApp/GUI_ENHANCEMENTS.md` |

## 🎯 File Locations

```
Dual_Sense_AI/
├── WebApp/
│   ├── index.html          ← Main page
│   ├── style.css           ← Styling
│   ├── app.js              ← 3D Avatar (don't modify)
│   ├── ui-manager.js       ← NEW
│   ├── api-client.js       ← NEW
│   └── README.md           ← Documentation
├── backend/
│   ├── app.py              ← Start here
│   ├── config.py
│   └── routes/
├── WEBAPP_SETUP_GUIDE.md   ← Setup instructions
└── ...
```

## 🚀 Deployment

### Local Testing
```bash
# Terminal 1: Backend
python backend/app.py

# Terminal 2: WebApp
cd WebApp && python -m http.server 8000

# Browser
http://localhost:8000
```

### Production
```bash
# Build
npm run build  # or minify manually

# Deploy
docker build -t bridgesign-frontend .
docker run -p 80:80 bridgesign-frontend

# Or copy to web server
scp -r WebApp/* user@server:/var/www/html/
```

## 🎨 UI Components

### Buttons
```html
<button class="btn">Primary</button>
<button class="btn-icon"><i class="fas fa-icon"></i></button>
<button class="action-btn">Action</button>
```

### Cards
```html
<div class="metric-card">
    <div class="metric-label">FPS</div>
    <div class="metric-value" id="fpsMeter">60</div>
</div>
```

### Panels
```html
<div class="panel">
    <div class="panel-title">Title</div>
    <div class="panel-content">Content</div>
</div>
```

## 🎓 Learning Resources

- **Three.js**: https://threejs.org/docs/
- **Fetch API**: https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API
- **CSS Grid**: https://css-tricks.com/snippets/css/complete-guide-grid/
- **JavaScript**: https://javascript.info/

## 💡 Pro Tips

1. **Use DevTools Network tab** to debug API calls
2. **Check console regularly** for errors/warnings
3. **Use browser cache clear** if UI doesn't update
4. **Monitor FPS** to catch performance issues
5. **Test on mobile** using `localhost:8000` on phone
6. **Use screenshots** for error reporting

## 🆘 Getting Help

1. Check `WebApp/README.md` for detailed docs
2. Review `WEBAPP_SETUP_GUIDE.md` for setup issues
3. Look at browser console for error messages
4. Check network tab for API errors
5. Refer to `IMPLEMENTATION_GUIDE.md` for architecture

## ✨ What's Working

- ✅ Dashboard UI (responsive)
- ✅ Mode switching (Text↔Sign)
- ✅ Real-time metrics (FPS, Latency)
- ✅ Prediction display
- ✅ History tracking
- ✅ Alternatives selection
- ✅ Settings management
- ✅ Toast notifications
- ✅ Connection status
- ✅ Speech integration ready
- ✅ API communication
- ✅ Session management

## 🔄 Typical Workflow

```
1. User types "hello" → 2. Hits Send
   ↓
3. UI Manager sends to API Client
   ↓
4. API Client calls backend prediction
   ↓
5. Backend ML model predicts result
   ↓
6. Result returned to UI
   ↓
7. UI updates display + calls Three.js
   ↓
8. Avatar plays animation
   ↓
9. History + metrics updated
```

## 📈 Next Steps

1. ✅ GUI complete
2. 📍 Test all features (5 min)
3. 🔧 Connect to your data (1 hour)
4. 🎨 Customize branding (30 min)
5. 🚀 Deploy to production (1 hour)

---

**Your GUI is ready!** 🎉  
Start with: `python backend/app.py` and `python -m http.server 8000`
