# GreenSnap (macOS)

Screenshot-Tool im Stil von **Greenshot**, neu gebaut für aktuelle Macs (Apple Silicon und Intel, macOS 14 Sonoma oder neuer).
Es läuft in der Menüleiste und legt **keine Dateien** an: Screenshots landen in der Zwischenablage
oder im Editor, gespeichert wird nur, wenn du es ausdrücklich willst.

## Funktionen

| | Greenshot | GreenSnap |
|---|---|---|
| Bereich aufnehmen (mit Lupe und Pixelmaßen) | ✓ | ✓ – eingefrorener Bildschirm, Lupe, Größenanzeige |
| Fenster aufnehmen | ✓ | ✓ – Fenster anklicken, sauber ohne überlappende Fenster |
| Vollbild / letzten Bereich erneut aufnehmen | ✓ | ✓ |
| Editor: Rechteck, Ellipse, Linie, Pfeil, Freihand, Text | ✓ | ✓ |
| Hervorheben (Textmarker) | ✓ | ✓ |
| Unkenntlich machen (Verpixeln) | ✓ | ✓ |
| Nummerierung (1, 2, 3 …) | ✓ | ✓ – nummeriert sich beim Löschen automatisch neu |
| Zuschneiden, Rückgängig/Wiederholen | ✓ | ✓ |
| Markierungen nachträglich verschieben/ändern | ✓ | ✓ |
| In Zwischenablage kopieren | ✓ | ✓ – ohne Datei auf dem Schreibtisch |
| **Text erkennen (OCR)** – Text aus Bereich kopieren | – | ✓ (Deutsch + Englisch) |
| **Anheften** – Screenshot schwebt über allen Fenstern | – | ✓ |
| **Verlauf** der letzten 10 Aufnahmen (nur im Arbeitsspeicher) | – | ✓ |
| **Retina-Option**: in normaler Größe kopieren (für Teams/Outlook) | – | ✓ |
| Bild aus Zwischenablage / Datei öffnen und bearbeiten | ✓ | ✓ |

## Tastenkürzel

Global (in den Einstellungen änderbar):

| Kürzel | Aktion |
|---|---|
| ⇧⌘2 | Bereich / Fenster aufnehmen |
| ⇧⌘1 | Vollbild (Bildschirm unter der Maus) |
| ⇧⌘9 | Letzten Bereich erneut aufnehmen |
| ⇧⌘8 | Text aus Bereich kopieren (OCR) |

Bei der Bereichsauswahl: **Ziehen** = Bereich · **Klick** = Fenster unter der Maus · **↩** = ganzer Bildschirm · **Esc** = Abbrechen.

Im Editor:

| Taste | Aktion |
|---|---|
| ↩ | Kopieren und Editor schließen |
| ⌘C | In die Zwischenablage kopieren |
| ⌘S | Sichern unter … (PNG/JPEG) |
| ⌘Z / ⇧⌘Z | Rückgängig / Wiederholen |
| ⌫ | Ausgewählte Markierung löschen |
| Pfeiltasten (⇧ = 10 px) | Markierung verschieben |
| ⇧ beim Zeichnen | Quadrat/Kreis bzw. 45°-Winkel |
| V R E L A F T H O N C | Werkzeuge: Auswahl, Rechteck, Ellipse, Linie, Pfeil, Freihand, Text, Hervorheben, Verpixeln, Nummer, Zuschneiden |
| ⌘+ / ⌘- / ⌘0 / ⌘9 | Zoom rein/raus, Originalgröße, an Fenster anpassen (auch per Trackpad) |

Tipp: Wer ⇧⌘4 lieber für GreenSnap nutzen möchte, schaltet es unter *Systemeinstellungen → Tastatur →
Tastaturkurzbefehle → Bildschirmfotos* ab und legt es dann in den GreenSnap-Einstellungen fest.

## Installation

Einmalig die Xcode Command Line Tools installieren (falls nicht vorhanden):

```bash
xcode-select --install
```

Dann:

```bash
git clone https://github.com/Niklas9822/mac-tools.git
cd mac-tools/GreenSnap
./build.sh --install
```

Alternativ die fertige App laden: [GreenSnap.zip](https://github.com/Niklas9822/mac-tools/releases/download/greensnap/GreenSnap.zip),
entpacken und nach `/Programme` ziehen. Beim ersten Öffnen: *Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“*.

### Berechtigung „Bildschirmaufnahme“

Beim ersten Start fragt macOS nach der Berechtigung. Aktivieren unter
*Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- und Systemaudioaufnahme → GreenSnap*,
danach GreenSnap einmal beenden und neu starten. Nach einem Neu-Bauen der App muss die Berechtigung
ggf. erneut erteilt werden (Eintrag mit „–“ entfernen und neu erlauben).
