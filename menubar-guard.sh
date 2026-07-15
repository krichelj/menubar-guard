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

VERSION="1.0.0"
ICE_DOMAIN="com.jordanbaird.Ice"
ICE_DIVIDER_KEY="NSStatusItem Preferred Position Ice.ControlItem.Hidden"
POS_PREFIX="NSStatusItem Preferred Position"
# Bundle ids never killed for a relaunch (their position applies on next
# manual restart instead). Edit to taste.
SKIP_RESTART="com.anthropic.claudefordesktop"
DRY_RUN=0
NO_RESTART=0

usage() {
  cat <<'EOF'
menubar-guard - keep every macOS menu-bar icon either visible or in Ice's drawer

USAGE
  menubar-guard scan                           List all third-party status items
  menubar-guard pin  <bundle-id> [item] [pos]  Pin icon to the always-visible right
  menubar-guard hide <bundle-id> [item] [pos]  Move icon into Ice's hidden drawer
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
