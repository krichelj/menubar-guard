# Shared test harness for menubar-guard suites.
# System commands (defaults, pgrep, pkill, open, mdfind, sleep) are shimmed
# via PATH so every test runs against a synthetic, disposable "Mac".

LIB_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MG="$LIB_HERE/../menubar-guard.sh"
chmod +x "$LIB_HERE"/shims/* 2>/dev/null
export PATH="$LIB_HERE/shims:$PATH"

PASSED=0; FAILED=0; OUT=""; RC=0

t_setup() { # fresh synthetic Mac per test/scenario
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
seed_running()  { echo "$1" >>"$SHIM_STATE/running.txt"; }
unseed_running(){ grep -vxF "$1" "$SHIM_STATE/running.txt" >"$SHIM_STATE/r.tmp" || true; mv "$SHIM_STATE/r.tmp" "$SHIM_STATE/running.txt"; }
clear_log()     { : >"$SHIM_LOG"; }
store_val() { grep -F "$2=" "$MG_TEST_STORE/$(enc "$1").txt" 2>/dev/null | head -1 | cut -d= -f2-; }
store_hash() { # order-independent fingerprint of the entire prefs store
  (cd "$MG_TEST_STORE" && for f in $(ls | sort); do echo "== $f"; sort "$f"; done) | md5 -q 2>/dev/null \
    || (cd "$MG_TEST_STORE" && for f in $(ls | sort); do echo "== $f"; sort "$f"; done) | md5sum | cut -d' ' -f1
}

run() { OUT=$("$@" 2>&1); RC=$?; }
check() {
  local name=$1; shift
  if "$@"; then PASSED=$((PASSED+1)); echo "ok   $name"
  else FAILED=$((FAILED+1)); echo "FAIL $name"; printf '%s\n' "$OUT" | sed 's/^/     | /'; fi
}
contains()     { printf '%s' "$OUT" | grep -qF "$1"; }
not_contains() { ! printf '%s' "$OUT" | grep -qF "$1"; }
count_is()     { [ "$(printf '%s\n' "$OUT" | grep -cF "$1")" -eq "$2" ]; }
log_has()      { grep -qF "$1" "$SHIM_LOG"; }
log_lacks()    { ! grep -qF "$1" "$SHIM_LOG"; }
rc_is()        { [ "$RC" -eq "$1" ]; }

summary() {
  echo "---"
  echo "$PASSED passed, $FAILED failed"
  [ "$FAILED" -eq 0 ]
}
