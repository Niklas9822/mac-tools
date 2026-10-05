# mac-tools

Kleine, kostenlose macOS-Apps für Apple Silicon und Intel.

| App | Was sie macht | Download |
|---|---|---|
| **GreenSnap** | Screenshots im Stil von Greenshot: Bereich/Fenster aufnehmen, markieren (Pfeile, Text, Verpixeln, Nummern …), direkt in die Zwischenablage kopieren, Text erkennen (OCR), Anheften. macOS 14+. | [GreenSnap.zip](https://github.com/Niklas9822/mac-tools/releases/download/greensnap/GreenSnap.zip) |
| **Barkeeper** | Menüleisten-Symbole ein-/ausklappen – schlanke Alternative zu Bartender. macOS 13+. | [Barkeeper.zip](https://github.com/Niklas9822/mac-tools/releases/download/barkeeper/Barkeeper.zip) |
| **StayActive** | Hält den Mac wach und den Teams-Status grün – unbegrenzt oder mit Timer und Restzeit in der Menüleiste. macOS 12+. | [StayActive.zip](https://github.com/Niklas9822/mac-tools/releases/download/stayactive/StayActive.zip) |

## Installation

1. Zip herunterladen, entpacken, App in den Ordner **Programme** ziehen.
2. Beim ersten Öffnen meldet macOS, dass die App nicht geprüft werden kann (sie ist nicht bei Apple
   notarisiert). Dann: *Systemeinstellungen → Datenschutz & Sicherheit* → ganz unten **„Dennoch öffnen“**.
   Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/GreenSnap.app`
3. Berechtigung erteilen, nach der die App fragt (GreenSnap: *Bildschirmaufnahme*, StayActive: *Bedienungshilfen*, Barkeeper: keine).

Details zu den Apps: [GreenSnap/README.md](GreenSnap/README.md) · [Barkeeper/README.md](Barkeeper/README.md) · [StayActive/README.md](StayActive/README.md)

## Selbst bauen

```bash
xcode-select --install   # einmalig
git clone https://github.com/Niklas9822/mac-tools.git
cd mac-tools/GreenSnap && ./build.sh --install
```
