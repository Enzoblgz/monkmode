#!/bin/bash
# Compile MonkMode en release et assemble MonkMode.app (menu bar, sans icône Dock).
set -e
cd "$(dirname "$0")"

echo "→ Compilation release…"
swift build -c release

APP="MonkMode.app"
BIN=".build/release/monkmode"

echo "→ Assemblage de $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MonkMode"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MonkMode</string>
    <key>CFBundleDisplayName</key><string>MonkMode</string>
    <key>CFBundleIdentifier</key><string>com.enzo.monkmode</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>MonkMode</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Signature ad-hoc pour que macOS accepte le lancement local.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ $APP prête. Lance-la avec :  open $APP"
