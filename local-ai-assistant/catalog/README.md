# Katalog: Vorkonfigurierte Server-Vorlagen

Dieser Ordner enthält **Vorlagen** für MCP-Server, die du als Plugins hinzufügen kannst. Die Vorlagen werden nicht direkt verwendet, sondern nach `servers/` kopiert und dort aktiviert.

## Verfügbare Vorlagen

| Vorlage | Beschreibung | Voraussetzungen | Lokal/Offline |
|---|---|---|---|
| outlook | E-Mails lesen/suchen/senden | Outlook Desktop | ✅ Ja |
| filesystem | Dateien lesen/schreiben | Node.js | ✅ Ja |
| memory | Persistentes Gedächtnis | Node.js | ✅ Ja |
| everything-search | Blitzschnelle Dateisuche | Everything (voidtools) | ✅ Ja |
| fetch | Webseiten abrufen | Python | ❌ Nein (Internet) |
| sqlite | SQLite-Datenbanken | Python | ✅ Ja |

## Vorlage verwenden

Am einfachsten über das interaktive Script:

```powershell
.\scripts\add-server.ps1
```

Oder manuell:

```powershell
# Vorlage nach servers/ kopieren
Copy-Item catalog\memory.json servers\memory.json

# Ggf. Pfade anpassen
notepad servers\memory.json

# Config neu bauen
.\scripts\build-config.ps1
```

MCPO erkennt die Änderung automatisch dank Hot-Reload.

## Eigene Vorlagen erstellen

Du kannst eigene Vorlagen als JSON-Datei im selben Format in diesem Ordner ablegen. Das Format entspricht dem Claude-Desktop-Standard, erweitert um einen `_meta`-Block:

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
  "env": {}
}
```

## Wo finde ich weitere MCP-Server?

- https://mcpservers.org
- https://glama.ai/mcp/servers
- https://github.com/modelcontextprotocol/servers
