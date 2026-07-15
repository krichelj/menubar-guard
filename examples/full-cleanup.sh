#!/usr/bin/env bash
# Example: the real-world cleanup this tool was born from (2026-07-15).
# A notched MacBook kept "losing" one menu-bar icon at a time — whichever
# happened to be leftmost. End state: 3 pinned icons, everything else in
# Ice's drawer, nothing ever silently trimmed again.

set -eu

# See what you have first
menubar-guard scan

# Pin the essentials (clipboard manager, updater)
menubar-guard pin net.sf.Jumpcut JumpcutStatusItem 250
menubar-guard pin com.corecode.MacUpdater Item-0 300

# Sweep the crowd into Ice's drawer
menubar-guard hide com.google.drivefs
menubar-guard hide com.microsoft.OneDrive-mac Item-1
menubar-guard hide org.hammerspoon.Hammerspoon
menubar-guard hide com.jamf.connect
menubar-guard hide me.timschneeberger.galaxybudsclient

# Confirm
menubar-guard scan
