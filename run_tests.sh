#!/bin/bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
echo "Using Developer Dir: $DEVELOPER_DIR"
xcrun swift test -v
