# Barkeeper (macOS)

Schlanke Alternative zu **Bartender** / *Hidden Bar*: Menüleisten-Symbole per Klick ein- und ausklappen,
damit oben rechts nur das zu sehen ist, was du wirklich brauchst. Kostenlos, keine besonderen
Berechtigungen, keine Internetverbindung. macOS 13 (Ventura) oder neuer, Apple Silicon und Intel.

## So funktioniert's

Barkeeper legt einen Pfeil **‹** und eine Trennlinie **│** in die Menüleiste:

```
[ ausgeblendet … ]  │  [ immer sichtbar … ]  ‹
```

- **Klick auf den Pfeil**: alle Symbole links der Trennlinie ein- bzw. ausklappen.
- **Sortieren**: ⌘ (Befehlstaste) gedrückt halten und Symbole in der Menüleiste verschieben
  (vorher ausklappen). Was links der Linie liegt, wird versteckt; was rechts liegt, bleibt sichtbar.
- **Rechtsklick auf den Pfeil**: Menü mit Einstellungen, Hilfe und Beenden.
- **⌃⌥⌘B**: Ein-/Ausklappen per Tastatur (änderbar).

Optional (Einstellungen): Bereich **„Immer ausgeblendet“** mit einer zweiten, gestrichelten Linie **┆**.
Symbole links davon bleiben auch im ausgeklappten Zustand verborgen; **⌥-Klick** auf den Pfeil zeigt sie.

```
[ immer ausgeblendet ]  ┆  [ ausgeblendet ]  │  [ immer sichtbar ]  ‹
```

Weitere Einstellungen: automatisch wieder einklappen (nie / 5 s … 1 min; nicht solange die Maus in der
Menüleiste ist), beim Start eingeklappt, Trennlinien anzeigen, beim Anmelden starten.

Beenden von Barkeeper zeigt sofort wieder alle Symbole.

## Installation

Fertige App: [Barkeeper.zip](https://github.com/Niklas9822/mac-tools/releases/download/barkeeper/Barkeeper.zip)
herunterladen, entpacken, in `/Programme` ziehen. Beim ersten Öffnen:
*Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“* (App ist nicht bei Apple notarisiert).

Selbst bauen:

```bash
xcode-select --install   # einmalig
git clone https://github.com/Niklas9822/mac-tools.git
cd mac-tools/Barkeeper && ./build.sh --install
```

## Grenzen gegenüber Bartender

Bartender kann versteckte Symbole zusätzlich in einer eigenen Leiste unter der Menüleiste anzeigen,
nach Ereignissen automatisch einblenden und Symbole per Suche finden. Dafür braucht es
Bildschirmaufnahme- und Bedienungshilfen-Rechte. Barkeeper verzichtet bewusst darauf und nutzt nur den
robusten „Trennlinie“-Mechanismus. Bei MacBooks mit Notch können Symbole hinter der Notch landen,
wenn zu viele gleichzeitig ausgeklappt sind.
