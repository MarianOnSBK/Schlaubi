# start.ps1 - Startet alle Dienste des lokalen KI-Assistenten

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$buildScript = Join-Path $projektVerzeichnis "scripts\build-config.ps1"
$venvPfad = Join-Path $projektVerzeichnis ".venv"
$mcpoPidDatei = Join-Path $projektVerzeichnis ".mcpo.pid"
$openwebuiPidDatei = Join-Path $projektVerzeichnis ".openwebui.pid"
$mcpoLog = Join-Path $projektVerzeichnis "mcpo.log"
$mcpoErrorLog = Join-Path $projektVerzeichnis "mcpo-error.log"
$openwebuiLog = Join-Path $projektVerzeichnis "openwebui.log"
$openwebuiErrorLog = Join-Path $projektVerzeichnis "openwebui-error.log"

# --- Hilfsfunktionen ---

function Stop-ProcessTree {
    param([int]$ParentId)
    try {
        $children = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $ParentId }
        foreach ($child in $children) {
            Stop-ProcessTree -ParentId $child.ProcessId
        }
        Stop-Process -Id $ParentId -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Stop-ProcessOnPort {
    param([int]$Port)
    try {
        $verbindungen = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        foreach ($v in $verbindungen) {
            if ($v.OwningProcess -gt 0) {
                Stop-ProcessTree -ParentId $v.OwningProcess
            }
        }
    } catch {}
}

function Test-PortReady {
    param([int]$Port, [int]$TimeoutSec = 2)
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port" -Method Head -TimeoutSec $TimeoutSec -ErrorAction Stop -UseBasicParsing
        return $true
    } catch {
        # Manche Dienste antworten mit Fehlern auf HEAD, pruefen ob TCP offen ist
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $result = $tcp.BeginConnect("localhost", $Port, $null, $null)
            $success = $result.AsyncWaitHandle.WaitOne($TimeoutSec * 1000)
            $tcp.Close()
            return $success
        } catch {
            return $false
        }
    }
}

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
Write-Host "[1/5] Outlook pruefen..." -ForegroundColor Yellow

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
Write-Host "[2/5] MCPO-Konfiguration aktualisieren..." -ForegroundColor Yellow
try {
    & $buildScript
}
catch {
    Write-Host "  FEHLER: build-config.ps1 fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Ollama starten/prüfen ---

Write-Host ""
Write-Host "[3/5] Ollama pruefen/starten..." -ForegroundColor Yellow

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
Write-Host "[4/5] Dienste starten..." -ForegroundColor Yellow

$configDatei = Join-Path $projektVerzeichnis "mcpo-config.json"

# Alten MCPO-Prozess beenden (PID-Datei + Port-Fallback)
if (Test-Path $mcpoPidDatei) {
    $alterPid = Get-Content $mcpoPidDatei
    try {
        $prozess = Get-Process -Id $alterPid -ErrorAction SilentlyContinue
        if ($prozess) {
            Write-Host "  MCPO laeuft bereits (PID: $alterPid). Beende Prozessbaum..." -ForegroundColor Yellow
            Stop-ProcessTree -ParentId $alterPid
            Start-Sleep -Seconds 1
        }
    } catch {}
    Remove-Item $mcpoPidDatei -Force -ErrorAction SilentlyContinue
}
# Fallback: Port pruefen und belegen Prozess beenden
if (Test-PortReady -Port 8000 -TimeoutSec 1) {
    Write-Host "  Port 8000 ist noch belegt. Beende blockierenden Prozess..." -ForegroundColor Yellow
    Stop-ProcessOnPort -Port 8000
    Start-Sleep -Seconds 1
}

# MCPO mit Hot-Reload starten (mit Logging!)
Write-Host "  Starte MCPO (Port 8000, Hot-Reload)..." -ForegroundColor Gray

$mcpoExe = Get-Command mcpo -ErrorAction SilentlyContinue
if ($mcpoExe) {
    $mcpoPath = $mcpoExe.Source
} else {
    $mcpoPath = Join-Path $venvPfad "Scripts\mcpo.exe"
    if (-not (Test-Path $mcpoPath)) {
        Write-Host "  [FEHLER] mcpo nicht gefunden! Bitte installieren:" -ForegroundColor Red
        Write-Host "  pip install mcpo" -ForegroundColor Yellow
        $mcpoPath = $null
    }
}

$mcpoGestartet = $false
if ($mcpoPath) {
    $mcpoProzess = Start-Process -FilePath $mcpoPath `
        -ArgumentList "--config", $configDatei, "--port", "8000", "--hot-reload" `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $mcpoLog -RedirectStandardError $mcpoErrorLog
    $mcpoProzess.Id | Set-Content $mcpoPidDatei

    # Warte bis MCPO tatsaechlich auf Port 8000 antwortet
    $maxVersuche = 15
    $versuch = 0
    Write-Host "  Warte auf MCPO..." -ForegroundColor Gray
    while ($versuch -lt $maxVersuche) {
        Start-Sleep -Seconds 1
        $versuch++

        # Prüfe ob der Prozess noch lebt
        $proc = Get-Process -Id $mcpoProzess.Id -ErrorAction SilentlyContinue
        if (-not $proc) {
            Write-Host "  [FEHLER] MCPO Prozess ist abgestuerzt!" -ForegroundColor Red
            if (Test-Path $mcpoErrorLog) {
                Write-Host "  Fehlerlog:" -ForegroundColor Yellow
                Get-Content $mcpoErrorLog | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            }
            if (Test-Path $mcpoLog) {
                Write-Host "  Ausgabe:" -ForegroundColor Yellow
                Get-Content $mcpoLog | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
            }
            break
        }

        if (Test-PortReady -Port 8000 -TimeoutSec 1) {
            $mcpoGestartet = $true
            break
        }

        if ($versuch % 5 -eq 0) {
            Write-Host "  Noch nicht bereit... ($versuch/$maxVersuche)" -ForegroundColor Gray
        }
    }

    if ($mcpoGestartet) {
        Write-Host "  [OK] MCPO gestartet (PID: $($mcpoProzess.Id))" -ForegroundColor Green
        Write-Host "       http://localhost:8000" -ForegroundColor Cyan
    } elseif (Get-Process -Id $mcpoProzess.Id -ErrorAction SilentlyContinue) {
        Write-Host "  [WARNUNG] MCPO Prozess laeuft (PID: $($mcpoProzess.Id)), antwortet aber noch nicht." -ForegroundColor Yellow
        Write-Host "  Logdatei: $mcpoLog" -ForegroundColor Yellow
        Write-Host "  Fehlerlog: $mcpoErrorLog" -ForegroundColor Yellow
    }
}

# --- Open WebUI starten ---

# Alten Open WebUI Prozess beenden (PID-Datei + Port-Fallback)
if (Test-Path $openwebuiPidDatei) {
    $alterPid = Get-Content $openwebuiPidDatei
    try {
        $prozess = Get-Process -Id $alterPid -ErrorAction SilentlyContinue
        if ($prozess) {
            Write-Host "  Open WebUI laeuft bereits (PID: $alterPid). Beende Prozessbaum..." -ForegroundColor Yellow
            Stop-ProcessTree -ParentId $alterPid
            Start-Sleep -Seconds 1
        }
    } catch {}
    Remove-Item $openwebuiPidDatei -Force -ErrorAction SilentlyContinue
}
# Fallback: Port pruefen
if (Test-PortReady -Port 8080 -TimeoutSec 1) {
    Write-Host "  Port 8080 ist noch belegt. Beende blockierenden Prozess..." -ForegroundColor Yellow
    Stop-ProcessOnPort -Port 8080
    Start-Sleep -Seconds 1
}

# Open WebUI starten
Write-Host "  Starte Open WebUI (Port 8080)..." -ForegroundColor Gray
$env:OLLAMA_BASE_URL = "http://localhost:11434"
$env:PYTHONUTF8 = "1"

$openwebuiExe = Get-Command open-webui -ErrorAction SilentlyContinue
if (-not $openwebuiExe) {
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

    $maxVersuche = 30
    $versuch = 0
    Write-Host "  Warte auf Open WebUI..." -ForegroundColor Gray
    while ($versuch -lt $maxVersuche) {
        Start-Sleep -Seconds 2
        $versuch++

        $proc = Get-Process -Id $openwebuiProzess.Id -ErrorAction SilentlyContinue
        if (-not $proc) {
            Write-Host "  [FEHLER] Open WebUI Prozess ist abgestuerzt!" -ForegroundColor Red
            if (Test-Path $openwebuiErrorLog) {
                Write-Host "  Fehlerlog:" -ForegroundColor Yellow
                Get-Content $openwebuiErrorLog | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            }
            break
        }

        if (Test-PortReady -Port 8080) {
            $bereit = $true
            break
        }

        if ($versuch % 5 -eq 0) {
            Write-Host "  Noch nicht bereit... ($versuch/$maxVersuche)" -ForegroundColor Gray
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

# --- [5/5] MCPO-Verbindung in Open WebUI pruefen ---

Write-Host ""
Write-Host "[5/5] MCPO-Verbindung in Open WebUI pruefen..." -ForegroundColor Yellow

if ($bereit -and $mcpoGestartet) {
    # Pruefe ob MCPO ueber die OpenAPI-Docs erreichbar ist
    $mcpoDocs = $false
    try {
        $null = Invoke-RestMethod -Uri "http://localhost:8000/docs" -Method Get -TimeoutSec 3 -ErrorAction Stop -UseBasicParsing
        $mcpoDocs = $true
    } catch {
        try {
            $null = Invoke-RestMethod -Uri "http://localhost:8000/openapi.json" -Method Get -TimeoutSec 3 -ErrorAction Stop
            $mcpoDocs = $true
        } catch {}
    }

    if ($mcpoDocs) {
        Write-Host "  [OK] MCPO OpenAPI-Endpunkt erreichbar: http://localhost:8000" -ForegroundColor Green
        Write-Host "" -ForegroundColor Gray
        Write-Host "  Falls MCPO noch nicht in Open WebUI verbunden ist:" -ForegroundColor Yellow
        Write-Host "    1. Oeffne http://localhost:8080 > Admin > Einstellungen > Verbindungen" -ForegroundColor Cyan
        Write-Host "    2. Klicke 'Verbindung hinzufuegen' (+)" -ForegroundColor Cyan
        Write-Host "    3. Typ: OpenAPI | URL: http://localhost:8000 | Speichern" -ForegroundColor Cyan
        Write-Host "  (Nur einmalig noetig - Open WebUI merkt sich die Verbindung)" -ForegroundColor Gray
    } else {
        Write-Host "  [WARNUNG] MCPO laeuft, aber OpenAPI-Docs nicht erreichbar." -ForegroundColor Yellow
        Write-Host "  Pruefe: http://localhost:8000/docs" -ForegroundColor Yellow
    }
} else {
    if (-not $mcpoGestartet) {
        Write-Host "  [SKIP] MCPO nicht verfuegbar." -ForegroundColor Yellow
    }
    if (-not $bereit) {
        Write-Host "  [SKIP] Open WebUI nicht verfuegbar." -ForegroundColor Yellow
    }
}

# --- Zusammenfassung ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Status-Uebersicht" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Ollama
try {
    $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 2 -ErrorAction Stop
    Write-Host "  Ollama:     http://localhost:11434  [OK]" -ForegroundColor Green
} catch {
    Write-Host "  Ollama:     http://localhost:11434  [FEHLER]" -ForegroundColor Red
}

# MCPO
if ($mcpoGestartet) {
    Write-Host "  MCPO:       http://localhost:8000   [OK] (Hot-Reload aktiv)" -ForegroundColor Green
} else {
    Write-Host "  MCPO:       http://localhost:8000   [FEHLER] Pruefe $mcpoErrorLog" -ForegroundColor Red
}

# Open WebUI
if ($bereit) {
    Write-Host "  Open WebUI: http://localhost:8080   [OK]" -ForegroundColor Green
} else {
    Write-Host "  Open WebUI: http://localhost:8080   [FEHLER] Pruefe $openwebuiErrorLog" -ForegroundColor Red
}

# Browser oeffnen
if ($bereit) {
    Write-Host ""
    Write-Host "Oeffne den Browser..." -ForegroundColor Gray
    Start-Process "http://localhost:8080"
} else {
    Write-Host ""
    Write-Host "Browser wird nicht automatisch geoeffnet - nicht alle Dienste sind bereit." -ForegroundColor Yellow
    Write-Host "Pruefe die Logdateien fuer Details." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Zum Beenden: .\scripts\stop.ps1" -ForegroundColor Cyan
Write-Host "Neues Plugin hinzufuegen: .\scripts\add-server.ps1 (MCPO laedt automatisch nach)" -ForegroundColor Cyan
Write-Host "Logdateien: $projektVerzeichnis\*.log" -ForegroundColor Cyan
