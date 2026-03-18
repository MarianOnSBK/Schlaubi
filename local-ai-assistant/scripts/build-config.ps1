# build-config.ps1 - Baut mcpo-config.json aus servers/*.json
# Herzstück der Plugin-Architektur

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$serversVerzeichnis = Join-Path $projektVerzeichnis "servers"
$configDatei = Join-Path $projektVerzeichnis "mcpo-config.json"

Write-Host "`n=== MCPO-Konfiguration erstellen ===" -ForegroundColor Cyan
Write-Host ""

# Prüfe ob servers-Verzeichnis existiert
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
    Write-Host "Verwende '.\scripts\add-server.ps1' um einen Server hinzuzufügen." -ForegroundColor Yellow
    # Erstelle leere Config
    $leereConfig = @{ mcpServers = @{} } | ConvertTo-Json -Depth 10
    Set-Content -Path $configDatei -Value $leereConfig -Encoding UTF8
    Write-Host "Leere mcpo-config.json erstellt." -ForegroundColor Yellow
    exit 0
}

# Baue mcpServers-Objekt
$mcpServers = @{}
$fehler = @()

foreach ($datei in $aktiveDateien) {
    $serverName = $datei.BaseName
    try {
        $inhalt = Get-Content -Path $datei.FullName -Raw | ConvertFrom-Json

        # Erstelle Server-Eintrag ohne _meta-Block
        $serverEintrag = @{}

        # command ist Pflicht
        if (-not $inhalt.command) {
            $fehler += "  FEHLER: $($datei.Name) hat kein 'command'-Feld"
            continue
        }
        $serverEintrag["command"] = $inhalt.command

        # args ist optional
        if ($inhalt.args) {
            # Umgebungsvariablen in args ersetzen (z.B. %USERNAME% -> tatsaechlicher Wert)
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
        Write-Host "  [OK] $serverName - Aktiv" -ForegroundColor Green
    }
    catch {
        $fehler += "  FEHLER: $($datei.Name) - $($_.Exception.Message)"
    }
}

# Inaktive Server anzeigen
foreach ($datei in $inaktiveDateien) {
    $name = $datei.BaseName.TrimStart("_")
    Write-Host "  [--] $name - Deaktiviert (Datei: $($datei.Name))" -ForegroundColor DarkGray
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
Set-Content -Path $configDatei -Value $jsonOutput -Encoding UTF8

Write-Host ""
Write-Host "mcpo-config.json erfolgreich erstellt!" -ForegroundColor Green
Write-Host "  Aktive Server:     $($aktiveDateien.Count)" -ForegroundColor White
Write-Host "  Deaktivierte:      $($inaktiveDateien.Count)" -ForegroundColor DarkGray
Write-Host "  Gesamt:            $($alleDateien.Count)" -ForegroundColor White
Write-Host ""
Write-Host "Datei: $configDatei" -ForegroundColor Cyan
Write-Host "MCPO erkennt Aenderungen automatisch (Hot-Reload)." -ForegroundColor Cyan
