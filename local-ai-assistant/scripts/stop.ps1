# stop.ps1 - Beendet alle Dienste des lokalen KI-Assistenten

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$mcpoPidDatei = Join-Path $projektVerzeichnis ".mcpo.pid"
$openwebuiPidDatei = Join-Path $projektVerzeichnis ".openwebui.pid"

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
                Write-Host "  Beende $Name Prozessbaum (PID: $pid)..." -ForegroundColor Gray
                Stop-ProcessTree -ParentId $pid
                $beendet = $true
            }
        } catch {}
        Remove-Item $PidDatei -Force -ErrorAction SilentlyContinue
    }

    # Methode 2: Port pruefen (falls PID-Methode nichts gebracht hat)
    if ($Port -gt 0) {
        try {
            $verbindungen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
            foreach ($v in $verbindungen) {
                if ($v.OwningProcess -gt 0) {
                    Write-Host "  Beende Prozess auf Port $Port (PID: $($v.OwningProcess))..." -ForegroundColor Gray
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
                    Write-Host "  Beende $Name nach Prozessname '$pName' (PID: $($_.Id))..." -ForegroundColor Gray
                    Stop-ProcessTree -ParentId $_.Id
                }
                $beendet = $true
            }
        } catch {}
    }

    if ($beendet) {
        # Kurz warten und pruefen ob Port wirklich frei ist
        Start-Sleep -Milliseconds 500
        $nochBelegt = $false
        if ($Port -gt 0) {
            try {
                $check = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
                if ($check) { $nochBelegt = $true }
            } catch {}
        }
        if ($nochBelegt) {
            Write-Host "  [WARNUNG] Port $Port ist noch belegt. Versuche erneut..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            try {
                $verbindungen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
                foreach ($v in $verbindungen) {
                    Stop-Process -Id $v.OwningProcess -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
        Write-Host "  [OK] $Name beendet" -ForegroundColor Green
    } else {
        Write-Host "  $Name laeuft nicht." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lokaler KI-Assistent - Stop" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Open WebUI beenden ---

Write-Host "Open WebUI beenden..." -ForegroundColor Yellow
Stop-ServiceByPidAndPort -Name "Open WebUI" -PidDatei $openwebuiPidDatei -Port 8080 -ProzessNamen @("open-webui")

# --- MCPO beenden ---

Write-Host "MCPO beenden..." -ForegroundColor Yellow
Stop-ServiceByPidAndPort -Name "MCPO" -PidDatei $mcpoPidDatei -Port 8000 -ProzessNamen @("mcpo")

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

# --- Abschliessende Port-Pruefung ---

Write-Host ""
$allesFrei = $true
foreach ($port in @(8000, 8080)) {
    try {
        $check = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($check) {
            Write-Host "[WARNUNG] Port $port ist noch belegt (PID: $($check[0].OwningProcess))" -ForegroundColor Yellow
            $allesFrei = $false
        }
    } catch {}
}

if ($allesFrei) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Alle Dienste beendet. Ports frei." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  Nicht alle Ports konnten freigegeben werden." -ForegroundColor Yellow
    Write-Host "  Tipp: Task-Manager oeffnen und Prozesse manuell beenden." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Erneut starten: .\scripts\start.ps1" -ForegroundColor Cyan
