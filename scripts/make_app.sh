#!/bin/bash
# Empaqueta el binario release en dist/MyTasks.app (LSUIElement, firma ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/MyTasks.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MyTasks "$APP/Contents/MacOS/MyTasks"
cp Resources/MyTasks.icns "$APP/Contents/Resources/MyTasks.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.kintsugi-lab.mytasks</string>
	<key>CFBundleName</key>
	<string>MyTasks</string>
	<key>CFBundleDisplayName</key>
	<string>MyTasks</string>
	<key>CFBundleExecutable</key>
	<string>MyTasks</string>
	<key>CFBundleIconFile</key>
	<string>MyTasks</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Identidad estable ("MyTasks Dev", self-signed en el llavero): mantiene la
# misma firma entre rebuilds, así los permisos de Keychain/TCC y el login item
# sobreviven a las reinstalaciones. Fallback a ad-hoc si no existe.
IDENTITY="MyTasks Dev"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
	codesign --force --sign "$IDENTITY" "$APP"
	echo "firmado con identidad: $IDENTITY"
else
	codesign --force --sign - "$APP"
	echo "AVISO: identidad '$IDENTITY' no encontrada — firma ad-hoc (permisos no persistirán)"
fi
echo "OK → $APP"
