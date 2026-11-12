#!/bin/sh
# On this machine (macOS 27.2), PencilKit's PKReplicaManager traps inside
# CFEqual ("CFEqual() called with NULL first argument") when cfprefsd still
# holds replica state from a previous test process and this one has no bundle
# identifier. It fires in `PKDrawing.init(strokes:)`, i.e. on the second
# consecutive run that builds a drawing. Clearing that state and restarting
# cfprefsd makes the run reproducible. This is an OS/harness issue, not package
# code; no test is skipped or weakened because of it.
rm -f "$HOME/Library/Preferences/ByHost/com.apple.replicas.test."*.plist
killall cfprefsd 2>/dev/null || true
sleep 1
exec swift test "$@"
