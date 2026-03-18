# Lokaler KI-Assistent (erweiterbar)

> Ein komplett lokaler, erweiterbarer KI-Assistent fuer Windows – ohne Cloud, ohne Docker.
> Starte mit Outlook-E-Mails und fuege per Plugin-System beliebige Faehigkeiten hinzu.

## Highlights

- E-Mails lesen, suchen und zusammenfassen (Outlook)
- Lokale Dateien lesen und schreiben
- Plugin-System: Neue Faehigkeiten per JSON-Datei hinzufuegen
- Hot-Reload: Neue Plugins ohne Neustart verfuegbar
- 100% lokal – keine Daten verlassen deinen PC
- Schoene Web-Oberflaeche ueber Open WebUI

## Architektur

```
Du (Browser, http://localhost:8080)
  │
  └── Open WebUI ──── Chat-Oberflaeche
          │
          ├── Ollama (localhost:11434) ──── Lokales LLM
          │
          └── MCPO (localhost:8000, hot-reload) ──── MCP→OpenAPI Bridge
                  │
                  ├── outlook-mcp-server ──── win32com → Outlook Desktop
                  ├── filesystem-server ──── Node.js → Lokale Dateien
                  ├── memory-server ──── Persistentes Gedaechtnis
                  └── ... weitere Plugins aus servers/
```

## Voraussetzungen

- Windows 10/11
- Microsoft Outlook Desktop (fuer E-Mail-Plugin)
- Python 3.11
- Node.js 18+ (fuer Dateisystem- und andere npx-Server)
- Min. 16 GB RAM, GPU mit 8+ GB VRAM empfohlen
- Ca. 10-30 GB Festplatte

## Schnellstart

1. **Ollama installieren:** https://ollama.com/download
2. **Projekt klonen:**
   ```powershell
   git clone <repository-url>
   cd local-ai-assistant
   ```
3. **Setup ausfuehren:**
   ```powershell
   .\scripts\setup.ps1
   ```
4. **Starten:**
   ```powershell
   .\scripts\start.ps1
   ```
5. **MCPO einrichten:** Siehe `docs\open-webui-einrichtung.md`
6. **Chatten!** Oeffne http://localhost:8080

## Plugin-System

Das zentrale Design-Prinzip ist ein Server-Katalog. Jeder MCP-Server wird als eigenstaendiges Plugin behandelt.

```powershell
# Neues Plugin aus dem Katalog hinzufuegen:
.\scripts\add-server.ps1

# Alle installierten Plugins anzeigen:
.\scripts\list-servers.ps1

# Plugin deaktivieren (Unterstrich vor Dateinamen):
Rename-Item servers\memory.json servers\_memory.json

# Plugin aktivieren:
Rename-Item servers\_memory.json servers\memory.json
```

Ausfuehrliche Anleitung: `docs\server-hinzufuegen.md`

## Mitgelieferte Plugins

| Plugin | Status | Beschreibung |
|---|---|---|
| outlook | Aktiv | Zugriff auf lokale Outlook-E-Mails ueber win32com |
| filesystem | Aktiv | Lesen und Schreiben von lokalen Dateien |
| memory | Deaktiviert | Persistenter Speicher fuer Konversationen |

Weitere vorkonfigurierte Vorlagen findest du in `catalog\README.md`.

## Modell-Empfehlungen

| Modell | VRAM | Tool-Calling | Empfehlung |
|---|---|---|---|
| qwen2.5:7b | ~6 GB | Maessig | Zum Testen |
| **qwen2.5:14b** | **~12 GB** | **Gut** | **Empfohlen** |
| qwen2.5:32b | ~20 GB | Sehr gut | Beste Balance |
| llama3.1:8b | ~6 GB | Gut | Alternative |

Ausfuehrliche Infos: `docs\modell-empfehlungen.md`

## Troubleshooting

| Problem | Loesung |
|---|---|
| Outlook nicht verbunden | Outlook Desktop muss geoeffnet sein |
| MCPO startet nicht | venv aktiviert? `mcpo` installiert? |
| Kein Tool-Calling | Groesseres Modell verwenden (mind. 14B) |
| Keine Tools in Open WebUI | `http://localhost:8000` unter Admin → Settings → Tools |
| Open WebUI startet nicht | Port 8080 frei? Python 3.11? |
| Neuer Server erscheint nicht | `build-config.ps1` ausfuehren, Open WebUI Tool-Verbindung refreshen |
| Node.js Server funktioniert nicht | `node --version` pruefen (mind. v18) |

## Sicherheit & Datenschutz

- Alle Daten bleiben lokal auf deinem PC
- Kein Internet noetig nach dem Setup
- Nur ueber localhost erreichbar
- Jeder MCP-Server hat nur Zugriff auf explizit konfigurierte Ressourcen

## Weiterentwicklung

- Neue Plugins hinzufuegen: `docs\server-hinzufuegen.md`
- MCP-Server finden:
  - https://mcpservers.org
  - https://glama.ai/mcp/servers
  - https://github.com/modelcontextprotocol/servers
- MCPO-Dokumentation: https://github.com/open-webui/mcpo

## Lizenz

MIT
