# list-servers.ps1 - Zeigt alle installierten und aktiven MCP-Server an

$ErrorActionPreference = "Stop"
$projektVerzeichnis = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$serversVerzeichnis = Join-Path $projektVerzeichnis "servers"

Write-Host "`n=== Installierte MCP-Server ===" -ForegroundColor Cyan
Write-Host ""

# Prüfe ob servers-Verzeichnis existiert
if (-not (Test-Path $serversVerzeichnis)) {
    Write-Host "Verzeichnis 'servers/' nicht gefunden." -ForegroundColor Red
    exit 1
}

$alleDateien = Get-ChildItem -Path $serversVerzeichnis -Filter "*.json" -File

if ($alleDateien.Count -eq 0) {
    Write-Host "Keine Server konfiguriert." -ForegroundColor Yellow
    Write-Host "Verwende '.\scripts\add-server.ps1' um einen Server hinzuzufuegen." -ForegroundColor Cyan
    exit 0
}

# Tabellenkopf
$format = "{0,-10} {1,-22} {2}"
Write-Host ($format -f "Status", "Name", "Beschreibung") -ForegroundColor White
Write-Host ($format -f "------", "----", "------------") -ForegroundColor DarkGray

$aktiveAnzahl = 0
$gesamtAnzahl = 0

foreach ($datei in ($alleDateien | Sort-Object Name)) {
    $gesamtAnzahl++
    $istAktiv = -not $datei.Name.StartsWith("_")
    $name = $datei.BaseName
    if (-not $istAktiv) {
        $name = $name.TrimStart("_")
    }

    $beschreibung = "-"
    try {
        $inhalt = Get-Content -Path $datei.FullName -Raw | ConvertFrom-Json
        if ($inhalt._meta.description) {
            $beschreibung = $inhalt._meta.description
        }
    }
    catch {
        $beschreibung = "(Fehler beim Lesen)"
    }

    if ($istAktiv) {
        $aktiveAnzahl++
        $statusText = "Aktiv"
        Write-Host ($format -f $statusText, $name, $beschreibung) -ForegroundColor Green
    }
    else {
        $statusText = "Aus"
        Write-Host ($format -f $statusText, $name, $beschreibung) -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "$aktiveAnzahl von $gesamtAnzahl Servern aktiv" -ForegroundColor Cyan
Write-Host ""
Write-Host "Server aktivieren:    Unterstrich vom Dateinamen entfernen" -ForegroundColor Gray
Write-Host "Server deaktivieren:  Unterstrich vor Dateinamen setzen" -ForegroundColor Gray
Write-Host ""
Write-Host "Beispiel:" -ForegroundColor Gray
Write-Host "  Rename-Item servers\_memory.json servers\memory.json    # Aktivieren" -ForegroundColor DarkGray
Write-Host "  Rename-Item servers\memory.json servers\_memory.json    # Deaktivieren" -ForegroundColor DarkGray
