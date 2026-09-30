#!/bin/bash
# Baut StayActive.app (Universal: Apple Silicon + Intel).
#   ./build.sh            -> build/StayActive.app + build/StayActive.zip
#   ./build.sh --install  -> zusätzlich nach /Applications kopieren und starten
set -euo pipefail
cd "$(dirname "$0")"

APP=StayActive
OUT=build
BUNDLE="$OUT/$APP.app"

rm -rf "$OUT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

for arch in arm64 x86_64; do
  echo "==> Kompiliere für $arch"
  xcrun swiftc -O -swift-version 5 \
    -target "$arch-apple-macos12.0" \
    Sources/main.swift \
    -o "$OUT/$APP-$arch"
done

lipo -create -output "$BUNDLE/Contents/MacOS/$APP" "$OUT/$APP-arm64" "$OUT/$APP-x86_64"
rm "$OUT/$APP-arm64" "$OUT/$APP-x86_64"
cp Info.plist "$BUNDLE/Contents/Info.plist"

echo "==> Signiere (ad-hoc)"
codesign --force --sign - --identifier com.niklastewes.stayactive "$BUNDLE"

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
