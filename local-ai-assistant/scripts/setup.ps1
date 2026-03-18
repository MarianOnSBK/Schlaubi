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

# Python prüfen
try {
    $pythonVersion = python --version 2>&1
    Write-Host "  [OK] Python gefunden: $pythonVersion" -ForegroundColor Green
    if ($pythonVersion -notmatch "3\.11") {
        Write-Host "  WARNUNG: Python 3.11 wird empfohlen! Open WebUI funktioniert moeglicherweise nicht mit anderen Versionen." -ForegroundColor Yellow
        Write-Host "  Installiert: $pythonVersion" -ForegroundColor Yellow
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
    Write-Host "  Virtual Environment existiert bereits." -ForegroundColor Gray
}
else {
    # Versuche zuerst uv, dann Fallback auf python -m venv
    try {
        $uvVorhanden = Get-Command uv -ErrorAction SilentlyContinue
        if ($uvVorhanden) {
            Write-Host "  Erstelle venv mit uv (Python 3.11)..." -ForegroundColor Gray
            uv venv --python 3.11 $venvPfad
        }
        else {
            throw "uv nicht gefunden"
        }
    }
    catch {
        Write-Host "  Erstelle venv mit python -m venv..." -ForegroundColor Gray
        python -m venv $venvPfad
    }
    Write-Host "  [OK] Virtual Environment erstellt" -ForegroundColor Green
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

$pakete = @("open-webui", "mcpo", "outlook-mcp-server-windows-com", "pywin32")
foreach ($paket in $pakete) {
    Write-Host "  Installiere $paket..." -ForegroundColor Gray
    $pipOutput = pip install $paket 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $paket" -ForegroundColor Green
    } else {
        Write-Host "  [FEHLER] $paket konnte nicht installiert werden:" -ForegroundColor Red
        $pipOutput | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
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
