# stop.ps1 - Beendet alle Dienste des lokalen KI-Assistenten

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$mcpoPidDatei = Join-Path $projektVerzeichnis ".mcpo.pid"
$openwebuiPidDatei = Join-Path $projektVerzeichnis ".openwebui.pid"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lokaler KI-Assistent - Stop" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Open WebUI beenden ---

Write-Host "Open WebUI beenden..." -ForegroundColor Yellow
if (Test-Path $openwebuiPidDatei) {
    $pid = Get-Content $openwebuiPidDatei
    try {
        $prozess = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($prozess) {
            Stop-Process -Id $pid -Force
            Write-Host "  [OK] Open WebUI beendet (PID: $pid)" -ForegroundColor Green
        }
        else {
            Write-Host "  Open WebUI war bereits beendet." -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  Konnte Prozess $pid nicht beenden: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Remove-Item $openwebuiPidDatei -Force -ErrorAction SilentlyContinue
}
else {
    # Versuche über Prozessnamen zu finden
    $prozesse = Get-Process -Name "open-webui" -ErrorAction SilentlyContinue
    if ($prozesse) {
        $prozesse | Stop-Process -Force
        Write-Host "  [OK] Open WebUI beendet" -ForegroundColor Green
    }
    else {
        Write-Host "  Open WebUI laeuft nicht." -ForegroundColor Gray
    }
}

# --- MCPO beenden ---

Write-Host "MCPO beenden..." -ForegroundColor Yellow
if (Test-Path $mcpoPidDatei) {
    $pid = Get-Content $mcpoPidDatei
    try {
        $prozess = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($prozess) {
            Stop-Process -Id $pid -Force
            Write-Host "  [OK] MCPO beendet (PID: $pid)" -ForegroundColor Green
        }
        else {
            Write-Host "  MCPO war bereits beendet." -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  Konnte Prozess $pid nicht beenden: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Remove-Item $mcpoPidDatei -Force -ErrorAction SilentlyContinue
}
else {
    $prozesse = Get-Process -Name "mcpo" -ErrorAction SilentlyContinue
    if ($prozesse) {
        $prozesse | Stop-Process -Force
        Write-Host "  [OK] MCPO beendet" -ForegroundColor Green
    }
    else {
        Write-Host "  MCPO laeuft nicht." -ForegroundColor Gray
    }
}

# --- Ollama (optional) ---

Write-Host ""
$ollamaProzess = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
if ($ollamaProzess) {
    Write-Host "Ollama laeuft noch." -ForegroundColor Yellow
    $beenden = Read-Host "Ollama auch beenden? (j/n)"
    if ($beenden -eq "j") {
        $ollamaProzess | Stop-Process -Force
        Write-Host "  [OK] Ollama beendet" -ForegroundColor Green
    }
    else {
        Write-Host "  Ollama laeuft weiter." -ForegroundColor Gray
    }
}

# --- Aufräumen ---

# PID-Dateien aufräumen
Remove-Item (Join-Path $projektVerzeichnis ".mcpo.pid") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $projektVerzeichnis ".openwebui.pid") -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Alle Dienste beendet." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Erneut starten: .\scripts\start.ps1" -ForegroundColor Cyan
