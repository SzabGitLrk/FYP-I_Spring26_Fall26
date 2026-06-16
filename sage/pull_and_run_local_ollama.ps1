try {
    $ErrorActionPreference = 'Stop'
    $zip = Join-Path $env:TEMP 'ollama-windows-amd64.zip'
    $url = 'https://github.com/ollama/ollama/releases/download/v0.20.2/ollama-windows-amd64.zip'
    Write-Output "Downloading $url to $zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

    $dest = 'C:\Tools\ollama'
    Write-Output "Extracting to $dest"
    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force

    Set-Location $dest
    Write-Output "Extracted files (top 20):"
    Get-ChildItem -File -Recurse | Select-Object -First 20 | ForEach-Object { Write-Output $_.FullName }

    Write-Output "Checking ollama binary"
    $ollamaExe = Join-Path $dest 'ollama.exe'
    if (-not (Test-Path $ollamaExe)) { Write-Output 'ERROR: ollama.exe not found in extracted folder'; exit 2 }

    Write-Output "Running ollama --help"
    & $ollamaExe --help | Select-Object -First 40 | ForEach-Object { Write-Output $_ }

    Write-Output "Pulling mistral:7b-instruct-q4_0"
    & $ollamaExe pull mistral:7b-instruct-q4_0 2>&1 | Tee-Object -Variable pullout
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'Pull failed. Last 40 lines of output:'
        $pullout | Select-Object -Last 40 | ForEach-Object { Write-Output $_ }
        exit 3
    }

    Write-Output 'Pull succeeded.'
    Write-Output 'Starting ollama serve in background'
    $proc = Start-Process -FilePath $ollamaExe -ArgumentList 'serve' -PassThru
    Write-Output "Started process ID: $($proc.Id)"
    Start-Sleep -Seconds 8

    Write-Output 'Checking API /api/tags'
    try {
        $r = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 20
        Write-Output 'API OK'
        $r | ConvertTo-Json -Depth 5 | ForEach-Object { Write-Output $_ }
    } catch {
        Write-Output 'API check failed: ' + $_.Exception.Message
        exit 4
    }

    Write-Output 'Running pytest'
    Set-Location 'D:\FYP PROJECT DEMO\sage'
    .\sage_env\Scripts\python.exe -m pytest tests/ -q

} catch {
    Write-Output 'Script error: ' + $_.Exception.Message
    exit 9
}
