# Open WebUI einrichten - MCPO als Tool verbinden

Diese Anleitung erklaert Schritt fuer Schritt, wie du MCPO als Tool-Server in Open WebUI einrichtest.

## Voraussetzung

Alle Dienste muessen laufen:

```powershell
.\scripts\start.ps1
```

## Schritt 1: Open WebUI oeffnen

Oeffne deinen Browser und gehe zu:

```
http://localhost:8080
```

## Schritt 2: Admin-Account erstellen

Beim ersten Start wirst du aufgefordert, einen Account zu erstellen. Dieser Account ist rein lokal und hat nichts mit Cloud-Diensten zu tun.

- Waehle einen Benutzernamen und Passwort
- Der erste Account wird automatisch zum Admin

## Schritt 3: Ollama-Verbindung pruefen

1. Klicke auf dein Profilbild (oben rechts) → **Admin Panel**
2. Gehe zu **Settings** → **Connections**
3. Unter **Ollama API** sollte stehen: `http://localhost:11434`
4. Klicke auf das Refresh-Symbol um die Verbindung zu testen
5. Wenn die Verbindung steht, siehst du die installierten Modelle

Falls die Verbindung fehlschlaegt:
- Pruefe ob Ollama laeuft: `ollama list`
- Starte Ollama manuell: `ollama serve`

## Schritt 4: MCPO als Tool-Server hinzufuegen

1. Gehe zu **Admin Panel** → **Settings** → **Tools**
2. Klicke auf **+** (Neuen Server hinzufuegen)
3. Gib die URL ein: `http://localhost:8000`
4. Klicke auf **Speichern**
5. Die verfuegbaren Tools sollten jetzt angezeigt werden

## Schritt 5: Chat starten

1. Gehe zurueck zur Chat-Ansicht
2. Waehle ein Modell (z.B. `qwen2.5:14b`)
3. Aktiviere die Tools ueber das Werkzeug-Symbol im Chat
4. Stelle eine Frage wie: "Zeige mir meine neuesten E-Mails"

## Neue Plugins nach Hot-Reload

Wenn du neue Server ueber `.\scripts\add-server.ps1` hinzufuegst:

1. MCPO erkennt die Aenderung automatisch (Hot-Reload)
2. Gehe in Open WebUI zu **Admin Panel** → **Settings** → **Tools**
3. Klicke auf das **Refresh-Symbol** neben der MCPO-Verbindung
4. Die neuen Tools sollten nun verfuegbar sein

## Troubleshooting

| Problem | Loesung |
|---|---|
| "Connection refused" bei MCPO | Pruefe ob MCPO laeuft: `http://localhost:8000/docs` im Browser |
| Keine Tools sichtbar | Refresh-Button in den Tool-Einstellungen klicken |
| Modell nutzt Tools nicht | Groesseres Modell verwenden (mind. 14B Parameter) |
| Timeout bei Tool-Aufrufen | MCPO oder der jeweilige MCP-Server antwortet nicht |
