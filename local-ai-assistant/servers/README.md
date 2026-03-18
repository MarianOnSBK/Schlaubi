# Server-Verzeichnis (Plugin-Konfigurationen)

Dieses Verzeichnis enthält die **aktiven MCP-Server-Konfigurationen**. Jede JSON-Datei entspricht einem Plugin.

## Format

Jede Datei hat folgendes Format:

```json
{
  "_meta": {
    "name": "Anzeigename",
    "description": "Was der Server tut",
    "requires": "Voraussetzungen",
    "install": "Installationsbefehl"
  },
  "command": "startbefehl",
  "args": ["arg1", "arg2"],
  "env": {
    "VARIABLE": "wert"
  }
}
```

## Felder

| Feld | Pflicht | Beschreibung |
|---|---|---|
| `_meta` | Optional | Metadaten (werden beim Build ignoriert) |
| `command` | Ja | Der Befehl zum Starten des Servers |
| `args` | Nein | Kommandozeilen-Argumente als Array |
| `env` | Nein | Umgebungsvariablen als Key-Value-Paare |

## Server aktivieren / deaktivieren

- **Aktiv:** Normaler Dateiname, z.B. `outlook.json`
- **Deaktiviert:** Unterstrich-Präfix, z.B. `_memory.json`

```powershell
# Server deaktivieren:
Rename-Item servers\memory.json servers\_memory.json

# Server aktivieren:
Rename-Item servers\_memory.json servers\memory.json
```

## Neuen Server hinzufügen

1. **Aus dem Katalog:** `.\scripts\add-server.ps1`
2. **Manuell:** Neue JSON-Datei in diesem Verzeichnis erstellen
3. **Config neu bauen:** `.\scripts\build-config.ps1`

MCPO erkennt Änderungen automatisch dank Hot-Reload.

## Hinweise

- Die Datei `mcpo-config.json` im Stammverzeichnis wird **automatisch generiert** – nicht manuell bearbeiten!
- Umgebungsvariablen wie `%USERNAME%` werden beim Build durch ihre tatsächlichen Werte ersetzt.
- Der Servername in der generierten Config entspricht dem Dateinamen (ohne `.json`).
