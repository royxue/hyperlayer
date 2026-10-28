# Hyperlayer Agent Guide

macOS menu bar app (Swift, no dependencies) that turns Caps Lock into a Hyper key with a navigation layer.

## Architecture

Two layers, no device seizure, no event re-injection:

1. **`KeyRemapper`** sets `UserKeyMapping` (Caps Lock `0x700000039` -> F18 `0x70000006D`) on each keyboard `IOHIDServiceClient` via `IOHIDEventSystemClient`. It merges with any existing mappings, and re-applies on device connect (`IOServiceAddMatchingNotification`), on wake, and on a 5 s timer. `stop()` removes only our entry.
2. **`HyperKey`** installs one `CGEventTap` (session, head insert). F18 down/up toggles hyper state; while held, `NavigationLayer` keys are rewritten in place and other keys get Cmd+Ctrl+Opt+Shift.

| File | Purpose |
|------|---------|
| `main.swift` | Entry point, single-instance check, `log()` |
| `AppDelegate.swift` | Menu bar UI (rebuilt on each open), preferences, Accessibility polling, login item (`SMAppService`), signal handling |
| `KeyRemapper.swift` | Per-keyboard Caps Lock -> F18 mapping and keyboard list |
| `HyperKey.swift` | Event tap and hyper state machine, tap-for-Escape |
| `NavigationLayer.swift` | Layer key table (grouped, with labels) and Caps Lock toggle. Single source for both the event tap and the overlay |
| `KeyMapOverlay.swift` | "Key Mapping…" floating panel (SwiftUI in a borderless `NSPanel`), closes on Esc or losing focus |

## Patterns

- C callbacks (event tap, IOKit notifications) are top-level functions that get their object back through the `userInfo`/`refcon` pointer. Don't use capturing closures there.
- Never block the main thread (e.g. waiting for Accessibility). Use timers.
- Only public IOKit headers are used. `IOHIDEventSystemClientRegisterDeviceMatchingCallback` is private, which is why device changes come from `IOServiceAddMatchingNotification` instead.
- If the system disables the event tap, re-enable it and reset hyper state, since the F18 key-up may have been missed.
- Keep the layer rewrite stripping `maskAlphaShift`, otherwise arrows behave as shifted when Caps Lock is on.

## Build

```bash
swift build          # debug
make install         # release build, ad-hoc sign, reset Accessibility grant, install, launch
make uninstall
```

The app icon is generated: `Resources/mark-source.png` (light mark on dark, drawn by the author) is turned into a mask and placed on a dark tile by `scripts/make-icon.swift`. The same script writes the menu bar template images (`Resources/MenuBarIcon*.png`), with the mark thickened so its thin outlines survive at 18pt. Run `make icon` after changing the source, and commit everything it writes to `Resources/`.

`make install` resets the Accessibility grant because each ad-hoc build has a new code hash, and macOS keeps showing the old grant as enabled even though it no longer applies.

## Release

Push a tag: `git tag v0.X.Y && git push origin v0.X.Y`. `.github/workflows/release.yml` builds a universal binary (`make universal`), bundles it with the version stamped from the tag (`make zip BIN=... VERSION=...`), and publishes `Hyperlayer.zip` as a GitHub release. The website's download buttons point at `releases/latest/download/Hyperlayer.zip`, so keep that asset name.

The app is ad-hoc signed and not notarized, so users must use "Open Anyway" on first launch.

## Website

`docs/index.html` is the landing page, served by GitHub Pages from `docs/` on `main` at royxue.github.io/hyperlayer. It is a single static file with no build step. Its keyboard demo mirrors `NavigationLayer.groups`; update the `LAYER` table in the page when the layer changes. `docs/assets/mark.png` comes from `Resources/Mark.png` (written by `make icon`).

## Debugging

- Run the binary directly to see logs on stderr.
- Check the current mapping: `hidutil property --get UserKeyMapping` (global) or `hidutil property --matching '{"Product":"<name>"}' --get UserKeyMapping` (per keyboard).
- Secure Input (password fields, some terminals) blocks all event taps. `IsSecureEventInputEnabled()` drives the menu warning.
