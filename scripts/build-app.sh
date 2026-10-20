#!/bin/zsh
# Builds build/Pip.app: SwiftPM compiles (Swift 6 language mode), then the
# binary is wrapped in an app bundle with Info.plist (LSUIElement) and an
# ad-hoc signature, which notifications and launch at login need.
#
#   scripts/build-app.sh                 release build for this Mac
#   scripts/build-app.sh debug           debug build
#   UNIVERSAL=1 VERSION=0.2.0 scripts/build-app.sh
#                                        Apple silicon + Intel, stamped with a
#                                        version, and zipped to build/Pip-0.2.0.zip
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
APP=build/Pip.app
ARCHS=()
[[ ${UNIVERSAL:-0} == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c $CONFIG --product Pip $ARCHS
BIN=$(swift build -c $CONFIG $ARCHS --show-bin-path)/Pip

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/Pip
cp Resources/Info.plist $APP/Contents/Info.plist
cp Resources/AppIcon.icns $APP/Contents/Resources/AppIcon.icns
if [[ -n ${VERSION:-} ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" $APP/Contents/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$VERSION}" $APP/Contents/Info.plist
fi
codesign --force --sign - $APP >/dev/null
echo "Built $APP ($(lipo -archs $APP/Contents/MacOS/Pip))"

if [[ -n ${VERSION:-} ]]; then
    ZIP=build/Pip-$VERSION.zip
    rm -f $ZIP
    # ditto keeps the bundle's signature and extended attributes intact.
    ditto -c -k --keepParent $APP $ZIP
    echo "Zipped $ZIP  sha256 $(shasum -a 256 $ZIP | cut -d' ' -f1)"
fi
