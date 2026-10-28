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
