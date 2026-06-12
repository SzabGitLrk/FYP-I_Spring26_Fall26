$env:TF_CPP_MIN_LOG_LEVEL = "3"
$env:TF_ENABLE_ONEDNN_OPTS = "0"
$env:TF_CPP_MAX_PARALLELISM = "4"
$env:FLASK_ENV = "development"
$env:CORS_ORIGINS = "*"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# Kill any leftover servers from previous runs
Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match "flask|server.py|backend.app"
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2

# Start Flask API backend on port 5001 (hidden window)
Write-Host "[1/2] Starting Flask API backend on :5001 ..." -ForegroundColor Yellow
$flaskProc = Start-Process -FilePath "venv\Scripts\python.exe" `
    -ArgumentList @("-W", "ignore", "-m", "flask", "--app", "backend.app", "run", "--port", "5001", "--no-reload") `
    -WindowStyle Hidden -PassThru

# Start sign-to-text prediction server on port 5002 (hidden window)
Start-Sleep 3
Write-Host "[2/2] Starting Sign-to-Text server on :5002 ..." -ForegroundColor Yellow
$predProc = Start-Process -FilePath "venv\Scripts\python.exe" `
    -ArgumentList @("-W", "ignore", "backend\server.py") `
    -WindowStyle Hidden -PassThru

# Save PIDs so we can clean up later
$flaskProc.Id | Out-File "$root\.flask_pid" -Force
$predProc.Id | Out-File "$root\.pred_pid" -Force

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Both servers started in background!" -ForegroundColor Green
Write-Host "  Flask API:     http://localhost:5001" -ForegroundColor Cyan
Write-Host "  Sign-to-Text:  http://localhost:5002" -ForegroundColor Cyan
Write-Host "  Open WebApp at http://localhost:8000" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Green

Write-Host ""
Write-Host "To stop servers later, run:  Stop-Process -Id $($flaskProc.Id), $($predProc.Id) -Force" -ForegroundColor Gray
