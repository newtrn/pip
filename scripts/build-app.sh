#!/bin/zsh
# Builds build/Pip.app: SwiftPM compiles (Swift 6 language mode), then the
# binary is wrapped in an app bundle with Info.plist (LSUIElement) and an
# ad-hoc signature, which notifications and launch at login need.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
APP=build/Pip.app

swift build -c $CONFIG --product Pip
BIN=$(swift build -c $CONFIG --show-bin-path)/Pip

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/Pip
cp Resources/Info.plist $APP/Contents/Info.plist
codesign --force --sign - $APP >/dev/null
echo "Built $APP"
