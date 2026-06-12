// API Client - Handles all backend communication (REST API + WebSocket webcam)

class APIClient {
    constructor(baseURL = 'http://localhost:5001') {
        this.baseURL = baseURL;
        this.sessionId = this.getOrCreateSession();
        this.isConnected = false;

        // HTTP frame posting state
        this.predictUrl = 'http://localhost:5002/predict';
        this.captureTimer = null;
        this.isCapturing = false;
        this.videoEl = null;
        this.displayVideoEl = null;
        this.canvasEl = null;
        this.mediaStream = null;
        this.reconnectAttempts = 0;
        this.maxReconnect = 5;

        this.setupWebcamElements();
        this.listenRecordButton();
        this.checkConnection();
    }

    // ─────────────────────────────────────────────────────────────────────
    // WEBCAM SETUP (creates hidden <video> + <canvas> at runtime)
    // ─────────────────────────────────────────────────────────────────────

    setupWebcamElements() {
        // Hidden video for reliable capture (always created, offscreen)
        this.videoEl = document.createElement('video');
        this.videoEl.id = 'webcam-feed';
        this.videoEl.setAttribute('autoplay', '');
        this.videoEl.setAttribute('playsinline', '');
        this.videoEl.style.cssText = 'position:fixed;top:-9999px;left:-9999px;width:320px;height:240px';
        document.body.appendChild(this.videoEl);

        // Visible video (from sign-to-text UI) — used only for display
        this.displayVideoEl = document.getElementById('webcamFeedVisible');

        this.canvasEl = document.createElement('canvas');
        this.canvasEl.id = 'capture-canvas';
        this.canvasEl.style.cssText = 'position:fixed;top:-9999px;left:-9999px';
        document.body.appendChild(this.canvasEl);
        console.log('[API] Webcam elements created');
    }

    listenRecordButton() {
        const btn = document.getElementById('recordBtn');
        if (!btn) return;
        btn.addEventListener('click', () => {
            // Defer to let ui-manager's handler toggle the class first
            setTimeout(() => {
                if (btn.classList.contains('active')) {
                    this.startCapture();
                } else {
                    this.stopCapture();
                }
            }, 0);
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    // WEBCAM CAPTURE (10-15 FPS)
    // ─────────────────────────────────────────────────────────────────────

    async startCapture() {
        if (this.isCapturing) return;
        try {
            this.mediaStream = await navigator.mediaDevices.getUserMedia({
                video: { width: 320, height: 240, fps: 15 }
            });
            // Hidden video for frame capture
            this.videoEl.srcObject = this.mediaStream;
            await this.videoEl.play();
            // Visible video for display
            if (this.displayVideoEl) {
                this.displayVideoEl.srcObject = this.mediaStream;
                await this.displayVideoEl.play();
            }
            this.isCapturing = true;
            // Hide placeholder when capture starts
            const placeholder = document.getElementById('webcamPlaceholder');
            if (placeholder) placeholder.classList.add('hidden');
            this.reconnectAttempts = 0;
            this.startFrameLoop();
            console.log('[API] Webcam capture started');
        } catch (err) {
            console.error('[API] Webcam error:', err);
            if (window.uiManager) {
                window.uiManager.showToast('Camera access denied', 'error');
            }
        }
    }

    stopCapture() {
        this.isCapturing = false;
        if (this.captureTimer) {
            clearInterval(this.captureTimer);
            this.captureTimer = null;
        }
        if (this.mediaStream) {
            this.mediaStream.getTracks().forEach(t => t.stop());
            this.mediaStream = null;
        }
        if (this.videoEl) this.videoEl.srcObject = null;
        if (this.displayVideoEl) this.displayVideoEl.srcObject = null;
        this.captureInFlight = false;
        // Show placeholder again
        const placeholder = document.getElementById('webcamPlaceholder');
        if (placeholder) placeholder.classList.remove('hidden');
        console.log('[API] Webcam capture stopped');
    }

    startFrameLoop() {
        const FPS = 8;
        const ctx = this.canvasEl.getContext('2d');
        this.captureInFlight = false;
        this.captureTimer = setInterval(() => {
            if (!this.isCapturing || this.captureInFlight) return;
            this.captureInFlight = true;
            const w = 320, h = 240;
            this.canvasEl.width = w;
            this.canvasEl.height = h;
            ctx.drawImage(this.videoEl, 0, 0, w, h);
            const b64 = this.canvasEl.toDataURL('image/jpeg', 70);

            fetch(this.predictUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ frame: b64 }),
            })
            .then(r => r.json())
            .then(data => {
                this.captureInFlight = false;
                if (data.text && window.uiManager) {
                    window.uiManager.updatePrediction(
                        data.text,
                        data.confidence || 0,
                        data.alternatives || []
                    );
                }
            })
            .catch(() => {
                this.captureInFlight = false;
            });
        }, 1000 / FPS);
    }

    // ─────────────────────────────────────────────────────────────────────
    // CONNECTION MANAGEMENT (REST)
    // ─────────────────────────────────────────────────────────────────────

    async checkConnection() {
        try {
            const response = await this.get('/api/health');
            this.isConnected = response.success;
            this.updateConnectionStatus();
            return this.isConnected;
        } catch (error) {
            this.isConnected = false;
            this.updateConnectionStatus();
            return false;
        }
    }

    updateConnectionStatus() {
        if (window.uiManager) {
            if (this.isConnected) {
                window.uiManager.updateStatus('connected', 'Connected to Backend');
            } else {
                window.uiManager.updateStatus('offline', 'Offline - Backend unavailable');
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // HTTP METHODS (REST)
    // ─────────────────────────────────────────────────────────────────────

    async get(endpoint) {
        try {
            const response = await fetch(this.baseURL + endpoint, {
                method: 'GET',
                headers: this.getHeaders()
            });
            return await this.handleResponse(response);
        } catch (error) {
            throw this.handleError(error);
        }
    }

    async post(endpoint, data = {}) {
        try {
            const response = await fetch(this.baseURL + endpoint, {
                method: 'POST',
                headers: this.getHeaders(),
                body: JSON.stringify(data)
            });
            return await this.handleResponse(response);
        } catch (error) {
            throw this.handleError(error);
        }
    }

    async put(endpoint, data = {}) {
        try {
            const response = await fetch(this.baseURL + endpoint, {
                method: 'PUT',
                headers: this.getHeaders(),
                body: JSON.stringify(data)
            });
            return await this.handleResponse(response);
        } catch (error) {
            throw this.handleError(error);
        }
    }

    async handleResponse(response) {
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
        if (!data.success) throw new Error(data.error || 'Request failed');
        return data.data || data;
    }

    handleError(error) {
        console.error('API Error:', error);
        return error;
    }

    getHeaders() {
        return {
            'Content-Type': 'application/json',
            'X-Session-ID': this.sessionId
        };
    }

    // ─────────────────────────────────────────────────────────────────────
    // SESSION MANAGEMENT
    // ─────────────────────────────────────────────────────────────────────

    getOrCreateSession() {
        let sessionId = localStorage.getItem('bridgesign_session_id');
        if (!sessionId) {
            sessionId = this.generateUUID();
            localStorage.setItem('bridgesign_session_id', sessionId);
        }
        return sessionId;
    }

    generateUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            const r = Math.random() * 16 | 0;
            const v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    // PREDICTION ENDPOINTS (REST)
    // ─────────────────────────────────────────────────────────────────────

    async predictSign(keypoints) {
        try {
            const startTime = performance.now();
            const result = await this.post('/api/predict/sign', {
                keypoints: keypoints,
                session_id: this.sessionId
            });
            const latency = performance.now() - startTime;
            if (window.uiManager) window.uiManager.updateLatency(latency);
            return result;
        } catch (error) {
            if (window.uiManager) {
                window.uiManager.showToast('Prediction failed: ' + error.message, 'error');
            }
            throw error;
        }
    }

    async predictAlphabet(keypoints) {
        try {
            return await this.post('/api/predict/alphabet', {
                keypoints: keypoints,
                session_id: this.sessionId
            });
        } catch (error) {
            console.error('Alphabet prediction error:', error);
            throw error;
        }
    }

    async predictBatch(keypoints_batch) {
        try {
            return await this.post('/api/predict/batch', {
                keypoints_batch: keypoints_batch,
                session_id: this.sessionId
            });
        } catch (error) {
            console.error('Batch prediction error:', error);
            throw error;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // TRANSLATION ENDPOINTS (REST)
    // ─────────────────────────────────────────────────────────────────────

    async translateTextToASL(text) {
        try {
            const result = await this.post('/api/translate/text-to-asl', {
                text: text
            });
            return result;
        } catch (error) {
            if (window.uiManager) {
                window.uiManager.showToast('Translation failed: ' + error.message, 'error');
            }
            throw error;
        }
    }

    async translateASLToText(gesture_sequence) {
        try {
            return await this.post('/api/translate/asl-to-text', {
                gesture_sequence: gesture_sequence
            });
        } catch (error) {
            console.error('ASL to text error:', error);
            throw error;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // SPEECH ENDPOINTS (REST)
    // ─────────────────────────────────────────────────────────────────────

    async recognizeSpeech(options = {}) {
        try {
            return await this.post('/api/speech/recognize', {
                language: options.language || 'en-US',
                timeout_ms: options.timeout_ms || 30000
            });
        } catch (error) {
            if (window.uiManager) {
                window.uiManager.showToast('Speech recognition failed: ' + error.message, 'error');
            }
            throw error;
        }
    }

    async synthesizeSpeech(text, voice = 'en-US-AriaNeural', rate = 1.0) {
        try {
            return await this.post('/api/speech/synthesize', {
                text: text,
                voice: voice,
                rate: rate
            });
        } catch (error) {
            if (window.uiManager) {
                window.uiManager.showToast('Speech synthesis failed: ' + error.message, 'error');
            }
            throw error;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATUS ENDPOINTS (REST)
    // ─────────────────────────────────────────────────────────────────────

    async getHealth() {
        try {
            return await this.get('/api/health');
        } catch (error) {
            console.error('Health check error:', error);
            throw error;
        }
    }

    async getModelStatus() {
        try {
            return await this.get('/api/status/models');
        } catch (error) {
            console.error('Model status error:', error);
            throw error;
        }
    }

    async getSystemStatus() {
        try {
            return await this.get('/api/status/system');
        } catch (error) {
            console.error('System status error:', error);
            throw error;
        }
    }

    async getServiceStatus() {
        try {
            return await this.get('/api/status/services');
        } catch (error) {
            console.error('Service status error:', error);
            throw error;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // HELPER METHODS
    // ─────────────────────────────────────────────────────────────────────

    startHealthChecks(interval = 30000) {
        this.healthCheckInterval = setInterval(async () => {
            try { await this.checkConnection(); }
            catch (error) { console.warn('Health check failed:', error); }
        }, interval);
    }

    stopHealthChecks() {
        if (this.healthCheckInterval) clearInterval(this.healthCheckInterval);
    }

    async isAvailable() {
        try { await this.checkConnection(); return this.isConnected; }
        catch (error) { return false; }
    }
}

// Initialize API Client globally
document.addEventListener('DOMContentLoaded', () => {
    window.apiClient = new APIClient();
    window.apiClient.startHealthChecks();
    console.log('✅ API Client initialized');
});
