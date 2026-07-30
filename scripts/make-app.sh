#!/bin/bash
# Build Dicta.app from the SwiftPM executable.
# Usage: scripts/make-app.sh [output-dir]   (default: ./dist)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-dist}"
APP="$OUT/Dicta.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Dicta "$APP/Contents/MacOS/Dicta"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Bundle the speech model so the app never needs the network. The build
# machine must have run Dicta (or a selftest) once to populate the cache.
MODEL_CACHE="$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3"
if [ -f "$MODEL_CACHE/parakeet_vocab.json" ]; then
    mkdir -p "$APP/Contents/Resources/Models"
    cp -R "$MODEL_CACHE" "$APP/Contents/Resources/Models/"
    echo "Bundled speech model ($(du -sh "$MODEL_CACHE" | cut -f1))"
else
    echo "WARNING: no cached speech model at $MODEL_CACHE — app will download on first run" >&2
fi

# Sign with CODESIGN_ID if set (a stable identity keeps TCC grants like
# Accessibility valid across rebuilds). Ad-hoc otherwise: works, but every
# rebuild invalidates the Accessibility grant and it must be re-toggled.
codesign --force --deep --sign "${CODESIGN_ID:--}" "$APP"

echo "Built $APP"
