#!/bin/zsh
# Compila, empacota TH80 Bar.app e instala em ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/TH80 Bar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TH80Bar "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
mkdir -p ~/Applications
pkill -x TH80Bar 2>/dev/null || true
rm -rf ~/Applications/"TH80 Bar.app"
cp -R "$APP" ~/Applications/
echo "Instalado em ~/Applications/TH80 Bar.app"
