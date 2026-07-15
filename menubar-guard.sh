#!/usr/bin/env bash
# menubar-guard - stop macOS menu-bar icons from silently disappearing.
# https://github.com/krichelj/menubar-guard
# MIT License - (c) 2026 Joshua Shay Kricheli
#
# THE PROBLEM
#   macOS lays out third-party status icons right-to-left and, when the
#   frontmost app's menus or the notch eat the remaining space, silently
#   drops whichever icon sits LEFTMOST. No error, no placeholder - the
#   icon is just gone. With Ice (github.com/jordanbaird/Ice) the bar is
#   split by a divider: items right of it are always shown, items left of
#   it live in Ice's hidden drawer (click the Ice icon to reveal them).
#
# THE FIX
#   Keep the shown section tiny and pinned hard-right; push everything
#   else left of Ice's divider. macOS persists icon order in each app's
#   preferences as "NSStatusItem Preferred Position <item>" - points from
#   the RIGHT screen edge, the same hint Cmd-dragging writes. This script
#   rewrites that hint and relaunches the app so it takes effect.

set -eu

VERSION="1.2.0"
ICE_DOMAIN="com.jordanbaird.Ice"
ICE_DIVIDER_KEY="NSStatusItem Preferred Position Ice.ControlItem.Hidden"
POS_PREFIX="NSStatusItem Preferred Position"
# Bundle ids never killed for a relaunch (their position applies on next
# manual restart instead). Edit to taste.
SKIP_RESTART="com.anthropic.claudefordesktop"
DRY_RUN=0
NO_RESTART=0
# verify tuning (override via environment)
PIN_MAX=${MG_PIN_MAX:-450}      # shown items must sit at position <= PIN_MAX
MAX_SHOWN=${MG_MAX_SHOWN:-13}   # rough capacity of the visible strip (notch)

usage() {
  cat <<'EOF'
menubar-guard - keep every macOS menu-bar icon either visible or in Ice's drawer

USAGE
  menubar-guard scan                           List all third-party status items
  menubar-guard pin  <bundle-id> [item] [pos]  Pin icon to the always-visible right
  menubar-guard hide <bundle-id> [item] [pos]  Move icon into Ice's hidden drawer
  menubar-guard verify                         Assert the no-lost-icons invariant
  menubar-guard divider                        Print Ice's divider position

OPTIONS
  --dry-run      Show what would change, change nothing
  --no-restart   Write the position but do not relaunch the app
  -h, --help     This help
  -v, --version  Version

NOTES
  * <item> defaults to "Item-0" - run `scan` to see each icon's real item name.
  * Positions are points from the RIGHT edge of the screen:
      position < divider  ->  shown section (always visible)
      position > divider  ->  Ice's hidden drawer (click the Ice icon)
  * The app owning the icon is relaunched in the background so the new
    position takes effect - equivalent to Cmd-dragging the icon by hand.
EOF
}

divider_pos() {
  defaults read "$ICE_DOMAIN" "$ICE_DIVIDER_KEY" 2>/dev/null || echo 100000
}

all_positions() {
  local d
  for d in $(defaults domains | tr ',' ' '); do
    defaults read "$d" 2>/dev/null | grep -F "$POS_PREFIX" \
      | sed -E 's/.*= *"?(-?[0-9.]+)"?;?$/\1/'
  done
}

cmd_scan() {
  local div body
  div=$(divider_pos)
  if [ "$div" = "100000" ]; then
    echo "Ice not detected - no hidden drawer; every item below counts as SHOWN."
  else
    echo "Ice divider position: $div  (items with position > $div live in Ice's drawer)"
  fi
  printf '%-10s %-7s %-44s %s\n' POSITION STATE DOMAIN ITEM
  body=$(
    for d in $(defaults domains | tr ',' ' '); do
      case "$d" in (com.apple.*) continue ;; esac
      defaults read "$d" 2>/dev/null | grep -F "$POS_PREFIX" | while IFS= read -r line; do
        item=$(printf '%s' "$line" | sed -E 's/.*Preferred Position ([^"]+)" *=.*/\1/')
        pos=$(printf '%s' "$line" | sed -E 's/.*= *"?(-?[0-9.]+)"?;?$/\1/')
        state=SHOWN
        if awk -v p="$pos" -v d="$div" 'BEGIN{exit !(p>d)}'; then state=HIDDEN; fi
        [ "$d" = "$ICE_DOMAIN" ] && state=ICE
        printf '%-10s %-7s %-44s %s\n' "$pos" "$state" "$d" "$item"
      done
    done
  )
  printf '%s\n' "$body" | sort -n
}

app_path_for() {
  mdfind "kMDItemCFBundleIdentifier == '$1'" 2>/dev/null | grep -m1 '\.app$' || true
}

app_running() { # $1 = executable name, $2 = .app path
  # Exact process name first; fall back to any process launched from inside
  # the bundle (Electron apps report helper names, not the app name).
  pgrep -xq "$1" 2>/dev/null && return 0
  pgrep -qf "$2/" 2>/dev/null
}

collides() {
  local cand=$1 p
  for p in $EXISTING; do
    if awk -v a="$p" -v b="$cand" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<12)}'; then
      return 0
    fi
  done
  return 1
}

next_free() {
  local want=$1 step=$2
  EXISTING=$(all_positions)
  while collides "$want"; do
    want=$(awk -v w="$want" -v s="$step" 'BEGIN{print w+s}')
  done
  echo "$want"
}

bounce() {
  local dom=$1 app exe
  if [ "$NO_RESTART" = 1 ]; then
    echo "  (relaunch skipped - takes effect next time $dom restarts)"
    return
  fi
  case " $SKIP_RESTART " in *" $dom "*)
    echo "  ! $dom is on the do-not-restart list - relaunch it yourself"
    return ;;
  esac
  app=$(app_path_for "$dom")
  if [ -z "$app" ]; then
    echo "  ! no .app found for $dom - relaunch it manually"
    return
  fi
  exe=$(defaults read "$app/Contents/Info" CFBundleExecutable 2>/dev/null \
        || basename "$app" .app)
  echo "  relaunching $(basename "$app") ..."
  pkill -x "$exe" 2>/dev/null || true
  sleep 1
  open -g -j -b "$dom" 2>/dev/null || open -g "$app"
}

apply() {
  local dom=$1 item=$2 pos=$3 what=$4
  case "$dom" in (com.apple.*)
    echo "refusing: $dom is a macOS system item. Its visibility is whatever you chose in System Settings (Control Center / Menu Bar) - this tool never overrides that choice." >&2
    exit 2 ;;
  esac
  echo "$what: $dom / $item -> position $pos"
  if [ "$DRY_RUN" = 1 ]; then
    echo "  (dry run - nothing written)"
    return
  fi
  defaults write "$dom" "$POS_PREFIX $item" -float "$pos"
  bounce "$dom"
}

cmd_pin() {
  local dom=$1 item=$2 pos=$3
  [ -n "$pos" ] || pos=$(next_free 250 30)
  apply "$dom" "$item" "$pos" "pin (always visible)"
}

cmd_hide() {
  local dom=$1 item=$2 pos=$3 div
  div=$(divider_pos)
  if [ "$div" = "100000" ]; then
    echo "warning: Ice not detected - hidden items have no drawer to appear in" >&2
  fi
  [ -n "$pos" ] || pos=$(next_free 5500 20)
  apply "$dom" "$item" "$pos" "hide (Ice drawer)"
}

list_items() { # tab-separated rows: pos <TAB> domain <TAB> item
  local d line item pos
  for d in $(defaults domains | tr ',' ' '); do
    case "$d" in (com.apple.*) continue ;; esac
    defaults read "$d" 2>/dev/null | grep -F "$POS_PREFIX" | while IFS= read -r line; do
      item=$(printf '%s' "$line" | sed -E 's/.*Preferred Position ([^"]+)" *=.*/\1/')
      pos=$(printf '%s' "$line" | sed -E 's/.*= *"?(-?[0-9.]+)"?;?$/\1/')
      printf '%s\t%s\t%s\n' "$pos" "$d" "$item"
    done
  done
}

cmd_verify() {
  # Invariant: every third-party status item is either pinned right
  # (pos <= PIN_MAX, owning app running) or in Ice's drawer (pos > divider).
  # Anything in between is in the trim zone and may silently disappear.
  local div fails=0 warns=0 shown_tp=0 rows pos d item app exe cc18 total
  div=$(divider_pos)
  if pgrep -xq Ice 2>/dev/null; then
    echo "PASS  Ice is running (drawer available)"
  elif [ "$div" = "100000" ]; then
    echo "WARN  Ice not detected - no drawer; only pinned items are protected"
    warns=$((warns+1))
  else
    echo "FAIL  Ice is installed but NOT running - drawer items are unreachable"
    fails=$((fails+1))
  fi
  rows=$(list_items)
  while IFS="$(printf '\t')" read -r pos d item; do
    [ -n "$pos" ] || continue
    [ "$d" = "$ICE_DOMAIN" ] && continue
    if awk -v p="$pos" -v m="$PIN_MAX" 'BEGIN{exit !(p<=m)}'; then
      shown_tp=$((shown_tp+1))
      app=$(app_path_for "$d")
      if [ -z "$app" ]; then
        echo "WARN  $d ($item) pinned at $pos - owning app not found on disk"
        warns=$((warns+1))
      else
        exe=$(defaults read "$app/Contents/Info" CFBundleExecutable 2>/dev/null \
              || basename "$app" .app)
        if app_running "$exe" "$app"; then
          echo "PASS  $d ($item) pinned at $pos, app running"
        else
          echo "FAIL  $d ($item) pinned at $pos but app NOT running - icon absent"
          fails=$((fails+1))
        fi
      fi
    elif awk -v p="$pos" -v dd="$div" 'BEGIN{exit !(p>dd)}'; then
      echo "PASS  $d ($item) in drawer at $pos"
    else
      echo "FAIL  $d ($item) at $pos - TRIM ZONE ($PIN_MAX..$div): may vanish. Run pin or hide."
      fails=$((fails+1))
    fi
  done <<VERIFY_EOF
$rows
VERIFY_EOF
  cc18=$(defaults -currentHost read com.apple.controlcenter 2>/dev/null | grep -c '= 18' || true)
  cc18=${cc18:-0}
  total=$((shown_tp + cc18 + 5)) # +5: battery, wifi, spotlight, control center, clock
  if [ "$total" -gt "$MAX_SHOWN" ]; then
    echo "WARN  ~$total always-visible items > capacity $MAX_SHOWN - overflow risk. Hide something or set Control Center modules to 'Show When Active'."
    warns=$((warns+1))
  else
    echo "PASS  visible-strip load ~$total/$MAX_SHOWN"
  fi
  echo "---"
  echo "verify: $fails failure(s), $warns warning(s)"
  [ "$fails" -eq 0 ]
}

main() {
  local cmd="" a1="" a2="" a3="" a
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY_RUN=1 ;;
      --no-restart) NO_RESTART=1 ;;
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "menubar-guard $VERSION"; exit 0 ;;
      *)
        if [ -z "$cmd" ]; then cmd=$a
        elif [ -z "$a1" ]; then a1=$a
        elif [ -z "$a2" ]; then a2=$a
        elif [ -z "$a3" ]; then a3=$a
        fi ;;
    esac
  done
  case "${cmd:-help}" in
    scan) cmd_scan ;;
    verify) cmd_verify ;;
    divider) divider_pos ;;
    pin)
      [ -n "$a1" ] || { echo "pin needs a bundle id (see: menubar-guard scan)" >&2; exit 1; }
      cmd_pin "$a1" "${a2:-Item-0}" "$a3" ;;
    hide)
      [ -n "$a1" ] || { echo "hide needs a bundle id (see: menubar-guard scan)" >&2; exit 1; }
      cmd_hide "$a1" "${a2:-Item-0}" "$a3" ;;
    help) usage ;;
    *) echo "unknown command: $cmd" >&2; usage >&2; exit 1 ;;
  esac
}

main "$@"
