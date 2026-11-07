#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(cat VERSION)
./scripts/build.sh --universal --test
mkdir -p dist
name="PaySprout-$version-macOS-universal"
ditto -c -k --sequesterRsrc --keepParent 'build/上班鼓励器.app' "dist/$name.zip"
stage=$(mktemp -d "${TMPDIR:-/tmp}/paysprout-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto 'build/上班鼓励器.app' "$stage/上班鼓励器.app"
ln -s /Applications "$stage/Applications"
cp docs/INSTALL-macOS.txt "$stage/首次打开说明.txt"
hdiutil create -volname 'PaySprout 薪芽' -srcfolder "$stage" -ov -format UDZO "dist/$name.dmg"
codesign --verify --deep --strict 'build/上班鼓励器.app'
lipo -info 'build/上班鼓励器.app/Contents/MacOS/Encourager'
