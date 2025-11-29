#!/bin/bash

# Build the AdvancedCopyApp target
swift build -c debug --product AdvancedCopyApp

# Create the App Bundle structure
APP_NAME="AdvancedCopy"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy the executable
cp .build/debug/AdvancedCopyApp "$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Compile Assets
if [ -d "Sources/AdvancedCopyApp/Assets.xcassets" ]; then
    echo "Compiling Assets.xcassets..."
    if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    fi
    xcrun actool "Sources/AdvancedCopyApp/Assets.xcassets" --compile "$APP_NAME.app/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist /tmp/partial.plist
fi

# Copy Info.plist (Create a simple one if needed, or use existing)
# We'll create a simple one on the fly to ensure it works
cat > "$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.uniuyuni.AdvancedCopy</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Created $APP_NAME.app in project root."
