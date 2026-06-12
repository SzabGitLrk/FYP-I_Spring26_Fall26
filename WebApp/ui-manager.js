// UI Manager - Handles all GUI interactions and state management

class UIManager {
    constructor() {
        this.currentMode = 'text-to-sign';
        this.isRecording = false;
        this.history = [];
        this.maxHistoryItems = 10;

        // Word builder state
        this.wordSentence = [];
        this.wordBuffer = [];
        this.wordStableLetter = null;
        this.wordStableConfidence = 0;
        this.wordConsecutive = 0;
        this.wordLastRaw = null;
        this.commitTimer = null;
        this.STABILITY_THRESHOLD = 3;
        this.COMMIT_DELAY = 1500;
        this._backspaceAt = 0; // timestamp of last backspace (prevents prediction re-add race)

        // Push a history entry so the popstate fallback can catch back-navigation
        history.pushState('s2t', '');

        this.initializeElements();
        this.attachEventListeners();
        this.startMetricsUpdate();
    }

    // ─────────────────────────────────────────────────────────────────────
    // INITIALIZATION
    // ─────────────────────────────────────────────────────────────────────

    initializeElements() {
        // Buttons
        this.textToSignBtn = document.getElementById('textToSignBtn');
        this.signToTextBtn = document.getElementById('signToTextBtn');
        this.speakBtn = document.getElementById('speakBtn');
        this.sendBtn = document.getElementById('sendBtn');
        this.repeatBtn = document.getElementById('repeatBtn');
        this.recordBtn = document.getElementById('recordBtn');
        this.clearBtn = document.getElementById('clearBtn');
        this.settingsBtn = document.getElementById('settingsBtn');
        this.helpBtn = document.getElementById('helpBtn');

        // Input
        this.textInput = document.getElementById('textInput');

        // Display Elements
        this.fpsMeter = document.getElementById('fpsMeter');
        this.latencyMeter = document.getElementById('latencyMeter');
        this.confidenceMeter = document.getElementById('confidenceMeter');
        this.confidenceBar = document.getElementById('confidenceBar');
        this.currentPrediction = document.getElementById('currentPrediction');
        this.infoMessage = document.getElementById('infoMessage');

        // Lists
        this.historyList = document.getElementById('historyList');
        this.alternativesList = document.getElementById('alternativesList');

        // Panels
        this.settingsPanel = document.getElementById('settingsPanel');

        // Settings
        this.confidenceThreshold = document.getElementById('confidenceThreshold');
        this.animationSpeed = document.getElementById('animationSpeed');
        this.thresholdValue = document.getElementById('thresholdValue');
        this.speedValue = document.getElementById('speedValue');

        // Status
        this.statusIndicator = document.getElementById('statusIndicator');
        this.statusDot = document.querySelector('.status-dot');
        this.statusText = document.querySelector('.status-text');

        // Toast Container
        this.toastContainer = document.getElementById('toastContainer');
    }

    attachEventListeners() {
        // Mode buttons
        this.textToSignBtn.addEventListener('click', () => this.switchMode('text-to-sign'));
        this.signToTextBtn.addEventListener('click', () => this.switchMode('sign-to-text'));

        // Action buttons
        this.speakBtn.addEventListener('click', () => this.handleSpeak());
        this.sendBtn.addEventListener('click', () => this.handleSend());
        this.repeatBtn.addEventListener('click', () => this.handleRepeat());
        this.recordBtn.addEventListener('click', () => this.handleRecord());
        this.clearBtn.addEventListener('click', () => this.handleClear());

        // Settings
        this.settingsBtn.addEventListener('click', () => this.toggleSettings());
        this.helpBtn.addEventListener('click', () => this.showHelp());

        // Input
        this.textInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') this.handleSend();
        });

        // Settings sliders
        this.confidenceThreshold.addEventListener('input', (e) => {
            this.thresholdValue.textContent = e.target.value + '%';
            this.updateSettings();
        });

        this.animationSpeed.addEventListener('input', (e) => {
            this.speedValue.textContent = e.target.value + 'x';
            this.updateSettings();
        });

        // Sign-to-text panel buttons
        const sentenceClearBtn = document.getElementById('sentenceClearBtn');
        if (sentenceClearBtn) {
            sentenceClearBtn.addEventListener('click', () => this.handleClear());
        }
        const signBackspaceBtn = document.getElementById('signBackspaceBtn');
        if (signBackspaceBtn) {
            signBackspaceBtn.addEventListener('click', () => this.handleSignBackspace());
        }
        const signSpaceBtn = document.getElementById('signSpaceBtn');
        if (signSpaceBtn) {
            signSpaceBtn.addEventListener('click', () => this.handleSignSpace());
        }

        // ─── Keyboard shortcuts for sign-to-text mode ─────────────────────
        window.addEventListener('keydown', (e) => {
            if (this.currentMode !== 'sign-to-text') return;
            const key = e.key;
            if (key === 'Backspace') {
                e.preventDefault();
                this.handleSignBackspace();
                return;
            }
            if (key === ' ' || key === 'Spacebar') {
                e.preventDefault();
                this.handleSignSpace();
                return;
            }
        }, { capture: true });

        // popstate fallback — catches browsers that ignore preventDefault() on Backspace
        window.addEventListener('popstate', (e) => {
            if (this.currentMode !== 'sign-to-text') return;
            history.pushState('s2t', '');
            this.handleSignBackspace();
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    // MODE SWITCHING
    // ─────────────────────────────────────────────────────────────────────

    switchMode(mode) {
        this.currentMode = mode;

        const avatarContainer = document.getElementById('avatarContainer');
        const webcamContainer = document.getElementById('webcamContainer');
        const inputPanel = document.querySelector('.input-panel');
        const infoPanel = document.querySelector('.info-panel');

        if (mode === 'text-to-sign') {
            this.textToSignBtn.classList.add('active');
            this.signToTextBtn.classList.remove('active');
            this.textInput.placeholder = 'Type text to translate to sign language...';
            this.updateStatus('connected', 'Connected - Text to Sign Mode');

            if (avatarContainer) avatarContainer.style.display = '';
            if (webcamContainer) webcamContainer.style.display = 'none';
            if (inputPanel) inputPanel.style.display = '';
            if (infoPanel) infoPanel.style.display = '';

            // Stop webcam if running
            if (window.apiClient && window.apiClient.isCapturing) {
                const recordBtn = document.getElementById('recordBtn');
                if (recordBtn) { recordBtn.classList.remove('active'); recordBtn.innerHTML = '<i class="fas fa-circle"></i> Record'; }
                window.apiClient.stopCapture();
            }
            this.repeatBtn.disabled = false;
        } else {
            this.signToTextBtn.classList.add('active');
            this.textToSignBtn.classList.remove('active');
            this.textInput.placeholder = 'Sign in front of camera...';
            this.updateStatus('connected', 'Connected - Sign to Text Mode');

            if (avatarContainer) avatarContainer.style.display = 'none';
            if (webcamContainer) webcamContainer.style.display = 'flex';
            if (inputPanel) inputPanel.style.display = 'none';
            if (infoPanel) infoPanel.style.display = 'none';

            this.repeatBtn.disabled = true;

            history.pushState('s2t', '');
        }

        this.showToast(`Switched to ${mode === 'text-to-sign' ? 'Text → Sign' : 'Sign → Text'} mode`, 'success');
        this.clearHistory();
    }

    // ─────────────────────────────────────────────────────────────────────
    // ACTION HANDLERS
    // ─────────────────────────────────────────────────────────────────────

    handleSend() {
        const text = this.textInput.value.trim();
        if (!text) {
            this.showToast('Please enter text', 'warning');
            return;
        }

        this.setLoading(true);

        // Play avatar animation for the word
        if (window.playWord && window.playSign) {
            try {
                // For single words, play directly (spells multi-letter words)
                if (text.split(/\s+/).length === 1) {
                    window.playWord(text);
                    this.updatePrediction(text, 0.92, []);
                    this.addToHistory(text, 0.92);
                    this.textInput.value = '';
                    this.repeatBtn.disabled = false;
                    this.showToast(`Animating: ${text}`, 'success');
                    this.setLoading(false);
                } else {
                    // For multiple words, try API first for sequence
                    if (window.apiClient) {
                        window.apiClient.translateTextToASL(text)
                            .then(result => {
                                if (result && result.animation_sequence) {
                                    const words = result.animation_sequence;
                                    this.updatePrediction(text, 0.92, []);
                                    
                                    // Play each animation in sequence with timing
                                    words.forEach((w, i) => {
                                        setTimeout(() => {
                                            window.playSign(w);
                                        }, i * 1800); // 1.8s per sign
                                    });
                                    
                                    this.showToast(`Playing ${words.length} signs`, 'success');
                                }
                            })
                            .catch(err => {
                                console.warn('Translation API failed:', err);
                                // Fallback: play each word individually
                                const words = text.split(/\s+/);
                                words.forEach((w, i) => {
                                    setTimeout(() => {
                                        window.playSign(w);
                                    }, i * 1800);
                                });
                                this.showToast(`Playing ${words.length} signs (API unavailable)`, 'info');
                            })
                            .finally(() => {
                                this.addToHistory(text, 0.92);
                                this.textInput.value = '';
                                this.setLoading(false);
                            });
                    } else {
                        // No API, just play words
                        const words = text.split(/\s+/);
                        words.forEach((w, i) => {
                            setTimeout(() => {
                                window.playSign(w);
                            }, i * 1800);
                        });
                        this.addToHistory(text, 0.92);
                        this.textInput.value = '';
                        this.showToast(`Playing ${words.length} signs`, 'success');
                        this.setLoading(false);
                    }
                }
            } catch (err) {
                console.error('Animation error:', err);
                this.showToast('Error playing animation: ' + err.message, 'error');
                this.setLoading(false);
            }
        } else {
            this.showToast('Animation system not ready', 'error');
            this.setLoading(false);
        }
    }

    handleSpeak() {
        if (this.speakBtn.classList.contains('active')) {
            this.speakBtn.classList.remove('active');
            this.showToast('Speech recognition stopped', 'info');
        } else {
            this.speakBtn.classList.add('active');
            this.showToast('Listening...', 'info');

            // Use Web Speech API if available
            if ('webkitSpeechRecognition' in window || 'SpeechRecognition' in window) {
                const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
                const recognition = new SpeechRecognition();
                recognition.continuous = false;
                recognition.interimResults = false;
                recognition.lang = 'en-US';

                recognition.onresult = (event) => {
                    const transcript = event.results[0][0].transcript;
                    this.textInput.value = transcript;
                    this.speakBtn.classList.remove('active');
                    this.showToast('Speech recognized', 'success');
                };

                recognition.onerror = () => {
                    this.speakBtn.classList.remove('active');
                    this.showToast('Speech recognition error', 'error');
                };

                recognition.onend = () => {
                    this.speakBtn.classList.remove('active');
                };

                recognition.start();
                this._recognition = recognition;
            } else {
                // Fallback: call backend speech API
                if (window.apiClient) {
                    window.apiClient.recognizeSpeech().then(result => {
                        if (result && result.text) {
                            this.textInput.value = result.text;
                        }
                    }).catch(() => {
                        this.showToast('Speech recognition not available', 'error');
                    }).finally(() => {
                        this.speakBtn.classList.remove('active');
                    });
                } else {
                    this.speakBtn.classList.remove('active');
                    this.showToast('Speech recognition not available', 'error');
                }
            }
        }
    }

    handleRepeat() {
        if (window.repeatLastSign) {
            window.repeatLastSign();
            const lastWord = window.lastPlayedWordFn ? window.lastPlayedWordFn() : '';
            if (lastWord) {
                this.showToast(`Repeating: ${lastWord}`, 'success');
            }
        } else {
            this.showToast('No previous sign to repeat', 'warning');
        }
    }

    handleRecord() {
        this.isRecording = !this.isRecording;

        if (this.isRecording) {
            this.recordBtn.classList.add('active');
            this.recordBtn.innerHTML = '<i class="fas fa-stop"></i> Recording...';
            this.showToast('Recording started', 'success');
        } else {
            this.recordBtn.classList.remove('active');
            this.recordBtn.innerHTML = '<i class="fas fa-circle"></i> Record';
            this.showToast('Recording saved', 'success');
        }
    }

    handleClear() {
        this.clearHistory();
        this.clearAlternatives();
        this.textInput.value = '';
        this.currentPrediction.textContent = '-';
        this.confidenceBar.style.width = '0%';
        this.confidenceMeter.textContent = '0%';
        this.showToast('Cleared', 'info');
    }

    // ─────────────────────────────────────────────────────────────────────
    // PREDICTION & DISPLAY
    // ─────────────────────────────────────────────────────────────────────

    updatePrediction(word, confidence, alternatives = []) {
        // Update current prediction (text-to-sign feedback panel)
        if (this.currentPrediction) this.currentPrediction.textContent = word;

        // Update confidence (text-to-sign)
        const confidencePercent = Math.round(confidence * 100);
        if (this.confidenceMeter) this.confidenceMeter.textContent = confidencePercent + '%';
        if (this.confidenceBar) this.confidenceBar.style.width = confidencePercent + '%';

        // Update alternatives (text-to-sign)
        this.clearAlternatives();
        alternatives.forEach(alt => {
            this.addAlternative(alt.word, alt.confidence);
        });

        // Update confidence bar in sign-to-text panel
        const resultConfBar = document.getElementById('textResultConfBar');
        const resultConfValue = document.getElementById('textResultConfValue');
        if (resultConfBar) resultConfBar.style.width = confidencePercent + '%';
        if (resultConfValue) resultConfValue.textContent = confidencePercent + '%';

        // ════════════════════════════════════════════════════════════════
        // WORD BUILDER — only active in sign-to-text mode
        // ════════════════════════════════════════════════════════════════

        if (this.currentMode !== 'sign-to-text') return;

        const isNoise = ['NOTHING', 'NO_MODEL', 'ERROR', 'BAD_FRAME', 'NO_FRAME'].includes(word);

        if (isNoise) {
            this.wordConsecutive = 0;
            this.wordLastRaw = null;

            // If buffer has letters, keep showing them (timer will commit)
            if (this.wordBuffer.length === 0) {
                this.renderSpelling();
                this.setSpellingStatus('idle', '');
            }
            return;
        }

        // Suppress letter re-add for 500ms after a Backspace (prevents race condition)
        if (this._backspaceAt && Date.now() - this._backspaceAt < 500) {
            this.wordConsecutive = 0;
            this.wordLastRaw = null;
            return;
        }

        // It's a letter prediction — apply stability gating
        if (this.wordLastRaw === word) {
            this.wordConsecutive++;
        } else {
            this.wordConsecutive = 1;
            this.wordLastRaw = word;
            this.setSpellingStatus('spelling', `Detecting ${word}...`);
            return;
        }

        // Check if letter passed stability threshold
        if (this.wordConsecutive >= this.STABILITY_THRESHOLD && word !== this.wordStableLetter) {
            this.wordStableLetter = word;
            this.wordStableConfidence = confidence;
            this.wordBuffer.push(word);

            // Reset commit timer
            this.resetCommitTimer();

            // Update UI
            this.renderSpelling();
            this.setSpellingStatus('spelling', `Comitting in ${this.COMMIT_DELAY / 1000}s`);

            const placeholder = document.getElementById('webcamPlaceholder');
            if (placeholder) placeholder.classList.add('hidden');
        } else if (this.wordConsecutive >= this.STABILITY_THRESHOLD) {
            this.setSpellingStatus('spelling', `Locked: ${word}`);
        } else {
            this.setSpellingStatus('spelling', `${word} (${this.STABILITY_THRESHOLD - this.wordConsecutive} more)`);
        }

        // Update info message
        this.updateInfo(`Prediction: ${word} (${confidencePercent}% confident)`);
    }

    resetCommitTimer() {
        if (this.commitTimer) {
            clearTimeout(this.commitTimer);
        }
        this.commitTimer = setTimeout(() => {
            this.commitWord();
        }, this.COMMIT_DELAY);
    }

    commitWord() {
        if (this.wordBuffer.length === 0) return;

        const word = this.wordBuffer.join('');
        this.wordSentence.push(word);
        this.wordBuffer = [];
        this.wordStableLetter = null;
        this.wordConsecutive = 0;
        this.wordLastRaw = null;
        this.commitTimer = null;

        this.renderSentence();
        this.renderSpelling();
        this.setSpellingStatus('idle', 'Word committed');

        // Add to history
        this.addToHistory(word, this.wordStableConfidence || 0);
    }

    renderSpelling() {
        const el = document.getElementById('textResultSpelling');
        if (!el) return;

        if (this.wordBuffer.length === 0) {
            el.innerHTML = '<span class="spelling-placeholder">&mdash;</span>';
            return;
        }

        el.innerHTML = this.wordBuffer.map((letter, i) => {
            const cls = i === this.wordBuffer.length - 1 ? 'letter-tile latest' : 'letter-tile';
            return `<span class="${cls}">${this.escapeHtml(letter)}</span>`;
        }).join('');
    }

    renderSentence() {
        const el = document.getElementById('textResultSentence');
        if (!el) return;

        if (this.wordSentence.length === 0) {
            el.innerHTML = '<span class="sentence-empty">Start spelling...</span>';
            return;
        }

        el.innerHTML = this.wordSentence
            .map(item => {
                if (item === ' ') {
                    return '<span class="sentence-space">&nbsp;&nbsp;</span>';
                }
                return `<span class="sentence-word">${this.escapeHtml(item)}</span>`;
            })
            .join('');
    }

    setSpellingStatus(state, msg) {
        const el = document.getElementById('textResultStatus');
        if (!el) return;

        const clsMap = { idle: 'status-idle', spelling: 'status-spelling', committing: 'status-committing' };
        el.className = 'text-result-status ' + (clsMap[state] || 'status-idle');
        el.textContent = msg;
    }

    handleSignBackspace() {
        // Mark the time so prediction loop doesn't re-add a letter immediately
        this._backspaceAt = Date.now();

        // 1) Remove last letter from current word buffer
        if (this.wordBuffer.length > 0) {
            this.wordBuffer.pop();
            this.wordStableLetter = this.wordBuffer.length > 0 ? this.wordBuffer[this.wordBuffer.length - 1] : null;
            this.wordConsecutive = 0;
            this.wordLastRaw = null;

            if (this.wordBuffer.length > 0) {
                this.resetCommitTimer();
            } else {
                if (this.commitTimer) {
                    clearTimeout(this.commitTimer);
                    this.commitTimer = null;
                }
            }

            this.renderSpelling();
            this.setSpellingStatus('spelling', 'Letter removed');
            this.showToast('Letter removed', 'info');
            return;
        }

        // 2) Buffer empty — remove last committed word from sentence
        if (this.wordSentence.length > 0) {
            // Pop trailing space if present, then pop the word
            if (this.wordSentence[this.wordSentence.length - 1] === ' ') {
                this.wordSentence.pop();
            }
            if (this.wordSentence.length > 0) {
                const removed = this.wordSentence.pop();
                this.renderSentence();
                this.setSpellingStatus('idle', `Removed "${removed}"`);
                this.showToast(`Removed "${removed}"`, 'info');
                return;
            }
        }

        // 3) Nothing to delete
        this.setSpellingStatus('idle', 'Nothing to delete');
        this.showToast('Nothing to delete', 'warning');
    }

    handleSignSpace() {
        // Commit current word if any letters in buffer
        if (this.wordBuffer.length > 0) {
            const word = this.wordBuffer.join('');
            this.wordSentence.push(word);
            this.addToHistory(word, this.wordStableConfidence || 0);
        }

        // Add visible space marker
        this.wordSentence.push(' ');

        // Reset word builder state
        this.wordBuffer = [];
        this.wordStableLetter = null;
        this.wordConsecutive = 0;
        this.wordLastRaw = null;
        if (this.commitTimer) {
            clearTimeout(this.commitTimer);
            this.commitTimer = null;
        }

        this.renderSentence();
        this.renderSpelling();
        this.setSpellingStatus('idle', 'Space inserted');
    }

    // ─────────────────────────────────────────────────────────────────────
    // HISTORY MANAGEMENT
    // ─────────────────────────────────────────────────────────────────────

    addToHistory(text, confidence) {
        const item = { text, confidence, timestamp: new Date() };
        this.history.unshift(item);

        if (this.history.length > this.maxHistoryItems) {
            this.history.pop();
        }

        this.renderHistory();

        // Also update sign-to-text history panel
        const historyList = document.getElementById('resultHistoryList');
        if (historyList) {
            // Remove empty message if present
            const empty = historyList.querySelector('.empty-msg');
            if (empty) empty.remove();

            const div = document.createElement('div');
            div.className = 'history-sign-item';
            div.innerHTML = `<span class="hs-word">${this.escapeHtml(text)}</span><span class="hs-conf">${Math.round(confidence * 100)}%</span>`;
            historyList.insertBefore(div, historyList.firstChild);
        }
    }

    escapeHtml(text) {
        const d = document.createElement('div');
        d.textContent = text;
        return d.innerHTML;
    }

    clearHistory() {
        this.history = [];
        this.renderHistory();

        // Also clear sign-to-text history panel
        const historyList = document.getElementById('resultHistoryList');
        if (historyList) {
            historyList.innerHTML = '<span class="empty-msg">No signs recognized yet</span>';
        }

        // Clear word builder state
        this.wordSentence = [];
        this.wordBuffer = [];
        this.wordStableLetter = null;
        this.wordConsecutive = 0;
        this.wordLastRaw = null;
        if (this.commitTimer) {
            clearTimeout(this.commitTimer);
            this.commitTimer = null;
        }
        this.renderSentence();
        this.renderSpelling();
        this.setSpellingStatus('idle', '');

        // Reset result panel confidence
        const resultConfBar = document.getElementById('textResultConfBar');
        const resultConfValue = document.getElementById('textResultConfValue');
        if (resultConfBar) resultConfBar.style.width = '0%';
        if (resultConfValue) resultConfValue.textContent = '0%';
    }

    renderHistory() {
        if (this.history.length === 0) {
            this.historyList.innerHTML = `
                <div class="empty-state">
                    <i class="fas fa-inbox"></i>
                    <p>No predictions yet</p>
                </div>
            `;
            return;
        }

        this.historyList.innerHTML = '';
        this.history.forEach(item => {
            const div = document.createElement('div');
            div.className = 'history-item fade-in';
            const textDiv = document.createElement('div');
            textDiv.className = 'history-item-text';
            const strong = document.createElement('strong');
            strong.textContent = item.text;
            const confDiv = document.createElement('div');
            confDiv.className = 'history-item-confidence';
            confDiv.textContent = Math.round(item.confidence * 100) + '%';
            textDiv.appendChild(strong);
            textDiv.appendChild(confDiv);
            div.appendChild(textDiv);
            this.historyList.appendChild(div);
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    // ALTERNATIVES MANAGEMENT
    // ─────────────────────────────────────────────────────────────────────

    addAlternative(word, confidence) {
        const item = document.createElement('div');
        item.className = 'alternative-item fade-in';
        const textSpan = document.createElement('span');
        textSpan.className = 'alternative-text';
        textSpan.textContent = word;
        const confSpan = document.createElement('span');
        confSpan.className = 'alternative-confidence';
        confSpan.textContent = Math.round(confidence * 100) + '%';
        item.appendChild(textSpan);
        item.appendChild(confSpan);
        item.addEventListener('click', () => this.selectAlternative(word));
        this.alternativesList.appendChild(item);
    }

    selectAlternative(word) {
        this.textInput.value = word;
        this.textInput.focus();
        this.showToast(`Selected: ${word}`, 'info');
    }

    clearAlternatives() {
        if (this.alternativesList.firstElementChild?.classList.contains('empty-state')) {
            return;
        }
        this.alternativesList.innerHTML = `
            <div class="empty-state">
                <i class="fas fa-lightbulb"></i>
                <p>Alternatives will appear here</p>
            </div>
        `;
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATUS & NOTIFICATIONS
    // ─────────────────────────────────────────────────────────────────────

    updateStatus(type, message) {
        this.statusIndicator.className = `status-indicator ${type === 'offline' ? 'offline' : ''}`;
        this.statusText.textContent = message;
    }

    updateInfo(message) {
        this.infoMessage.textContent = message;
    }

    showToast(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `toast ${type} fade-in`;

        let icon = 'fas fa-info-circle';
        if (type === 'success') icon = 'fas fa-check-circle';
        if (type === 'error') icon = 'fas fa-times-circle';
        if (type === 'warning') icon = 'fas fa-exclamation-circle';

        const iconEl = document.createElement('i');
        iconEl.className = icon;
        const spanEl = document.createElement('span');
        spanEl.textContent = message;
        toast.appendChild(iconEl);
        toast.appendChild(spanEl);
        this.toastContainer.appendChild(toast);

        setTimeout(() => {
            toast.style.animation = 'slideOut 300ms ease-in';
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    }

    // ─────────────────────────────────────────────────────────────────────
    // SETTINGS
    // ─────────────────────────────────────────────────────────────────────

    toggleSettings() {
        const isHidden = this.settingsPanel.style.display === 'none';
        this.settingsPanel.style.display = isHidden ? 'block' : 'none';
        this.settingsBtn.classList.toggle('active');
    }

    updateSettings() {
        const threshold = this.confidenceThreshold.value / 100;
        const speed = this.animationSpeed.value;
        
        // Dispatch custom event for other components
        window.dispatchEvent(new CustomEvent('settingsChanged', {
            detail: { threshold, speed }
        }));
    }

    // ─────────────────────────────────────────────────────────────────────
    // METRICS
    // ─────────────────────────────────────────────────────────────────────

    startMetricsUpdate() {
        let frameCount = 0;
        let lastTime = performance.now();

        const updateMetrics = () => {
            frameCount++;
            const currentTime = performance.now();
            const elapsed = currentTime - lastTime;

            if (elapsed >= 1000) {
                this.fpsMeter.textContent = Math.round((frameCount * 1000) / elapsed);
                frameCount = 0;
                lastTime = currentTime;
            }

            requestAnimationFrame(updateMetrics);
        };

        updateMetrics();
    }

    updateLatency(ms) {
        this.latencyMeter.textContent = ms.toFixed(0) + 'ms';
    }

    // ─────────────────────────────────────────────────────────────────────
    // UI STATE
    // ─────────────────────────────────────────────────────────────────────

    setLoading(isLoading) {
        this.sendBtn.disabled = isLoading;
        this.textInput.disabled = isLoading;
        
        if (isLoading) {
            this.sendBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';
        } else {
            this.sendBtn.innerHTML = '<i class="fas fa-paper-plane"></i>';
        }
    }

    showHelp() {
        const helpMessage = `
BridgeSign AI Help:

Text to Sign Mode:
- Enter text and click Send
- Avatar will perform sign language gestures
- Click alternatives for different interpretations

Sign to Text Mode:
- Enable your camera
- Perform sign language gestures
- System will recognize and show text

Tips:
- Good lighting improves recognition
- Steady hand movements work better
- Keep hands visible in camera view
        `;
        alert(helpMessage);
    }
}

// Initialize UI Manager when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    window.uiManager = new UIManager();
    console.log('✅ UI Manager initialized');
});
