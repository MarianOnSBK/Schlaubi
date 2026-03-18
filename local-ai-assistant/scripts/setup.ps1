# setup.ps1 - Einmaliges Setup fuer den lokalen KI-Assistenten

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$buildScript = Join-Path $projektVerzeichnis "scripts\build-config.ps1"
$testOutlookScript = Join-Path $projektVerzeichnis "scripts\test-outlook-connection.ps1"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lokaler KI-Assistent - Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Prüfungen ---

Write-Host "[1/7] Systemvoraussetzungen pruefen..." -ForegroundColor Yellow
Write-Host ""

# Windows prüfen
if ($env:OS -ne "Windows_NT") {
    Write-Host "FEHLER: Dieses Projekt ist fuer Windows konzipiert." -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Windows erkannt" -ForegroundColor Green

# Python prüfen - open-webui braucht >=3.11, <3.13
$python311 = $null
try {
    $pythonVersion = python --version 2>&1
    Write-Host "  [OK] Python gefunden: $pythonVersion" -ForegroundColor Green

    # Pruefe ob die Version kompatibel ist (3.11 oder 3.12)
    if ($pythonVersion -match "3\.(11|12)\.") {
        Write-Host "  [OK] Python-Version ist kompatibel mit open-webui" -ForegroundColor Green
    }
    else {
        Write-Host "  WARNUNG: open-webui benoetigt Python >=3.11 und <3.13!" -ForegroundColor Yellow
        Write-Host "  Installiert: $pythonVersion" -ForegroundColor Yellow

        # Versuche Python 3.11 oder 3.12 ueber den Windows Python Launcher zu finden
        try {
            $py311 = py -3.11 --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Python 3.11 ueber py-Launcher gefunden: $py311" -ForegroundColor Green
                $python311 = "py -3.11"
            }
        } catch {}

        if (-not $python311) {
            try {
                $py312 = py -3.12 --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [OK] Python 3.12 ueber py-Launcher gefunden: $py312" -ForegroundColor Green
                    $python311 = "py -3.12"
                }
            } catch {}
        }

        if (-not $python311) {
            Write-Host "  TIPP: Installiere Python 3.11 von https://python.org" -ForegroundColor Cyan
            Write-Host "  Oder installiere 'uv' (empfohlen): pip install uv" -ForegroundColor Cyan
            Write-Host "  uv kann automatisch die richtige Python-Version herunterladen." -ForegroundColor Cyan
        }
    }
}
catch {
    Write-Host "  FEHLER: Python nicht gefunden!" -ForegroundColor Red
    Write-Host "  Bitte installiere Python 3.11 von https://python.org" -ForegroundColor Yellow
    exit 1
}

# Node.js prüfen
try {
    $nodeVersion = node --version 2>&1
    Write-Host "  [OK] Node.js gefunden: $nodeVersion" -ForegroundColor Green
    $majorVersion = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
    if ($majorVersion -lt 18) {
        Write-Host "  WARNUNG: Node.js 18+ wird empfohlen! Installiert: $nodeVersion" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  WARNUNG: Node.js nicht gefunden!" -ForegroundColor Yellow
    Write-Host "  Node.js wird fuer Dateisystem- und andere npx-basierte Server benoetigt." -ForegroundColor Yellow
    Write-Host "  Download: https://nodejs.org" -ForegroundColor Cyan
}

# Ollama prüfen
try {
    $ollamaVersion = ollama --version 2>&1
    Write-Host "  [OK] Ollama gefunden: $ollamaVersion" -ForegroundColor Green
}
catch {
    Write-Host "  FEHLER: Ollama nicht gefunden!" -ForegroundColor Red
    Write-Host "  Bitte installiere Ollama von https://ollama.com/download" -ForegroundColor Yellow
    Write-Host "  Nach der Installation starte dieses Script erneut." -ForegroundColor Yellow
    exit 1
}

# Outlook prüfen
try {
    $outlook = New-Object -ComObject Outlook.Application 2>$null
    if ($outlook) {
        Write-Host "  [OK] Microsoft Outlook gefunden" -ForegroundColor Green
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null
    }
}
catch {
    Write-Host "  WARNUNG: Microsoft Outlook Desktop nicht gefunden oder nicht gestartet." -ForegroundColor Yellow
    Write-Host "  Das Outlook-Plugin funktioniert nur mit installiertem Outlook Desktop." -ForegroundColor Yellow
}

Write-Host ""

# --- Virtual Environment ---

Write-Host "[2/7] Python Virtual Environment erstellen..." -ForegroundColor Yellow
$venvPfad = Join-Path $projektVerzeichnis ".venv"

if (Test-Path $venvPfad) {
    # Pruefe ob bestehendes venv eine kompatible Python-Version hat
    $venvPython = Join-Path $venvPfad "Scripts\python.exe"
    if (Test-Path $venvPython) {
        $venvPyVer = & $venvPython --version 2>&1
        if ($venvPyVer -match "3\.(11|12)\.") {
            Write-Host "  Virtual Environment existiert bereits ($venvPyVer)." -ForegroundColor Gray
        }
        else {
            Write-Host "  WARNUNG: Bestehendes venv nutzt $venvPyVer (inkompatibel mit open-webui)." -ForegroundColor Yellow
            Write-Host "  Loesche altes venv und erstelle neues..." -ForegroundColor Yellow
            Remove-Item -Recurse -Force $venvPfad
        }
    }
    else {
        Write-Host "  Virtual Environment existiert bereits." -ForegroundColor Gray
    }
}

if (-not (Test-Path $venvPfad)) {
    $venvErstellt = $false

    # 1. Versuch: uv mit Python 3.11
    $uvVorhanden = Get-Command uv -ErrorAction SilentlyContinue
    if ($uvVorhanden) {
        Write-Host "  Erstelle venv mit uv (Python 3.11)..." -ForegroundColor Gray
        try {
            uv venv --python 3.11 $venvPfad 2>&1
            if ($LASTEXITCODE -eq 0) {
                $venvErstellt = $true
                Write-Host "  [OK] Virtual Environment erstellt (uv, Python 3.11)" -ForegroundColor Green
            }
        } catch {}

        if (-not $venvErstellt) {
            Write-Host "  uv konnte Python 3.11 nicht finden, versuche 3.12..." -ForegroundColor Gray
            try {
                uv venv --python 3.12 $venvPfad 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $venvErstellt = $true
                    Write-Host "  [OK] Virtual Environment erstellt (uv, Python 3.12)" -ForegroundColor Green
                }
            } catch {}
        }
    }

    # 2. Versuch: py-Launcher mit kompatibler Version
    if (-not $venvErstellt -and $python311) {
        Write-Host "  Erstelle venv mit $python311..." -ForegroundColor Gray
        try {
            Invoke-Expression "$python311 -m venv `"$venvPfad`""
            $venvErstellt = $true
            Write-Host "  [OK] Virtual Environment erstellt ($python311)" -ForegroundColor Green
        }
        catch {
            Write-Host "  Fehler beim Erstellen mit $python311" -ForegroundColor Yellow
        }
    }

    # 3. Fallback: System-Python (warnt wenn inkompatibel)
    if (-not $venvErstellt) {
        Write-Host "  Erstelle venv mit python -m venv (System-Python)..." -ForegroundColor Gray
        python -m venv $venvPfad
        $venvErstellt = $true
        Write-Host "  [OK] Virtual Environment erstellt (System-Python)" -ForegroundColor Green
        $venvPyVer = python --version 2>&1
        if ($venvPyVer -notmatch "3\.(11|12)\.") {
            Write-Host "  WARNUNG: System-Python ($venvPyVer) ist NICHT kompatibel mit open-webui!" -ForegroundColor Red
            Write-Host "  open-webui benoetigt Python >=3.11, <3.13" -ForegroundColor Red
            Write-Host "  Loesung: Installiere Python 3.11 oder 'uv' (pip install uv)" -ForegroundColor Cyan
        }
    }
}

# Aktiviere venv
$aktivierungsScript = Join-Path $venvPfad "Scripts\Activate.ps1"
if (Test-Path $aktivierungsScript) {
    Write-Host "  Aktiviere Virtual Environment..." -ForegroundColor Gray
    & $aktivierungsScript
    Write-Host "  [OK] Virtual Environment aktiviert" -ForegroundColor Green
}
else {
    Write-Host "  FEHLER: Aktivierungsscript nicht gefunden: $aktivierungsScript" -ForegroundColor Red
    exit 1
}

Write-Host ""

# --- Python-Pakete ---

Write-Host "[3/7] Python-Pakete installieren..." -ForegroundColor Yellow

# Pruefe ob uv fuer schnellere Installation verfuegbar ist
$pipCmd = "pip"
$uvVorhanden = Get-Command uv -ErrorAction SilentlyContinue
if ($uvVorhanden) {
    $pipCmd = "uv pip"
    Write-Host "  Nutze uv pip (schneller)..." -ForegroundColor Gray
}

# Zeige Python-Version im venv vor Installation
$venvPythonExe = Join-Path $venvPfad "Scripts\python.exe"
if (Test-Path $venvPythonExe) {
    $venvPyVersion = & $venvPythonExe --version 2>&1
    Write-Host "  Python im venv: $venvPyVersion" -ForegroundColor Gray
}

# Pruefe ob Visual C++ Build Tools vorhanden sind (einige Pakete benoetigen sie)
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasBuildTools = $false
if (Test-Path $vsWhere) {
    $vsInstalls = & $vsWhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json 2>$null | ConvertFrom-Json
    if ($vsInstalls.Count -gt 0) { $hasBuildTools = $true }
}
if (-not $hasBuildTools) {
    Write-Host "  HINWEIS: Visual C++ Build Tools nicht erkannt." -ForegroundColor Yellow
    Write-Host "  Falls Pakete nicht installierbar sind, installiere:" -ForegroundColor Yellow
    Write-Host "  https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor Cyan
    Write-Host "  (Waehle 'Desktopentwicklung mit C++' bei der Installation)" -ForegroundColor Cyan
    Write-Host ""
}

# pip aktualisieren bevor Pakete installiert werden
Write-Host "  Aktualisiere pip..." -ForegroundColor Gray
Invoke-Expression "$pipCmd install --upgrade pip" 2>&1 | Out-Null

$pakete = @("open-webui", "mcpo", "outlook-mcp-server-windows-com", "pywin32")
foreach ($paket in $pakete) {
    Write-Host "  Installiere $paket..." -ForegroundColor Gray
    $pipOutput = Invoke-Expression "$pipCmd install $paket --no-cache-dir" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $paket" -ForegroundColor Green
    } else {
        Write-Host "  [FEHLER] $paket konnte nicht installiert werden:" -ForegroundColor Red
        # Zeige die letzten 15 Zeilen fuer bessere Fehlerdiagnose
        $pipOutput | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        Write-Host ""
        if ($paket -eq "open-webui") {
            Write-Host "  === Fehlerbehebung fuer open-webui ===" -ForegroundColor Yellow
            Write-Host "  1. Python-Version pruefen (braucht >=3.11, <3.13):" -ForegroundColor Yellow
            Write-Host "     .venv\Scripts\python --version" -ForegroundColor Cyan
            Write-Host "  2. Visual C++ Build Tools installieren:" -ForegroundColor Yellow
            Write-Host "     https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor Cyan
            Write-Host "  3. Manuell mit ausfuehrlichem Log installieren:" -ForegroundColor Yellow
            Write-Host "     .venv\Scripts\pip install open-webui -v" -ForegroundColor Cyan
            Write-Host "  4. Alternative: Fertige Wheels verwenden:" -ForegroundColor Yellow
            Write-Host "     .venv\Scripts\pip install open-webui --only-binary :all:" -ForegroundColor Cyan
        }
    }
}

Write-Host ""

# --- Ollama-Modell ---

Write-Host "[4/7] Ollama-Modell herunterladen..." -ForegroundColor Yellow
Write-Host "  Lade qwen2.5:14b (empfohlenes Modell, ca. 9 GB)..." -ForegroundColor Gray
Write-Host "  Alternative Modelle: qwen2.5:7b (kleiner), qwen2.5:32b (besser), llama3.1:8b" -ForegroundColor DarkGray

try {
    ollama pull qwen2.5:14b
    Write-Host "  [OK] Modell qwen2.5:14b heruntergeladen" -ForegroundColor Green
}
catch {
    Write-Host "  FEHLER: Modell konnte nicht heruntergeladen werden." -ForegroundColor Red
    Write-Host "  Stelle sicher, dass Ollama laeuft ('ollama serve') und versuche es erneut:" -ForegroundColor Yellow
    Write-Host "  ollama pull qwen2.5:14b" -ForegroundColor Cyan
}

Write-Host ""

# --- MCPO-Konfiguration ---

Write-Host "[5/7] MCPO-Konfiguration erstellen..." -ForegroundColor Yellow

try {
    & $buildScript
    Write-Host "  [OK] mcpo-config.json erstellt" -ForegroundColor Green
}
catch {
    Write-Host "  FEHLER: Konfiguration konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# --- Outlook-Test ---

Write-Host "[6/7] Outlook-Verbindung testen..." -ForegroundColor Yellow

if (Test-Path $testOutlookScript) {
    try {
        & $testOutlookScript
    }
    catch {
        Write-Host "  Outlook-Test fehlgeschlagen. Das ist OK, wenn Outlook nicht gestartet ist." -ForegroundColor Yellow
    }
}
else {
    Write-Host "  Test-Script nicht gefunden, ueberspringe." -ForegroundColor Gray
}

Write-Host ""

# --- Zusammenfassung ---

Write-Host "[7/7] Setup abgeschlossen!" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Setup erfolgreich!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Naechste Schritte:" -ForegroundColor Cyan
Write-Host "  1. Starte den Assistenten:  .\scripts\start.ps1" -ForegroundColor White
Write-Host "  2. Oeffne den Browser:      http://localhost:8080" -ForegroundColor White
Write-Host "  3. Erstelle einen Account in Open WebUI" -ForegroundColor White
Write-Host "  4. Richte MCPO als Tool ein: siehe docs\open-webui-einrichtung.md" -ForegroundColor White
Write-Host ""
Write-Host "Weitere Infos:" -ForegroundColor Gray
Write-Host "  Modell-Empfehlungen:  docs\modell-empfehlungen.md" -ForegroundColor DarkGray
Write-Host "  Plugins hinzufuegen:  docs\server-hinzufuegen.md" -ForegroundColor DarkGray
Write-Host "  Beispiel-Prompts:     examples\beispiel-prompts.md" -ForegroundColor DarkGray
