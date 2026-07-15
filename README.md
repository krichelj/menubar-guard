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
