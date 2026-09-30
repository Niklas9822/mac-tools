#!/bin/bash
# Baut GreenSnap.app (Universal: Apple Silicon + Intel, macOS 14+).
#   ./build.sh            -> build/GreenSnap.app + build/GreenSnap.zip
#   ./build.sh --install  -> zusätzlich nach /Applications kopieren und starten
set -euo pipefail
cd "$(dirname "$0")"

APP=GreenSnap
OUT=build
BUNDLE="$OUT/$APP.app"

rm -rf "$OUT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

for arch in arm64 x86_64; do
  echo "==> Kompiliere für $arch"
  xcrun swiftc -O -swift-version 5 \
    -target "$arch-apple-macos14.0" \
    Sources/*.swift \
    -o "$OUT/$APP-$arch"
done
lipo -create -output "$BUNDLE/Contents/MacOS/$APP" "$OUT/$APP-arm64" "$OUT/$APP-x86_64"
rm "$OUT/$APP-arm64" "$OUT/$APP-x86_64"
cp Info.plist "$BUNDLE/Contents/Info.plist"

echo "==> Erzeuge App-Symbol"
xcrun swiftc -O -swift-version 5 IconTool/main.swift Sources/AppIcon.swift -o "$OUT/icontool"
"$OUT/icontool" "$OUT/AppIcon.iconset"
iconutil -c icns "$OUT/AppIcon.iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$OUT/icontool" "$OUT/AppIcon.iconset"

echo "==> Signiere (ad-hoc)"
codesign --force --sign - --identifier com.niklastewes.greensnap "$BUNDLE"

ditto -c -k --keepParent "$BUNDLE" "$OUT/$APP.zip"
echo "==> Fertig: $BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x "$APP" 2>/dev/null || true
  rm -rf "/Applications/$APP.app"
  cp -R "$BUNDLE" /Applications/
  xattr -dr com.apple.quarantine "/Applications/$APP.app" 2>/dev/null || true
  open "/Applications/$APP.app"
  echo "==> Installiert und gestartet: /Applications/$APP.app"
fi
