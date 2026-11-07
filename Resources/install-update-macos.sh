#!/bin/sh
# Every path is passed as an argument. Never interpolate paths into shell source.
set -eu
old_pid=$1
target=$2
incoming=$3
backup=$4
workspace=$5
token=$6
new_pid=''
moved=0
rollback() {
    trap - EXIT HUP INT TERM
    if [ -n "$new_pid" ]; then kill "$new_pid" 2>/dev/null || true; fi
    if [ "$moved" -eq 1 ] && [ -d "$backup" ]; then
        if [ -d "$target" ]; then /bin/mv "$target" "$workspace/failed.app" || true; fi
        if /bin/mv "$backup" "$target"; then
            printf 'rolled-back\n' > "$workspace/result.txt"
            "$target/Contents/MacOS/Encourager" --paysprout-rollback "$token" > "$workspace/rollback.log" 2>&1 &
        else
            printf 'needs-recovery\n%s\n' "$backup" > "$workspace/result.txt"
        fi
    else
        printf 'failed\n' > "$workspace/result.txt"
        if [ -d "$target" ] && ! kill -0 "$old_pid" 2>/dev/null; then
            "$target/Contents/MacOS/Encourager" --paysprout-rollback "$token" > "$workspace/rollback.log" 2>&1 &
        fi
    fi
    exit 1
}
trap rollback EXIT HUP INT TERM
count=0
while kill -0 "$old_pid" 2>/dev/null; do
    count=$((count + 1))
    [ "$count" -lt 60 ] || exit 1
    /bin/sleep 1
done
[ -d "$incoming" ] && [ -d "$target" ] && [ ! -e "$backup" ]
/usr/bin/codesign --verify --deep --strict "$incoming"
/bin/mv "$target" "$backup"
moved=1
/bin/mv "$incoming" "$target"
"$target/Contents/MacOS/Encourager" --paysprout-updated "$token" > "$workspace/launch.log" 2>&1 &
new_pid=$!
count=0
while [ "$count" -lt 30 ]; do
    if [ -f "$workspace/ready.txt" ] && [ "$(/bin/cat "$workspace/ready.txt")" = "$new_pid" ]; then
        printf 'installed\n' > "$workspace/result.txt"
        trap - EXIT HUP INT TERM
        /bin/rm -rf "$backup" || true
        exit 0
    fi
    kill -0 "$new_pid" 2>/dev/null || exit 1
    count=$((count + 1))
    /bin/sleep 1
done
exit 1
