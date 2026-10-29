# Cats in Menubar — 2026-10-28

## Current: native 2x master, 16-frame slow walk, 128 cells

**Update:** the app master is now GPT's style-unified `walk/orange.png` (ART_GUIDE 17): same layout/metadata, cell 0 pixel-identical, 69 cells redrawn. The eye test now checks drawn head height (after ground lift) within a 2 pt bob instead of cell placement. Not yet seen live: turn frame 31 sits ~11 pt further left; pounce art is a bit wider than the collision radius.

This supersedes the earlier 64-cell / 8-frame walk descriptions below. User supplied `cat_walk_sheet_4x4.png` and `cat_walk_legmap_4x4.png`, selected a slow 16-phase walk, requested 128-cell capacity, and approved native menu-bar resolution. Active source is now `app/macos/Resources/Cats/sheets/orange.png` + `orange.json`: 8×16 cells, each 102×68 px (2x), total816×1088. 70 cells occupied, 58 transparent. Walk was first appended as `[4...11,62...69]`; the sheet has since been reordered so the walk is cells 4–19 and every later pose moved up 8. Code no longer has frame numbers: `animations` in `orange.json` names each pose's cells and `SpriteAtlas.Pose` looks them up. The behavior-doc generators keep the old 62-frame numbers as labels and translate them through that table. The other54 poses are pixel-identical to the previous adult-2x sheet (verified all54).

The initial built-in ImageGen redraw changed the foot order and was rejected. Adopted artwork is a seam-repair edit of the user's exact16 poses (`design/native-walk16/cleanup-source.png`, full prompt/provenance and measured landmarks there). `tools/import_walk16.swift` measures the eyes and uses one common scale to register the native master. The generation tool returned a larger intermediate; do not claim it directly output102×68 cells. The active authoring/runtime master itself is native2x, with no larger runtime sheet. Builds create the three sizes at1x/2x. Renderer uses metadata `pixelsPerPoint`, avoiding an accidental size change when source resolution changes.

Adult walking6pt/s, acceleration12pt/s², stride9.6pt, 16phases/1.6seconds; size scales both speed and stride. A slower-walk regression exposed cats already at a notch entrance facing the wrong way. Entry now derives direction from its side and turns before crossing; a deterministic test covers it. Slow crossing bound24s; hidden middle still120pt/s. Picking test excludes the crossing cat itself while allowing a different visible cat at the same x.

Full `tools/test.sh` passed336,749 assertions, 30,000 changing-obstacle steps and all standard renders. Verifies actual source pictures, all16 distinct/order/wrap across sizes, native eye scale/anchor,128cells/58empty and power/tunnel behavior. Inspected baked1x/2x, fore/hind crops and16→1 in `build/previews/native-walk16/review.html`. `walk.gif` is16frames×100ms and shows exact screen cells at integer zoom plus actual1x. These checks are not proof of perfect anatomy or pixel-perfect ground locking in all behaviors; broader non-walk artwork corrections remain separate.

App restarted from the same bundle with existing Accessibility access. Fresh log: pid46071, Accessibility true; usable free areas and notch tunnel open. No live desktop screenshot (menu/screen privacy), no manual drag observation. No sibling app, key, permission or preferences changed.

Behavior-document generators now read native metadata/baked images and use the new timing/IDs. Original `design/cat-behaviors.docx` remains untouched: candidate generated in ignored build/, but three bundled-renderer checks omitted Korean body text (two font choices and a host retry), so no unverified DOCX was delivered. Do not call its existing content current. Native-walk README records this limitation.

## Latest review: proportions and connected poses — NOT completed

User requested corrected proportions across all 62 poses, especially natural short-legged walking, and repeated review against `design/cat-behaviors.docx` connections. Full document text and connection diagrams were read and compared with actual runtime routing. Two full atlas attempts, three walk-only attempts and one isolated forepaw pose were generated with built-in ImageGen. All were rejected for inadequate foreleg pose adherence, hub/crouch-to-bat discontinuities or character drift. **No new art was installed.** See `design/proportion-v7/QA.md`; do not report this art request as finished.

Added `tools/audit_sprite_sheet.cjs`: measurements, ordered connection strips and a source/1x HTML player with pause/step controls. Outputs: `build/previews/proportion-before/` and `proportion-attempt-02/`. The player is a source-art inspection aid, not the actual AppKit renderer. Source/strip/browser review confirmed existing defects; it did not approve a new animation.

Added optional single registered atlas input at `app/macos/Resources/Cats/sheets/<coat>.png` in `prepare_assets.swift`. No source atlas is installed there yet, so existing strip behavior is retained. A fixture importing the existing built atlas produced pixel-identical full and all six menu-bar sheets. Full `tools/test.sh` passed: 335,395 assertions, 30,000 changing-obstacle steps and all standard renders. This is code/regression validation, not proof that the artwork issue is fixed. Existing app identity and preferences retained; no GUI restart or manual drag test in this pass.

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


## Independent artwork, scaled movement, restored pickup (2026-10-28, Codex)

Supersedes the previous recoloring/sitting-placeholder implementation. User reported the calico's blocky pattern, kitten frame speed, and awkward walk transitions; then explicitly requested independent cat images and restoring dangling/sway artwork when dragging.

- Replaced runtime recoloring with eight independent PNG sheets in `app/macos/Resources/Cats/`. Orange is the approved original. The other seven were generated separately with the built-in ImageGen tool. The calico now has actual organic coat patches in the artwork; no rectangular pixel masks remain.
- Added a dedicated held atlas with 8 identities × 3 poses (neutral, trail left, trail right). Corrected the black row so it has no tuxedo bib. Very low-alpha red/yellow pixels in source previews are alpha 1–2/255, not opaque painted artifacts; alpha component detection excludes them from sprite bounds.
- `tools/prepare_assets.swift` runs during build, crops alpha components into eight independent 21-frame folders, and writes head/foot metadata. Bundle owns all runtime images. No Python/image libraries are required to build.
- Sprite origins use a head landmark instead of the changing tail-inclusive bounding-box center. Walking feet use the same ground plane. Moving speeds and acceleration scale by 0.64/0.82/1.0 (walk 9.6/12.3/15 pt/s); the distance-based frame clock uses the matching stride scale, so kittens no longer have a faster normal walk cycle.
- `Cat.heldLean` and `heldLeanVelocity` provide damped spring response to drag speed. Pickup uses frames 18–20, never sitting. Right drag → left-trailing pose, left drag → right-trailing pose. Mouse grab offset attaches to the held pose's head; release uses existing grooming behavior. Existing safe-space clamping is preserved.
- Verified optimized build, all 168 bundled sprite files, 140,809 assertions, random/mixed-size simulation, size-specific travel distances, equal normal walk cadence at all sizes, directional sway and settling/release for every coat. Collection/pose/settings images and motion GIF rendered and inspected.
- Restarted new app with existing permissions intact and saw PNG cats in the live overlay. CUA mouse targeting of the borderless click-through panel returned AXError.notImplemented, so actual pointer dragging was not automated successfully; only drag/event wiring and state transitions were exercised in tests. Do not claim a successful manual end-to-end drag observation.
- Further art work: six illustrated walk/run key poses can still benefit from hand-authored in-betweens. Do not promise that automatic frame sequencing alone produces a perfect gait.

- Final timing check: physics now advances with 30 Hz substeps independently of drawing frequency. Equal real-time travel verified at 8/15/30 fps; low-power idle updates no longer discard elapsed time.

## Stopped poses and pose blending (2026-10-28, Claude)

- Choppiness diagnosis: the 21 sprite frames are separate illustrations, not drawn as continuous cycles (tail, head height and body length jump between walk frames) and there are no transition or standing frames. Art request for GPT: `design/art-request-v3.md` (27 frames first priority, 62 total, orange first). Code below uses only the current art; do not assume the new frames exist.
- Moving cats that stop (turn pause, arrival, waiting at the tower) used to freeze on a mid-stride walk frame. They now use `SpriteAtlas.standFrame` (walk frame 4, legs under the body) until a real standing frame exists.
- Pose changes between frame groups (walk, run, held, each still pose) and direction flips blend: the previous pose fades out on top of the new one over 0.15 s, at full frame rate even while resting.
- Frozen crouch by the ball: a ball resting at the end of the free space was out of reach (cat clamped by its radius, bat range 14 pt), so the cat held run frame 10 for the whole play time. Now it bats from the closest reachable spot, gives up after 2.5 s without moving or batting, sits (frame 12) while watching after a bat and crouches (frame 10) only just before batting. Self-test covers the edge case.

## Shrink-once sprites and art guide (2026-10-28, Claude)

- Sprites were scaled from ~216 x 143 px to ~29 x 19 px on every draw (the user's two displays are 1x). `SpriteAtlas.shrunk` now halves step by step to the exact pixel size once per frame/size and caches it; menu bar drawing snaps to the pixel grid. Previews at other scales and the tower hop still draw the original. Visual quality is about the same; per-frame drawing cost dropped to roughly a quarter (Full mode drawing now costs less than Eco did; menu scanning is the largest cost).
- `design/ART_GUIDE.md` (replaces `art-request-v3.md`) explains the current pipeline and frame table, the real on-screen size and readability rules, what is wrong with the current frames, the delivery format for new art (one 256 px-cell strip per animation, ground line 232 px, `Resources/Cats/v3/orange/<animation>.png`, orange first), the frame list (27 first priority, 62 total) and the code work after delivery. AGENTS.md points to it.
- `tools/onion_strip.swift` draws a strip side by side, an onion skin and actual-size frames, to check new animations.

## V3 orange-first integration (2026-10-28)

User authorized applying the staged artwork after Claude's rendering changes. All coat preferences now resolve to the new orange set until a complete v3 set exists for that coat. No preference migration or bundle identity change. Build reads 18 source sheets, normalizes to a shared 256px canvas/232px ground plane, strips stand halo and near-transparent specks, and bundles 62 frames plus resolved coat mapping. Runtime uses dedicated standing, eight-step distance-based walk/run, rest transition sequences, turning, grooming, stretching, stalking, pounce/bat and dangling kicks. Existing spring supplies held sway; shrink-once caching and short blends for other transitions remain. Original artwork and staging originals preserved. Source art still has imperfect gait/marking continuity; do not claim hand-authored seamless animation.

V3 verification: final `tools/test.sh` passed 152,274 assertions and 30,000 simulation steps; collection, held, pose, motion and settings previews rendered. `tools/onion_strip.swift` checks of normalized walk/run were rendered and inspected (still some source-art movement variation). All eight coat previews show orange, sizes preserved. CLI `--diagnostics` reports Accessibility false when invoked from the command runner; this is not evidence of the GUI app's live permission state. No permission reset was performed.
GUI restart confirmed: pid 9960 launched with Accessibility true and detected one safe area, 850 pt available. No new permission grant was needed. Live pointer dragging was not manually exercised in this pass.

## Gait redraw and size-independent clock

User corrected scope: redraw artwork rather than reorder existing frames. Built-in ImageGen produced new eight-frame walk and gallop sheets, with a second pass repairing static hind legs and clipped run framing. Selected originals/prompts in `design/gait-redraw-v4/`; imported at existing v3 filenames, preserving 0–61 numbering. Other 46 poses unchanged. Playback now reads `cat.phase` seconds, never gait/size: walk10, run16, creep5 fps. Physics speed/acceleration still size-scaled. Tests compare unrelated distances at identical times for all sizes and all three locomotion actions. `design/ANIMATION_MAP.md` documents all 62 frames, loops, rest transitions and missing dedicated connectors; a map does not guarantee that all artwork transitions are visually seamless.

V4 verification: `tools/test.sh` passed 152,754 assertions and 30,000 simulation steps. New normalized walk/run onion and actual-size checks inspected (`build/previews/v4-*-check.png`). Interactive 62-frame gallery and simultaneous three-size walk/run player at `build/previews/animation-map.html` (generator in ignored build folder). New gait drawings have better hind-leg variation and gallop phase separation, but residual anatomy/marking differences remain; do not claim a perfect seamless loop. App restarted after final build. No preference or permission reset.

## Motion registration and stretch return (v5)

Investigation found a contradictory walk prompt (grounded hind paw moved forward in body coordinates), independent width-fit scaling that shrank run heads, and an invented head anchor=.87*tail-inclusive width. User authorized correction. New rig-guided walk and front-stretch/return sheets are stored in `design/motion-v5/` with prompts and before images. Runtime source filenames/62 IDs unchanged. New `registration.json` records actual eye landmarks and normalization to13px eye height; walk/run eye height97px above ground is preserved. Stretch uses planted hind-paw root, not moving head. Authored poses get a384x256 transparent canvas so extended run poses are not shrunk to256px; unsupported legacy poses retain old normalization. Current orange markers belong to current source PNGs and must be updated with replacements. Habitat radius expanded21→24pt to cover the larger unshrunk run; free-space simulation is rechecked. Preview width now follows source pixel scale instead of squeezing every canvas to the same CSS width. Rectangular onion-strip checks supported. All size clocks unchanged10/16/5fps; speeds remain size-scaled.

V5 final verification: 152,406 assertions and 30,000 changing-obstacle steps passed, including pixel-level walk/run eye size and centroid regression checks. Rectangular onion/actual-size previews inspected. Rendered unrotated sprites have max horizontal extent19.94pt from the cat origin (within24pt collision margin). Main-component isolation removes detached solid specks inside crop bounds. HTML gallery has62 frames, physical-pixel sizing and a stretch-return button; JS syntax checked with system JavaScriptCore. App restarted with existing identity and privileges; preview HTML regenerated. No manual live pointer-drag test in this pass.

## Frame connectivity fixes without new art (2026-10-28, Claude)

- Review of v5 orange (62 frames, measured at runtime placement): walk front legs barely move, walk frame-to-frame silhouette change is uneven (13/24/10/25/11/11/16/19 %), walk feet dip up to 7 px below ground, run never touches ground, stand is ~5 % larger than walk, sit/groom/yawn differ in size, creep is higher than crouch, bat is a sitting pose, turn ended ~5 pt off the mirrored pose. Details and redraw direction: `design/ART_GUIDE.md` section 0 (hub poses, first/last frame equals hub, eye/head size reference).
- Code: locomotion frames advance by distance again with size-scaled strides (walk 12 pt, run 29 pt, creep 4.8 pt per cycle; same rhythm at every size's cruising speed). `SpriteAtlas.groundFix` puts the lowest paw on the 232 px ground line per frame (run and pounce as a group, held untouched). Turn: cat holds still for `Colony.turnTime` and the body center slides from the old pose to the mirrored new pose. Bat is a one-shot (58→59, 0.3 s), watching sits (26), pre-swipe crouch and stopped stalking use 46.
- `--render-scenario` / `build/previews/scenario.png`: real drawing path at 1x while walking, stopping, turning, walking back. Parts/cutout rig was considered and rejected by the user (would lose the illustration quality).

## Notch tunnel (2026-10-29, Claude)

- First run on a notched MacBook (built-in Liquid Retina XDR). The notch was already an obstacle, so the bar splits into two free spaces that cats could never cross.
- User chose a tunnel: about a quarter of walks next to the notch head to the lane edge, walk into the notch, hurry while fully hidden (120 pt/s scaled), and walk out on the other side. `Colony.tunnel` is the raw notch interval; `tunnelEnds()` only opens it when free space touches both sides (within the 8 pt padding), so no free space is invented. Drawing clips to lanes plus the gap between the two ends, so the cat disappears exactly at the notch edge.
- Dragging also goes through: `carryLane(for:)` joins the two sides through the notch for a held cat (hidden while behind it), and a layout refresh does not drop it there. Let go behind the notch, it walks out of the nearer side.
- A crossing cat cannot be picked up, keeps crossing if called home (then goes home), and escapes to the nearest free spot if the notch or far side disappears.
- Status/log shows `notch tunnel open`. Live log confirmed it open on this Mac. Self-test: 60,000 notched steps, crossings end on the other side within 12 s, closed-tunnel escape. Not yet watched live by the user.

## Behavior document (2026-10-29, Claude)

- `design/cat-behaviors.docx` (Korean, for the user): every behavior with start/end conditions, durations, speeds, frames and playback; next-behavior probability tables (also per activity/power setting); connection graphs (hub, fixed chains, interrupts, rest ladder, motion links); each frame group in high quality plus real app pixels at 2x and 1x.
- Numbers were copied from `Colony.choose`/`advance`, `SpriteAtlas.frameIndex`/`transition` and `HabitatView.drawCat` at a35c35a. Update the document when behavior changes.
- Regenerate (needs a Python venv with python-docx, pillow, matplotlib, numpy; not app dependencies): run `tools/behavior_doc/strips.py <orange frames> build/behavior-doc`, then `graphs.py` with the same arguments, then `make_doc.py build/behavior-doc design/cat-behaviors.docx`. Frames come from `build/Cats in Menubar.app/Contents/Resources/Cats/orange`.
- Checked through Quick Look only (Pages/Word automation was not authorized); final layout in Word not yet seen.

## 64-cell sprite sheets (2026-10-29, Claude)

- User direction: frames live in sprite sheets, and the menu bar uses low-resolution sheets made once at build time, not runtime shrinking; dozens of cat designs will be added later.
- `prepare_assets.swift` now writes, per artwork set, `sheet.png` (8 x 8 cells of 384 x 256, frames 0-61, cells 62-63 empty), `sheet-<1|2>x-<size>.png` (pre-shrunk with the same halving method, per screen density and CatSize) and `sheet.json` (cell size, head anchor 300, ground 232, per-frame `lift`, `left`, `right`). Per-frame PNGs and `metadata.json` are gone; ground fixes and body extents are measured at build time.
- `SpriteAtlas` crops cells from cached sheet images; the menu bar picks the variant from `backingScaleFactor` (>=1.5 → 2x) and cat size. `shrunk`, runtime extents and per-frame files were removed. Ground fixes are identical to before; scenario/lineup/pose renders match the previous build except rounding-level pixel differences.
- Tests: 8 x 8 layout, 62 filled / 2 empty cells, every variant's cell size equals the menu bar pixel size, 1x cells drawable. `tools/behavior_doc/` reads `sheet.png`. Live app relaunched with Accessibility intact; the live overlay itself was not visually inspected in this pass.
- Coat names are still a fixed list of 8 in `prepare_assets.swift`, Settings and `CatAppearance`; scaling to dozens of designs needs that list made data-driven.
