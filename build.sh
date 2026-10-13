#!/bin/zsh
# Compila ClaudeUsage.app (app de barra de menús, sin icono en el Dock).
# Uso: ./build.sh            → compila en ./build
#      ./build.sh install    → además la copia a ~/Applications y la abre
set -e
cd "$(dirname "$0")"

APP="build/ClaudeUsage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/ClaudeUsage" Sources/ClaudeUsage/*.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.local.claudeusage</string>
  <key>CFBundleName</key><string>Claude Usage</string>
  <key>CFBundleExecutable</key><string>ClaudeUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✓ Compilado: $APP"

if [[ "$1" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -x ClaudeUsage 2>/dev/null || true
  rm -rf ~/Applications/ClaudeUsage.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/ClaudeUsage.app
  echo "✓ Instalado en ~/Applications/ClaudeUsage.app"
fi
