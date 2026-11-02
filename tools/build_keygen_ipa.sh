#!/bin/bash
set -e
echo "==> Building Nova Keygen Standalone IPA..."
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
BUILD_DIR="build-keygen"
APP_DIR="$BUILD_DIR/Payload/NovaKeygen.app"

rm -rf "$BUILD_DIR" Nova-Keygen.ipa
mkdir -p "$APP_DIR"

xcrun swiftc \
  -parse-as-library \
  -target arm64-apple-ios15.0 \
  -sdk "$SDK_PATH" \
  -O \
  -framework UIKit \
  -framework Foundation \
  -framework CryptoKit \
  app/Keygen/NovaKeygen.swift \
  -o "$APP_DIR/NovaKeygen"

cp app/Keygen/Info.plist "$APP_DIR/Info.plist"

cd "$BUILD_DIR"
zip -qry "../Nova-Keygen.ipa" Payload
cd ..
rm -rf "$BUILD_DIR"

echo "==> Nova-Keygen.ipa built successfully! ($(ls -lh Nova-Keygen.ipa | awk '{print $5}'))"
