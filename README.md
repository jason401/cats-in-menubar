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

Each of the eight cats has its own PNG sprite sheet in `app/macos/Resources/Cats/`: orange, black, white, silver tabby, cream tabby, tuxedo, calico and Siamese. No coat is generated with runtime color filters or rectangular masks. Orange keeps the approved source artwork; the other sheets were made with the built-in ImageGen tool using the approved artwork as reference. `design/asset-prompts-v2.json` records the generation prompts.

The held artwork in `design/held-cats-v1.png` has three dedicated poses per cat: neutral, body trailing left, body trailing right. The build prepares a separate folder per cat with 21 cropped images: six walk, six run, six lifestyle and three held poses. `tools/prepare_assets.swift` detects each cat's alpha bounds, ignores stray transparent pixels, and writes per-cat anchor metadata. Images and metadata are bundled inside the standalone app; source sheets are not read at runtime.

Three sizes preserve their artwork's proportions: Kitten 64%, Young 82%, Adult 100%. Movement speed and acceleration scale with size: normal walking is 9.6 / 12.3 / 15 pt/s. Stride length scales as well, so a small cat does not cycle its feet faster than an adult at its normal walking speed. Walk frames share a foot baseline and a head landmark rather than the tail-inclusive crop center.

Click and hold a cat to use its dangling sprite. Drag right and its body trails left; drag left and it trails right. A damped spring settles the sway when the mouse stops. Release returns to grooming. Held cats stay inside their connected safe interval. The original native vector drawing remains a development fallback, but tests require all eight independent artwork sets and all 24 held sprites to be bundled.

By default each launch selects distinct random coats, random sizes and random positions in detected free space. In Settings → Cats → Your cats, select each coat and size. Editing enables **Keep my cats** to save the lineup. Turn it off for random appearances next launch; **Shuffle cats** randomizes immediately. Positions are always randomized, including for a saved lineup. Count remains 1–3 (default 3).

`tools/test.sh` builds and runs the simulation, renders the full collection and held poses, and creates a size/speed comparison GIF in `build/previews/`. The source artwork is still a small set of illustrated key poses, not a fully hand-authored in-between animation. Pose-to-pose artwork consistency can be refined further after visual feedback.

### Current v3 artwork preview

All coat selections currently display the new orange animation set; selected coat and size preferences are preserved. The build imports 18 source sheets (62 poses) from `app/macos/Resources/Cats/v3/orange/`. To enable a future coat, add a complete set with the same filenames and pose order in `v3/<coat>/` and rebuild; missing sets fall back to orange. See `design/ART_GUIDE.md` section 7 for the current pipeline. Earlier 21-frame artwork remains archived in the source tree.

The full 0–61 animation sequence and transition map is in `design/ANIMATION_MAP.md`. Walk/run artwork was redrawn (originals/prompts in `design/gait-redraw-v4/`). All sizes now share time-based walk10/run16/creep5 fps; only physical travel speed and acceleration vary with size. This replaces the earlier distance-based clock description.

Motion v5 normalizes walk/run by authored eye landmarks instead of tail-inclusive width, preserving head size when running. Stretch now returns to standing. Source assets, previous images and prompts: `design/motion-v5/`. See ART_GUIDE section10 for registration requirements.
