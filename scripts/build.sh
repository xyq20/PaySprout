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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
architectures=(arm64)
if [[ " ${*:-} " == *" --universal "* ]]; then architectures+=(x86_64); fi
for arch in "${architectures[@]}"; do
    xcrun swiftc Sources/Models.swift Sources/Effects.swift Sources/main.swift -o "$work_dir/Encourager-$arch" "${flags[@]}" -O -framework AppKit -framework SwiftUI -target "$arch-apple-macosx26.0"
done
if [[ ${#architectures[@]} -gt 1 ]]; then
    lipo -create "$work_dir/Encourager-arm64" "$work_dir/Encourager-x86_64" -output "$work_dir/Encourager"
else
    cp "$work_dir/Encourager-arm64" "$work_dir/Encourager"
fi
cp "$work_dir/Encourager" "$app/Contents/MacOS/Encourager"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
if [[ " ${*:-} " == *" --test "* ]]; then
    xcrun swiftc "${flags[@]}" Sources/Models.swift Tests/Progress.swift -o "$work_dir/ProgressTests"
    "$work_dir/ProgressTests"
fi
