#!/bin/bash
# Compile FocusLock en release et assemble FocusLock.app (menu bar, sans icône Dock).
set -e
cd "$(dirname "$0")"

echo "→ Compilation release…"
swift build -c release

APP="FocusLock.app"
BIN=".build/release/FocusLock"

echo "→ Assemblage de $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FocusLock"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FocusLock</string>
    <key>CFBundleDisplayName</key><string>FocusLock</string>
    <key>CFBundleIdentifier</key><string>com.enzo.focuslock</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>FocusLock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Signature ad-hoc pour que macOS accepte le lancement local.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ $APP prête. Lance-la avec :  open $APP"
