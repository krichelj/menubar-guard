# Changelog

## 1.0.0 — 2026-07-15

Initial release.

- `scan`: enumerate every third-party `NSStatusItem` with position and SHOWN/HIDDEN state relative to Ice's divider
- `pin`: place an icon in the always-visible right side of the menu bar (auto slot picking, collision avoidance)
- `hide`: sweep an icon into Ice's hidden drawer
- Automatic background relaunch of the owning app (`--no-restart` to opt out, `SKIP_RESTART` safety list)
- `--dry-run` mode
- Works without Ice (pin only) — warns when hiding with no drawer present
