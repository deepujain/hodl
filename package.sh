#!/bin/bash
# Builds the app and packages it for download: build/HODL.zip
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

ZIP="build/HODL.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/HODL.app" "$ZIP"
echo "Packaged $ZIP"
