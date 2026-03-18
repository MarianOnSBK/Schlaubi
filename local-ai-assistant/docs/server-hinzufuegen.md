# So fuegst du neue Faehigkeiten hinzu

Der KI-Assistent kann durch MCP-Server beliebig erweitert werden. Jeder MCP-Server ist ein Plugin, das eine neue Faehigkeit bereitstellt.

## Methode 1: Aus dem Katalog (empfohlen)

Am einfachsten ueber das interaktive Script:

```powershell
.\scripts\add-server.ps1
# → Waehle z.B. "filesystem" aus dem Katalog
# → Passe den Dateipfad an
# → Fertig! MCPO laedt den Server automatisch nach.
```

Das Script:
1. Zeigt alle verfuegbaren Vorlagen aus `catalog/`
2. Kopiert die gewaehlte Vorlage nach `servers/`
3. Fragt nach individuellen Anpassungen (z.B. Dateipfade)
4. Fuehrt den Installationsbefehl aus (mit Bestaetigung)
5. Aktualisiert die MCPO-Konfiguration

## Methode 2: Manuell

1. Erstelle eine neue Datei in `servers/`, z.B. `servers/mein-server.json`

2. Verwende folgendes Format:

```json
{
  "_meta": {
    "name": "Mein Server",
    "description": "Was er tut",
    "requires": "Was installiert sein muss",
    "install": "Installationsbefehl"
  },
  "command": "befehl",
  "args": ["arg1", "arg2"],
  "env": {
    "VARIABLE": "wert"
  }
}
```

3. Baue die Konfiguration neu:

```powershell
.\scripts\build-config.ps1
```

4. MCPO erkennt die Aenderung automatisch (Hot-Reload)

## Methode 3: mcpo-config.json direkt bearbeiten

Fuer fortgeschrittene Nutzer ist es moeglich, die `mcpo-config.json` direkt zu bearbeiten.

**Achtung:** Die Datei wird beim naechsten Aufruf von `build-config.ps1` ueberschrieben! Aenderungen gehen verloren, wenn du sie nicht auch in `servers/` eintraegst.

## Server deaktivieren / aktivieren

```powershell
# Server deaktivieren (Unterstrich vor Dateinamen):
Rename-Item servers\memory.json servers\_memory.json

# Server aktivieren (Unterstrich entfernen):
Rename-Item servers\_memory.json servers\memory.json

# Config neu bauen:
.\scripts\build-config.ps1
```

MCPO erkennt die Aenderung automatisch dank Hot-Reload.

## Alle Server anzeigen

```powershell
.\scripts\list-servers.ps1
```

Zeigt eine Tabelle aller installierten Server mit Status (aktiv/deaktiviert).

## Wo finde ich MCP-Server?

Es gibt inzwischen hunderte MCP-Server fuer verschiedenste Zwecke:

- **https://mcpservers.org** - Umfassendes Verzeichnis
- **https://glama.ai/mcp/servers** - Kuratierte Sammlung
- **https://github.com/modelcontextprotocol/servers** - Offizielle Server

## Wie finde ich die richtige Konfiguration?

Die meisten MCP-Server dokumentieren ihre **Claude-Desktop-Konfiguration** im README. Dieses Format ist identisch mit dem `servers/*.json`-Format. Du musst nur den `_meta`-Block hinzufuegen.

**Beispiel:** Ein MCP-Server dokumentiert:

```json
{
  "mcpServers": {
    "mein-tool": {
      "command": "uvx",
      "args": ["mcp-server-mein-tool"],
      "env": {}
    }
  }
}
```

Daraus wird fuer `servers/mein-tool.json`:

```json
{
  "_meta": {
    "name": "Mein Tool",
    "description": "Beschreibung",
    "requires": "Python",
    "install": "pip install mcp-server-mein-tool"
  },
  "command": "uvx",
  "args": ["mcp-server-mein-tool"],
  "env": {}
}
```

## Tipps

- Teste neue Server nach der Installation mit einer einfachen Anfrage
- Deaktiviere Server die du nicht brauchst, um Ressourcen zu sparen
- Pruefe die Tool-Verbindung in Open WebUI nach dem Hinzufuegen (Refresh-Button)
- Bei Problemen: Pruefe ob alle Voraussetzungen installiert sind (`_meta.requires`)
