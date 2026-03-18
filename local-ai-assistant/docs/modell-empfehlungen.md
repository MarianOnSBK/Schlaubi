# Modell-Empfehlungen

Uebersicht der empfohlenen lokalen LLM-Modelle fuer den KI-Assistenten.

## Vergleichstabelle

| Modell | Befehl | VRAM | RAM (CPU) | Tool-Calling | Empfehlung |
|---|---|---|---|---|---|
| qwen2.5:7b | `ollama pull qwen2.5:7b` | ~6 GB | ~8 GB | Maessig | Zum Testen |
| **qwen2.5:14b** | `ollama pull qwen2.5:14b` | **~12 GB** | **~16 GB** | **Gut** | **Empfohlen** |
| qwen2.5:32b | `ollama pull qwen2.5:32b` | ~20 GB | ~32 GB | Sehr gut | Beste Balance |
| llama3.1:8b | `ollama pull llama3.1:8b` | ~6 GB | ~8 GB | Gut | Alternative |
| llama3.1:70b | `ollama pull llama3.1:70b` | ~40 GB | ~64 GB | Exzellent | High-End |

## Empfehlung

**qwen2.5:14b** ist das empfohlene Standardmodell:
- Gutes Tool-Calling (wichtig fuer MCP-Server)
- Laeuft auf den meisten Gaming-GPUs (12 GB VRAM)
- Gute Balance zwischen Geschwindigkeit und Qualitaet
- Versteht Deutsch gut

## CPU-Offloading

Wenn deine GPU nicht genug VRAM hat, verlagert Ollama automatisch Teile des Modells in den RAM (CPU-Offloading). Das funktioniert, ist aber deutlich langsamer.

**Faustregel:**
- Modell passt komplett in VRAM → schnell (GPU-Inferenz)
- Modell wird teilweise in RAM ausgelagert → mittel
- Modell laeuft komplett auf CPU → langsam, aber funktioniert

## Modell wechseln

```powershell
# Neues Modell herunterladen
ollama pull qwen2.5:32b

# In Open WebUI: Einfach das Modell im Dropdown oben links wechseln
```

## Modell loeschen

```powershell
# Modell entfernen (spart Speicherplatz)
ollama rm qwen2.5:7b
```

## Installierte Modelle anzeigen

```powershell
ollama list
```

## Hinweise zum Tool-Calling

Nicht alle Modelle unterstuetzen Tool-Calling gleich gut. Fuer den KI-Assistenten ist Tool-Calling essentiell, da er so die MCP-Server (E-Mail, Dateisystem, etc.) nutzen kann.

**Testen:**
```powershell
.\scripts\test-ollama-tools.ps1
```

Wenn das Modell keine Tool-Calls erzeugt, probiere ein groesseres Modell (mind. 14B Parameter).
