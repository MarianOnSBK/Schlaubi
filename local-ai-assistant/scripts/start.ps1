# start.ps1 - Startet alle Dienste des lokalen KI-Assistenten
# Schreibt detailliertes Log nach logs\start.log fuer Nachvollziehbarkeit

# --- Konfiguration ---
$ErrorActionPreference = "Continue"
$startZeitpunkt = Get-Date
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$buildScript = Join-Path $projektVerzeichnis "scripts\build-config.ps1"
$venvPfad = Join-Path $projektVerzeichnis ".venv"
$mcpoPidDatei = Join-Path $projektVerzeichnis ".mcpo.pid"
$openwebuiPidDatei = Join-Path $projektVerzeichnis ".openwebui.pid"

# Log-Verzeichnis erstellen
$logVerzeichnis = Join-Path $projektVerzeichnis "logs"
try {
    if (-not (Test-Path $logVerzeichnis)) {
        New-Item -ItemType Directory -Path $logVerzeichnis -Force | Out-Null
    }
} catch {
    $logVerzeichnis = $projektVerzeichnis
}

$script:logDatei = Join-Path $logVerzeichnis "start.log"
$mcpoLog = Join-Path $logVerzeichnis "mcpo-stdout.log"
$mcpoErrorLog = Join-Path $logVerzeichnis "mcpo-stderr.log"
$openwebuiLog = Join-Path $logVerzeichnis "openwebui-stdout.log"
$openwebuiErrorLog = Join-Path $logVerzeichnis "openwebui-stderr.log"

# Altes Start-Log sichern
if (Test-Path $script:logDatei) {
    $backup = Join-Path $logVerzeichnis "start.log.bak"
    Copy-Item -Path $script:logDatei -Destination $backup -Force -ErrorAction SilentlyContinue
}
"" | Set-Content -Path $script:logDatei -ErrorAction SilentlyContinue

# --- Logging-Funktion ---
# Schreibt gleichzeitig auf Konsole (farbig) und in Logdatei (mit Level)
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "STEP", "DETAIL")]
        [string]$Level = "INFO"
    )

    # Leerzeilen ohne Timestamp
    if ([string]::IsNullOrWhiteSpace($Message)) {
        Write-Host ""
        Add-Content -Path $script:logDatei -Value "" -ErrorAction SilentlyContinue
        return
    }

    $ts = Get-Date -Format "HH:mm:ss"
    $farbe = switch ($Level) {
        "OK"     { "Green" }
        "WARN"   { "Yellow" }
        "ERROR"  { "Red" }
        "STEP"   { "Cyan" }
        "DETAIL" { "Gray" }
        default  { "White" }
    }

    Write-Host "[$ts] $Message" -ForegroundColor $farbe
    Add-Content -Path $script:logDatei -Value "[$ts] [$($Level.PadRight(6))] $Message" -ErrorAction SilentlyContinue
}

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
                Write-Log "  Beende Prozess PID $($v.OwningProcess) auf Port $Port" -Level DETAIL
                Stop-ProcessTree -ParentId $v.OwningProcess
            }
        }
    } catch {
        Write-Log "  Port $Port konnte nicht freigegeben werden: $($_.Exception.Message)" -Level WARN
    }
}

function Test-PortReady {
    param([int]$Port, [int]$TimeoutSec = 2)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $result = $tcp.BeginConnect("localhost", $Port, $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne($TimeoutSec * 1000)
        if ($success) {
            try { $tcp.EndConnect($result) } catch {}
        }
        $tcp.Close()
        return $success
    } catch {
        return $false
    }
}

function Find-Executable {
    param([string]$Name, [string]$VenvFallback)
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if ($VenvFallback -and (Test-Path $VenvFallback)) { return $VenvFallback }
    return $null
}

# ============================================================
#  Banner
# ============================================================

Write-Log ""
Write-Log "========================================" -Level STEP
Write-Log "  Lokaler KI-Assistent - Start" -Level STEP
Write-Log "========================================" -Level STEP
Write-Log ""
Write-Log "Logdatei: $($script:logDatei)" -Level DETAIL

# --- System-Diagnose ---
Write-Log "--- System-Diagnose ---" -Level STEP
Write-Log "  Zeitpunkt:          $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level DETAIL
Write-Log "  Computer:           $env:COMPUTERNAME" -Level DETAIL
Write-Log "  Benutzer:           $env:USERNAME" -Level DETAIL
Write-Log "  Projektverzeichnis: $projektVerzeichnis" -Level DETAIL

try { $psVer = "$($PSVersionTable.PSVersion)"; Write-Log "  PowerShell:         $psVer" -Level DETAIL } catch {}

try {
    $pyVer = python --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "  Python:             $pyVer" -Level DETAIL
    } else {
        Write-Log "  Python:             NICHT GEFUNDEN" -Level WARN
    }
} catch {
    Write-Log "  Python:             NICHT GEFUNDEN" -Level WARN
}

try {
    $nodeVer = node --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "  Node.js:            $nodeVer" -Level DETAIL
    } else {
        Write-Log "  Node.js:            NICHT GEFUNDEN" -Level WARN
    }
} catch {
    Write-Log "  Node.js:            NICHT GEFUNDEN" -Level WARN
}

try {
    $ollamaVer = ollama --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "  Ollama:             $ollamaVer" -Level DETAIL
    } else {
        Write-Log "  Ollama:             NICHT GEFUNDEN" -Level WARN
    }
} catch {
    Write-Log "  Ollama:             NICHT GEFUNDEN" -Level WARN
}

Write-Log ""

# --- Virtual Environment aktivieren ---

$aktivierungsScript = Join-Path $venvPfad "Scripts\Activate.ps1"
if (Test-Path $aktivierungsScript) {
    try {
        & $aktivierungsScript
        $venvPython = Join-Path $venvPfad "Scripts\python.exe"
        if (Test-Path $venvPython) {
            $venvPyVer = & $venvPython --version 2>&1
            Write-Log "Virtual Environment aktiviert ($venvPyVer)" -Level OK
        } else {
            Write-Log "Virtual Environment aktiviert" -Level OK
        }
    } catch {
        Write-Log "Virtual Environment konnte nicht aktiviert werden: $($_.Exception.Message)" -Level ERROR
        Write-Log "  Loesung: setup.ps1 erneut ausfuehren" -Level DETAIL
    }
} else {
    Write-Log "Kein Virtual Environment gefunden: $venvPfad" -Level WARN
    Write-Log "  Loesung: .\scripts\setup.ps1 ausfuehren" -Level DETAIL
}

Write-Log ""

# ============================================================
# [1/5] Outlook pruefen
# ============================================================

Write-Log "[1/5] Outlook pruefen..." -Level STEP

$outlookStatus = "unbekannt"
try {
    $outlookProzess = Get-Process OUTLOOK -ErrorAction SilentlyContinue
    if ($outlookProzess) {
        $pids = ($outlookProzess | ForEach-Object { $_.Id }) -join ", "
        Write-Log "  [OK] Outlook ist geoeffnet (PID: $pids)" -Level OK
        $outlookStatus = "laeuft"
    } else {
        Write-Log "  [WARN] Outlook scheint nicht geoeffnet zu sein" -Level WARN
        Write-Log "  Grund: Kein Prozess 'OUTLOOK' gefunden" -Level DETAIL
        Write-Log "  Auswirkung: E-Mail-Plugin funktioniert nicht" -Level DETAIL
        Write-Log "  Loesung: Microsoft Outlook Desktop starten" -Level DETAIL
        $outlookStatus = "nicht gestartet"
    }
} catch {
    Write-Log "  [WARN] Outlook-Pruefung fehlgeschlagen: $($_.Exception.Message)" -Level WARN
    $outlookStatus = "pruefung fehlgeschlagen"
}

Write-Log ""

# ============================================================
# [2/5] MCPO-Konfiguration bauen
# ============================================================

Write-Log "[2/5] MCPO-Konfiguration aktualisieren..." -Level STEP

$configDatei = Join-Path $projektVerzeichnis "mcpo-config.json"

if (-not (Test-Path $buildScript)) {
    Write-Log "  [ERROR] build-config.ps1 nicht gefunden: $buildScript" -Level ERROR
    Write-Log "  Loesung: Datei wiederherstellen oder Repository neu klonen" -Level DETAIL
} else {
    try {
        & $buildScript
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            Write-Log "  [WARN] build-config.ps1 beendet mit Exit-Code $LASTEXITCODE" -Level WARN
        }

        if (Test-Path $configDatei) {
            $configInhalt = Get-Content $configDatei -Raw | ConvertFrom-Json
            $serverAnzahl = 0
            if ($configInhalt.mcpServers) {
                $serverAnzahl = ($configInhalt.mcpServers.PSObject.Properties | Measure-Object).Count
            }
            Write-Log "  [OK] mcpo-config.json erstellt ($serverAnzahl aktive Server)" -Level OK

            # Pruefen ob Server-Executables installiert sind
            foreach ($server in $configInhalt.mcpServers.PSObject.Properties) {
                $srvName = $server.Name
                $srvCmd = $server.Value.command
                $cmdPfad = Find-Executable -Name $srvCmd -VenvFallback (Join-Path $venvPfad "Scripts\$srvCmd.exe")
                if ($cmdPfad) {
                    Write-Log "    Server '${srvName}': $srvCmd [OK]" -Level OK
                } else {
                    Write-Log "    Server '${srvName}': $srvCmd [NICHT INSTALLIERT]" -Level ERROR
                    Write-Log "    Loesung: pip install $srvCmd" -Level DETAIL
                }
            }
        } else {
            Write-Log "  [ERROR] mcpo-config.json wurde nicht erstellt" -Level ERROR
            Write-Log "  Grund: build-config.ps1 lief ohne Fehler, aber die Datei fehlt" -Level DETAIL
        }
    } catch {
        Write-Log "  [ERROR] build-config.ps1 fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
        Write-Log "  Loesung: JSON-Dateien in servers/ auf Syntaxfehler pruefen" -Level DETAIL
    }
}

Write-Log ""

# ============================================================
# [3/5] Ollama pruefen/starten
# ============================================================

Write-Log "[3/5] Ollama pruefen/starten..." -Level STEP

$ollamaLaeuft = $false

try {
    $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 3 -ErrorAction Stop
    $ollamaLaeuft = $true
    $modellAnzahl = if ($response.models) { $response.models.Count } else { 0 }
    Write-Log "  [OK] Ollama laeuft bereits (Port 11434, $modellAnzahl Modelle installiert)" -Level OK

    if ($modellAnzahl -eq 0) {
        Write-Log "  [WARN] Kein Modell installiert!" -Level WARN
        Write-Log "  Loesung: ollama pull qwen2.5:14b" -Level DETAIL
    } else {
        foreach ($m in $response.models) {
            Write-Log "    Modell: $($m.name)" -Level DETAIL
        }
    }
} catch {
    Write-Log "  Ollama nicht erreichbar auf Port 11434. Versuche zu starten..." -Level INFO

    $ollamaExe = Find-Executable -Name "ollama"
    if (-not $ollamaExe) {
        Write-Log "  [ERROR] 'ollama' nicht im PATH gefunden" -Level ERROR
        Write-Log "  Loesung: Ollama installieren von https://ollama.com/download" -Level DETAIL
    } else {
        Write-Log "  Starte: $ollamaExe serve" -Level DETAIL
        try {
            Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep -Seconds 3

            try {
                $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
                $ollamaLaeuft = $true
                $modellAnzahl = if ($response.models) { $response.models.Count } else { 0 }
                Write-Log "  [OK] Ollama gestartet (Port 11434, $modellAnzahl Modelle)" -Level OK
            } catch {
                Write-Log "  [ERROR] Ollama gestartet, antwortet aber nicht" -Level ERROR
                Write-Log "  Grund: $($_.Exception.Message)" -Level DETAIL
                Write-Log "  Loesung: 'ollama serve' manuell in einem Terminal starten" -Level DETAIL
            }
        } catch {
            Write-Log "  [ERROR] Konnte Ollama nicht starten: $($_.Exception.Message)" -Level ERROR
        }
    }
}

Write-Log ""

# ============================================================
# [4/5] Dienste starten (MCPO + Open WebUI)
# ============================================================

Write-Log "[4/5] Dienste starten..." -Level STEP

$mcpoGestartet = $false
$bereit = $false

# --- MCPO ---

Write-Log "  --- MCPO (Port 8000) ---" -Level INFO

# Alten MCPO-Prozess beenden
if (Test-Path $mcpoPidDatei) {
    $alterPid = Get-Content $mcpoPidDatei
    try {
        $proc = Get-Process -Id $alterPid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Log "  Alter MCPO-Prozess gefunden (PID: $alterPid). Beende..." -Level WARN
            Stop-ProcessTree -ParentId $alterPid
            Start-Sleep -Seconds 1
        }
    } catch {}
    Remove-Item $mcpoPidDatei -Force -ErrorAction SilentlyContinue
}

if (Test-PortReady -Port 8000 -TimeoutSec 1) {
    Write-Log "  Port 8000 noch belegt. Beende blockierenden Prozess..." -Level WARN
    Stop-ProcessOnPort -Port 8000
    Start-Sleep -Seconds 1
}

# MCPO starten
$mcpoExe = Find-Executable -Name "mcpo" -VenvFallback (Join-Path $venvPfad "Scripts\mcpo.exe")

if (-not $mcpoExe) {
    Write-Log "  [ERROR] mcpo nicht gefunden" -Level ERROR
    Write-Log "  Gesucht in: PATH und $(Join-Path $venvPfad 'Scripts\mcpo.exe')" -Level DETAIL
    Write-Log "  Loesung: pip install mcpo" -Level DETAIL
} elseif (-not (Test-Path $configDatei)) {
    Write-Log "  [ERROR] mcpo-config.json fehlt: $configDatei" -Level ERROR
    Write-Log "  Loesung: .\scripts\build-config.ps1 ausfuehren" -Level DETAIL
} else {
    Write-Log "  Executable: $mcpoExe" -Level DETAIL
    Write-Log "  Config:     $configDatei" -Level DETAIL
    Write-Log "  Starte MCPO mit Hot-Reload..." -Level INFO

    try {
        $mcpoProzess = Start-Process -FilePath $mcpoExe `
            -ArgumentList "--config", $configDatei, "--port", "8000", "--hot-reload" `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $mcpoLog -RedirectStandardError $mcpoErrorLog
        $mcpoProzess.Id | Set-Content $mcpoPidDatei
        Write-Log "  Prozess gestartet (PID: $($mcpoProzess.Id)). Warte auf Port 8000..." -Level DETAIL

        $maxVersuche = 15
        for ($i = 1; $i -le $maxVersuche; $i++) {
            Start-Sleep -Seconds 1

            # Prozess noch am Leben?
            $proc = Get-Process -Id $mcpoProzess.Id -ErrorAction SilentlyContinue
            if (-not $proc) {
                Write-Log "  [ERROR] MCPO-Prozess abgestuerzt nach $i Sekunden!" -Level ERROR
                # Fehlerlog anzeigen
                if (Test-Path $mcpoErrorLog) {
                    $errInhalt = Get-Content $mcpoErrorLog -ErrorAction SilentlyContinue | Select-Object -Last 15
                    if ($errInhalt) {
                        Write-Log "  --- MCPO Fehlerlog ---" -Level ERROR
                        foreach ($zeile in $errInhalt) {
                            Write-Log "  | $zeile" -Level ERROR
                        }
                    }
                }
                if (Test-Path $mcpoLog) {
                    $stdInhalt = Get-Content $mcpoLog -ErrorAction SilentlyContinue | Select-Object -Last 5
                    if ($stdInhalt) {
                        Write-Log "  --- MCPO Ausgabe ---" -Level DETAIL
                        foreach ($zeile in $stdInhalt) {
                            Write-Log "  | $zeile" -Level DETAIL
                        }
                    }
                }
                break
            }

            if (Test-PortReady -Port 8000 -TimeoutSec 1) {
                $mcpoGestartet = $true
                break
            }

            if ($i % 5 -eq 0) {
                Write-Log "  Warte auf MCPO... ($i/$maxVersuche Sekunden)" -Level DETAIL
            }
        }

        if ($mcpoGestartet) {
            Write-Log "  [OK] MCPO gestartet (PID: $($mcpoProzess.Id), Port 8000, Hot-Reload aktiv)" -Level OK
        } elseif (Get-Process -Id $mcpoProzess.Id -ErrorAction SilentlyContinue) {
            Write-Log "  [WARN] MCPO-Prozess laeuft (PID: $($mcpoProzess.Id)), antwortet aber noch nicht" -Level WARN
            Write-Log "  Der Start kann beim ersten Mal laenger dauern" -Level DETAIL
            Write-Log "  Stdout: $mcpoLog" -Level DETAIL
            Write-Log "  Stderr: $mcpoErrorLog" -Level DETAIL
        }
    } catch {
        Write-Log "  [ERROR] MCPO konnte nicht gestartet werden: $($_.Exception.Message)" -Level ERROR
    }
}

# --- Open WebUI ---

Write-Log ""
Write-Log "  --- Open WebUI (Port 8080) ---" -Level INFO

# Alten Open WebUI Prozess beenden
if (Test-Path $openwebuiPidDatei) {
    $alterPid = Get-Content $openwebuiPidDatei
    try {
        $proc = Get-Process -Id $alterPid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Log "  Alter Open WebUI-Prozess gefunden (PID: $alterPid). Beende..." -Level WARN
            Stop-ProcessTree -ParentId $alterPid
            Start-Sleep -Seconds 1
        }
    } catch {}
    Remove-Item $openwebuiPidDatei -Force -ErrorAction SilentlyContinue
}

if (Test-PortReady -Port 8080 -TimeoutSec 1) {
    Write-Log "  Port 8080 noch belegt. Beende blockierenden Prozess..." -Level WARN
    Stop-ProcessOnPort -Port 8080
    Start-Sleep -Seconds 1
}

# Umgebungsvariablen setzen
$env:OLLAMA_BASE_URL = "http://localhost:11434"
$env:PYTHONUTF8 = "1"
Write-Log "  OLLAMA_BASE_URL=$($env:OLLAMA_BASE_URL)" -Level DETAIL

$openwebuiExe = Find-Executable -Name "open-webui" -VenvFallback (Join-Path $venvPfad "Scripts\open-webui.exe")

if (-not $openwebuiExe) {
    Write-Log "  [ERROR] open-webui nicht gefunden" -Level ERROR
    Write-Log "  Gesucht in: PATH und $(Join-Path $venvPfad 'Scripts\open-webui.exe')" -Level DETAIL
    Write-Log "  Loesung: pip install open-webui" -Level DETAIL
} else {
    Write-Log "  Executable: $openwebuiExe" -Level DETAIL
    Write-Log "  Starte Open WebUI..." -Level INFO

    try {
        $openwebuiProzess = Start-Process -FilePath $openwebuiExe -ArgumentList "serve" `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $openwebuiLog -RedirectStandardError $openwebuiErrorLog
        $openwebuiProzess.Id | Set-Content $openwebuiPidDatei
        Write-Log "  Prozess gestartet (PID: $($openwebuiProzess.Id)). Warte auf Port 8080..." -Level DETAIL

        $maxVersuche = 30
        for ($i = 1; $i -le $maxVersuche; $i++) {
            Start-Sleep -Seconds 2

            $proc = Get-Process -Id $openwebuiProzess.Id -ErrorAction SilentlyContinue
            if (-not $proc) {
                Write-Log "  [ERROR] Open WebUI-Prozess abgestuerzt nach $($i * 2) Sekunden!" -Level ERROR
                if (Test-Path $openwebuiErrorLog) {
                    $errInhalt = Get-Content $openwebuiErrorLog -ErrorAction SilentlyContinue | Select-Object -Last 15
                    if ($errInhalt) {
                        Write-Log "  --- Open WebUI Fehlerlog ---" -Level ERROR
                        foreach ($zeile in $errInhalt) {
                            Write-Log "  | $zeile" -Level ERROR
                        }
                    }
                }
                break
            }

            if (Test-PortReady -Port 8080) {
                $bereit = $true
                break
            }

            if ($i % 5 -eq 0) {
                Write-Log "  Warte auf Open WebUI... ($($i * 2)s vergangen, max $($maxVersuche * 2)s)" -Level DETAIL
            }
        }

        if ($bereit) {
            Write-Log "  [OK] Open WebUI gestartet (PID: $($openwebuiProzess.Id), Port 8080)" -Level OK
        } elseif (Get-Process -Id $openwebuiProzess.Id -ErrorAction SilentlyContinue) {
            Write-Log "  [WARN] Open WebUI-Prozess laeuft (PID: $($openwebuiProzess.Id)), antwortet aber noch nicht" -Level WARN
            Write-Log "  Der erste Start kann mehrere Minuten dauern (Datenbank-Migration etc.)" -Level DETAIL
            Write-Log "  Pruefe manuell: http://localhost:8080" -Level DETAIL
            Write-Log "  Stdout: $openwebuiLog" -Level DETAIL
            Write-Log "  Stderr: $openwebuiErrorLog" -Level DETAIL
        }
    } catch {
        Write-Log "  [ERROR] Open WebUI konnte nicht gestartet werden: $($_.Exception.Message)" -Level ERROR
    }
}

Write-Log ""

# ============================================================
# [5/5] MCPO-Verbindung pruefen
# ============================================================

Write-Log "[5/5] MCPO-Verbindung pruefen..." -Level STEP

if ($mcpoGestartet) {
    # Tool-Discovery mit Retry: MCPO initialisiert MCP-Server im Hintergrund.
    # Bei langsamen Servern (z.B. npm-basierte) kann das bis zu 90 Sekunden dauern.
    $toolAnzahl = 0
    $endpoints = $null
    $maxToolVersuche = 12
    $toolWarteZeit = 5

    for ($t = 1; $t -le $maxToolVersuche; $t++) {
        try {
            $spec = Invoke-RestMethod -Uri "http://localhost:8000/openapi.json" -Method Get -TimeoutSec 5 -ErrorAction Stop
            if ($spec.paths) {
                $endpoints = $spec.paths.PSObject.Properties | Where-Object { $_.Name -notmatch "^/(docs|openapi|health)" }
                $toolAnzahl = ($endpoints | Measure-Object).Count
            }
            if ($toolAnzahl -gt 0) { break }
        } catch {}

        if ($t -lt $maxToolVersuche) {
            $vergangen = $t * $toolWarteZeit
            Write-Log "  Warte auf MCP-Server-Initialisierung... (${vergangen}s / max $($maxToolVersuche * $toolWarteZeit)s)" -Level DETAIL
            Start-Sleep -Seconds $toolWarteZeit
        }
    }

    if ($toolAnzahl -gt 0) {
        Write-Log "  [OK] MCPO erreichbar - $toolAnzahl Tools verfuegbar:" -Level OK
        foreach ($ep in $endpoints) {
            $beschreibung = ""
            if ($ep.Value.post -and $ep.Value.post.summary) {
                $beschreibung = " - $($ep.Value.post.summary)"
            }
            Write-Log "    $($ep.Name)$beschreibung" -Level DETAIL
        }

        # Outlook-spezifisch pruefen
        $outlookTools = $endpoints | Where-Object { $_.Name -match "outlook" }
        if ($outlookTools) {
            $outlookCount = ($outlookTools | Measure-Object).Count
            Write-Log "  [OK] Outlook-Tools verfuegbar ($outlookCount Endpunkte)" -Level OK
        } else {
            Write-Log "  [WARN] Outlook-Tools sind NICHT verfuegbar!" -Level WARN
            Write-Log "  Moegliche Ursachen:" -Level DETAIL
            Write-Log "    - outlook-mcp-server-windows-com nicht installiert (pip install outlook-mcp-server-windows-com)" -Level DETAIL
            Write-Log "    - Outlook Desktop nicht geoeffnet" -Level DETAIL
            Write-Log "    - Pruefe MCPO Fehlerlog: $mcpoErrorLog" -Level DETAIL
        }
    } else {
        Write-Log "  [WARN] MCPO laeuft, aber noch keine Tools verfuegbar" -Level WARN
        Write-Log "  MCPO initialisiert moeglicherweise noch Server (kann bis zu 90s dauern)" -Level DETAIL
        Write-Log "  Pruefe spaeter manuell: http://localhost:8000/docs" -Level DETAIL
        Write-Log "  MCPO Fehlerlog: $mcpoErrorLog" -Level DETAIL
    }

    # MCPO-Log parsen: Welche MCP-Server haben sich verbunden, welche nicht?
    # MCPO schreibt Zeilen wie:
    #   "Successfully connected to 'outlook'."
    #   "Failed to connect to MCP server 'filesystem': McpError: Connection closed"
    Write-Log ""
    Write-Log "  --- MCP-Server Verbindungsstatus (aus MCPO-Log) ---" -Level INFO
    if (Test-Path $mcpoErrorLog) {
        $mcpoLogInhalt = Get-Content $mcpoErrorLog -ErrorAction SilentlyContinue
        $erfolgreich = @()
        $fehlgeschlagen = @{}

        foreach ($zeile in $mcpoLogInhalt) {
            if ($zeile -match "Successfully connected to '([^']+)'") {
                $srvName = $Matches[1]
                if ($erfolgreich -notcontains $srvName) {
                    $erfolgreich += $srvName
                }
            }
            elseif ($zeile -match "Failed to (connect|establish).*?'([^']+)'") {
                $srvName = $Matches[2]
                $grund = "unbekannt"
                if ($zeile -match "McpError:\s*(.+)$") {
                    $grund = $Matches[1].Trim()
                } elseif ($zeile -match "-\s+(.+)$") {
                    $grund = $Matches[1].Trim()
                }
                $fehlgeschlagen[$srvName] = $grund
            }
        }

        if ($erfolgreich.Count -gt 0 -or $fehlgeschlagen.Count -gt 0) {
            foreach ($s in $erfolgreich) {
                Write-Log "    [OK] $s - verbunden" -Level OK
            }
            foreach ($s in $fehlgeschlagen.Keys) {
                Write-Log "    [FEHLER] $s - Verbindung fehlgeschlagen" -Level ERROR
                Write-Log "      Grund: $($fehlgeschlagen[$s])" -Level DETAIL
            }
        } else {
            Write-Log "  MCPO-Log noch leer oder Server werden noch initialisiert" -Level DETAIL
            Write-Log "  Pruefe spaeter: $mcpoErrorLog" -Level DETAIL
        }
    } else {
        Write-Log "  MCPO-Logdatei nicht gefunden: $mcpoErrorLog" -Level DETAIL
    }

    Write-Log ""
    Write-Log "  Falls MCPO noch nicht in Open WebUI verbunden ist:" -Level INFO
    Write-Log "    1. Oeffne http://localhost:8080 > Admin > Einstellungen > Verbindungen" -Level INFO
    Write-Log "    2. Klicke 'Verbindung hinzufuegen' (+)" -Level INFO
    Write-Log "    3. Typ: OpenAPI | URL: http://localhost:8000 | Speichern" -Level INFO
    Write-Log "  (Nur einmalig noetig - Open WebUI merkt sich die Verbindung)" -Level DETAIL
} else {
    Write-Log "  [SKIP] MCPO nicht verfuegbar - Tool-Pruefung uebersprungen" -Level WARN
    Write-Log "  Ohne MCPO sind keine MCP-Tools (Outlook etc.) verfuegbar" -Level DETAIL
}

Write-Log ""

# ============================================================
#  Zusammenfassung
# ============================================================

$dauer = (Get-Date) - $startZeitpunkt
$dauerSek = [math]::Round($dauer.TotalSeconds)

Write-Log "========================================" -Level STEP
Write-Log "  Status-Uebersicht" -Level STEP
Write-Log "========================================" -Level STEP
Write-Log ""

# Ollama
if ($ollamaLaeuft) {
    Write-Log "  Ollama:     http://localhost:11434  [OK]" -Level OK
} else {
    Write-Log "  Ollama:     http://localhost:11434  [FEHLER]" -Level ERROR
}

# MCPO
if ($mcpoGestartet) {
    Write-Log "  MCPO:       http://localhost:8000   [OK] (Hot-Reload aktiv)" -Level OK
} else {
    Write-Log "  MCPO:       http://localhost:8000   [FEHLER]" -Level ERROR
    Write-Log "              Pruefe: $mcpoErrorLog" -Level DETAIL
}

# Open WebUI
if ($bereit) {
    Write-Log "  Open WebUI: http://localhost:8080   [OK]" -Level OK
} else {
    Write-Log "  Open WebUI: http://localhost:8080   [FEHLER]" -Level ERROR
    Write-Log "              Pruefe: $openwebuiErrorLog" -Level DETAIL
}

# Outlook
if ($outlookStatus -eq "laeuft") {
    Write-Log "  Outlook:    Desktop-App             [OK]" -Level OK
} else {
    Write-Log "  Outlook:    Desktop-App             [WARN] $outlookStatus" -Level WARN
}

Write-Log ""

# Fehleranzahl zaehlen
$fehlerAnzahl = 0
if (-not $ollamaLaeuft) { $fehlerAnzahl++ }
if (-not $mcpoGestartet) { $fehlerAnzahl++ }
if (-not $bereit) { $fehlerAnzahl++ }

if ($fehlerAnzahl -eq 0) {
    Write-Log "Alle Dienste laufen! ($dauerSek Sekunden)" -Level OK
} else {
    Write-Log "$fehlerAnzahl von 3 Diensten nicht bereit. ($dauerSek Sekunden)" -Level WARN
    Write-Log "Pruefe die Logdateien fuer Details:" -Level INFO
    Write-Log "  Start-Log:         $($script:logDatei)" -Level DETAIL
    Write-Log "  MCPO Stdout:       $mcpoLog" -Level DETAIL
    Write-Log "  MCPO Stderr:       $mcpoErrorLog" -Level DETAIL
    Write-Log "  Open WebUI Stdout: $openwebuiLog" -Level DETAIL
    Write-Log "  Open WebUI Stderr: $openwebuiErrorLog" -Level DETAIL
}

# Browser oeffnen
if ($bereit) {
    Write-Log ""
    Write-Log "Oeffne Browser: http://localhost:8080" -Level INFO
    Start-Process "http://localhost:8080"
}

Write-Log ""
Write-Log "Zum Beenden:        .\scripts\stop.ps1" -Level INFO
Write-Log "Plugin hinzufuegen: .\scripts\add-server.ps1" -Level INFO
Write-Log "Alle Logs:          $logVerzeichnis" -Level INFO
