# start.ps1 - Startet alle Dienste des lokalen KI-Assistenten

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$buildScript = Join-Path $projektVerzeichnis "scripts\build-config.ps1"
$venvPfad = Join-Path $projektVerzeichnis ".venv"
$mcpoPidDatei = Join-Path $projektVerzeichnis ".mcpo.pid"
$openwebuiPidDatei = Join-Path $projektVerzeichnis ".openwebui.pid"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lokaler KI-Assistent - Start" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Virtual Environment aktivieren ---

$aktivierungsScript = Join-Path $venvPfad "Scripts\Activate.ps1"
if (Test-Path $aktivierungsScript) {
    & $aktivierungsScript
    Write-Host "[OK] Virtual Environment aktiviert" -ForegroundColor Green
}
else {
    Write-Host "WARNUNG: Kein Virtual Environment gefunden. Bitte zuerst setup.ps1 ausfuehren." -ForegroundColor Yellow
}

# --- Outlook-Prüfung ---

Write-Host ""
Write-Host "[1/4] Outlook pruefen..." -ForegroundColor Yellow

try {
    $outlookProzess = Get-Process OUTLOOK -ErrorAction SilentlyContinue
    if ($outlookProzess) {
        Write-Host "  [OK] Outlook ist geoeffnet" -ForegroundColor Green
    }
    else {
        Write-Host "  WARNUNG: Outlook scheint nicht geoeffnet zu sein." -ForegroundColor Yellow
        Write-Host "  Bitte starte Microsoft Outlook, damit das E-Mail-Plugin funktioniert." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Outlook-Status konnte nicht geprueft werden." -ForegroundColor Gray
}

# --- MCPO-Konfiguration bauen ---

Write-Host ""
Write-Host "[2/4] MCPO-Konfiguration aktualisieren..." -ForegroundColor Yellow
try {
    & $buildScript
}
catch {
    Write-Host "  FEHLER: build-config.ps1 fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Ollama starten/prüfen ---

Write-Host ""
Write-Host "[3/4] Ollama pruefen/starten..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 3 -ErrorAction SilentlyContinue
    Write-Host "  [OK] Ollama laeuft bereits auf Port 11434" -ForegroundColor Green
}
catch {
    Write-Host "  Starte Ollama..." -ForegroundColor Gray
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 3

    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5
        Write-Host "  [OK] Ollama gestartet auf Port 11434" -ForegroundColor Green
    }
    catch {
        Write-Host "  WARNUNG: Ollama konnte nicht gestartet werden." -ForegroundColor Yellow
        Write-Host "  Bitte starte Ollama manuell: ollama serve" -ForegroundColor Yellow
    }
}

# --- MCPO starten ---

Write-Host ""
Write-Host "[4/4] Dienste starten..." -ForegroundColor Yellow

$configDatei = Join-Path $projektVerzeichnis "mcpo-config.json"

# Prüfe ob MCPO schon läuft
if (Test-Path $mcpoPidDatei) {
    $alterPid = Get-Content $mcpoPidDatei
    $prozess = Get-Process -Id $alterPid -ErrorAction SilentlyContinue
    if ($prozess) {
        Write-Host "  MCPO laeuft bereits (PID: $alterPid). Beende alten Prozess..." -ForegroundColor Yellow
        Stop-Process -Id $alterPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

# MCPO mit Hot-Reload starten
Write-Host "  Starte MCPO (Port 8000, Hot-Reload)..." -ForegroundColor Gray
# Versuche zuerst den direkten Befehl, dann Fallback auf python -m
$mcpoExe = Get-Command mcpo -ErrorAction SilentlyContinue
if ($mcpoExe) {
    $mcpoProzess = Start-Process -FilePath "mcpo" -ArgumentList "--config", $configDatei, "--port", "8000", "--hot-reload" -WindowStyle Hidden -PassThru
} else {
    $pythonExe = Join-Path $venvPfad "Scripts\python.exe"
    $mcpoProzess = Start-Process -FilePath $pythonExe -ArgumentList "-m", "mcpo", "--config", $configDatei, "--port", "8000", "--hot-reload" -WindowStyle Hidden -PassThru
}
$mcpoProzess.Id | Set-Content $mcpoPidDatei
Write-Host "  [OK] MCPO gestartet (PID: $($mcpoProzess.Id))" -ForegroundColor Green
Write-Host "       http://localhost:8000" -ForegroundColor Cyan

# Prüfe ob Open WebUI schon läuft
if (Test-Path $openwebuiPidDatei) {
    $alterPid = Get-Content $openwebuiPidDatei
    $prozess = Get-Process -Id $alterPid -ErrorAction SilentlyContinue
    if ($prozess) {
        Write-Host "  Open WebUI laeuft bereits (PID: $alterPid). Beende alten Prozess..." -ForegroundColor Yellow
        Stop-Process -Id $alterPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

# Open WebUI starten
Write-Host "  Starte Open WebUI (Port 8080)..." -ForegroundColor Gray
$openwebuiLog = Join-Path $projektVerzeichnis "openwebui.log"
$openwebuiErrorLog = Join-Path $projektVerzeichnis "openwebui-error.log"
$env:OLLAMA_BASE_URL = "http://localhost:11434"
$env:PYTHONUTF8 = "1"
# Versuche: 1) open-webui im PATH, 2) open-webui.exe im venv Scripts-Ordner
$openwebuiExe = Get-Command open-webui -ErrorAction SilentlyContinue
if (-not $openwebuiExe) {
    # Fallback: direkt im venv Scripts-Ordner suchen
    $venvOpenWebui = Join-Path $venvPfad "Scripts\open-webui.exe"
    if (Test-Path $venvOpenWebui) {
        $openwebuiExe = $venvOpenWebui
    }
}
if ($openwebuiExe) {
    $exePath = if ($openwebuiExe -is [string]) { $openwebuiExe } else { $openwebuiExe.Source }
    $openwebuiProzess = Start-Process -FilePath $exePath -ArgumentList "serve" -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $openwebuiLog -RedirectStandardError $openwebuiErrorLog
} else {
    Write-Host "  [FEHLER] open-webui nicht gefunden! Bitte installieren:" -ForegroundColor Red
    Write-Host "  pip install open-webui" -ForegroundColor Yellow
    $openwebuiProzess = $null
}
$bereit = $false
if ($openwebuiProzess) {
    $openwebuiProzess.Id | Set-Content $openwebuiPidDatei

    # Warte bis Open WebUI tatsaechlich auf Port 8080 antwortet
    $maxVersuche = 30
    $versuch = 0
    Write-Host "  Warte auf Open WebUI..." -ForegroundColor Gray
    while ($versuch -lt $maxVersuche) {
        Start-Sleep -Seconds 2
        $versuch++
        # Prüfe ob der Prozess noch lebt
        $proc = Get-Process -Id $openwebuiProzess.Id -ErrorAction SilentlyContinue
        if (-not $proc) {
            Write-Host "  [FEHLER] Open WebUI Prozess ist abgestuerzt!" -ForegroundColor Red
            Write-Host "  Pruefe die Logdateien:" -ForegroundColor Yellow
            Write-Host "    $openwebuiLog" -ForegroundColor Yellow
            Write-Host "    $openwebuiErrorLog" -ForegroundColor Yellow
            if (Test-Path $openwebuiErrorLog) {
                Write-Host "  Fehlerlog:" -ForegroundColor Yellow
                Get-Content $openwebuiErrorLog | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            }
            break
        }
        try {
            $null = Invoke-WebRequest -Uri "http://localhost:8080" -Method Head -TimeoutSec 2 -ErrorAction Stop
            $bereit = $true
            break
        } catch {
            if ($versuch % 5 -eq 0) {
                Write-Host "  Noch nicht bereit... ($versuch/$maxVersuche)" -ForegroundColor Gray
            }
        }
    }
    if ($bereit) {
        Write-Host "  [OK] Open WebUI gestartet (PID: $($openwebuiProzess.Id))" -ForegroundColor Green
        Write-Host "       http://localhost:8080" -ForegroundColor Cyan
    } elseif (Get-Process -Id $openwebuiProzess.Id -ErrorAction SilentlyContinue) {
        Write-Host "  [WARNUNG] Open WebUI Prozess laeuft (PID: $($openwebuiProzess.Id)), antwortet aber noch nicht auf Port 8080." -ForegroundColor Yellow
        Write-Host "  Moeglicherweise braucht der erste Start laenger. Pruefe http://localhost:8080 manuell." -ForegroundColor Yellow
        Write-Host "  Logdatei: $openwebuiLog" -ForegroundColor Yellow
    }
}

# --- Zusammenfassung ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Alle Dienste gestartet!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Ollama:     http://localhost:11434" -ForegroundColor White
Write-Host "  MCPO:       http://localhost:8000   (Hot-Reload aktiv)" -ForegroundColor White
Write-Host "  Open WebUI: http://localhost:8080" -ForegroundColor White
if ($bereit) {
    Write-Host ""
    Write-Host "Oeffne den Browser..." -ForegroundColor Gray
    Start-Process "http://localhost:8080"
} else {
    Write-Host ""
    Write-Host "Browser wird nicht automatisch geoeffnet - Open WebUI ist noch nicht bereit." -ForegroundColor Yellow
    Write-Host "Oeffne http://localhost:8080 manuell, sobald der Dienst bereit ist." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Zum Beenden: .\scripts\stop.ps1" -ForegroundColor Cyan
Write-Host "Neues Plugin hinzufuegen: .\scripts\add-server.ps1 (MCPO laedt automatisch nach)" -ForegroundColor Cyan
