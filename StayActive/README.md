# StayActive (macOS)

Kleine Menüleisten-App (☕ oben rechts), die deinen Mac aktiv hält – damit z. B.
Microsoft Teams dich nicht auf „Abwesend“ setzt und der Mac nicht in den Ruhezustand geht.

## Funktionen

- **Aktiv halten** (an/aus): verhindert Ruhezustand von Mac und Bildschirm und meldet dem
  System regelmäßig Nutzeraktivität.
- **Maus-Impuls (für Teams-Status)**: bewegt den Mauszeiger um 1 Pixel hin und zurück –
  aber nur, wenn du gerade selbst nichts tust. Das ist der zuverlässigste Weg, damit Teams
  grün bleibt. Braucht die Berechtigung *Bedienungshilfen*.
- **Intervall**: 30 s / 1 / 2 / 4 Minuten (Standard: 1 Minute; Teams wird nach ca. 5 Min. gelb).
- **Aktiv lassen für**: unbegrenzt oder 1/2/4/8 Stunden, danach schaltet es sich ab.
- **Beim Anmelden starten** (ab macOS 13).

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
