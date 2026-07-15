#!/usr/bin/env bash
# menubar-guard test suite.
# System commands (defaults, pgrep, pkill, open, mdfind, sleep) are shimmed
# via PATH so every test runs against a synthetic, disposable "Mac".
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

# ---------------------------------------------------------------- scan
t_setup
seed_ice_divider 714
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 250
seed_key org.example.hidden "NSStatusItem Preferred Position Item-0" 5600
seed_key com.apple.controlcenter "NSStatusItem Preferred Position Battery" 249
run "$MG" scan
check "scan: shows divider position"        contains "Ice divider position: 714"
check "scan: pinned item listed as SHOWN"   contains "250"
check "scan: pinned item row has SHOWN"     contains "SHOWN"
check "scan: drawer item listed as HIDDEN"  contains "HIDDEN"
check "scan: com.apple.* domains skipped"   not_contains "com.apple.controlcenter"
check "scan: exits 0"                       rc_is 0

# ------------------------------------------------- scan without Ice
t_setup
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 250
run "$MG" scan
check "scan/no-ice: warns Ice not detected" contains "Ice not detected"
check "scan/no-ice: item counts as SHOWN"   contains "SHOWN"

# ---------------------------------------------------------------- pin
t_setup
seed_ice_divider 714
seed_app org.example.app /Apps/Example.app Example
run "$MG" pin org.example.app
check "pin: default slot 250"               contains "position 250"
check "pin: hint written to prefs"          test "$(store_val org.example.app 'NSStatusItem Preferred Position Item-0')" = "250"
check "pin: app relaunched (pkill)"         log_has "pkill -x Example"
check "pin: app relaunched (open)"          log_has "open -g -b org.example.app"
check "pin: never launch-hidden (-j)"       log_lacks " -j "
check "pin: exits 0"                        rc_is 0

# ------------------------------------------------- pin collision avoidance
t_setup
seed_ice_divider 714
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 250
seed_app org.example.app /Apps/Example.app Example
run "$MG" pin org.example.app
check "pin/collision: skips 250, picks 280" contains "position 280"

# ---------------------------------------------------------------- hide
t_setup
seed_ice_divider 714
seed_app org.example.app /Apps/Example.app Example
run "$MG" hide org.example.app
check "hide: default slot 5500"             contains "position 5500"
check "hide: hint written to prefs"         test "$(store_val org.example.app 'NSStatusItem Preferred Position Item-0')" = "5500"

t_setup
seed_ice_divider 714
seed_key org.other.app "NSStatusItem Preferred Position Item-0" 5500
seed_app org.example.app /Apps/Example.app Example
run "$MG" hide org.example.app
check "hide/collision: skips 5500 -> 5520"  contains "position 5520"

# ------------------------------------------------- hide without Ice warns
t_setup
seed_app org.example.app /Apps/Example.app Example
run "$MG" hide org.example.app
check "hide/no-ice: warns no drawer"        contains "no drawer"

# ---------------------------------------------------------------- flags
t_setup
seed_ice_divider 714
seed_app org.example.app /Apps/Example.app Example
run "$MG" --dry-run pin org.example.app
check "dry-run: announces itself"           contains "dry run"
check "dry-run: writes nothing"             test -z "$(store_val org.example.app 'NSStatusItem Preferred Position Item-0')"
check "dry-run: no pkill/open"              log_lacks "pkill"

t_setup
seed_ice_divider 714
seed_app org.example.app /Apps/Example.app Example
run "$MG" --no-restart pin org.example.app
check "no-restart: hint written"            test "$(store_val org.example.app 'NSStatusItem Preferred Position Item-0')" = "250"
check "no-restart: app not killed"          log_lacks "pkill"

# ------------------------------------------------- protected + missing apps
t_setup
seed_ice_divider 714
seed_app com.anthropic.claudefordesktop /Apps/Claude.app Claude
run "$MG" pin com.anthropic.claudefordesktop
check "skip-list: hint still written"       test -n "$(store_val com.anthropic.claudefordesktop 'NSStatusItem Preferred Position Item-0')"
check "skip-list: app never killed"         log_lacks "pkill"
check "skip-list: says do-not-restart"      contains "do-not-restart"

t_setup
seed_ice_divider 714
run "$MG" pin org.ghost.app
check "missing-app: warns manual relaunch"  contains "relaunch it manually"
check "missing-app: no pkill attempted"     log_lacks "pkill"

# ---------------------------------------------------------------- pin-ice
t_setup
seed_ice_divider 714
seed_app com.jordanbaird.Ice /Apps/Ice.app Ice
run "$MG" pin-ice
check "pin-ice: default slot 235"           contains "position 235"
check "pin-ice: position written"           test "$(store_val com.jordanbaird.Ice 'NSStatusItem Preferred Position Ice.ControlItem.Visible')" = "235"
check "pin-ice: ShowIceIcon forced on"      test "$(store_val com.jordanbaird.Ice 'ShowIceIcon')" = "1"
check "pin-ice: item unsuppressed"          test "$(store_val com.jordanbaird.Ice 'NSStatusItem Visible Ice.ControlItem.Visible')" = "1"
check "pin-ice: Ice relaunched (pkill)"     log_has "pkill -x Ice"
check "pin-ice: Ice relaunched (open)"      log_has "open -g -b com.jordanbaird.Ice"
check "pin-ice: never launch-hidden (-j)"   log_lacks " -j "

t_setup
seed_ice_divider 714
seed_key org.other.app "NSStatusItem Preferred Position Item-0" 235
seed_app com.jordanbaird.Ice /Apps/Ice.app Ice
run "$MG" pin-ice
check "pin-ice/collision: 235 taken -> 250" contains "position 250"

# ------------------------------------------- verify guards the Ice button
t_setup
seed_ice_divider 714
seed_running Ice
seed_key com.jordanbaird.Ice "ShowIceIcon" 1
seed_key com.jordanbaird.Ice "NSStatusItem Visible Ice.ControlItem.Visible" 1
seed_key com.jordanbaird.Ice "NSStatusItem Preferred Position Ice.ControlItem.Visible" 240
run "$MG" verify
check "verify/ice-btn: pinned PASSes"       contains "Ice button pinned at 240"
check "verify/ice-btn: exits 0"             rc_is 0

t_setup
seed_ice_divider 714
seed_running Ice
seed_key com.jordanbaird.Ice "ShowIceIcon" 1
seed_key com.jordanbaird.Ice "NSStatusItem Visible Ice.ControlItem.Visible" 1
seed_key com.jordanbaird.Ice "NSStatusItem Preferred Position Ice.ControlItem.Visible" 500
run "$MG" verify
check "verify/ice-btn: trim zone FAILs"     contains "drawer handle itself can vanish"
check "verify/ice-btn: trim zone exits 1"   rc_is 1

t_setup
seed_ice_divider 714
seed_running Ice
seed_key com.jordanbaird.Ice "ShowIceIcon" 0
run "$MG" verify
check "verify/ice-btn: disabled FAILs"      contains "ShowIceIcon=0"
check "verify/ice-btn: disabled exits 1"    rc_is 1

t_setup
seed_ice_divider 714
seed_running Ice
seed_key com.jordanbaird.Ice "ShowIceIcon" 1
seed_key com.jordanbaird.Ice "NSStatusItem Visible Ice.ControlItem.Visible" 0
run "$MG" verify
check "verify/ice-btn: suppressed FAILs"    contains "suppressed"
check "verify/ice-btn: suppressed exits 1"  rc_is 1

# ------------------------------------------------- system items are sacred
t_setup
seed_ice_divider 714
run "$MG" pin com.apple.controlcenter Battery
check "guard: pin refuses com.apple.*"      contains "refusing"
check "guard: pin exits 2"                  rc_is 2
check "guard: nothing written"              test -z "$(store_val com.apple.controlcenter 'NSStatusItem Preferred Position Battery')"
check "guard: no process touched"           log_lacks "pkill"

t_setup
seed_ice_divider 714
run "$MG" hide com.apple.TextInputMenuAgent
check "guard: hide refuses com.apple.*"     contains "refusing"
check "guard: hide exits 2"                 rc_is 2

t_setup   # verify must be agnostic to the user's Control Center choices
seed_ice_divider 714
seed_running Ice
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 250
seed_app net.sf.Jumpcut /Apps/Jumpcut.app Jumpcut
seed_running Jumpcut
seed_key com.apple.controlcenter "NSStatusItem Preferred Position Bluetooth" 528
seed_key com.apple.controlcenter "Sound" 18
seed_key com.apple.controlcenter "NowPlaying" 8
run "$MG" verify
check "verify/cc-agnostic: system rows ignored"  not_contains "com.apple.controlcenter"
check "verify/cc-agnostic: no FAIL from CC"      contains "0 failure(s)"
check "verify/cc-agnostic: exits 0"              rc_is 0

# ---------------------------------------------------------------- verify
t_setup
seed_ice_divider 714
seed_running Ice
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 250
seed_app net.sf.Jumpcut /Apps/Jumpcut.app Jumpcut
seed_running Jumpcut
seed_key org.example.hidden "NSStatusItem Preferred Position Item-0" 5600
run "$MG" verify
check "verify/green: Ice running PASS"      contains "PASS  Ice is running"
check "verify/green: pinned+running PASS"   contains "pinned at 250, app running"
check "verify/green: drawer item PASS"      contains "in drawer at 5600"
check "verify/green: zero failures"         contains "0 failure(s)"
check "verify/green: exits 0"               rc_is 0

t_setup
seed_ice_divider 714
seed_running Ice
seed_key com.google.drivefs "NSStatusItem Preferred Position Item-0" 580
seed_app com.google.drivefs "/Apps/Google Drive.app" "Google Drive"
seed_running "Google Drive"
run "$MG" verify
check "verify/trim-zone: FAILs item at 580" contains "TRIM ZONE"
check "verify/trim-zone: names the app"     contains "com.google.drivefs"
check "verify/trim-zone: exits 1"           rc_is 1

t_setup
seed_ice_divider 714
seed_running Ice
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 250
seed_app net.sf.Jumpcut /Apps/Jumpcut.app Jumpcut   # Jumpcut NOT running
run "$MG" verify
check "verify/dead-app: FAILs stopped app"  contains "app NOT running"
check "verify/dead-app: exits 1"            rc_is 1

t_setup   # Electron-style app: no process named after the bundle, only helpers
seed_ice_divider 714
seed_running Ice
seed_key com.electron.app "NSStatusItem Preferred Position Item-0" 260
seed_app com.electron.app /Apps/Electro.app Electro
seed_running "/Apps/Electro.app/Contents/Frameworks/Electro Helper"
run "$MG" verify
check "verify/electron: helper counts as running" contains "pinned at 260, app running"
check "verify/electron: exits 0"            rc_is 0

t_setup
seed_key net.sf.Jumpcut "NSStatusItem Preferred Position JumpcutStatusItem" 250
seed_app net.sf.Jumpcut /Apps/Jumpcut.app Jumpcut
seed_running Jumpcut
run "$MG" verify   # Ice absent entirely
check "verify/no-ice: WARNs, not FAILs"     contains "WARN  Ice not detected"
check "verify/no-ice: exits 0"              rc_is 0

t_setup
seed_ice_divider 714
run env MG_MAX_SHOWN=4 "$MG" verify   # 0 tp + 0 cc + 5 fixed = 5 > 4
check "verify/capacity: WARNs on overflow"  contains "overflow risk"

# ---------------------------------------------------------- idempotency
t_setup
seed_ice_divider 714
seed_app org.example.app /Apps/Example.app Example
run "$MG" pin org.example.app
clear_log
run "$MG" pin org.example.app
check "idempotent: 2nd pin is a no-op"      contains "already pinned at 250"
check "idempotent: 2nd pin writes nothing"  log_lacks "defaults write"
check "idempotent: 2nd pin kills nothing"   log_lacks "pkill"
run "$MG" pin org.example.app Item-0 260
check "idempotent: explicit pos overrides"  contains "position 260"

t_setup
seed_ice_divider 714
seed_app org.example.app /Apps/Example.app Example
run "$MG" hide org.example.app
clear_log
run "$MG" hide org.example.app
check "idempotent: 2nd hide is a no-op"     contains "already in drawer at 5500"
check "idempotent: 2nd hide kills nothing"  log_lacks "pkill"

t_setup
seed_ice_divider 714
seed_app com.jordanbaird.Ice /Apps/Ice.app Ice
run "$MG" pin-ice
clear_log
run "$MG" pin-ice
check "idempotent: 2nd pin-ice is a no-op"  contains "already pinned at 235"
check "idempotent: 2nd pin-ice no relaunch" log_lacks "pkill"

# ---------------------------------------------------------------- summary
echo "---"
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
