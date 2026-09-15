#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="1.2.0"
BUILD="124"
PACKAGE_VERSION="1.2.0.124"
OUT="$ROOT/dist"
APP="$OUT/PunkteRetter.app"
PKGROOT="$OUT/pkgroot"
INSTALLER_BASENAME="PunkteRetter-${VERSION}-Build${BUILD}"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents" "$PKGROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Dieser Release-Build muss auf macOS mit Xcode ausgeführt werden." >&2
  exit 2
fi

swift test
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN/PunkteRetter" "$APP/Contents/MacOS/PunkteRetter"
cp "$BIN/PunkteRetterAgent" "$APP/Contents/Resources/PunkteRetterAgent"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
cp Resources/de.punkteretter.agent.plist "$APP/Contents/Library/LaunchAgents/de.punkteretter.agent.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

APP_IDENTITY="${PUNKTERETTER_APP_IDENTITY:-}"
INSTALLER_IDENTITY="${PUNKTERETTER_INSTALLER_IDENTITY:-}"
NOTARY_PROFILE="${PUNKTERETTER_NOTARY_PROFILE:-}"

if [[ -n "$APP_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --entitlements Resources/PunkteRetter.entitlements --sign "$APP_IDENTITY" "$APP/Contents/Resources/PunkteRetterAgent"
  codesign --force --options runtime --timestamp --entitlements Resources/PunkteRetter.entitlements --sign "$APP_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  codesign --force --options runtime --entitlements Resources/PunkteRetter.entitlements --sign - "$APP/Contents/Resources/PunkteRetterAgent"
  codesign --force --options runtime --entitlements Resources/PunkteRetter.entitlements --sign - "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  echo "HINWEIS: Keine Developer-ID-App-Identität angegeben; App und Agent wurden nur ad-hoc signiert." >&2
fi

cp -R "$APP" "$PKGROOT/PunkteRetter.app"
cat > "$OUT/component.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
<key>BundleIdentifier</key><string>de.punkteretter.app</string>
<key>RootRelativeBundlePath</key><string>PunkteRetter.app</string>
<key>BundleIsRelocatable</key><false/>
<key>BundleIsVersionChecked</key><false/>
<key>BundleOverwriteAction</key><string>upgrade</string>
</dict></array></plist>
PLIST
plutil -lint "$OUT/component.plist"

mkdir -p "$OUT/scripts"
cat > "$OUT/scripts/postinstall" <<'POST'
#!/bin/zsh
APP_PATH="/Applications/PunkteRetter.app"
echo "PunkteRetter postinstall: prüfe $APP_PATH"
/bin/ls -ld /Applications "$APP_PATH" 2>&1 || true
/bin/ls -l "$APP_PATH/Contents/MacOS" 2>&1 || true
if [[ ! -d "$APP_PATH" || ! -x "$APP_PATH/Contents/MacOS/PunkteRetter" ]]; then
  echo "FEHLER: PunkteRetter wurde nicht korrekt unter /Applications installiert." >&2
  exit 1
fi
CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console)
if [[ "$CONSOLE_USER" != "root" && "$CONSOLE_USER" != "loginwindow" ]]; then
  UID_NUM=$(/usr/bin/id -u "$CONSOLE_USER")
  /bin/launchctl asuser "$UID_NUM" /usr/bin/open "$APP_PATH" || true
fi
exit 0
POST
chmod 755 "$OUT/scripts/postinstall"

pkgbuild --root "$PKGROOT" --component-plist "$OUT/component.plist" --identifier de.punkteretter.pkg --version "$PACKAGE_VERSION" --install-location /Applications --ownership recommended --scripts "$OUT/scripts" "$OUT/PunkteRetter-component.pkg"

mkdir -p "$OUT/installer-resources"
cp Resources/InstallerWelcome.html "$OUT/installer-resources/InstallerWelcome.html"
cp Resources/InstallerConclusion.html "$OUT/installer-resources/InstallerConclusion.html"
cat > "$OUT/Distribution.xml" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>PunkteRetter</title><organization>de.punkteretter</organization>
<domains enable_localSystem="true"/><options customize="never" require-scripts="false" rootVolumeOnly="true"/>
<welcome file="InstallerWelcome.html"/><conclusion file="InstallerConclusion.html"/>
<choices-outline><line choice="default"/></choices-outline>
<choice id="default" visible="false"><pkg-ref id="de.punkteretter.pkg"/></choice>
<pkg-ref id="de.punkteretter.pkg" version="$PACKAGE_VERSION">PunkteRetter-component.pkg</pkg-ref>
</installer-gui-script>
DIST

if [[ -n "$INSTALLER_IDENTITY" ]]; then
  productbuild --distribution "$OUT/Distribution.xml" --resources "$OUT/installer-resources" --package-path "$OUT" --sign "$INSTALLER_IDENTITY" "$OUT/${INSTALLER_BASENAME}.pkg"
else
  productbuild --distribution "$OUT/Distribution.xml" --resources "$OUT/installer-resources" --package-path "$OUT" "$OUT/${INSTALLER_BASENAME}-UNSIGNED.pkg"
fi
rm -f "$OUT/PunkteRetter-component.pkg"

if [[ -n "$INSTALLER_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$OUT/${INSTALLER_BASENAME}.pkg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT/${INSTALLER_BASENAME}.pkg"
  spctl --assess --type install --verbose=2 "$OUT/${INSTALLER_BASENAME}.pkg"
else
  echo "HINWEIS: Notarisierung übersprungen. Setze PUNKTERETTER_INSTALLER_IDENTITY und PUNKTERETTER_NOTARY_PROFILE für einen Gatekeeper-sauberen Release." >&2
fi

echo "Fertig: $OUT"
