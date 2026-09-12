#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$ROOT_DIR/app"
APP_NAME="静态页面展示"
EXECUTABLE_NAME="StaticPageHub"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "构建 Swift 可执行文件..."
swift build --package-path "$PACKAGE_DIR" -c release
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)"

echo "创建应用包..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

install -m 755 "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
install -m 644 "$PACKAGE_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$PACKAGE_DIR/Resources/Web" "$RESOURCES_DIR/Web"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "签名应用包..."
codesign --force --sign - --timestamp=none "$APP_BUNDLE"

echo "构建完成：$APP_BUNDLE"

