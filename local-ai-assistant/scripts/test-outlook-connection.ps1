# test-outlook-connection.ps1 - Testet die Outlook-COM-Verbindung

$ErrorActionPreference = "Stop"

Write-Host "`n=== Outlook-Verbindung testen ===" -ForegroundColor Cyan
Write-Host ""

# Teste über Python (wie der MCP-Server es auch tut)
$pythonTest = @"
import sys
try:
    import win32com.client
    print("[OK] pywin32 ist installiert")
except ImportError:
    print("[FEHLER] pywin32 ist nicht installiert!")
    print("  Installiere mit: pip install pywin32")
    sys.exit(1)

try:
    outlook = win32com.client.Dispatch("Outlook.Application")
    mapi = outlook.GetNamespace("MAPI")
    print("[OK] Outlook-COM-Verbindung hergestellt")
except Exception as e:
    print(f"[FEHLER] Kann nicht mit Outlook verbinden: {e}")
    print("  Stelle sicher, dass Microsoft Outlook Desktop geoeffnet ist.")
    sys.exit(1)

try:
    ordner = mapi.Folders
    print(f"\nGefundene E-Mail-Konten/Ordner:")
    for i in range(ordner.Count):
        folder = ordner.Item(i + 1)
        print(f"  - {folder.Name}")
except Exception as e:
    print(f"[WARNUNG] Ordner konnten nicht aufgelistet werden: {e}")

try:
    inbox = mapi.GetDefaultFolder(6)  # 6 = Posteingang
    nachrichten = inbox.Items
    nachrichten.Sort("[ReceivedTime]", True)
    anzahl = min(3, nachrichten.Count)

    if anzahl > 0:
        print(f"\nLetzte {anzahl} E-Mails im Posteingang:")
        for i in range(anzahl):
            mail = nachrichten.Item(i + 1)
            print(f"  - {mail.Subject} (von: {mail.SenderName})")
    else:
        print("\nPosteingang ist leer.")
except Exception as e:
    print(f"[WARNUNG] E-Mails konnten nicht gelesen werden: {e}")

print("\n[OK] Outlook-Verbindung funktioniert!")
"@

try {
    $pythonTest | python -
    Write-Host ""
    Write-Host "Test erfolgreich!" -ForegroundColor Green
}
catch {
    Write-Host "Test fehlgeschlagen." -ForegroundColor Red
    Write-Host "Moegliche Ursachen:" -ForegroundColor Yellow
    Write-Host "  - Microsoft Outlook Desktop ist nicht installiert" -ForegroundColor Yellow
    Write-Host "  - Outlook ist nicht geoeffnet" -ForegroundColor Yellow
    Write-Host "  - pywin32 ist nicht installiert (pip install pywin32)" -ForegroundColor Yellow
    Write-Host "  - Virtual Environment ist nicht aktiviert" -ForegroundColor Yellow
}
