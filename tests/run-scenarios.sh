#!/usr/bin/env bash
# menubar-guard SCENARIO suite - merged, multi-step behaviours.
# Unlike run-tests.sh (isolated unit assertions), these scenarios chain
# commands on ONE evolving synthetic Mac and assert every state transition:
# messy machine -> full cleanup -> idempotent re-run -> stubborn app fights
# back -> Ice dies/uninstalls -> new app arrives -> Control Center churn ->
# dry-run sweeps -> system-item guard. CLI only, zero real side effects.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

echo "SCENARIO 1: messy Mac -> full cleanup -> verify green -> idempotent re-run"
t_setup
seed_ice_divider 714
seed_app com.jordanbaird.Ice /Apps/Ice.app Ice
seed_running Ice
# five icons stranded in the trim zone (the whack-a-mole state)
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 652
seed_app net.sf.Jumpcut /Apps/Jumpcut.app Jumpcut;               seed_running Jumpcut
seed_key com.corecode.MacUpdater "NSStatusItem Preferred Position Item-0" 560
seed_app com.corecode.MacUpdater /Apps/MacUpdater.app MacUpdater; seed_running MacUpdater
seed_key com.google.drivefs "NSStatusItem Preferred Position Item-0" 610
seed_app com.google.drivefs "/Apps/Google Drive.app" "Google Drive"; seed_running "Google Drive"
seed_key org.hammerspoon.Hammerspoon "NSStatusItem Preferred Position Item-0" 574
seed_app org.hammerspoon.Hammerspoon /Apps/Hammerspoon.app Hammerspoon; seed_running Hammerspoon
# Electron app on the do-not-restart list: only a helper process runs
seed_key com.anthropic.claudefordesktop "NSStatusItem Preferred Position Item-0" 642
seed_app com.anthropic.claudefordesktop /Apps/Claude.app Claude
seed_running "/Apps/Claude.app/Contents/Frameworks/Claude Helper"
# two apps already safe in the drawer + a system item (must be ignored)
seed_key com.microsoft.teams2 "NSStatusItem Preferred Position Item-0" 5861
seed_key ru.keepcoder.Telegram "NSStatusItem Preferred Position Item-0" 6077
seed_key com.apple.controlcenter "NSStatusItem Preferred Position Bluetooth" 528

run "$MG" verify
check "s1: dirty state FAILs"                rc_is 1
check "s1: exactly 5 trim-zone failures"     count_is "TRIM ZONE" 5
check "s1: Ice button WARNs (no position)"   contains "no saved position"
check "s1: drawer items already PASS"        contains "in drawer at 5861"
check "s1: system item ignored"              not_contains "com.apple.controlcenter"

run "$MG" pin net.sf.Jumpcut JumpcutStatusItem
check "s1: jumpcut -> first free slot 250"   contains "position 250"
run "$MG" pin com.corecode.MacUpdater
check "s1: macupdater avoids 250 -> 280"     contains "position 280"
run "$MG" pin com.anthropic.claudefordesktop
check "s1: claude -> 310, but never killed"  contains "position 310"
check "s1: claude on do-not-restart list"    contains "do-not-restart"
run "$MG" pin-ice
check "s1: ice button -> safest slot 235"    contains "position 235"
run "$MG" hide com.google.drivefs
check "s1: drive -> drawer 5500"             contains "position 5500"
run "$MG" hide org.hammerspoon.Hammerspoon
check "s1: hammerspoon -> drawer 5520"       contains "position 5520"

run "$MG" verify
check "s1: verify green after cleanup"       rc_is 0
check "s1: zero failures reported"           contains "0 failure(s)"
check "s1: ice button pinned PASS"           contains "Ice button pinned at 235"
check "s1: electron helper counts as alive"  contains "pinned at 310, app running"

H_BEFORE=$(store_hash); clear_log
run "$MG" pin net.sf.Jumpcut JumpcutStatusItem
run "$MG" pin com.corecode.MacUpdater
run "$MG" pin com.anthropic.claudefordesktop
OUT_LAST=$OUT
run "$MG" pin-ice
check "s1: re-run pin-ice is a no-op"        contains "nothing to do"
run "$MG" hide com.google.drivefs
check "s1: re-run hide is a no-op"           contains "nothing to do"
run "$MG" hide org.hammerspoon.Hammerspoon
check "s1: idempotent - store byte-identical" test "$(store_hash)" = "$H_BEFORE"
check "s1: idempotent - nothing written"     log_lacks "defaults write"
check "s1: idempotent - nothing relaunched"  log_lacks "pkill"

echo
echo "SCENARIO 2: stubborn app rewrites its own position after relaunch"
defaults write com.google.drivefs "NSStatusItem Preferred Position Item-0" -float 580
run "$MG" verify
check "s2: drive's self-rewrite caught"      rc_is 1
check "s2: culprit named"                    contains "com.google.drivefs"
check "s2: flagged as trim zone"             contains "TRIM ZONE"
clear_log
run "$MG" hide com.google.drivefs
check "s2: re-hide picks a drawer slot"      contains "hide (Ice drawer)"
check "s2: drive relaunched to apply"        log_has "pkill -x Google Drive"
run "$MG" verify
check "s2: green again after re-hide"        rc_is 0

echo
echo "SCENARIO 3: Ice stops, then 'uninstalls', then comes back"
unseed_running Ice
run "$MG" verify
check "s3: dead Ice FAILs"                   rc_is 1
check "s3: names the drawer risk"            contains "NOT running"
seed_running Ice
run "$MG" verify
check "s3: Ice back -> green"                rc_is 0

defaults delete com.jordanbaird.Ice "NSStatusItem Preferred Position Ice.ControlItem.Hidden"
run "$MG" verify
check "s3: no divider -> drawer items unsafe" rc_is 1
check "s3: all 4 drawer items now trim zone" count_is "TRIM ZONE" 4
defaults write com.jordanbaird.Ice "NSStatusItem Preferred Position Ice.ControlItem.Hidden" -float 714
run "$MG" verify
check "s3: divider restored -> green"        rc_is 0

echo
echo "SCENARIO 4: new app arrives + Control Center churn (user's choices)"
seed_key org.brandnew.app "NSStatusItem Preferred Position Item-0" 6200
run "$MG" verify
check "s4: new app lands in drawer, no action needed" contains "in drawer at 6200"
check "s4: still green"                      rc_is 0

defaults write com.apple.controlcenter M1 -int 18
defaults write com.apple.controlcenter M2 -int 18
defaults write com.apple.controlcenter M3 -int 18
defaults write com.apple.controlcenter M4 -int 18
defaults write com.apple.controlcenter M5 -int 18
defaults write com.apple.controlcenter M6 -int 18
run "$MG" verify
check "s4: heavy CC config -> capacity WARN" contains "overflow risk"
check "s4: user's CC choice never a FAILURE" rc_is 0
defaults write com.apple.controlcenter M1 -int 8
defaults write com.apple.controlcenter M2 -int 8
defaults write com.apple.controlcenter M3 -int 8
defaults write com.apple.controlcenter M4 -int 8
defaults write com.apple.controlcenter M5 -int 8
defaults write com.apple.controlcenter M6 -int 8
run "$MG" verify
check "s4: lighter CC config -> warning clears" not_contains "overflow risk"
check "s4: verify agnostic either way"       rc_is 0

echo
echo "SCENARIO 5: dry-run sweep mutates nothing, relaunches nothing"
H_DRY=$(store_hash); clear_log
run "$MG" --dry-run pin org.brandnew.app Item-0 400
check "s5: dry pin announces itself"         contains "dry run"
run "$MG" --dry-run hide net.sf.Jumpcut JumpcutStatusItem 6000
check "s5: dry hide announces itself"        contains "dry run"
run "$MG" --dry-run pin-ice 999
check "s5: dry pin-ice announces itself"     contains "dry run"
check "s5: store byte-identical"             test "$(store_hash)" = "$H_DRY"
check "s5: no writes logged"                 log_lacks "defaults write"
check "s5: no relaunches logged"             log_lacks "pkill"
run "$MG" verify
check "s5: state still green"                rc_is 0

echo
echo "SCENARIO 6: system items stay sacred even when pre-positioned"
seed_key com.apple.controlcenter "NSStatusItem Preferred Position Battery" 249
run "$MG" pin com.apple.controlcenter Battery
check "s6: pin refuses despite saved pos"    contains "refusing"
check "s6: pin exits 2"                      rc_is 2
check "s6: battery position untouched"       test "$(store_val com.apple.controlcenter 'NSStatusItem Preferred Position Battery')" = "249"
run "$MG" hide com.apple.controlcenter Battery
check "s6: hide refuses too"                 rc_is 2
run "$MG" verify
check "s6: final state green end-to-end"     rc_is 0

summary
