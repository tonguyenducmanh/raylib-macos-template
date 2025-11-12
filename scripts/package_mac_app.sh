#!/usr/bin/env bash
set -euo pipefail

# Simple packaging script for macOS .app and DMG
# Usage examples:
#   APP_NAME=MyGame ./scripts/package_mac_app.sh
#   CODESIGN_ID="Developer ID Application: Your Name (TEAMID)" APP_NAME=MyGame ./scripts/package_mac_app.sh
# Environment variables (optional):
#   APP_NAME        - app name (default: raylib-game)
#   EXECUTABLE      - path to built executable (default: src/main)
#   BUNDLE_ID       - bundle identifier (default: com.example.raylibgame)
#   VERSION         - version string (default: 1.0)
#   ICON            - path to .icns file (optional)
#   CODESIGN_ID     - codesign identity (optional)

APP_NAME=${APP_NAME:-raylib-game}
EXECUTABLE=${EXECUTABLE:-src/main}
BUNDLE_ID=${BUNDLE_ID:-com.example.raylibgame}
VERSION=${VERSION:-1.0}
ICON=${ICON:-}
CODESIGN_ID=${CODESIGN_ID:-}

BUNDLE="$APP_NAME.app"
CONTENTS="$BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
TEMPLATE_PLIST="bundle/Info.plist.template"
OUT_DMG="$APP_NAME-$VERSION.dmg"

echo "Packaging $APP_NAME -> $BUNDLE"

# 1) Ensure executable exists; if not try to build a release binary
if [ ! -x "$EXECUTABLE" ]; then
  echo "Executable $EXECUTABLE not found or not executable. Building release..."
  clang -O2 \
    -I./include \
    -L./lib \
    src/main.c \
    -o "$EXECUTABLE" \
    -lraylib \
    -framework CoreVideo \
    -framework IOKit \
    -framework Cocoa \
    -framework CoreFoundation \
    -framework AppKit
  echo "Build finished"
fi

# 2) Create bundle structure
rm -rf "$BUNDLE"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# 3) Copy executable into bundle (rename to APP_NAME for clarity)
EXEC_NAME="$APP_NAME"
cp "$EXECUTABLE" "$MACOS_DIR/$EXEC_NAME"
chmod +x "$MACOS_DIR/$EXEC_NAME"

# 4) Copy icon if provided
ICON_BASENAME=""
if [ -n "$ICON" ] && [ -f "$ICON" ]; then
  cp "$ICON" "$RES_DIR/"
  ICON_BASENAME=$(basename "$ICON")
  echo "Copied icon: $ICON_BASENAME"
fi

# 5) Create Info.plist from template
if [ ! -f "$TEMPLATE_PLIST" ]; then
  echo "ERROR: Info.plist template not found at $TEMPLATE_PLIST"
  exit 1
fi

# Replace placeholders: __APP_NAME__, __BUNDLE_IDENTIFIER__, __VERSION__, __ICON_FILE__
ICON_FILE_PLACEHOLDER=""
if [ -n "$ICON_BASENAME" ]; then
  ICON_FILE_PLACEHOLDER="$ICON_BASENAME"
fi

sed \
  -e "s|__APP_NAME__|$APP_NAME|g" \
  -e "s|__BUNDLE_IDENTIFIER__|$BUNDLE_ID|g" \
  -e "s|__VERSION__|$VERSION|g" \
  -e "s|__ICON_FILE__|$ICON_FILE_PLACEHOLDER|g" \
  "$TEMPLATE_PLIST" > "$CONTENTS/Info.plist"

# 6) Optionally codesign
if [ -n "$CODESIGN_ID" ]; then
  echo "Codesigning with identity: $CODESIGN_ID"
  # Use deep to sign nested code; adjust entitlements as needed
  codesign --deep --force --verify --verbose --sign "$CODESIGN_ID" "$BUNDLE"
  echo "Codesign done"
fi

# 7) Create DMG
if [ -f "$OUT_DMG" ]; then
  echo "Removing existing $OUT_DMG"
  rm -f "$OUT_DMG"
fi

echo "Creating DMG $OUT_DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$BUNDLE" -ov -format UDZO "$OUT_DMG"

echo "Packaging complete: $OUT_DMG"

# 8) Notarization instructions (manual)
cat <<'NOTES'
Next steps (optional):
- To distribute outside Mac App Store you should codesign with Developer ID and notarize with Apple.
  Example notarization flow with notarytool (Xcode 13+):

  # Upload for notarization
  xcrun notarytool submit "$OUT_DMG" --apple-id "YOUR_APPLE_ID" --team-id "TEAMID" --password 
  # or use API key: notarytool submit --key /path/AuthKey.p8 --key-id KEYID --issuer ISSUERID "$OUT_DMG"

  # Wait for notarization to finish, then staple the ticket
  xcrun stapler staple "$BUNDLE"

NOTES

exit 0
