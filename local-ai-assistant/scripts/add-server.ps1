# add-server.ps1 - Interaktiv einen neuen MCP-Server als Plugin hinzufügen

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$serversVerzeichnis = Join-Path $projektVerzeichnis "servers"
$catalogVerzeichnis = Join-Path $projektVerzeichnis "catalog"
$buildScript = Join-Path $projektVerzeichnis "scripts\build-config.ps1"

Write-Host "`n=== Neuen MCP-Server hinzufuegen ===" -ForegroundColor Cyan
Write-Host ""

# Frage ob Vorlage verwendet werden soll
$vorlagen = Get-ChildItem -Path $catalogVerzeichnis -Filter "*.json" -File 2>$null
if ($vorlagen -and $vorlagen.Count -gt 0) {
    Write-Host "Verfuegbare Vorlagen aus dem Katalog:" -ForegroundColor Yellow
    Write-Host ""

    $index = 1
    $vorlagenListe = @()
    foreach ($vorlage in $vorlagen) {
        try {
            $inhalt = Get-Content -Path $vorlage.FullName -Raw | ConvertFrom-Json
            $name = if ($inhalt._meta.name) { $inhalt._meta.name } else { $vorlage.BaseName }
            $beschreibung = if ($inhalt._meta.description) { $inhalt._meta.description } else { "-" }
            Write-Host "  [$index] $name" -ForegroundColor White -NoNewline
            Write-Host " - $beschreibung" -ForegroundColor Gray
            $vorlagenListe += $vorlage
        }
        catch {
            Write-Host "  [$index] $($vorlage.BaseName)" -ForegroundColor White -NoNewline
            Write-Host " - (Fehler beim Lesen)" -ForegroundColor Red
            $vorlagenListe += $vorlage
        }
        $index++
    }

    Write-Host "  [0] Manuell eingeben (ohne Vorlage)" -ForegroundColor DarkCyan
    Write-Host ""

    $auswahl = Read-Host "Vorlage waehlen (Nummer)"

    if ($auswahl -ne "0" -and $auswahl -match '^\d+$') {
        $auswahlIndex = [int]$auswahl - 1
        if ($auswahlIndex -ge 0 -and $auswahlIndex -lt $vorlagenListe.Count) {
            $gewaehlteVorlage = $vorlagenListe[$auswahlIndex]
            $inhalt = Get-Content -Path $gewaehlteVorlage.FullName -Raw | ConvertFrom-Json

            Write-Host ""
            Write-Host "Vorlage: $($inhalt._meta.name)" -ForegroundColor Green
            Write-Host "Beschreibung: $($inhalt._meta.description)" -ForegroundColor Gray
            if ($inhalt._meta.requires) {
                Write-Host "Voraussetzungen: $($inhalt._meta.requires)" -ForegroundColor Yellow
            }
            if ($inhalt._meta.hinweis) {
                Write-Host "Hinweis: $($inhalt._meta.hinweis)" -ForegroundColor Yellow
            }
            Write-Host ""

            # Servername bestimmen
            $serverName = Read-Host "Servername (Enter fuer '$($gewaehlteVorlage.BaseName)')"
            if ([string]::IsNullOrWhiteSpace($serverName)) {
                $serverName = $gewaehlteVorlage.BaseName
            }

            # Prüfen ob Server schon existiert
            $zielDatei = Join-Path $serversVerzeichnis "$serverName.json"
            if (Test-Path $zielDatei) {
                Write-Host "WARNUNG: Server '$serverName' existiert bereits!" -ForegroundColor Red
                $ueberschreiben = Read-Host "Ueberschreiben? (j/n)"
                if ($ueberschreiben -ne "j") {
                    Write-Host "Abgebrochen." -ForegroundColor Yellow
                    exit 0
                }
            }

            # Vorlage kopieren
            Copy-Item -Path $gewaehlteVorlage.FullName -Destination $zielDatei -Force
            Write-Host ""
            Write-Host "Server '$serverName' nach servers/ kopiert." -ForegroundColor Green

            # Optional: Pfade anpassen
            $inhaltText = Get-Content -Path $zielDatei -Raw
            if ($inhaltText -match 'PFAD|Pfad\\zur') {
                Write-Host ""
                Write-Host "Diese Vorlage enthaelt Platzhalter-Pfade!" -ForegroundColor Yellow
                $anpassen = Read-Host "Moechtest du die Datei jetzt bearbeiten? (j/n)"
                if ($anpassen -eq "j") {
                    notepad $zielDatei
                    Write-Host "Bitte speichere die Datei und druecke Enter..." -ForegroundColor Cyan
                    Read-Host
                }
            }

            # Installation
            if ($inhalt._meta.install) {
                Write-Host ""
                Write-Host "Installationsbefehl: $($inhalt._meta.install)" -ForegroundColor Cyan
                $installieren = Read-Host "Jetzt installieren? (j/n)"
                if ($installieren -eq "j") {
                    Write-Host "Fuehre aus: $($inhalt._meta.install)" -ForegroundColor Gray
                    try {
                        Invoke-Expression $inhalt._meta.install
                        Write-Host "Installation erfolgreich!" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "Installation fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "Du kannst den Befehl spaeter manuell ausfuehren." -ForegroundColor Yellow
                    }
                }
            }

            # Config neu bauen
            Write-Host ""
            Write-Host "Aktualisiere mcpo-config.json..." -ForegroundColor Cyan
            & $buildScript

            Write-Host ""
            Write-Host "Fertig! MCPO erkennt die Aenderung automatisch dank Hot-Reload." -ForegroundColor Green
            Write-Host "Der neue Server sollte in Kuerze in Open WebUI verfuegbar sein." -ForegroundColor Cyan
            exit 0
        }
        else {
            Write-Host "Ungueltige Auswahl." -ForegroundColor Red
            exit 1
        }
    }
}

# Manuelle Eingabe
Write-Host "Manuell einen neuen Server konfigurieren:" -ForegroundColor Yellow
Write-Host ""

$serverName = Read-Host "Servername (wird zum Dateinamen, z.B. 'mein-tool')"
if ([string]::IsNullOrWhiteSpace($serverName)) {
    Write-Host "Kein Name angegeben. Abgebrochen." -ForegroundColor Red
    exit 1
}

# Prüfen ob Server schon existiert
$zielDatei = Join-Path $serversVerzeichnis "$serverName.json"
if (Test-Path $zielDatei) {
    Write-Host "WARNUNG: Server '$serverName' existiert bereits!" -ForegroundColor Red
    $ueberschreiben = Read-Host "Ueberschreiben? (j/n)"
    if ($ueberschreiben -ne "j") {
        Write-Host "Abgebrochen." -ForegroundColor Yellow
        exit 0
    }
}

$beschreibung = Read-Host "Beschreibung"
$command = Read-Host "Befehl (command)"
if ([string]::IsNullOrWhiteSpace($command)) {
    Write-Host "Kein Befehl angegeben. Abgebrochen." -ForegroundColor Red
    exit 1
}

$argsEingabe = Read-Host "Argumente (kommagetrennt, oder leer lassen)"
$args_array = @()
if (-not [string]::IsNullOrWhiteSpace($argsEingabe)) {
    $args_array = $argsEingabe -split "," | ForEach-Object { $_.Trim() }
}

$envEingabe = Read-Host "Umgebungsvariablen (KEY=VALUE kommagetrennt, oder leer lassen)"
$envObj = @{}
if (-not [string]::IsNullOrWhiteSpace($envEingabe)) {
    $envPaare = $envEingabe -split "," | ForEach-Object { $_.Trim() }
    foreach ($paar in $envPaare) {
        $teile = $paar -split "=", 2
        if ($teile.Count -eq 2) {
            $envObj[$teile[0].Trim()] = $teile[1].Trim()
        }
    }
}

$voraussetzungen = Read-Host "Voraussetzungen (was muss installiert sein?)"
$installBefehl = Read-Host "Installationsbefehl (oder leer lassen)"

# JSON erstellen
$serverConfig = [ordered]@{
    _meta = [ordered]@{
        name = if ([string]::IsNullOrWhiteSpace($beschreibung)) { $serverName } else { $beschreibung.Split("-")[0].Trim() }
        description = $beschreibung
        requires = $voraussetzungen
        install = $installBefehl
    }
    command = $command
}

if ($args_array.Count -gt 0) {
    $serverConfig["args"] = $args_array
}

$serverConfig["env"] = $envObj

$jsonOutput = $serverConfig | ConvertTo-Json -Depth 10
Set-Content -Path $zielDatei -Value $jsonOutput -Encoding UTF8

Write-Host ""
Write-Host "Server-Konfiguration erstellt: $zielDatei" -ForegroundColor Green

# Installation anbieten
if (-not [string]::IsNullOrWhiteSpace($installBefehl)) {
    Write-Host ""
    Write-Host "Installationsbefehl: $installBefehl" -ForegroundColor Cyan
    $installieren = Read-Host "Jetzt installieren? (j/n)"
    if ($installieren -eq "j") {
        try {
            Invoke-Expression $installBefehl
            Write-Host "Installation erfolgreich!" -ForegroundColor Green
        }
        catch {
            Write-Host "Installation fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Du kannst den Befehl spaeter manuell ausfuehren." -ForegroundColor Yellow
        }
    }
}

# Config neu bauen
Write-Host ""
Write-Host "Aktualisiere mcpo-config.json..." -ForegroundColor Cyan
& $buildScript

Write-Host ""
Write-Host "Fertig! MCPO erkennt die Aenderung automatisch dank Hot-Reload." -ForegroundColor Green
Write-Host "Der neue Server sollte in Kuerze in Open WebUI verfuegbar sein." -ForegroundColor Cyan
