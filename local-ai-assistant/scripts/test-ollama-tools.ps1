# test-ollama-tools.ps1 - Testet Ollama Function-Calling (Tool-Use)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Ollama Tool-Calling testen ===" -ForegroundColor Cyan
Write-Host ""

# Prüfe ob Ollama erreichbar ist
Write-Host "Pruefe Ollama-Verbindung..." -ForegroundColor Yellow
try {
    $tags = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5
    Write-Host "  [OK] Ollama erreichbar" -ForegroundColor Green

    if ($tags.models.Count -eq 0) {
        Write-Host "  WARNUNG: Kein Modell installiert!" -ForegroundColor Red
        Write-Host "  Installiere ein Modell: ollama pull qwen2.5:14b" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  Installierte Modelle:" -ForegroundColor Gray
    foreach ($modell in $tags.models) {
        Write-Host "    - $($modell.name)" -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "  FEHLER: Ollama ist nicht erreichbar auf http://localhost:11434" -ForegroundColor Red
    Write-Host "  Starte Ollama: ollama serve" -ForegroundColor Yellow
    exit 1
}

# Test-Request mit Tool-Definition
Write-Host ""
Write-Host "Sende Test-Anfrage mit Tool-Definition..." -ForegroundColor Yellow

# Verwende das erste verfügbare Modell
$modell = $tags.models[0].name
Write-Host "  Verwende Modell: $modell" -ForegroundColor Gray

$body = @{
    model = $modell
    messages = @(
        @{
            role = "user"
            content = "Wie ist das Wetter in Berlin? Benutze das get_weather Tool."
        }
    )
    tools = @(
        @{
            type = "function"
            function = @{
                name = "get_weather"
                description = "Gibt das aktuelle Wetter fuer einen Ort zurueck"
                parameters = @{
                    type = "object"
                    properties = @{
                        location = @{
                            type = "string"
                            description = "Der Ort, z.B. 'Berlin'"
                        }
                    }
                    required = @("location")
                }
            }
        }
    )
    stream = $false
} | ConvertTo-Json -Depth 10

try {
    $antwort = Invoke-RestMethod -Uri "http://localhost:11434/api/chat" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 60

    Write-Host ""

    if ($antwort.message.tool_calls -and $antwort.message.tool_calls.Count -gt 0) {
        Write-Host "[OK] Tool-Calling funktioniert!" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Erkannter Tool-Call:" -ForegroundColor White
        foreach ($toolCall in $antwort.message.tool_calls) {
            Write-Host "    Funktion: $($toolCall.function.name)" -ForegroundColor Cyan
            Write-Host "    Parameter: $($toolCall.function.arguments | ConvertTo-Json -Compress)" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "[WARNUNG] Kein Tool-Call in der Antwort." -ForegroundColor Yellow
        Write-Host "  Das Modell '$modell' unterstuetzt moeglicherweise kein Tool-Calling." -ForegroundColor Yellow
        Write-Host "  Empfohlene Modelle: qwen2.5:14b, qwen2.5:32b, llama3.1:8b" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Antwort des Modells:" -ForegroundColor Gray
        Write-Host "  $($antwort.message.content)" -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "[FEHLER] Anfrage fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Stelle sicher, dass Ollama laeuft und ein Modell installiert ist." -ForegroundColor Yellow
}

Write-Host ""
