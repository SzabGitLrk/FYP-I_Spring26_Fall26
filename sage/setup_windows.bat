@echo off
echo ============================================================
echo  SAGE — Smart Academic Guide ^& Engine — Setup Script
echo ============================================================
echo.

REM Step 1: Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found. Install Python 3.10+ from python.org
    pause
    exit /b 1
)
echo [OK] Python found.

REM Step 2: Create virtual environment
if not exist sage_env (
    echo [STEP] Creating virtual environment...
    python -m venv sage_env
    echo [OK] Virtual environment created.
) else (
    echo [OK] Virtual environment already exists.
)

REM Step 3: Activate and install
echo [STEP] Installing dependencies (this may take a few minutes)...
call sage_env\Scripts\activate
pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo [ERROR] pip install failed. Check your internet connection.
    pause
    exit /b 1
)
echo [OK] All packages installed.

echo.
echo ============================================================
echo  NEXT STEPS:
echo  1. Install Ollama from https://ollama.com
echo  2. Open a NEW terminal and run: ollama pull phi3.5
echo  3. Keep Ollama running (ollama serve)
echo  4. Run SAGE:
echo       sage_env\Scripts\activate
echo       python main.py
echo ============================================================
pause
