# Cats in Menubar — 2026-10-28

## Scope

First native development app, macOS 14+. Standalone bundle at `build/Cats in Menubar.app`; no installed app or existing project was modified. Private GitHub repository: https://github.com/jason401/cats-in-menubar .

User intent: 2–3 cats occupy empty menu bar space, never deliberately enter menu/icon regions, react to newly occupied space, and spend time sleeping or playing with a ball rather than moving constantly.

## Implemented

- AppKit transparent, nonactivating, click-through panel and SwiftUI settings.
- Original code-drawn pixel cats with three coats; sitting, sleeping, grooming, walking, play and occasional chase.
- Interval subtraction of Accessibility menu-item bounds, 8 pt padding, full cat-body margin, notch exclusion, conservative hide on invalid/stale results.
- Layout refresh every 0.4 s on a utility queue, app/Space/display changes hide immediately and invalidate pending results.
- Separate connected intervals; an invalidated position is hidden for 0.45 s before reappearing safely. Ball is removed if its interval disappears.
- Cat count, quiet time, pause, ball action, debug safe-space visualization; preferences in own UserDefaults domain.
- No permissions requested automatically. Settings explains and links Accessibility grant; cats remain hidden without access.
- Private origin, local main branch. No auto-updater, installer, launch-at-login, screen capture or runtime network.

## Verification

- Swift optimized build and strict bundle signature verification passed.
- 146,383 assertions across 30,000 deterministic simulation steps passed.
- Procedural artwork rendered and visually inspected at actual size and enlarged.
- App launched; settings screenshot and Accessibility UI tree inspected. Layout is readable and controls visible.
- Live diagnostics: Accessibility was false, correctly yielded an unreadable layout and no cats. End-to-end live menu scanning and obstacle avoidance remain unverified until the user grants the new app access.
- A restricted shell cannot initialize the macOS GUI for preview rendering; use a normal GUI terminal or approved host execution. The simulation check itself works in the restricted shell.

## Known limits / next verification

- This is sampled detection, not an OS-enforced reservation; zero transient overlap cannot be promised.
- AX coverage for third-party menu bar apps and menu-bar managers needs live testing. The system-bar attribute has a standard-menu fallback. An AX app timeout hides cats conservatively.
- Primary display only. Full-screen, auto-hide and notch Macs need live testing. Cats can share/overlap one another. Reduce Motion is not yet implemented.
- Dedicated persistent **Cats in Menubar Local Signing** identity is now installed; builds require it with no ad-hoc fallback. Older ad-hoc grants need one-time re-registration. Other apps' identities remain untouched.
- App artwork is a first procedural prototype, not finished commissioned sprites.


## First live report: cats missing after permission grant

System Settings showed the app enabled in **Device Control and Data Access** (macOS 27 naming), while the running app still reported no Accessibility access. The first bundle was rebuilt under an ad-hoc signature while the previous process was running, so its designated requirement changed with the executable hash. This is the likely permission mismatch; restart alone did not restore access.

Fixed build identity with a dedicated app-specific local certificate. Verified designated requirement now uses the stable identifier and certificate hash rather than the executable cdhash. Candidate builds are signed and verified before replacing the output bundle. Added geometry-only blocked-scan details to settings for the next live check. Optimized build, full simulation checks and artwork rendering passed again. New signed app launched. User asked to re-register the existing permission for the new identity; live menu geometry validation is pending that step.

## Second live check: permission fixed, macOS 27 menu bar changes

- Stale Accessibility record reset with `tccutil reset Accessibility local.catsinmenubar`; after the user re-enabled it the app reported `Accessibility: true`.
- macOS 27 moved system status icons to `com.apple.MenuBarAgent` (Control Center / SystemUIServer return no extras). Now accepted as the system bar.
- With several displays AX reports menu items on whichever display shows the bar. Frames are mapped back to the primary display: app menus by left edge, status items by right edge.
- The real bar is 30 pt (`screen.frame.maxY - visibleFrame.maxY`); `NSStatusBar.thickness` still says 22.
- Only `.app` bundles are scanned (WebKit/XPC helpers were blocking every scan). A timeout only blocks if that process owned status items in the previous scan.
- Status is appended to `~/Library/Logs/CatsInMenubar.log`. `open -n "build/Cats in Menubar.app" --args --probe` logs AX roles/frames (no titles) of menu bars for debugging.
- Live log after fix: `1 safe area(s) · 840 pt available`. User confirmed cats are visible on the menu bar (2026-10-28).

## Look and motion pass (2026-10-28)

- Fast left-right shaking came from playing: the target spot depended on the facing direction, so the cat flipped every frame and kicked the ball every frame (922 rapid flips in the simulation). Now the side comes from the ball position, batting has a 0.9-2.3 s cooldown, cats brake, pause 0.6 s before turning, and ease in/out. Self-test asserts no direction flip within 0.5 s.
- Cats redrawn as simple antialiased vector silhouettes (orange, black, white) with one soft outline; leg motion follows distance walked.
- Menu bar icon and app icon are an original cat tower (`TowerIcon.swift`); the build renders `AppIcon.icns`.

## Poses and dragging (2026-10-28)

- Cats are drawn from a small skeleton (shoulder, hip, jointed legs, tail curve); head radius 4.2 pt for slimmer proportions.
- New behaviors: running (gallop with stretching spine and streaming tail), stalking (crouch, creep, butt wiggle) then pouncing, stretching (front then back, often after sleep), loafing. Self-test requires each to occur.
- Drag: overlay stays click-through except while the pointer is over a cat (`updateMouse` each tick). A held cat dangles, swings with drag speed and is clamped to its own free interval; it is put down when the layout changes or the overlay hides. User confirmed live dragging works.
- `build/previews/cats.png` shows every pose, the run cycle and actual size.

## Panel, settings, system stats, no more hiding (2026-10-28)

- Status item click opens a popover dashboard (CPU with history, memory, storage, battery/power, network, plus Ball/Pause/Settings/Quit). Readings come from `SystemMonitor.swift` (mach host statistics, sysctl, IOKit power sources, getifaddrs, SystemConfiguration). Matches RunCat Neo on the user's Mac.
- Settings window with sidebar: General (open at login via SMAppService, CPU % in menu bar), Cats, Behavior (activity, livelier with CPU, quiet time and night schedule), System Monitor, Permissions, About. Preferences use `Pref` keys and `@AppStorage`; `@State` is avoided because the Command Line Tools lack the SwiftUI macro plugin.
- Menu owner uses `menuBarOwningApplication`, so clicking another status app no longer hides cats (not yet confirmed live).
- User asked to stop hiding cats on uncertainty: app switches keep cats, unreliable scans keep the last good lanes, and a covered cat escapes to the nearest free spot (self-test bounds it to 1.5 s).
- `tools/test.sh` also renders `build/previews/dashboard.png` and `settings-*.png`.

## Gallop rework from RunCat reference (2026-10-28)

- Studied the user's screen recording frame by frame. Natural feel comes from body pitch (nose-up push off, nose-down landing), strong squash/stretch, tail follow-through (straight back when stretched, curled over the back when gathered), held key poses and a steadier head, not from frame count.
- `run(cycle:)` now does all of these; stride 20 pt. Cat envelope widened to 38 pt (`Habitat.catRadius = 19`) for the long stretch.

## Cat tower, shared ball, unified settings (2026-10-28)

- "Call home" (panel and Settings → Cats): cats run to the free-space edge nearest the tower icon, then hop in one at a time (shrinking arc, drawn unclipped). The menu bar icon shows 1-3 cats at home. "Let out" hops them back out 0.7 s apart. State persists in `catsHome`.
- Ball button drops the ball at a random spot (preferring a free space that has cats); every cat in that space plays, with staggered reactions.
- Held cats now trail behind the drag like a pendulum.
- Settings window rebuilt to match AI Face / AI Illuminati: `NSTabViewController` toolbar tabs (General, Cats, Monitor), 334 x 460, compact cards (`SettingsCard/Row/Switch/Segments/Menu`, copied pattern, sibling projects untouched).
- Panel position verified from the log: top edge sits just under the menu bar.
- User confirmed live: calling home works.

## CPU use (2026-10-28)

- Measured ~12 % of one core. Profile: menu scan on the main thread (bundle lookups for every process, AXIsProcessTrusted via tccd every scan), full-width redraw at 30 fps, network name lookup each sample.
- Now: trust cached 3 s, per-process candidate cache, scan timer 1 s (notifications still trigger immediate scans), dirty-rect redraws around cats and ball, 10 fps while every cat is sleeping/sitting/loafing, network name cached per interface. Measured ~2-3 %, ~5 % while cats run.

## Power levels (2026-10-28)

- User asked to invert the CPU reaction: plenty of headroom means lively cats; a busy Mac means the app backs off.
- `Power.swift`: `PowerGovernor` smooths CPU and uses gaps between thresholds (full → eco above 45 %, → low above 75 %; back to full below 30 %). macOS Low Power Mode or serious heat forces low; fair heat caps at eco.
- Per level: animation 30/15/8 fps (resting 10/5/2 fps), layout scan 1/2/4 s, system sampling at least 0/2/5 s, cat mood 0/-0.15/-0.35 (+0.08 when nearly idle). Low power has no zoomies (self-test).
- Setting: Cats → Behavior → "Save power" (key `adaptivePower`, replaces `reactToCPU`), with the current level shown; panel summary shows it too.
- Disk free space read every 30 s and battery every 10 s (free-space query was the top cost).
- Live: switched to Eco at 45 % system CPU. App measured 1-9 % of one core in Eco depending on cat activity; drawing moving cats is now the main cost.


## Approved PNG sprites and cat collection (2026-10-28, Codex)

User selected the generated concept PNG and requested eight coats, three sizes, random startup appearance/position and per-cat settings. An initial code-drawn approximation enlarged the head and was rejected by the user as looking different. That approximation was removed: the app now renders the approved PNG itself through `SpriteAtlas.swift`. Orange is unchanged source pixels; other coats are cached recolors. Existing native drawing remains only as a development fallback; the self-test requires the actual bundled atlas.

- 18 orange source frames: 6 walk, 6 run, 6 lifestyle poses. Pose crops retain one source scale and shared floor baselines. Held cats reuse sit with swing for now, not a new dangling illustration. Stretch uses the supplied front stretch.
- Eight coats and three uniformly scaled sizes (64/82/100%). No extra head enlargement on kittens. Adult max standing height 24 pt. Masks for tuxedo/calico/Siamese are simple image-relative recolor regions, not separately hand-painted frame sets.
- Startup chooses distinct random coats, random sizes, and safe random positions. A saved lineup changes only appearances, never starting locations. Startup no longer restores cats hidden in the tower; Pause remains preserved.
- Settings → Cats → Your cats has live thumbnails and per-slot color/size menus. Editing saves the lineup and enables Keep my cats. Turning that off restores random appearance on next launch; Shuffle cats does so immediately. Inactive saved slots survive a temporary count reduction.
- Individual scaled collision radii are used for dragging, walking, escapes, tower exits and chasing. A mixed-size chasing target bug found by simulation was fixed by clamping the target to the chasing cat's own bounds.
- Verified optimized build, strict signing, 140,705 assertions over 30,000 simulation steps, artwork and settings renders. All 24 coat/size combinations and persistence round trips tested. New app restarted without new permissions; live overlay screenshot shows three original-PNG cats with unchanged proportions. Generated settings render checked; live control clicking was interrupted by changing UI focus, so do not claim every menu was manually exercised.
- `build/previews/lineup.png` is the final collection preview; concept and comparison images are in `design/`. No sibling project, signing key or privacy grant was changed.
