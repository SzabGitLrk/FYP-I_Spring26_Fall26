#!/bin/bash
echo "============================================================"
echo " SAGE — Smart Academic Guide & Engine — Setup Script"
echo "============================================================"
echo ""

# Step 1: Check Python
if ! command -v python3 &>/dev/null; then
    echo "[ERROR] Python 3 not found. Install Python 3.10+ first."
    exit 1
fi
echo "[OK] Python found: $(python3 --version)"

# Step 2: Create virtual environment
if [ ! -d "sage_env" ]; then
    echo "[STEP] Creating virtual environment..."
    python3 -m venv sage_env
    echo "[OK] Virtual environment created."
else
    echo "[OK] Virtual environment already exists."
fi

# Step 3: Activate and install
echo "[STEP] Installing dependencies (may take a few minutes)..."
source sage_env/bin/activate
pip install -r requirements.txt

if [ $? -ne 0 ]; then
    echo "[ERROR] pip install failed."
    exit 1
fi

echo ""
echo "[OK] All packages installed."
echo ""
echo "============================================================"
echo " NEXT STEPS:"
echo " 1. Install Ollama: curl -fsSL https://ollama.com/install.sh | sh"
echo " 2. Pull the model: ollama pull phi3.5"
echo " 3. Keep Ollama running: ollama serve"
echo " 4. Run SAGE:"
echo "      source sage_env/bin/activate"
echo "      python main.py"
echo "============================================================"
