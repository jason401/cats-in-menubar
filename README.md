# Cats in Menubar

A native macOS menu bar playground for two or three tiny cats. They nap, groom, walk, occasionally chase one another, and play with a ball in the space between menus and status icons.

## Run

Requires macOS 14 or later and Apple's Command Line Tools. No package dependencies or API keys.

Double-click **Build Cats in Menubar.command**, or run:

```sh
zsh tools/build_app.sh
open "build/Cats in Menubar.app"
```

The cat menu bar icon opens settings. Grant **Accessibility** access to **Cats in Menubar** in System Settings → Privacy & Security → Accessibility. The app stays hidden until it can read a usable menu layout. Use **Show safe space** to check detected free regions, then disable it for normal use.

- Two or three cats; pause/hide; quiet time; bring out a ball.
- Primary display only in this first version.
- Cats and toys stay within connected free intervals, with 8 pt of clearance around occupied regions.
- If an occupied region expands over a cat, the cat disappears immediately after detection, then reappears in available space. It never deliberately traverses an occupied interval.
- Overlay clicks pass through to the menu bar.
- No screen capture, screen-recording permission, network requests, AI services, or downloaded artwork. Accessibility traversal reads roles, positions, sizes, visibility and child structure, not menu text.
- Preferences live in the app's own UserDefaults domain, `local.catsinmenubar`.

## Current limitations

This is an early prototype, not a guarantee of zero overlap. Layout polling runs every 0.4 seconds; a newly appearing item can overlap a cat before detection. App switches hide the overlay while layout is refreshed. Stale or unreadable layouts hide all cats. Some third-party status items may not expose complete Accessibility information; live coverage must be verified for the user's menu bar. No public single API supplies an authoritative map of every menu bar item.

Automatic menu bar hiding is treated conservatively: if the reserved menu bar region is absent, cats hide. Full-screen spaces, notch layouts, menu bar managers, and external-display changes need live compatibility testing. All cats currently share one ball; exact non-overlap between cats is not enforced. macOS Reduce Motion and launch at login are follow-up work.

The default build uses an ad-hoc development signature. Rebuilding can invalidate Accessibility approval; remove/re-add the app if needed. For a stable grant, provide a persistent signing identity:

```sh
CATS_SIGNING_IDENTITY="Your Signing Identity" zsh tools/build_app.sh
```

Existing AI Face / AI Illuminati identities, apps and data are never modified or reused automatically. The app bundle is standalone; it does not execute source files from this checkout.

## Verify

```sh
zsh tools/test.sh
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --diagnostics
```

The first command builds and checks interval subtraction, obstacle changes, disconnected regions, hidden states, quiet time and ball bounds through 30,000 reproducible simulation steps. It also renders `build/previews/cats.png`. Diagnostics reads the live menu geometry without requesting permission and reports whether it is usable.

## Layout

- `app/macos/Habitat.swift`: interval geometry and behavior simulation.
- `app/macos/CatDrawing.swift`: original procedural pixel art and overlay drawing.
- `app/macos/MenuBarMonitor.swift`: background Accessibility layout scan.
- `app/macos/App.swift`: app lifecycle, transparent panel, settings and menu.
- `app/macos/Verification.swift`: reproducible simulation checks and artwork preview.
- `tools/`: build and verification scripts.
