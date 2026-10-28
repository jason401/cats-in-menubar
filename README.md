# Cats in Menubar

A native macOS menu bar playground for two or three tiny cats. They nap, loaf, stretch, groom, walk, sometimes run or hunt an imaginary bug, chase one another, and play with a ball in the space between menus and status icons.

## Run

Requires macOS 14 or later and Apple's Command Line Tools. No package dependencies or API keys.

Create the dedicated local signing identity once, then build:

```sh
zsh tools/setup_signing.sh
```

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
- Overlay clicks pass through to the menu bar, except directly over a cat: cats can be picked up and dragged within their own free space.
- No screen capture, screen-recording permission, network requests, AI services, or downloaded artwork. Accessibility traversal reads roles, positions, sizes, visibility and child structure, not menu text.
- Preferences live in the app's own UserDefaults domain, `local.catsinmenubar`.

## Current limitations

This is an early prototype, not a guarantee of zero overlap. Layout polling runs every 0.4 seconds; a newly appearing item can overlap a cat before detection. App switches hide the overlay while layout is refreshed. Stale or unreadable layouts hide all cats. Some third-party status items may not expose complete Accessibility information; live coverage must be verified for the user's menu bar. No public single API supplies an authoritative map of every menu bar item.

Automatic menu bar hiding is treated conservatively: if the reserved menu bar region is absent, cats hide. Full-screen spaces, notch layouts, menu bar managers, and external-display changes need live compatibility testing. All cats currently share one ball; exact non-overlap between cats is not enforced. macOS Reduce Motion and launch at login are follow-up work.

Builds require the persistent **Cats in Menubar Local Signing** identity created by `tools/setup_signing.sh`. The build stops if it is missing; there is no ad-hoc fallback. Signing is done in a temporary candidate bundle before the final bundle is replaced.

When migrating from the first ad-hoc prototype, the existing permission can appear enabled while the new app reports no access. Re-register the new app in System Settings → Privacy & Security → **Device Control and Data Access** (called **Accessibility** on earlier macOS versions). Toggle the app off/on, or remove and add the current `build/Cats in Menubar.app` if macOS still retains the previous signature. Future builds keep the same app identity.

The setup script only creates this app's own non-exportable local key and code-signing certificate; trust is limited to code signing, and only Apple's codesign tool is preauthorized. It does not alter TLS trust or other apps' keys. A custom persistent identity can be supplied with `CATS_SIGNING_IDENTITY`.

Existing AI Face / AI Illuminati identities, apps and data are never modified or reused automatically. The app bundle is standalone; it does not execute source files from this checkout.

## Verify

```sh
zsh tools/test.sh
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --diagnostics
```

The first command builds and checks interval subtraction, obstacle changes, disconnected regions, hidden states, quiet time and ball bounds through 30,000 reproducible simulation steps. It also renders `build/previews/cats.png`. Diagnostics reads the live menu geometry without requesting permission and reports whether it is usable.

## Debugging

Status changes are appended to `~/Library/Logs/CatsInMenubar.log`. `open -n "build/Cats in Menubar.app" --args --probe` logs menu bar roles and frames (no text).

## Layout

- `app/macos/Habitat.swift`: interval geometry and behavior simulation.
- `app/macos/SpriteAtlas.swift`: approved PNG sprite frames, animation timing and cached color variants.
- `app/macos/CatDrawing.swift`: overlay drawing and cached cat thumbnails.
- `app/macos/TowerIcon.swift`: cat-tower menu bar and app icon.
- `app/macos/MenuBarMonitor.swift`: background Accessibility layout scan.
- `app/macos/App.swift`: app lifecycle, transparent panel, settings and menu.
- `app/macos/Probe.swift`: development probe of menu bar structure.
- `app/macos/Verification.swift`: reproducible simulation checks and artwork preview.
- `tools/`: build and verification scripts.


## Cat collection

The app renders the approved `design/cat-animation-concept-v1.png` as actual sprites, copied into the standalone app as `Resources/CatAtlas.png`. Orange uses the original image pixels. The other seven coats are cached color variants of the same silhouettes: black, white, silver tabby, cream tabby, tuxedo, calico and Siamese. There are six walk and six run poses plus sit, loaf, sleep, stretch and grooming poses. Held cats currently reuse the seated illustration with a small swing; a dedicated dangling sprite is future artwork.

Three sizes preserve the original head/body proportions: Kitten 64%, Young 82%, Adult 100%. The adult's tallest standing pose is 24 pt. Movement, dragging, chasing destinations and tower exits respect each cat's scaled collision radius.

By default each launch selects distinct random coats, random sizes and random positions within detected free space. Each launch starts with cats outside the tower; Pause is still respected. In Settings → Cats → Your cats, select each cat's coat and size. Editing a cat enables **Keep my cats** so the chosen appearances survive relaunch. Turn it off for random appearances next launch; **Shuffle cats** randomizes immediately and resumes random launches. Positions are always freshly randomized, including for a saved lineup. Existing count control still allows 1–3 cats (default 3).

`tools/test.sh` renders `build/previews/lineup.png` with all 24 coat/size combinations. Tests cover random coverage, persistent appearance encoding, size-specific dragging, mixed-size chasing and changing obstacles. The approved atlas must load for tests to pass.
