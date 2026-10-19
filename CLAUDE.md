# CLAUDE.md

Hinweise für Claude Code (und Menschen), die an diesem Repository arbeiten. Zwei Personen arbeiten hier
mit ihrem jeweils eigenen Claude Code zusammen: **Niklas9822** (Owner) und **Schobene**.

## Was ist das hier?

Kleine, eigenständige macOS-Menüleisten-Apps in Swift/AppKit, **ohne Xcode-Projekt und ohne Abhängigkeiten**.
Jede App liegt in einem eigenen Ordner und wird mit `swiftc` direkt gebaut. Ausnahme: `StayActiveWindows/` ist die
Windows-Version von StayActive (C#/WinForms, .NET Framework 4.8, gebaut mit `dotnet build`).

| Ordner | App | Minimum | Zweck |
|---|---|---|---|
| `GreenSnap/` | GreenSnap | macOS 14 | Screenshots im Stil von Greenshot: Bereich/Fenster/Vollbild, Editor zum Markieren, Kopieren ohne Datei, OCR, Anheften |
| `Barkeeper/` | Barkeeper | macOS 13 | Menüleisten-Symbole ein-/ausklappen (Alternative zu Bartender) |
| `StayActive/` | StayActive | macOS 12 | Hält den Mac wach / Teams-Status grün (Power-Assertion + optionaler Maus-Impuls) |
| `StayActiveWindows/` | StayActive für Windows | Windows 10 | Dasselbe für Windows: eine portable `StayActive.exe` im Infobereich, ohne Installation und ohne Adminrechte |

Sprache der Oberfläche, Kommentare und Commit-Texte: **Deutsch** (Code-Bezeichner Englisch).

## Zusammenarbeit (wichtig)

- **Nie direkt auf `main` pushen.** Für jede Änderung einen Branch anlegen, z. B.
  `<name>/<kurzbeschreibung>` (`schobene/greensnap-blur-tool`, `niklas/stayactive-timer`).
- Änderungen als **Pull Request** gegen `main` öffnen. Die andere Person reviewt und merged.
- Vor dem Start `git fetch origin && git rebase origin/main` (bzw. Branch frisch von `origin/main` erstellen),
  damit man nicht auf altem Stand arbeitet.
- PRs klein und thematisch halten (eine Funktion / ein Fix pro PR). Große Umbauten erst kurz absprechen,
  besonders an `GreenSnap/Sources/CanvasView.swift` und `EditorWindow.swift` – dort kollidiert man am ehesten.
- In der PR-Beschreibung: was geändert wurde, wie getestet (auf echtem Mac? welche macOS-Version?), Screenshots bei UI-Änderungen.
- Keine Secrets, Zugangsdaten oder Signing-Zertifikate committen.

## Bauen & Testen

Lokal auf einem Mac (Xcode Command Line Tools reichen: `xcode-select --install`):

```bash
cd GreenSnap && ./build.sh            # -> build/GreenSnap.app + build/GreenSnap.zip
cd GreenSnap && ./build.sh --install  # zusätzlich nach /Applications kopieren und starten
```

`build.sh` kompiliert alle `Sources/*.swift` für arm64 **und** x86_64 (Universal Binary) mit `-swift-version 5`,
erzeugt das App-Symbol (nur GreenSnap, via `IconTool/`), signiert ad-hoc und zippt.

- **Claude Code in der Cloud (Linux) kann nicht kompilieren** – kein macOS-SDK. Dort den Branch pushen und
  den GitHub-Actions-Lauf abwarten: jeder Push baut die betroffene App auf `macos-latest`. Ein grüner
  Build ist die Mindestvoraussetzung für einen PR; Verhalten muss trotzdem auf einem echten Mac getestet werden.
- Es gibt keine automatisierten Tests. Manuell testen: Aufnahme (Bereich, Fenster, Vollbild, letzter Bereich,
  OCR), Editor-Werkzeuge, Rückgängig/Wiederholen, Kopieren (↩ / ⌘C), Einstellungen.
- Nach jedem Neubau setzt macOS ggf. die Berechtigungen zurück (ad-hoc-Signatur ändert sich):
  *Datenschutz & Sicherheit → Bildschirmaufnahme / Bedienungshilfen* → Eintrag entfernen und neu erlauben.

## Releases / Download-Links

`.github/workflows/greensnap.yml`, `stayactive.yml`, `barkeeper.yml` und `stayactive-windows.yml` laufen bei Push auf
`main` (nur wenn sich der jeweilige App-Ordner ändert) und laden die Datei in ein festes Release hoch:

- https://github.com/Niklas9822/mac-tools/releases/download/greensnap/GreenSnap.zip
- https://github.com/Niklas9822/mac-tools/releases/download/stayactive/StayActive.zip
- https://github.com/Niklas9822/mac-tools/releases/download/barkeeper/Barkeeper.zip
- https://github.com/Niklas9822/mac-tools/releases/download/stayactive-windows/StayActive.exe
  (zusätzlich `StayActive-Windows.zip`)

Also: **Merge nach `main` = neue öffentliche Version.** Nur fertige, getestete Stände mergen.
Versionsnummer bei nennenswerten Änderungen in der jeweiligen `Info.plist` erhöhen
(`CFBundleShortVersionString`, `CFBundleVersion`), bei StayActive für Windows `<Version>`/`<FileVersion>` in
`StayActiveWindows/StayActive.csproj`.

## Architektur GreenSnap

| Datei | Inhalt |
|---|---|
| `main.swift` | Start, `.accessory`-App (nur Menüleiste) |
| `AppDelegate.swift` | Menüleisten-Menü, globale Kürzel registrieren, Aufnahme-Ablauf, Verlauf (nur RAM), Hauptmenü |
| `Prefs.swift` | `UserDefaults`-Einstellungen, `Shortcut`, `CaptureAction`, `AfterCapture` |
| `HotKeys.swift` | Globale Tastenkürzel über Carbon `RegisterEventHotKey` (keine Bedienungshilfen nötig), Tastennamen |
| `ScreenCapture.swift` | ScreenCaptureKit (`SCScreenshotManager`), Fensterliste via `CGWindowListCopyWindowInfo`, Zuschneiden |
| `SelectionOverlay.swift` | Vollbild-Overlay über eingefrorenem Bild: Bereich ziehen, Fenster anklicken, Lupe |
| `Annotation.swift` | `Tool`, `Annotation`-Modell (Werttyp) und `Renderer` (CoreGraphics-Zeichnen aller Markierungen) |
| `CanvasView.swift` | Zeichenfläche: Maus/Tastatur, Auswahl/Griffe, Text-Bearbeitung, Undo/Redo (State-Snapshots), Export |
| `EditorWindow.swift` | Editor-Fenster, Werkzeugleiste, Zoom, Menü-Aktionen (`EditorWindow`-Responder) |
| `ImageExport.swift` | Zwischenablage (PNG+TIFF, DPI), Speichern-Dialog, 1×-Verkleinerung, OCR (Vision) |
| `Windows.swift` | HUD-Einblendung, angeheftete Screenshots (Pin) |
| `SettingsWindow.swift` | Einstellungsfenster, `ShortcutRecorder` |
| `AppIcon.swift` | App-Symbol (zur Laufzeit und für `.icns` via `IconTool/`) |

Konventionen:
- Koordinaten im Editor: **Bildpunkte, Ursprung oben links** (`isFlipped = true`); Pixel = Punkte × `imageScale`.
  `ScreenCapture`-Fensterrahmen sind im globalen CG-Raum (oben links des Hauptbildschirms).
- Neue Markierungsart: `Tool` + `Annotation.Kind` erweitern, in `Renderer.draw` zeichnen, ggf. `hitTest`/`bounds`
  anpassen. Jede Zustandsänderung vorher mit `pushUndo()` sichern.
- Screenshots **nicht** automatisch als Datei speichern – das ist eine bewusste Designentscheidung.
- Neue Einstellungen in `Prefs` mit sinnvollem Default; UI in `SettingsWindow.swift`.

## Architektur Barkeeper

| Datei | Inhalt |
|---|---|
| `main.swift` | `AppDelegate`, Start (eingeklappt / Intro beim ersten Start), globales Kürzel |
| `MenuBarController.swift` | Pfeil + Trennlinien als `NSStatusItem`, Zustände eingeklappt/ausgeklappt/alles, Auto-Einklappen, Menü |
| `Prefs.swift` | Einstellungen, `Shortcut` |
| `SettingsWindow.swift` | Einstellungsfenster |
| `HotKeys.swift`, `ShortcutRecorder.swift` | Kopien aus GreenSnap (globale Kürzel, Kürzel-Aufnahme) |
| `AppIcon.swift` | App-Symbol für `.icns` (via `IconTool/`) |

Mechanismus: Eine Trennlinie mit `length = 10_000` schiebt alle Status-Symbole links von ihr aus dem
sichtbaren Bereich; schmal (12 pt) sind sie wieder da. Positionen merkt sich macOS über `autosaveName`
(`BarkeeperToggle`, `BarkeeperHidden`, `BarkeeperAlwaysHidden`); beim ersten Start werden über
`NSStatusItem Preferred Position <name>` Startpositionen gesetzt. Vor dem Einklappen wird geprüft, dass der
Pfeil rechts der Linie liegt, sonst würde er sich selbst verstecken. Keine Berechtigungen nötig – so soll es bleiben.

## Architektur StayActive

Alles in `StayActive/Sources/main.swift`: `Prefs`, `KeepAlive` (ProcessInfo-Activity gegen Schlaf/App Nap,
`IOPMAssertionDeclareUserActivity`, optionaler 1-px-Maus-Impuls nur bei Inaktivität), `TimeText` (Restzeit-/Uhrzeit-Texte),
`HUD` (kurze Einblendung ohne Mitteilungs-Berechtigung), `StatusHeaderView` (Status + Fortschrittsbalken im Menü) und
das Menü im `AppDelegate`. Ein Zeitraum wird als `endDate`/`startDate` in `UserDefaults` gespeichert und übersteht so
einen Neustart; ein einziger `tickTimer` aktualisiert die Restzeit in der Menüleiste genau dann, wenn sich die Anzeige
ändert, und schaltet bei Ablauf ab. Klick öffnet das Menü (`statusItem.menu` wird nur kurz gesetzt), ⌥-Klick schaltet um.

## Architektur StayActive für Windows

C# 7.3 / WinForms auf **.NET Framework 4.8** (auf Windows 10/11 vorinstalliert) → eine einzelne, portable
`StayActive.exe` ohne Installer. **Keine Adminrechte** (`app.manifest`: `asInvoker`); geschrieben wird nur nach
`HKCU\Software\StayActive` (Einstellungen + laufender Zeitraum) und optional `HKCU\…\CurrentVersion\Run` (Autostart).
Ein `ApplicationContext` (`TrayApp.cs`) ohne Hauptfenster hält `NotifyIcon` + `ContextMenuStrip`; das Menü wird bei
`Opening` neu aufgebaut, die Kopfzeile läuft bei offenem Menü sekündlich mit. Wach halten in `KeepAlive.cs` per
`SetThreadExecutionState` (UI-Thread) und optionalem 1-px-`SendInput`-Maus-Impuls nur bei Leerlauf (`GetLastInputInfo`).
Das Tray-Symbol zeichnet `IconRenderer.cs` zur Laufzeit mit GDI+ inkl. Restzeit (`45`, `2h`, `<1`); alte HICONs werden
mit `DestroyIcon` freigegeben. Linksklick öffnet das Menü (verzögert um die Doppelklickzeit), Doppelklick schaltet um.
Nach dem Aufwachen (`SystemEvents.PowerModeChanged`) wird der Ablauf geprüft. Texte/Verhalten bitte mit
`StayActive/Sources/main.swift` synchron halten.

Bauen: `dotnet build StayActiveWindows/StayActive.csproj -c Release` → `StayActiveWindows/bin/Release/StayActive.exe`.
Kompilieren geht auch unter Linux (z. B. Claude Code in der Cloud, `apt-get install dotnet-sdk-8.0`), ausführen nur
unter Windows – Verhalten also auf einem echten Windows-PC testen. Das Programm-Symbol `StayActive.ico` erzeugt
`StayActiveWindows/tools/make_icon.py` (Pillow).
