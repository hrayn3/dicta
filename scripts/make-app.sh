#!/bin/bash
# Build Dicta.app from the SwiftPM executable.
# Usage: scripts/make-app.sh [--install] [output-dir]   (default: ./dist)
#   --install   also copy the app to /Applications and launch it
set -euo pipefail

cd "$(dirname "$0")/.."

INSTALL=0
if [ "${1:-}" = "--install" ]; then
    INSTALL=1
    shift
fi
OUT="${1:-dist}"
APP="$OUT/Dicta.app"
BUNDLE_ID="com.hughrayner.dicta"

fail() {
    echo "" >&2
    echo "✗ $1" >&2
    shift
    for line in "$@"; do echo "  $line" >&2; done
    exit 1
}

# --- Preflight: catch the usual first-build failures with a clear fix ---

[ "$(uname -m)" = "arm64" ] ||
    fail "Dicta needs an Apple Silicon Mac (this one is $(uname -m))."

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [ -z "$DEV_DIR" ] || [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
    if [ -n "$XCODE" ]; then
        fail "The full Xcode app is installed but not selected (the Command Line Tools alone can't build Dicta)." \
            "Run:  sudo xcode-select -s \"$XCODE\"" \
            "Then run this script again."
    fi
    fail "The full Xcode app is required (the Command Line Tools alone can't build Dicta)." \
        "Install Xcode from the App Store, open it once, then run this script again."
fi

if ! xcodebuild -license check >/dev/null 2>&1; then
    fail "The Xcode licence hasn't been accepted yet." \
        "Run:  sudo xcodebuild -license accept" \
        "Then run this script again."
fi

# --- Build ---

echo "Building Dicta (the first build fetches dependencies and takes a few minutes)…"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Dicta "$APP/Contents/MacOS/Dicta"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp -R ThirdPartyLicenses "$APP/Contents/Resources/"

# Bundle the speech model so the app never needs the network. The build
# machine must have run Dicta (or a selftest) once to populate the cache.
MODEL_CACHE="$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3"
if [ -f "$MODEL_CACHE/parakeet_vocab.json" ]; then
    mkdir -p "$APP/Contents/Resources/Models"
    cp -R "$MODEL_CACHE" "$APP/Contents/Resources/Models/"
    echo "Bundled speech model ($(du -sh "$MODEL_CACHE" | cut -f1))"
else
    echo "Note: the speech model (~600 MB) will download the first time Dicta launches."
fi

# Sign with a stable identity so TCC grants (Accessibility) survive rebuilds.
# Preference: $CODESIGN_ID → local "Dicta Dev Signing" cert → ad-hoc (which
# invalidates the Accessibility grant on every rebuild).
IDENTITY="${CODESIGN_ID:-}"
if [ -z "$IDENTITY" ]; then
    if security find-identity -v -p codesigning | grep -q "Dicta Dev Signing"; then
        IDENTITY="Dicta Dev Signing"
    else
        IDENTITY="-"
    fi
fi
codesign --force --deep --sign "$IDENTITY" "$APP"
echo "Signed with: $IDENTITY"

# An ad-hoc signature changes on every build, so an Accessibility grant from
# a previous build no longer applies — yet System Settings still shows Dicta
# switched on. Clear the stale entry so macOS asks again on next launch.
if [ "$IDENTITY" = "-" ]; then
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo "Built $APP"

if [ "$INSTALL" = 1 ]; then
    osascript -e 'quit app "Dicta"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do pgrep -x Dicta >/dev/null || break; sleep 1; done
    rm -rf /Applications/Dicta.app
    cp -R "$APP" /Applications/
    open /Applications/Dicta.app
    echo ""
    echo "Installed /Applications/Dicta.app and launched it."
    echo "Dicta has no window: look for its icon in the menu bar (top right)."
    echo "Allow Accessibility when macOS asks, then tap ⌃⌥Space to dictate."
fi
