# Changelog

## 1.3.0 — 2026-07-15

- New `pin-ice` command: pins Ice's own button hard-right (default slot 235, rightmost of all pinned icons), forces `ShowIceIcon` on and un-suppresses the status item, then relaunches Ice. The Ice button is the drawer handle — if it gets trimmed, every hidden icon becomes unreachable.
- `verify` now guards the Ice button in all scenarios: FAILs if it is disabled (`ShowIceIcon=0`), suppressed (`NSStatusItem Visible=0`), or parked in the trim zone; WARNs if it has no saved position. The button also counts toward the capacity estimate.
- Test suite grows to 66 assertions.

## 1.2.0 — 2026-07-15

- **System items are sacred**: `pin`/`hide` now refuse `com.apple.*` domains (exit 2). The user's System Settings choices for Bluetooth, Sound, Now Playing, Display, etc. are never overridden.
- `verify` is provably agnostic to Control Center configuration — new tests seed CC modules in arbitrary states and assert identical results (capacity estimate stays informational).
- Test suite grows to 52 assertions.

## 1.1.0 — 2026-07-15

- New `verify` command — asserts the no-lost-icons invariant and exits non-zero on violations:
  - every third-party item is pinned right (≤ `MG_PIN_MAX`, default 450) or in Ice's drawer (> divider); anything in the trim zone FAILs
  - pinned items' owning apps must be running (Electron-aware: helper processes inside the `.app` bundle count)
  - Ice presence/liveness, and a visible-strip capacity estimate (`MG_MAX_SHOWN`, default 13) with overflow warnings
- Formal test suite: `tests/run-tests.sh` runs 43 assertions against a synthetic Mac (shimmed `defaults`/`pgrep`/`pkill`/`open`/`mdfind`), zero side effects on the real system
- Fix: bash 3.2 parser compatibility for `case` patterns inside command substitution

## 1.0.0 — 2026-07-15

Initial release.

- `scan`: enumerate every third-party `NSStatusItem` with position and SHOWN/HIDDEN state relative to Ice's divider
- `pin`: place an icon in the always-visible right side of the menu bar (auto slot picking, collision avoidance)
- `hide`: sweep an icon into Ice's hidden drawer
- Automatic background relaunch of the owning app (`--no-restart` to opt out, `SKIP_RESTART` safety list)
- `--dry-run` mode
- Works without Ice (pin only) — warns when hiding with no drawer present
