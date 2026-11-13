#!/bin/sh
# On this machine (macOS 27.2), PencilKit's PKReplicaManager crashes inside
# CFEqual with "CFEqual() called with NULL first argument" when cfprefsd still
# holds replica state and the test process has no bundle identifier. Clearing
# that state and restarting cfprefsd makes `swift test` reproducible.
rm -f "$HOME/Library/Preferences/ByHost/com.apple.replicas.test."*.plist
killall cfprefsd 2>/dev/null || true
sleep 1
exec swift test "$@"
