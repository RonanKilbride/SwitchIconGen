#!/usr/bin/env bash
# Builds a release SwitchIconGen.app from the Swift package.
# Usage: ./build.sh [signing identity]   (default: ad-hoc "-")
set -euo pipefail

cd "$(dirname "$0")"
IDENTITY="${1:--}"
VERSION="1.0.0"
APP="build/SwitchIconGen.app"

# Record the SDK we actually build against. `swift build` otherwise stamps the deployment
# target (14.0) as the SDK version, and macOS then runs the app in legacy-appearance
# compatibility mode: old flat sidebar, mismatched title-bar sections.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
LINK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
# Record source paths relative to the package, not to this machine.
LINK_FLAGS+=(-Xswiftc -file-prefix-map -Xswiftc "$PWD=.")

swift build -c release --arch arm64 --arch x86_64 "${LINK_FLAGS[@]}"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 "${LINK_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SwitchIconGen" "$APP/Contents/MacOS/SwitchIconGen"
# Drop debug symbols: they record the absolute source and build paths of this machine.
strip -S -x "$APP/Contents/MacOS/SwitchIconGen"
# SwiftPM's resource bundle; Bundle.module finds it in Contents/Resources.
cp -R "$BIN_DIR/SwitchIconGen_SwitchIconGenKit.bundle" "$APP/Contents/Resources/"
# App icon and About-panel credits.
cp Support/AppIcon.icns Support/Credits.rtf "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>SwitchIconGen</string>
    <key>CFBundleDisplayName</key>          <string>SwitchIconGen</string>
    <key>CFBundleIdentifier</key>           <string>com.switchicongen.app</string>
    <key>CFBundleExecutable</key>           <string>SwitchIconGen</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>   <string>${VERSION}</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>     <string>© 2026 Ronan Kilbride</string>
</dict>
</plist>
PLIST

# A secure timestamp is required for notarization; ad-hoc signatures can't have one.
TIMESTAMP=(--timestamp); [[ "$IDENTITY" == "-" ]] && TIMESTAMP=()
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --sign "$IDENTITY" "$APP"
echo "Built $APP"
