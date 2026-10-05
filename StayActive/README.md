# StayActive (macOS)

Kleine Menüleisten-App (☕ oben rechts), die deinen Mac aktiv hält – damit z. B.
Microsoft Teams dich nicht auf „Abwesend“ setzt und der Mac nicht in den Ruhezustand geht.

## So sieht's aus

- **Tasse in der Menüleiste**: gefüllt = aktiv, nur Umriss = aus (Mac darf schlafen).
  Läuft ein Zeitraum, steht die **Restzeit direkt daneben**, z. B. `☕ 1:23` (Std:Min),
  in der letzten Minute sekundengenau. Bei „Unbegrenzt“ nur die Tasse.
- **Klick** auf die Tasse öffnet das Menü, **⌥-Klick** schaltet direkt ein/aus (unbegrenzt).
- **Bestätigung**: Beim Starten, Ausschalten und Ablaufen erscheint oben in der Bildschirmmitte
  kurz eine Einblendung, z. B. „Aktiv für 2 Std. – bis 15:40“ oder
  „StayActive aus – Mac darf wieder schlafen“. Dafür ist keine Mitteilungs-Berechtigung nötig.

## Menü

- **Status oben** (groß): „Aktiv – noch 1 Std. 23 Min.“ mit „bis 15:40“ und einem
  Fortschrittsbalken, bzw. „Aktiv – unbegrenzt“ oder „Aus – Mac darf schlafen“.
- **Jetzt ausschalten** / **Jetzt aktivieren (unbegrenzt)**, bei laufendem Zeitraum
  zusätzlich **Verlängern um 30 Min.**
- **Starten für …**: Unbegrenzt, 15 Min., 30 Min., 1 / 2 / 4 / 8 Std., **Bis Feierabend**
  (Standard 17:00), **Bis Uhrzeit …** (Uhrzeit wählen, ggf. morgen) und **Eigene Dauer …**
  (z. B. `90`, `1:30` oder `2h`). Ein Klick startet sofort bzw. startet neu; das Häkchen zeigt
  die aktive Auswahl. Danach schaltet sich StayActive selbst ab.
- **Optionen**:
  - **Maus-Impuls (für Teams-Status)**: bewegt den Mauszeiger um 1 Pixel hin und zurück –
    aber nur, wenn du gerade selbst nichts tust. Das ist der zuverlässigste Weg, damit Teams
    grün bleibt. Braucht die Berechtigung *Bedienungshilfen* (Status steht direkt darunter).
  - **Impuls-Intervall**: 30 s / 1 / 2 / 4 Minuten (Standard: 1 Minute; Teams wird nach ca. 5 Min. gelb).
  - **Feierabend-Zeit ändern …**, **Restzeit in der Menüleiste anzeigen**, **Bestätigung einblenden**.
  - **Beim Start automatisch aktivieren**: schaltet beim App-Start immer ein (unbegrenzt),
    auch wenn es zuletzt aus war.
  - **Beim Anmelden starten** (ab macOS 13).

Was StayActive tut, solange es aktiv ist: Ruhezustand von Mac und Bildschirm verhindern und dem
System regelmäßig Nutzeraktivität melden (plus optional Maus-Impuls).

Ein laufender Zeitraum übersteht einen Neustart der App: Startest du StayActive vor Ablauf neu,
läuft der Countdown weiter; ist die Zeit inzwischen abgelaufen, bleibt es aus.

Voraussetzung: macOS 12 oder neuer, Apple Silicon oder Intel.

## Installation

### Variante A – selbst bauen (empfohlen, ~1 Minute)

Einmalig die Xcode Command Line Tools installieren (falls nicht vorhanden):

```bash
xcode-select --install
```

Dann:

```bash
git clone https://github.com/Niklas9822/mac-tools.git
cd mac-tools/StayActive
./build.sh --install
```

Die App liegt danach in `/Programme` und läuft sofort (Tassen-Symbol in der Menüleiste).

### Variante B – fertige App herunterladen

[StayActive.zip](https://github.com/Niklas9822/mac-tools/releases/download/stayactive/StayActive.zip) laden,
entpacken und `StayActive.app` in `/Programme` ziehen. Da die App nicht von Apple notarisiert ist, beim ersten
Öffnen: *Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“*, oder im Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/StayActive.app
```

## Berechtigung „Bedienungshilfen“

Für den Maus-Impuls fragt die App beim Start nach dem Zugriff. Aktivieren unter
*Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → StayActive*.
Falls die App neu gebaut wurde und der Maus-Impuls nicht mehr greift: Eintrag dort
entfernen (–) und die App neu hinzufügen/erlauben.

Ohne diese Berechtigung funktioniert der Rest trotzdem (kein Ruhezustand, Aktivitätsmeldung),
Teams kann dann aber je nach Version trotzdem auf „Abwesend“ springen.

## Hinweise

- Ist der Bildschirm gesperrt (⌃⌘Q), zeigt Teams dich unabhängig davon als abwesend.
- Beenden über das Menü → *StayActive beenden*.
