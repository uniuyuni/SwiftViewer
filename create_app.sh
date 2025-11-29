#!/bin/bash

APP_NAME="SwiftViewer"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/debug"
BINARY="$BUILD_DIR/$APP_NAME"

swift build

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY. Please run 'swift build' first."
    exit 1
fi

# clean
rm -rf "$APP_BUNDLE"

# create structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/"

# copy resources (if any)
# SwiftPM bundle naming can vary, checking for likely candidates
if [ -d "$BUILD_DIR/${APP_NAME}_SwiftViewerCore.bundle" ]; then
    cp -r "$BUILD_DIR/${APP_NAME}_SwiftViewerCore.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# create Info.plist
# create Info.plist
# Compile Assets
if [ -d "Sources/SwiftViewer/Assets.xcassets" ]; then
    echo "Compiling Assets.xcassets..."
    # Ensure we use Xcode's actool if available
    if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    fi
    xcrun actool "Sources/SwiftViewer/Assets.xcassets" --compile "$APP_BUNDLE/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist /tmp/partial.plist
fi

# create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.uniuyuni.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Set permissions
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Created $APP_BUNDLE in project root."
