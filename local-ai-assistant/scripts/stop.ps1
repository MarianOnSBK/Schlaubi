# stop.ps1 - Beendet alle Dienste des lokalen KI-Assistenten
# Schreibt Log nach logs\stop.log

# --- Konfiguration ---
$ErrorActionPreference = "Continue"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$mcpoPidDatei = Join-Path $projektVerzeichnis ".mcpo.pid"
$openwebuiPidDatei = Join-Path $projektVerzeichnis ".openwebui.pid"

# Log-Verzeichnis
$logVerzeichnis = Join-Path $projektVerzeichnis "logs"
try {
    if (-not (Test-Path $logVerzeichnis)) {
        New-Item -ItemType Directory -Path $logVerzeichnis -Force | Out-Null
    }
} catch {
    $logVerzeichnis = $projektVerzeichnis
}
$script:logDatei = Join-Path $logVerzeichnis "stop.log"
"" | Set-Content -Path $script:logDatei -ErrorAction SilentlyContinue

# --- Logging-Funktion ---
function Write-Log {
    param(
        [Parameter(Position = 0)]
        [string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "STEP", "DETAIL")]
        [string]$Level = "INFO"
    )

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

function Stop-ServiceByPidAndPort {
    param(
        [string]$Name,
        [string]$PidDatei,
        [int]$Port,
        [string[]]$ProzessNamen = @()
    )

    $beendet = $false

    # Methode 1: PID-Datei
    if (Test-Path $PidDatei) {
        $pid = Get-Content $PidDatei
        try {
            $prozess = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($prozess) {
                Write-Log "  PID-Datei: Beende $Name Prozessbaum (PID: $pid)..." -Level DETAIL
                Stop-ProcessTree -ParentId $pid
                $beendet = $true
            } else {
                Write-Log "  PID-Datei vorhanden, aber Prozess $pid existiert nicht mehr" -Level DETAIL
            }
        } catch {}
        Remove-Item $PidDatei -Force -ErrorAction SilentlyContinue
    } else {
        Write-Log "  Keine PID-Datei fuer $Name vorhanden" -Level DETAIL
    }

    # Methode 2: Port pruefen
    if ($Port -gt 0) {
        try {
            $verbindungen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
            foreach ($v in $verbindungen) {
                if ($v.OwningProcess -gt 0) {
                    Write-Log "  Port ${Port}: Beende Prozess PID $($v.OwningProcess)..." -Level DETAIL
                    Stop-ProcessTree -ParentId $v.OwningProcess
                    $beendet = $true
                }
            }
        } catch {}
    }

    # Methode 3: Prozessname suchen
    foreach ($pName in $ProzessNamen) {
        try {
            $prozesse = Get-Process -Name $pName -ErrorAction SilentlyContinue
            if ($prozesse) {
                $prozesse | ForEach-Object {
                    Write-Log "  Prozessname '$pName': Beende PID $($_.Id)..." -Level DETAIL
                    Stop-ProcessTree -ParentId $_.Id
                }
                $beendet = $true
            }
        } catch {}
    }

    if ($beendet) {
        # Pruefen ob Port wirklich frei ist
        Start-Sleep -Milliseconds 500
        $nochBelegt = $false
        if ($Port -gt 0) {
            try {
                $check = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
                if ($check) { $nochBelegt = $true }
            } catch {}
        }
        if ($nochBelegt) {
            Write-Log "  Port $Port noch belegt. Zweiter Versuch..." -Level WARN
            Start-Sleep -Seconds 2
            try {
                $verbindungen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
                foreach ($v in $verbindungen) {
                    Stop-Process -Id $v.OwningProcess -Force -ErrorAction SilentlyContinue
                }
            } catch {}
            # Nochmal pruefen
            Start-Sleep -Milliseconds 500
            try {
                $check = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
                if ($check) {
                    Write-Log "  [WARN] Port $Port konnte nicht freigegeben werden (PID: $($check[0].OwningProcess))" -Level WARN
                    return
                }
            } catch {}
        }
        Write-Log "  [OK] $Name beendet" -Level OK
    } else {
        Write-Log "  $Name war nicht aktiv (kein Prozess gefunden)" -Level DETAIL
    }
}

# ============================================================
#  Stop
# ============================================================

Write-Log ""
Write-Log "========================================" -Level STEP
Write-Log "  Lokaler KI-Assistent - Stop" -Level STEP
Write-Log "========================================" -Level STEP
Write-Log ""

# --- Open WebUI beenden ---

Write-Log "Open WebUI beenden..." -Level INFO
Stop-ServiceByPidAndPort -Name "Open WebUI" -PidDatei $openwebuiPidDatei -Port 8080 -ProzessNamen @("open-webui")

# --- MCPO beenden ---

Write-Log "MCPO beenden..." -Level INFO
Stop-ServiceByPidAndPort -Name "MCPO" -PidDatei $mcpoPidDatei -Port 8000 -ProzessNamen @("mcpo")

# --- Ollama (optional) ---

Write-Log ""
$ollamaProzess = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
if ($ollamaProzess) {
    Write-Log "Ollama laeuft noch (PID: $($ollamaProzess.Id))" -Level INFO
    $beenden = Read-Host "Ollama auch beenden? (j/n)"
    if ($beenden -eq "j") {
        $ollamaProzess | Stop-Process -Force
        Write-Log "  [OK] Ollama beendet" -Level OK
    } else {
        Write-Log "  Ollama laeuft weiter" -Level DETAIL
    }
} else {
    Write-Log "Ollama: nicht aktiv" -Level DETAIL
}

# --- Abschliessende Port-Pruefung ---

Write-Log ""
$allesFrei = $true
foreach ($port in @(8000, 8080)) {
    try {
        $check = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($check) {
            Write-Log "[WARN] Port $port ist noch belegt (PID: $($check[0].OwningProcess))" -Level WARN
            $allesFrei = $false
        } else {
            Write-Log "Port ${port}: frei" -Level DETAIL
        }
    } catch {}
}

Write-Log ""
if ($allesFrei) {
    Write-Log "========================================" -Level OK
    Write-Log "  Alle Dienste beendet. Ports frei." -Level OK
    Write-Log "========================================" -Level OK
} else {
    Write-Log "========================================" -Level WARN
    Write-Log "  Nicht alle Ports konnten freigegeben werden." -Level WARN
    Write-Log "  Tipp: Task-Manager oeffnen und Prozesse manuell beenden." -Level WARN
    Write-Log "========================================" -Level WARN
}

Write-Log ""
Write-Log "Erneut starten: .\scripts\start.ps1" -Level INFO
Write-Log "Logdatei: $($script:logDatei)" -Level DETAIL
