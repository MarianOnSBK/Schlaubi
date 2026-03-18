# Master Prompt: Erweiterbarer Lokaler KI-Assistent (ohne Docker)

## Projektbeschreibung

Erstelle ein vollständiges, sofort lauffähiges Projekt für einen **komplett lokalen, erweiterbaren KI-Assistenten** auf Windows. Der Assistent soll über eine modulare Plugin-Architektur verfügen, mit der beliebige lokale MCP-Server als Fähigkeiten hinzugefügt werden können. Als erstes Plugin wird Outlook-Zugriff mitgeliefert.

**Wichtige Einschränkungen:**
- **Kein Docker** – alles läuft nativ auf Windows
- **Keine Cloud-APIs** – der Assistent arbeitet komplett lokal
- **Keine Eigenentwicklung von MCP-Servern oder Bridges** – nur existierende, erprobte Open-Source-Tools verwenden
- **Erweiterbar** – neue Fähigkeiten lassen sich durch einfaches Hinzufügen eines MCP-Servers in eine Konfigurationsdatei ergänzen

## Technologie-Stack

| Komponente | Technologie | Installation | Zweck |
|---|---|---|---|
| LLM | **Ollama** | Windows-Installer von ollama.com | Lokales Sprachmodell |
| Chat-UI | **Open WebUI** | `pip install open-webui` → `open-webui serve` | Web-Chat auf localhost:8080 |
| MCP Bridge | **MCPO** (mit `--hot-reload`) | `pip install mcpo` | Wandelt MCP-Server in OpenAPI um, erkennt Konfig-Änderungen automatisch |
| Outlook-Zugriff | **outlook-mcp-server-windows-com** | `pip install outlook-mcp-server-windows-com` | Plugin: Greift über win32com auf lokale Outlook-App zu |
| Dateisystem | **@modelcontextprotocol/server-filesystem** | `npx -y @modelcontextprotocol/server-filesystem` | Plugin: Lesen/Schreiben lokaler Dateien |

### Hinweise zum Stack
- Open WebUI benötigt **Python 3.11** (nicht 3.12 oder 3.13)
- Open WebUI läuft auf Port **8080** (`open-webui serve`)
- MCPO läuft auf Port **8000** mit Hot-Reload (`mcpo --config mcpo-config.json --port 8000 --hot-reload`)
- Ollama läuft auf Port **11434**
- MCPO wird mit `--hot-reload` gestartet, damit neue Server erkannt werden ohne Neustart

## Kernkonzept: Plugin-Architektur

Das zentrale Design-Prinzip ist ein **Server-Katalog**. Jeder MCP-Server wird als eigenständiges Plugin behandelt:

1. Im Verzeichnis `servers/` liegt pro MCP-Server eine eigene JSON-Datei mit der Konfiguration
2. Ein PowerShell-Script `scripts/build-config.ps1` baut aus allen aktiven Server-Dateien die finale `mcpo-config.json` zusammen
3. MCPO läuft mit `--hot-reload` und erkennt Änderungen an der `mcpo-config.json` automatisch
4. Ein Script `scripts/add-server.ps1` hilft interaktiv beim Hinzufügen neuer Server
5. Ein Script `scripts/list-servers.ps1` zeigt alle installierten und aktiven Server an

So kann der Nutzer jederzeit neue Fähigkeiten hinzufügen, ohne Code zu schreiben.

## Projektstruktur

```
local-ai-assistant/
├── README.md                         # Ausführliche Anleitung (deutsch)
├── mcpo-config.json                  # GENERIERT – nicht manuell bearbeiten
│
├── servers/                          # Plugin-Verzeichnis: ein JSON pro MCP-Server
│   ├── outlook.json                  # ✅ Aktiv: Outlook E-Mail-Zugriff
│   ├── filesystem.json               # ✅ Aktiv: Lokaler Dateizugriff
│   ├── _memory.json                  # ❌ Inaktiv (Unterstrich-Präfix = deaktiviert)
│   └── README.md                     # Erklärt das Format und wie man Server hinzufügt
│
├── scripts/
│   ├── setup.ps1                     # Einmaliges Setup
│   ├── start.ps1                     # Alle Dienste starten
│   ├── stop.ps1                      # Alle Dienste stoppen
│   ├── build-config.ps1              # Baut mcpo-config.json aus servers/*.json
│   ├── add-server.ps1                # Interaktiv neuen Server hinzufügen
│   ├── list-servers.ps1              # Alle Server und Status anzeigen
│   ├── test-outlook-connection.ps1   # Outlook-COM-Verbindung testen
│   └── test-ollama-tools.ps1         # Ollama Function-Calling testen
│
├── docs/
│   ├── open-webui-einrichtung.md     # MCPO als Tool in Open WebUI einrichten
│   ├── modell-empfehlungen.md        # Modell-Vergleichstabelle
│   └── server-hinzufuegen.md         # Anleitung: Neue MCP-Server als Plugins
│
├── catalog/                          # Vorkonfigurierte Server-Vorlagen
│   ├── README.md                     # Übersicht aller verfügbaren Vorlagen
│   ├── outlook.json                  # Vorlage: Outlook (win32com, lokal)
│   ├── filesystem.json               # Vorlage: Dateisystem (Node.js)
│   ├── memory.json                   # Vorlage: Persistenter Speicher
│   ├── everything-search.json        # Vorlage: Windows Everything-Dateisuche
│   ├── fetch.json                    # Vorlage: HTTP Webseiten abrufen
│   └── sqlite.json                   # Vorlage: SQLite-Datenbank
│
└── examples/
    └── beispiel-prompts.md           # Beispiel-Prompts gruppiert nach Plugin
```

## Anforderungen an die einzelnen Dateien

---

### 1. Server-Plugin-Format (`servers/*.json`)

Jede Datei im `servers/`-Verzeichnis ist eine eigenständige Server-Konfiguration. Das Format entspricht dem Claude-Desktop-Standard, erweitert um Metadaten:

**`servers/outlook.json`:**
```json
{
  "_meta": {
    "name": "Outlook E-Mail",
    "description": "Zugriff auf lokale Outlook-E-Mails über win32com",
    "requires": "Microsoft Outlook Desktop, pywin32",
    "install": "pip install outlook-mcp-server-windows-com pywin32"
  },
  "command": "outlook-mcp-server-windows-com",
  "env": {}
}
```

**`servers/filesystem.json`:**
```json
{
  "_meta": {
    "name": "Dateisystem",
    "description": "Lesen und Schreiben von lokalen Dateien",
    "requires": "Node.js 18+",
    "install": "npm install -g @modelcontextprotocol/server-filesystem"
  },
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "C:\\Users\\%USERNAME%\\Documents"],
  "env": {}
}
```

**Konvention:** Dateien mit Unterstrich-Präfix (`_memory.json`) sind deaktiviert und werden beim Build ignoriert. So kann man Server ein-/ausschalten, ohne sie zu löschen.

---

### 2. `scripts/build-config.ps1`

Dieses Script ist das Herzstück der Plugin-Architektur:

- Liest alle `*.json`-Dateien aus `servers/` (ignoriert Dateien mit `_`-Präfix und `README.md`)
- Extrahiert aus jeder Datei alles außer dem `_meta`-Block
- Baut daraus eine valide `mcpo-config.json` im Format:
  ```json
  {
    "mcpServers": {
      "outlook": { "command": "...", "env": {} },
      "filesystem": { "command": "...", "args": [...], "env": {} }
    }
  }
  ```
- Der Servername wird aus dem Dateinamen abgeleitet (ohne `.json`)
- Ersetzt Umgebungsvariablen wie `%USERNAME%` durch ihre tatsächlichen Werte
- Gibt eine Übersicht aus welche Server aktiviert/deaktiviert sind
- Wird automatisch von `start.ps1` aufgerufen

---

### 3. `scripts/add-server.ps1`

Interaktives Script zum Hinzufügen neuer MCP-Server:

1. Fragt den Nutzer: "Möchtest du eine Vorlage aus dem Katalog verwenden?" → Zeigt verfügbare Vorlagen aus `catalog/`
2. Wenn ja: Kopiert die Vorlage nach `servers/`, fragt nach individuellen Anpassungen (z.B. Dateipfade)
3. Wenn nein: Fragt interaktiv nach:
   - Servername (wird zum Dateinamen)
   - Beschreibung
   - Befehl (`command`)
   - Argumente (`args`) – optional
   - Umgebungsvariablen (`env`) – optional
   - Installationsbefehl
4. Erstellt die JSON-Datei in `servers/`
5. Führt den Installationsbefehl aus (mit Bestätigung)
6. Ruft `build-config.ps1` auf, um die Konfiguration zu aktualisieren
7. Gibt einen Hinweis aus: "MCPO erkennt die Änderung automatisch dank Hot-Reload"

---

### 4. `scripts/list-servers.ps1`

- Liest alle JSON-Dateien in `servers/`
- Zeigt eine formatierte Tabelle:
  ```
  Status    Name                 Beschreibung
  ------    ----                 ------------
  ✅ Aktiv  outlook              Zugriff auf lokale Outlook-E-Mails über win32com
  ✅ Aktiv  filesystem           Lesen und Schreiben von lokalen Dateien
  ❌ Aus    memory               Persistenter Speicher für Konversationen
  ```
- Zeigt am Ende: "X von Y Servern aktiv"
- Hinweis: "Server aktivieren: Unterstrich vom Dateinamen entfernen"
- Hinweis: "Server deaktivieren: Unterstrich vor Dateinamen setzen"

---

### 5. `catalog/` – Vorkonfigurierte Server-Vorlagen

Jede Vorlage ist eine JSON-Datei mit `_meta`-Block. Der Katalog enthält folgende Server:

**`catalog/outlook.json`** – Outlook E-Mail (win32com, kein Azure nötig)
- command: `outlook-mcp-server-windows-com`
- install: `pip install outlook-mcp-server-windows-com pywin32`

**`catalog/filesystem.json`** – Dateisystem-Zugriff
- command: `npx`, args: `["-y", "@modelcontextprotocol/server-filesystem", "PFAD"]`
- install: Node.js muss installiert sein
- Hinweis in `_meta`: Nutzer muss den Pfad anpassen

**`catalog/memory.json`** – Persistenter Speicher / Notizen
- command: `npx`, args: `["-y", "@modelcontextprotocol/server-memory"]`
- install: Node.js muss installiert sein

**`catalog/everything-search.json`** – Windows Everything-Dateisuche (extrem schnell)
- command: `uvx`, args: `["mcp-server-everything-search"]`
- install: `pip install mcp-server-everything-search` + Everything von voidtools.com muss installiert sein
- env: `EVERYTHING_SDK_PATH` muss gesetzt werden

**`catalog/fetch.json`** – HTTP Webseiten abrufen
- command: `uvx`, args: `["mcp-server-fetch"]`
- install: `pip install mcp-server-fetch`

**`catalog/sqlite.json`** – SQLite-Datenbank-Zugriff
- command: `uvx`, args: `["mcp-server-sqlite", "--db-path", "PFAD"]`
- install: `pip install mcp-server-sqlite`
- Hinweis: Nutzer muss Datenbank-Pfad anpassen

**`catalog/README.md`** – Übersicht mit Tabelle:

| Vorlage | Beschreibung | Voraussetzungen | Lokal/Offline |
|---|---|---|---|
| outlook | E-Mails lesen/suchen/senden | Outlook Desktop | ✅ Ja |
| filesystem | Dateien lesen/schreiben | Node.js | ✅ Ja |
| memory | Persistentes Gedächtnis | Node.js | ✅ Ja |
| everything-search | Blitzschnelle Dateisuche | Everything (voidtools) | ✅ Ja |
| fetch | Webseiten abrufen | Python | ❌ Nein (Internet) |
| sqlite | SQLite-Datenbanken | Python | ✅ Ja |

Plus Hinweis: "Eigene Vorlagen können einfach als JSON-Datei im selben Format hinzugefügt werden."
Plus Verweis auf MCP-Server-Verzeichnisse: https://mcpservers.org, https://glama.ai/mcp/servers, https://github.com/modelcontextprotocol/servers

---

### 6. `scripts/setup.ps1`

Vollständiges Setup-Skript:

**Prüfungen:**
- Windows als OS
- Python installiert + Version (Warnung wenn nicht 3.11)
- Node.js installiert (für filesystem und andere npx-basierte Server)
- Ollama installiert (falls nicht: Anweisung + Link)
- Microsoft Outlook Desktop installiert

**Installation:**
- Erstellt Python Virtual Environment `.venv` (bevorzugt mit `uv venv --python 3.11`, Fallback: `python -m venv`)
- Aktiviert venv
- Installiert Python-Pakete: `open-webui`, `mcpo`, `outlook-mcp-server-windows-com`, `pywin32`
- Lädt Ollama-Modell: `ollama pull qwen2.5:14b` (mit Kommentaren zu Alternativen)
- Ruft `build-config.ps1` auf, um die initiale `mcpo-config.json` zu generieren
- Testet Outlook-COM-Verbindung

**Fehlerbehandlung:** try/catch, farbige Ausgaben, idempotent

---

### 7. `scripts/start.ps1`

Startet alle Dienste:

1. Prüft ob Outlook geöffnet ist (Warnung falls nicht)
2. Ruft `build-config.ps1` auf (generiert/aktualisiert mcpo-config.json)
3. Prüft/startet Ollama (`ollama serve` als Hintergrundprozess falls nötig)
4. Startet **MCPO mit `--hot-reload`** als Hintergrundprozess:
   - `mcpo --config .\mcpo-config.json --port 8000 --hot-reload`
   - PID in `.mcpo.pid` speichern
5. Startet **Open WebUI** als Hintergrundprozess:
   - Umgebungsvariable `OLLAMA_BASE_URL=http://localhost:11434`
   - `open-webui serve`
   - PID in `.openwebui.pid` speichern
6. Gibt URLs aus + öffnet Browser nach 10s

**Wichtig:** Durch `--hot-reload` erkennt MCPO automatisch Änderungen an `mcpo-config.json`. Der Nutzer kann also `add-server.ps1` ausführen oder `servers/*.json` bearbeiten, und die neuen Tools erscheinen in Open WebUI ohne Neustart.

---

### 8. `scripts/stop.ps1`

- Beendet Open WebUI (über `.openwebui.pid`)
- Beendet MCPO (über `.mcpo.pid`)
- Optional: Ollama beenden (mit Rückfrage)
- PID-Dateien aufräumen

---

### 9. `scripts/test-outlook-connection.ps1`

- Testet win32com-Verbindung über Python
- Listet Outlook-Ordner auf
- Zeigt letzte 3 E-Mail-Betreffzeilen
- Klare Fehlermeldungen

---

### 10. `scripts/test-ollama-tools.ps1`

- Sendet Test-Request an Ollama mit einer Tool-Definition
- Prüft ob Tool-Call zurückkommt
- Gibt Erfolg/Fehler aus

---

### 11. `docs/server-hinzufuegen.md`

Ausführliche Anleitung auf Deutsch: "So fügst du neue Fähigkeiten hinzu"

**Methode 1: Aus dem Katalog (empfohlen)**
```powershell
.\scripts\add-server.ps1
# → Wähle "filesystem" aus dem Katalog
# → Passe den Dateipfad an
# → Fertig! MCPO lädt den Server automatisch nach.
```

**Methode 2: Manuell**
1. Erstelle eine neue Datei in `servers/`, z.B. `servers/mein-server.json`
2. Format:
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
3. Führe `.\scripts\build-config.ps1` aus (oder starte `start.ps1` neu)
4. MCPO erkennt die Änderung automatisch (Hot-Reload)

**Methode 3: mcpo-config.json direkt bearbeiten**
- Für fortgeschrittene Nutzer
- Achtung: Wird beim nächsten `build-config.ps1`-Aufruf überschrieben!

**Server deaktivieren:** Dateiname mit Unterstrich versehen → `_mein-server.json`
**Server aktivieren:** Unterstrich entfernen → `mein-server.json`

**Wo finde ich MCP-Server?**
- https://mcpservers.org
- https://glama.ai/mcp/servers
- https://github.com/modelcontextprotocol/servers

**Wie finde ich die richtige Konfiguration?**
- Die meisten MCP-Server dokumentieren ihre Claude-Desktop-Konfiguration im README
- Dieses Format ist identisch mit dem `servers/*.json`-Format (nur `_meta` hinzufügen)

---

### 12. `docs/open-webui-einrichtung.md`

Schritt-für-Schritt-Anleitung:
1. http://localhost:8080 öffnen
2. Admin-Account erstellen
3. Ollama-Verbindung prüfen (Settings → Connections → `http://localhost:11434`)
4. MCPO als Tool-Server hinzufügen (Settings → Tools → `http://localhost:8000`)
5. Chat starten, Modell wählen, Tools aktivieren

Hinweis: Wenn neue Server über `add-server.ps1` hinzugefügt werden, erscheinen sie nach Hot-Reload automatisch. Ggf. muss die Tool-Verbindung in Open WebUI einmal aktualisiert werden (Refresh-Button).

---

### 13. `docs/modell-empfehlungen.md`

| Modell | Befehl | VRAM | RAM (CPU) | Tool-Calling | Empfehlung |
|---|---|---|---|---|---|
| qwen2.5:7b | `ollama pull qwen2.5:7b` | ~6 GB | ~8 GB | Mäßig | Testen |
| qwen2.5:14b | `ollama pull qwen2.5:14b` | ~12 GB | ~16 GB | Gut | **Empfohlen** |
| qwen2.5:32b | `ollama pull qwen2.5:32b` | ~20 GB | ~32 GB | Sehr gut | Beste Balance |
| llama3.1:8b | `ollama pull llama3.1:8b` | ~6 GB | ~8 GB | Gut | Alternative |
| llama3.1:70b | `ollama pull llama3.1:70b` | ~40 GB | ~64 GB | Exzellent | High-End |

Plus Erklärungen zu CPU-Offloading, Modellwechsel, Modell löschen.

---

### 14. `examples/beispiel-prompts.md`

Beispiel-Prompts **gruppiert nach Plugin/Server**:

**📧 Outlook (E-Mail):**
- "Fasse mir alle E-Mails von heute zusammen"
- "Suche nach E-Mails zum Thema Deployment"
- "Was steht in der letzten E-Mail von Max Müller?"
- "Welche ungelesenen E-Mails habe ich?"
- "Liste alle meine E-Mail-Ordner auf"

**📁 Dateisystem:**
- "Lies die Datei C:\Users\ich\Documents\notizen.txt"
- "Erstelle eine Zusammenfassung aller .md Dateien in meinem Projekte-Ordner"
- "Suche nach Dateien mit dem Namen 'Rechnung' in meinen Dokumenten"
- "Zeige mir die Verzeichnisstruktur von meinem Projekte-Ordner"

**🔗 Kombinierte Anfragen (mehrere Plugins):**
- "Suche in meinen E-Mails nach dem Projektbericht und speichere eine Zusammenfassung als Textdatei"
- "Lies die Datei Aufgaben.txt und erstelle daraus eine E-Mail an mein Team"

**🧠 Memory (wenn aktiviert):**
- "Merke dir: Mein aktuelles Projekt heißt Phoenix und der Deadline ist der 15. April"
- "Was habe ich dir letztens über das Phoenix-Projekt erzählt?"

**🔍 Everything Search (wenn aktiviert):**
- "Finde alle PDF-Dateien die das Wort 'Vertrag' im Namen haben"
- "Wo liegt die Datei 'präsentation_q4.pptx' auf meinem PC?"

---

### 15. `README.md`

Ausführliche, deutschsprachige README:

#### Titel
```
# 🤖 Lokaler KI-Assistent (erweiterbar)
> Ein komplett lokaler, erweiterbarer KI-Assistent für Windows – ohne Cloud, ohne Docker.
> Starte mit Outlook-E-Mails und füge per Plugin-System beliebige Fähigkeiten hinzu.
```

#### Highlights
- 📧 E-Mails lesen, suchen und zusammenfassen
- 📁 Lokale Dateien lesen und schreiben
- 🔌 Plugin-System: Neue Fähigkeiten per JSON-Datei hinzufügen
- 🔄 Hot-Reload: Neue Plugins ohne Neustart verfügbar
- 🔒 100% lokal – keine Daten verlassen deinen PC
- 🖥️ Schöne Web-Oberfläche über Open WebUI

#### Architektur
```
Du (Browser, http://localhost:8080)
  │
  └── Open WebUI ──── Chat-Oberfläche
          │
          ├── Ollama (localhost:11434) ──── Lokales LLM
          │
          └── MCPO (localhost:8000, hot-reload) ──── MCP→OpenAPI Bridge
                  │
                  ├── 📧 outlook-mcp-server ──── win32com → Outlook Desktop
                  ├── 📁 filesystem-server ──── Node.js → Lokale Dateien
                  ├── 🧠 memory-server ──── Persistentes Gedächtnis
                  └── 🔌 ... weitere Plugins aus servers/
```

#### Voraussetzungen
- Windows 10/11
- Microsoft Outlook Desktop (für E-Mail-Plugin)
- Python 3.11
- Node.js 18+ (für Dateisystem- und andere npx-Server)
- Min. 16 GB RAM, GPU mit 8+ GB VRAM empfohlen
- Ca. 10-30 GB Festplatte

#### Schnellstart
1. Ollama installieren: https://ollama.com/download
2. `git clone ... && cd local-ai-assistant`
3. `.\scripts\setup.ps1`
4. `.\scripts\start.ps1`
5. MCPO einrichten: → `docs/open-webui-einrichtung.md`
6. Chatten!

#### Plugin-System
Erklärt das Konzept kurz mit Verweis auf `docs/server-hinzufuegen.md`:
```powershell
# Neues Plugin aus dem Katalog hinzufügen:
.\scripts\add-server.ps1

# Alle installierten Plugins anzeigen:
.\scripts\list-servers.ps1

# Plugin deaktivieren (Unterstrich vor Dateinamen):
Rename-Item servers\memory.json servers\_memory.json

# Plugin aktivieren:
Rename-Item servers\_memory.json servers\memory.json
```

#### Mitgelieferte Plugins
Tabelle mit outlook und filesystem als aktiv, + Verweis auf `catalog/README.md` für weitere

#### Modell-Empfehlungen
Kurztabelle + Verweis auf `docs/modell-empfehlungen.md`

#### Troubleshooting
| Problem | Lösung |
|---|---|
| Outlook nicht verbunden | Outlook Desktop muss geöffnet sein |
| MCPO startet nicht | venv aktiviert? `mcpo` installiert? |
| Kein Tool-Calling | Größeres Modell verwenden (mind. 14B) |
| Keine Tools in Open WebUI | `http://localhost:8000` unter Admin → Settings → Tools |
| Open WebUI startet nicht | Port 8080 frei? Python 3.11? |
| Neuer Server erscheint nicht | `build-config.ps1` ausführen, Open WebUI Tool-Verbindung refreshen |
| Node.js Server funktioniert nicht | `node --version` prüfen (mind. v18) |

#### Sicherheit & Datenschutz
- Alle Daten lokal
- Kein Internet nötig nach Setup
- Nur localhost erreichbar
- Jeder MCP-Server hat nur Zugriff auf explizit konfigurierte Ressourcen

#### Weiterentwicklung
- Verweis auf `docs/server-hinzufuegen.md`
- Verweis auf MCP-Verzeichnisse: mcpservers.org, glama.ai, github.com/modelcontextprotocol/servers
- Verweis auf MCPO-Docs: https://github.com/open-webui/mcpo

#### Lizenz
MIT

---

## Qualitätsanforderungen

1. **Alles auf Deutsch** – README, Docs, Script-Ausgaben, Kommentare
2. **Kein Docker** – alles nativ auf Windows
3. **Plugin-Architektur** ist das zentrale Design-Prinzip – `servers/`-Verzeichnis, `_meta`-Block, Build-Script, Hot-Reload
4. **PowerShell-Scripts** mit try/catch, farbigen Ausgaben (Grün/Gelb/Rot), informativen Meldungen
5. **Keine Cloud-Abhängigkeiten** nach dem Setup
6. **Idempotente Scripts** – mehrfach ausführbar ohne Fehler
7. **Virtual Environment** (`.venv`) für alle Python-Pakete
8. **Hot-Reload** – MCPO wird immer mit `--hot-reload` gestartet
9. **README für Nicht-Entwickler** – klare Schritt-für-Schritt-Anleitungen
10. **Alle Pfade relativ** zum Projektverzeichnis
11. **PID-Management** für Hintergrundprozesse
12. **Katalog und Server-Dateien** sind sauber getrennt (Vorlagen vs. aktive Konfiguration)
13. **Umgebungsvariablen** in Server-Configs (z.B. `%USERNAME%`) werden beim Build aufgelöst
14. **`mcpo-config.json` wird generiert** – nie manuell bearbeiten, immer über `build-config.ps1`
