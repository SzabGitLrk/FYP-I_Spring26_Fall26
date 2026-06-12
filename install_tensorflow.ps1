# Install TensorFlow (this is a large ~350MB download, may take 10-20 minutes)
Write-Host "Installing TensorFlow... This may take a while." -ForegroundColor Yellow
& "venv\Scripts\python.exe" -m pip install tensorflow
if ($?) {
    Write-Host "TensorFlow installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Failed to install TensorFlow. Try running manually:" -ForegroundColor Red
    Write-Host "  .\venv\Scripts\python.exe -m pip install tensorflow"
}
