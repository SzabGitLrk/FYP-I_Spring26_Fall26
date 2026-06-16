$paths = @(
    'C:\Users\ABBAS\AppData\Local\Temp\ollama-portable\ollama.exe',
    'C:\Users\ABBAS\AppData\Local\Microsoft\WinGet\Packages\Ollama.Ollama.Portable_Microsoft.Winget.Source_8wekyb3d8bbwe\ollama.exe'
)
$ollama = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
if(-not $ollama) {
    Write-Output 'ERROR: ollama.exe not found'
    exit 2
}
$root = Split-Path $ollama -Parent
$vc = Join-Path $root 'vc_redist.x64.exe'
if(Test-Path $vc){
    Write-Output 'Running vc_redist.x64.exe (silent)'
    Start-Process -FilePath $vc -ArgumentList '/quiet','/norestart' -Wait
} else {
    Write-Output 'vc_redist not found, skipping.'
}
Write-Output "Using ollama: $ollama"
Write-Output 'Pulling mistral:7b-instruct-q4_0 (may take several minutes)...'
& $ollama pull mistral:7b-instruct-q4_0 2>&1 | Tee-Object -Variable pullout
if($LASTEXITCODE -ne 0){
    Write-Output 'Pull failed, output:'
    $pullout | Select-Object -Last 50
    exit 3
}
Write-Output 'Pull complete.'
Write-Output 'Starting Ollama server...'
$proc = Start-Process -FilePath $ollama -ArgumentList 'serve' -PassThru
Start-Sleep -Seconds 6
try{
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
    Write-Output 'API OK'
    $r | ConvertTo-Json -Depth 5 | Write-Output
} catch {
    Write-Output 'API check failed:'
    Write-Output $_.Exception.Message
    exit 4
}
Write-Output 'Running pytest...'
Set-Location 'D:\FYP PROJECT DEMO\sage'
.\sage_env\Scripts\python.exe -m pytest tests/ -q
