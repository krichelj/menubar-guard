#!/usr/bin/env bash
# menubar-guard test suite.
# System commands (defaults, pgrep, pkill, open, mdfind, sleep) are shimmed
# via PATH so every test runs against a synthetic, disposable "Mac".
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
MG="$HERE/../menubar-guard.sh"
chmod +x "$HERE"/shims/* 2>/dev/null
export PATH="$HERE/shims:$PATH"

PASSED=0; FAILED=0; OUT=""; RC=0

t_setup() { # fresh synthetic Mac per test
  TMP=$(mktemp -d)
  export MG_TEST_STORE="$TMP/store" SHIM_STATE="$TMP/state" SHIM_LOG="$TMP/log"
  mkdir -p "$MG_TEST_STORE" "$SHIM_STATE"
  : >"$SHIM_LOG"; : >"$SHIM_STATE/running.txt"; : >"$SHIM_STATE/apps.txt"
  : >"$MG_TEST_STORE/_domains"
}
enc() { printf '%s' "$1" | tr '/: ' '___'; }
seed_key() { # domain key value  (registers domain in manifest)
  grep -qxF "$1" "$MG_TEST_STORE/_domains" || echo "$1" >>"$MG_TEST_STORE/_domains"
  echo "$2=$3" >>"$MG_TEST_STORE/$(enc "$1").txt"
}
seed_info() { # like seed_key but NOT listed in `defaults domains` (Info.plist)
  echo "$2=$3" >>"$MG_TEST_STORE/$(enc "$1").txt"
}
seed_ice_divider() { seed_key com.jordanbaird.Ice "NSStatusItem Preferred Position Ice.ControlItem.Hidden" "$1"; }
seed_app() { # bundle-id app-path exe-name
  printf '%s\t%s\n' "$1" "$2" >>"$SHIM_STATE/apps.txt"
  seed_info "$2/Contents/Info" CFBundleExecutable "$3"
}
seed_running() { echo "$1" >>"$SHIM_STATE/running.txt"; }
store_val() { grep -F "$2=" "$MG_TEST_STORE/$(enc "$1").txt" 2>/dev/null | head -1 | cut -d= -f2-; }

run() { OUT=$("$@" 2>&1); RC=$?; }
check() {
  local name=$1; shift
  if "$@"; then PASSED=$((PASSED+1)); echo "ok   $name"
  else FAILED=$((FAILED+1)); echo "FAIL $name"; printf '%s\n' "$OUT" | sed 's/^/     | /'; fi
}
contains()     { printf '%s' "$OUT" | grep -qF "$1"; }
not_contains() { ! printf '%s' "$OUT" | grep -qF "$1"; }
log_has()      { grep -qF "$1" "$SHIM_LOG"; }
log_lacks()    { ! grep -qF "$1" "$SHIM_LOG"; }
rc_is()        { [ "$RC" -eq "$1" ]; }

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
check "pin: app relaunched (open)"          log_has "open -g -j -b org.example.app"
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

# ---------------------------------------------------------------- summary
echo "---"
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
