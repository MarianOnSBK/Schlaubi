# build-config.ps1 - Baut mcpo-config.json aus servers/*.json
# Validiert jeden Server vor dem Einbau - fehlende Executables werden uebersprungen
# Damit laeuft MCPO zuverlaessig, auch wenn einzelne Server nicht installiert sind

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$serversVerzeichnis = Join-Path $projektVerzeichnis "servers"
$configDatei = Join-Path $projektVerzeichnis "mcpo-config.json"
$venvPfad = Join-Path $projektVerzeichnis ".venv"

Write-Host "`n=== MCPO-Konfiguration erstellen ===" -ForegroundColor Cyan
Write-Host ""

# Pruefe ob servers-Verzeichnis existiert
if (-not (Test-Path $serversVerzeichnis)) {
    Write-Host "FEHLER: Verzeichnis 'servers/' nicht gefunden!" -ForegroundColor Red
    Write-Host "Erwartet: $serversVerzeichnis" -ForegroundColor Yellow
    exit 1
}

# Sammle alle JSON-Dateien
$alleDateien = Get-ChildItem -Path $serversVerzeichnis -Filter "*.json" -File
$aktiveDateien = $alleDateien | Where-Object { -not $_.Name.StartsWith("_") }
$inaktiveDateien = $alleDateien | Where-Object { $_.Name.StartsWith("_") }

if ($alleDateien.Count -eq 0) {
    Write-Host "WARNUNG: Keine Server-Konfigurationen in 'servers/' gefunden." -ForegroundColor Yellow
    Write-Host "Verwende '.\scripts\add-server.ps1' um einen Server hinzuzufuegen." -ForegroundColor Yellow
    $leereConfig = @{ mcpServers = @{} } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($configDatei, $leereConfig, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Leere mcpo-config.json erstellt." -ForegroundColor Yellow
    exit 0
}

# --- Hilfsfunktion: Prueft ob ein Executable verfuegbar ist ---
function Test-ServerExecutable {
    param([string]$Command)
    # Im PATH suchen
    $cmd = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # Im venv suchen
    $venvExe = Join-Path $venvPfad "Scripts\$Command.exe"
    if (Test-Path $venvExe) { return $venvExe }
    return $null
}

# Baue mcpServers-Objekt
$mcpServers = @{}
$fehler = @()
$uebersprungen = @()
$aufgenommen = @()

foreach ($datei in $aktiveDateien) {
    $serverName = $datei.BaseName
    try {
        $inhalt = Get-Content -Path $datei.FullName -Raw | ConvertFrom-Json

        # command ist Pflicht
        if (-not $inhalt.command) {
            $fehler += "  FEHLER: $($datei.Name) hat kein 'command'-Feld"
            continue
        }

        # --- Validierung: Ist das Executable verfuegbar? ---
        $cmdPfad = Test-ServerExecutable -Command $inhalt.command
        if (-not $cmdPfad) {
            $uebersprungen += $serverName
            $installHinweis = ""
            if ($inhalt._meta -and $inhalt._meta.install) {
                $installHinweis = " | Installieren: $($inhalt._meta.install)"
            }
            Write-Host "  [SKIP] $serverName - '$($inhalt.command)' nicht gefunden$installHinweis" -ForegroundColor Yellow
            continue
        }

        # Erstelle Server-Eintrag ohne _meta-Block
        $serverEintrag = @{}
        $serverEintrag["command"] = $inhalt.command

        # args ist optional
        if ($inhalt.args) {
            $aufgeloesteArgs = @()
            foreach ($arg in $inhalt.args) {
                $aufgeloest = $arg
                $matches_found = [regex]::Matches($aufgeloest, '%(\w+)%')
                foreach ($match in $matches_found) {
                    $varName = $match.Groups[1].Value
                    $varValue = [Environment]::GetEnvironmentVariable($varName)
                    if ($varValue) {
                        $aufgeloest = $aufgeloest -replace [regex]::Escape($match.Value), $varValue
                    }
                }
                $aufgeloesteArgs += $aufgeloest
            }
            $serverEintrag["args"] = $aufgeloesteArgs
        }

        # env ist optional
        if ($inhalt.env) {
            $aufgeloestesEnv = @{}
            foreach ($prop in $inhalt.env.PSObject.Properties) {
                $wert = $prop.Value
                $matches_found = [regex]::Matches($wert, '%(\w+)%')
                foreach ($match in $matches_found) {
                    $varName = $match.Groups[1].Value
                    $varValue = [Environment]::GetEnvironmentVariable($varName)
                    if ($varValue) {
                        $wert = $wert -replace [regex]::Escape($match.Value), $varValue
                    }
                }
                $aufgeloestesEnv[$prop.Name] = $wert
            }
            $serverEintrag["env"] = $aufgeloestesEnv
        }

        $mcpServers[$serverName] = $serverEintrag
        $aufgenommen += $serverName
        Write-Host "  [OK] $serverName - $($inhalt.command) ($cmdPfad)" -ForegroundColor Green
    }
    catch {
        $fehler += "  FEHLER: $($datei.Name) - $($_.Exception.Message) (Tipp: JSON-Syntax mit einem Online-Validator pruefen)"
    }
}

# Inaktive Server anzeigen
foreach ($datei in $inaktiveDateien) {
    $name = $datei.BaseName.TrimStart("_")
    Write-Host "  [--] $name - Deaktiviert (Datei: $($datei.Name))" -ForegroundColor DarkGray
}

# Uebersprungene Server hervorheben
if ($uebersprungen.Count -gt 0) {
    Write-Host ""
    Write-Host "Uebersprungene Server (Executable fehlt):" -ForegroundColor Yellow
    foreach ($s in $uebersprungen) {
        Write-Host "  - $s (servers\$s.json ist aktiv, aber Programm nicht installiert)" -ForegroundColor Yellow
    }
    Write-Host "  Installiere fehlende Server oder deaktiviere sie: ren servers\NAME.json _NAME.json" -ForegroundColor Yellow
}

# Fehler anzeigen
if ($fehler.Count -gt 0) {
    Write-Host ""
    Write-Host "Fehler beim Verarbeiten:" -ForegroundColor Red
    foreach ($f in $fehler) {
        Write-Host $f -ForegroundColor Red
    }
}

# Config-Datei schreiben
$config = @{
    mcpServers = $mcpServers
}

$jsonOutput = $config | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($configDatei, $jsonOutput, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "mcpo-config.json erstellt:" -ForegroundColor Green
Write-Host "  Aufgenommen:       $($aufgenommen.Count) ($($aufgenommen -join ', '))" -ForegroundColor Green
if ($uebersprungen.Count -gt 0) {
    Write-Host "  Uebersprungen:     $($uebersprungen.Count) ($($uebersprungen -join ', '))" -ForegroundColor Yellow
}
Write-Host "  Deaktiviert:       $($inaktiveDateien.Count)" -ForegroundColor DarkGray
Write-Host "  Gesamt:            $($alleDateien.Count)" -ForegroundColor White
Write-Host ""
Write-Host "Datei: $configDatei" -ForegroundColor Cyan
Write-Host "MCPO erkennt Aenderungen automatisch (Hot-Reload)." -ForegroundColor Cyan
