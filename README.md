# menubar-guard

> Stop macOS menu-bar icons from silently disappearing — every icon is either always visible or one click away in [Ice](https://github.com/jordanbaird/Ice)'s drawer.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![shell](https://img.shields.io/badge/shell-bash-89e051)
![license](https://img.shields.io/badge/license-MIT-green)

## The problem

macOS lays out third-party status icons right-to-left. When the frontmost app has long menus — or your MacBook's **notch** eats the middle of the bar — macOS silently drops whichever icon sits **leftmost**. No error, no placeholder. The icon is just gone, and it's always "that one app" (your clipboard manager, your updater...) whose icon happens to be leftmost that day.

Menu-bar managers like [Ice](https://github.com/jordanbaird/Ice) split the bar with a divider: icons right of it stay shown, icons left of it live in a hidden drawer you open by clicking the Ice icon. But Ice can't create more physical space — icons in the *shown* section still overflow and vanish.

## The fix

The only stable layout: keep the shown section **small and pinned hard-right** (last to be trimmed, clear of the notch), and sweep everything else **left of Ice's divider** into the drawer.

macOS persists each icon's order in the owning app's preferences under `NSStatusItem Preferred Position <item>` — points from the *right* screen edge, the exact hint written when you Cmd-drag an icon. `menubar-guard` rewrites that hint and relaunches the app (backgrounded) so it takes effect. Deterministic, scriptable, reboot-proof.

## Install

```sh
git clone https://github.com/krichelj/menubar-guard.git
cd menubar-guard
chmod +x menubar-guard.sh
sudo ln -s "$PWD/menubar-guard.sh" /usr/local/bin/menubar-guard
```

## Usage

```sh
# 1. See every third-party status item, its position, and whether it's
#    SHOWN or HIDDEN relative to Ice's divider
menubar-guard scan

# 2. Pin the icons you must always see (auto-picks a free right-side slot)
menubar-guard pin net.sf.Jumpcut JumpcutStatusItem
menubar-guard pin com.corecode.MacUpdater

# 3. Sweep the rest into Ice's drawer
menubar-guard hide com.google.drivefs
menubar-guard hide org.hammerspoon.Hammerspoon
menubar-guard hide com.microsoft.OneDrive-mac Item-1

# Preview without touching anything
menubar-guard --dry-run hide com.jamf.connect

# 4. Prove the invariant holds — every icon pinned or in the drawer,
#    every pinned app alive. Non-zero exit on any violation (CI-friendly).
menubar-guard verify
```

`scan` output looks like:

```
Ice divider position: 714  (items with position > 714 live in Ice's drawer)
POSITION   STATE   DOMAIN                                       ITEM
250        SHOWN   net.sf.Jumpcut                               JumpcutStatusItem
300        SHOWN   com.corecode.MacUpdater                      Item-0
5540       HIDDEN  com.google.drivefs                           Item-0
5861       HIDDEN  com.microsoft.teams2                         Item-0
```

## How positions work

| Position | Meaning |
|---|---|
| `< divider` (e.g. 250–400) | Shown section, right side — trimmed **last**, clear of the notch |
| `> divider` (e.g. 5500+) | Ice's hidden drawer — click the Ice icon to reveal |

New apps spawn their icon at the far left, which lands in the hidden drawer automatically — so future installs can never silently lose an icon either.

## Verify & test

`menubar-guard verify` asserts the invariant this tool exists for: **no icon can silently disappear**. It checks that every third-party item is either pinned right (position ≤ 450) or in Ice's drawer (position > divider), that every pinned item's owning app is actually running (Electron helpers count), that Ice itself is alive, and that the always-visible strip isn't over capacity. Exit code 0 = invariant holds; run it from cron/CI if you're paranoid.

The repo ships a formal test suite — `tests/run-tests.sh` — that runs 52 assertions against a synthetic Mac built from shimmed `defaults`, `pgrep`, `pkill`, `open`, and `mdfind`. It never touches your real preferences or processes:

```sh
./tests/run-tests.sh   # -> 52 passed, 0 failed
```

## Stubborn apps & system icons

- Some apps (notably **Google Drive**) rewrite their own status-item position when they relaunch, undoing a `hide`. Re-run `hide` — or add a `verify` cron so you find out immediately. Their hint sticks until the app decides otherwise.
- **Apple's Control Center modules** (Bluetooth, Sound, Now Playing, ...) belong to the user, full stop. `pin` and `hide` **refuse** `com.apple.*` domains (exit 2), and `verify` treats your Control Center choices as ground truth — it works identically whatever you picked for Display/Sound/Now Playing, and only reports an informational capacity estimate. If the strip is tight, *you* can choose "Show When Active" for modules in System Settings → Control Center; the tool will never do it for you. If a module is toggled on but never draws, its status-item record is orphaned — flip its checkbox off and on in System Settings to force recreation.

## Caveats

- Positions are *hints*: exact pixel spots drift as icons come and go, but relative order — and which side of the divider an icon is on — persists, including across reboots.
- The owning app must relaunch for a new position to apply. `menubar-guard` does this for you (`--no-restart` to opt out). Apps on the `SKIP_RESTART` list in the script (default: Claude desktop) are never killed.
- Apple's own icons (`com.apple.*`, Control Center modules) are system-managed and deliberately untouched.
- Requires Ice for the drawer behavior; without Ice, `pin` still works and `hide` warns.

## Requirements

macOS 13+, `bash` (stock 3.2 works), [Ice](https://github.com/jordanbaird/Ice) recommended. No dependencies.

## Keywords

`macos` · `menu-bar` · `status-bar` · `notch` · `NSStatusItem` · `Ice` · `menu-bar-manager` · `disappearing-icons` · `cli`

## License

[MIT](LICENSE) © 2026 Joshua Shay Kricheli
