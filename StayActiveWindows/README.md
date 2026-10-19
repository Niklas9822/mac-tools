# StayActive (Windows)

Kleines Programm für den Infobereich der Taskleiste (☕ unten rechts), das deinen PC aktiv hält –
damit z. B. Microsoft Teams dich nicht auf „Abwesend“ setzt und der PC nicht in den Energiesparmodus geht.
Das Gegenstück zur [macOS-Version](../StayActive/README.md), mit denselben Funktionen.

- **Eine einzige Datei** (`StayActive.exe`, unter 100 KB) – keine Installation, kein Dienst.
- **Keine Administratorrechte nötig.** Es wird nichts nach *Programme* oder in `HKEY_LOCAL_MACHINE` geschrieben.
- Windows 10 und 11 (.NET Framework 4.8 ist dort bereits enthalten).

## Download

**[StayActive.exe](https://github.com/Niklas9822/mac-tools/releases/download/stayactive-windows/StayActive.exe)**
(oder als [Zip](https://github.com/Niklas9822/mac-tools/releases/download/stayactive-windows/StayActive-Windows.zip))

Am besten an einen festen Ort legen, z. B. `Dokumente\Tools\StayActive.exe`, und doppelklicken.
Die Tasse erscheint unten rechts im Infobereich. Windows 11 versteckt neue Symbole gern hinter dem
Pfeil **^** – einfach in die Taskleiste ziehen, damit sie immer sichtbar ist
(oder *Einstellungen → Personalisierung → Taskleiste → Weitere Symbole der Taskleiste → StayActive: Ein*).

### „Der Computer wurde durch Windows geschützt“

Weil das Programm nicht (kostenpflichtig) signiert ist, warnt Windows SmartScreen beim ersten Start.
Dann auf **„Weitere Informationen“** und danach **„Trotzdem ausführen“** klicken.
Alternativ vor dem ersten Start: Rechtsklick auf `StayActive.exe` → *Eigenschaften* → unten **„Zulassen“** anhaken → OK.

### Firmen-PCs

Auf verwalteten PCs (AppLocker, Intune, „Smart App Control“ o. Ä.) können nicht signierte Programme komplett
gesperrt sein. Dann startet StayActive nicht oder wird sofort beendet – dafür gibt es keinen Workaround,
das entscheidet die IT. Bitte keine Sperren umgehen.

## So sieht's aus

- **Tasse im Infobereich**: farbig gefüllt mit Dampf = aktiv, graue Umriss-Tasse = aus (PC darf schlafen).
  Läuft ein Zeitraum, steht die **Restzeit im Symbol**: `45` (Minuten), `2h` (Stunden), in der letzten Minute `<1`.
  Bei „Unbegrenzt“ nur die Tasse.
- **Tooltip** (Maus über die Tasse): z. B. „StayActive: aktiv bis 15:40 (noch 1:23)“.
- **Klick** (links oder rechts) öffnet das Menü, **Doppelklick** schaltet direkt ein/aus (unbegrenzt).
- **Bestätigung**: Beim Starten, Verlängern, Ausschalten und Ablaufen erscheint kurz eine Windows-Benachrichtigung,
  z. B. „Aktiv für 2 Std. – bis 15:40“ oder „StayActive aus – PC darf wieder schlafen“. Keine Berechtigung nötig;
  ist *Nicht stören* / *Benachrichtigungen aus* eingeschaltet, zeigt Windows sie nicht an.

## Menü

- **Status oben** (fett): „Aktiv – noch 1 Std. 23 Min. (bis 15:40)“, „Aktiv – unbegrenzt“ oder
  „Aus – PC darf schlafen“. Läuft bei offenem Menü sekundengenau mit.
- **Jetzt ausschalten** / **Jetzt aktivieren (unbegrenzt)**, bei laufendem Zeitraum zusätzlich **Verlängern um 30 Min.**
- **Starten für …**: Unbegrenzt, 15 Min., 30 Min., 1 / 2 / 4 / 8 Std., **Bis Feierabend** (Standard 17:00,
  ausgegraut wenn schon vorbei), **Bis Uhrzeit …** (Uhrzeit wählen, liegt sie schon hinter dir: morgen) und
  **Eigene Dauer …** (z. B. `90`, `1:30` oder `2h`). Ein Klick startet sofort bzw. neu; das Häkchen zeigt die
  aktive Auswahl. Nach Ablauf schaltet sich StayActive selbst ab.
- **Optionen**:
  - **Maus-Impuls (Teams-Status)** (Standard: an): bewegt den Mauszeiger um 1 Pixel hin und zurück – aber nur,
    wenn du gerade selbst nichts tust. Das ist der zuverlässigste Weg, damit Teams grün bleibt.
  - **Impuls-Intervall**: 30 s / 1 / 2 / 4 Minuten (Standard: 1 Minute; Teams wird nach ca. 5 Min. gelb).
  - **Feierabend-Zeit ändern …**, **Restzeit im Symbol anzeigen**, **Bestätigung einblenden**.
  - **Beim Start automatisch aktivieren**: schaltet beim Programmstart immer ein (unbegrenzt), auch wenn es zuletzt aus war.
  - **Mit Windows starten**: Eintrag unter `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`
    (nur für deinen Benutzer, ohne Adminrechte). Auch in *Task-Manager → Autostart* sichtbar.
  - **Info …** (Version, Speicherort).
- **StayActive beenden**.

Was StayActive tut, solange es aktiv ist:

1. `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)` – kein Energiesparmodus,
   der Bildschirm bleibt an (dasselbe, was Video-Player beim Abspielen tun).
2. Optional der Maus-Impuls per `SendInput`, nur wenn du mindestens ~80 % des Intervalls nichts getan hast
   (`GetLastInputInfo`). Beim Arbeiten zuckt also nichts.

Ein laufender Zeitraum übersteht einen Neustart des Programms: Startest du StayActive vor Ablauf neu, läuft der
Countdown weiter; ist die Zeit inzwischen abgelaufen, bleibt es aus. Nach dem Aufwachen aus dem Ruhezustand
(z. B. Laptop zugeklappt) wird der Ablauf sofort geprüft.

## Hinweise

- Ist gerade ein Fenster **mit Administratorrechten** im Vordergrund (z. B. eine als Admin gestartete Konsole),
  blockiert Windows den Maus-Impuls (UIPI). Der Energiesparmodus bleibt trotzdem verhindert; Teams kann dann
  aber auf „Abwesend“ springen, bis wieder ein normales Fenster vorne ist.
- Bei **gesperrtem Bildschirm** (Win + L) zeigt Teams dich unabhängig davon als abwesend.
- Das Zuklappen des Laptops bzw. der Ein/Aus-Knopf schickt den PC trotzdem schlafen – das lässt sich nur in den
  Energieoptionen ändern.
- Startest du `StayActive.exe` ein zweites Mal, kommt nur der Hinweis, dass es bereits läuft.

## Deinstallieren

1. Menü → *Optionen* → **Mit Windows starten** ausschalten (falls an).
2. Menü → **StayActive beenden**.
3. `StayActive.exe` löschen.
4. Optional die Einstellungen entfernen: Registrierungs-Editor (`regedit`) → `HKEY_CURRENT_USER\Software\StayActive`
   löschen, oder in einer Eingabeaufforderung: `reg delete HKCU\Software\StayActive /f`

## Selbst bauen

Auf Windows mit dem [.NET SDK](https://dotnet.microsoft.com/download) (8 oder neuer):

```bat
git clone https://github.com/Niklas9822/mac-tools.git
cd mac-tools
dotnet build StayActiveWindows/StayActive.csproj -c Release
```

Ergebnis: `StayActiveWindows\bin\Release\StayActive.exe`. Das Ziel ist .NET Framework 4.8 (C# 7.3, WinForms);
die Referenz-Assemblies kommen per NuGet (`Microsoft.NETFramework.ReferenceAssemblies`). Kompilieren klappt
damit auch unter Linux/macOS – ausführen natürlich nur unter Windows.

GitHub Actions (`.github/workflows/stayactive-windows.yml`) baut bei jedem PR auf `windows-latest` und lädt bei
Merge nach `main` `StayActive.exe` und `StayActive-Windows.zip` ins Release `stayactive-windows`.

| Datei | Inhalt |
|---|---|
| `src/Program.cs` | Start, Einzelinstanz (Mutex), Fehlerbehandlung |
| `src/TrayApp.cs` | `ApplicationContext`: Tray-Symbol, Menü, Timer/Restzeit, Aktionen, Aufwachen aus dem Ruhezustand |
| `src/KeepAlive.cs` | `SetThreadExecutionState`, Maus-Impuls (`SendInput`), Leerlaufzeit (`GetLastInputInfo`) |
| `src/IconRenderer.cs` | Tassen-Symbol mit GDI+ zur Laufzeit (aus/aktiv/Restzeit), HICON-Freigabe |
| `src/Prefs.cs` | Einstellungen in `HKCU\Software\StayActive`, Autostart (`HKCU\…\Run`) |
| `src/TimeText.cs` | Restzeit-/Uhrzeit-Texte, „Eigene Dauer“ parsen |
| `src/Dialogs.cs` | Dialoge „Bis Uhrzeit“, „Eigene Dauer“, Meldungen |
| `src/NativeMethods.cs` | Win32-Deklarationen |
| `app.manifest` | `asInvoker` (keine Adminrechte), Per-Monitor-DPI, Windows 10/11 |
| `StayActive.ico`, `tools/make_icon.py` | Programm-Symbol der .exe (mit Python/Pillow erzeugt) |
