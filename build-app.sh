#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$ROOT_DIR/app"
APP_NAME="WebPort"
EXECUTABLE_NAME="WebPort"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$PACKAGE_DIR/.build/AppIcon.iconset"

echo "构建通用 Swift 可执行文件..."
swift build \
    --package-path "$PACKAGE_DIR" \
    -c release \
    --arch arm64 \
    --arch x86_64
BIN_DIR="$(
    swift build \
        --package-path "$PACKAGE_DIR" \
        -c release \
        --arch arm64 \
        --arch x86_64 \
        --show-bin-path
)"

echo "生成 App 图标..."
rm -rf "$ICONSET_DIR"
swift "$PACKAGE_DIR/Resources/make_app_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$PACKAGE_DIR/Resources/AppIcon.icns"

echo "创建应用包..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

install -m 755 "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
install -m 644 "$PACKAGE_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
install -m 644 "$PACKAGE_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
ditto "$PACKAGE_DIR/Resources/Web" "$RESOURCES_DIR/Web"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "使用 Developer ID 签名..."
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$APP_BUNDLE"
else
    echo "使用本机临时签名..."
    codesign --force --sign - --timestamp=none "$APP_BUNDLE"
fi

if [[ -n "${NOTARY_PROFILE:-}" && -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "提交 Apple 公证..."
    NOTARY_ZIP="$DIST_DIR/$APP_NAME-notary.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_BUNDLE"
    rm -f "$NOTARY_ZIP"
fi

echo "生成 DMG..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_BUNDLE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "构建完成："
echo "  $APP_BUNDLE"
echo "  $DMG_PATH"
