$os = Get-CimInstance Win32_OperatingSystem
$totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeGB  = [math]::Round($os.FreePhysicalMemory  / 1MB, 2)
Write-Output ("Total RAM (GB): " + $totalGB)
Write-Output ("Free  RAM (GB): " + $freeGB)
Write-Output "---"
Write-Output "Ollama process(es):"
$ol = Get-Process -Name ollama -ErrorAction SilentlyContinue
if ($ol) {
    $ol | Select-Object Name, Id, @{n='WS_MB'; e={[math]::Round($_.WorkingSet/1MB,1)}} | Format-Table -AutoSize
} else {
    Write-Output "  (ollama not running)"
}
Write-Output "---"
Write-Output "Top 5 memory consumers:"
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 Name, Id, @{n='WS_MB'; e={[math]::Round($_.WorkingSet/1MB,1)}} | Format-Table -AutoSize
Write-Output "---"
Write-Output "Installed Ollama models:"
$candidates = @(
    'C:\Tools\ollama\ollama.exe',
    'C:\Users\ABBAS\AppData\Local\Temp\ollama-portable\ollama.exe',
    'C:\Users\ABBAS\AppData\Local\Microsoft\WinGet\Packages\Ollama.Ollama.Portable_Microsoft.Winget.Source_8wekyb3d8bbwe\ollama.exe'
)
$exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($exe) {
    Write-Output ("Using: " + $exe)
    & $exe list
} else {
    Write-Output "No ollama.exe found in known locations."
}
