#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/encourager-build.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
flags=()
swift_include="$(xcode-select -p)/usr/include/swift"
# Some Command Line Tools updates leave two declarations of SwiftBridging.
# Mask the obsolete map only for this build; do not alter the installed toolchain.
if [[ -f "$swift_include/module.modulemap" && -f "$swift_include/bridging.modulemap" ]] &&
   /usr/bin/grep -q 'module SwiftBridging' "$swift_include/module.modulemap" &&
   /usr/bin/grep -q 'module SwiftBridging' "$swift_include/bridging.modulemap"; then
    touch "$work_dir/empty.modulemap"
    cat > "$work_dir/overlay.json" <<EOF
{"version":0,"roots":[{"type":"file","name":"$swift_include/module.modulemap","external-contents":"$work_dir/empty.modulemap"}]}
EOF
    flags=(-Xcc -ivfsoverlay -Xcc "$work_dir/overlay.json")
fi
app="build/上班鼓励器.app"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc Sources/main.swift -o "$work_dir/Encourager" "${flags[@]}" -framework AppKit -framework SwiftUI -target arm64-apple-macosx26.0
cp "$work_dir/Encourager" "$app/Contents/MacOS/Encourager"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
if [[ "${1:-}" == "--test" ]]; then
    xcrun swift "${flags[@]}" Tests/Progress.swift
fi
