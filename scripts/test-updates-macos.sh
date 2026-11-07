#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/paysprout-tests.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
flags=()
swift_include="$(xcode-select -p)/usr/include/swift"
if [[ -f "$swift_include/module.modulemap" && -f "$swift_include/bridging.modulemap" ]] && /usr/bin/grep -q 'module SwiftBridging' "$swift_include/module.modulemap" && /usr/bin/grep -q 'module SwiftBridging' "$swift_include/bridging.modulemap"; then
    touch "$work_dir/empty.modulemap"
    printf '{"version":0,"roots":[{"type":"file","name":"%s/module.modulemap","external-contents":"%s/empty.modulemap"}]}' "$swift_include" "$work_dir" > "$work_dir/overlay.json"
    flags=(-Xcc -ivfsoverlay -Xcc "$work_dir/overlay.json")
fi
xcrun swiftc "${flags[@]}" Sources/UpdateCore.swift Tests/Updates.swift -o "$work_dir/UpdateTests"
"$work_dir/UpdateTests"
