# Cats in Menubar — handoff (2026-10-29)

Current state only. Earlier iterations (procedural cats, 21-frame and 62-frame strip art, 64-cell sheets, rejected redraws) were removed from the tree on 2026-10-29 and live in git history.

## Scope

Native macOS 14+ development app. Standalone bundle at `build/Cats in Menubar.app`; nothing is installed. Private repository https://github.com/jason401/cats-in-menubar (commit and push to `main` after passing tests). 1–3 cats live in empty menu bar space, never deliberately enter menu or icon regions, react when space is taken, and mostly rest or play rather than move constantly.

## Artwork

- One authored sheet per coat: `app/macos/Resources/Cats/sheets/<coat>.png|json`, 8 × 16 cells of 102 × 68 px (adult at 2x), 70 poses, 58 empty cells. Orange, white and black exist; the other five coats fall back to orange.
- The json `animations` table names each behavior's cells; `SpriteAtlas.Pose` looks them up by name. No frame numbers in code.
- `tools/prepare_assets.swift` slices the sheet, measures each pose (ground lift, left/right extent) into `sheet.json`, and writes 1x/2x × three-size menu bar copies. It never rescales a single pose.
- Orange is GPT's style-unified redraw (stand cell kept); white and black are recolors of it. Black's stray amber specks (dark leg lines recolored as eye color) were cleaned before install.
- Rules, layout table and import steps: `design/ART_GUIDE.md`.

## Behavior

- `Colony.choose` picks the next action; `advance` runs physics in 30 Hz substeps, independent of draw rate. Walk 6 pt/s, accel 12 pt/s², 9.6 pt per 16-frame cycle; run 29 pt per cycle; creep 4.8 pt. Size (0.64/0.82/1.0) scales speed and stride together.
- Rest poses connect through their link art (stand ↔ sit ↔ loaf ↔ sleep); turns hold still and slide the body center across the mirrored pose; other pose changes blend over 0.15 s.
- Notch tunnel: on a notched display the free space splits in two. About a quarter of walks next to the notch walk in, hurry while hidden (120 pt/s scaled) and walk out the other side; a cat facing away at the entrance turns first. Dragging can carry a cat across; released behind the notch it walks out the nearer side. `tunnelEnds()` only opens when free space touches both sides, so no space is invented.
- Ball, chase, call home (tower icon), held cat with damped sway, escape to the nearest free spot within about a second when covered.
- `design/cat-behaviors.docx`: behaviors, durations, probabilities and connection graphs (Korean). Its frame numbers are the old 62-frame IDs; `tools/behavior_doc/*.py` translate them through the pose table. The docx itself was last generated before the sheet changes and the 6 pt/s walk.

## System

- macOS 27 status icons belong to `com.apple.MenuBarAgent`; AX frames on other displays are mapped back to the primary display. Real bar height comes from `screen.frame.maxY - visibleFrame.maxY` (30 pt).
- Unreliable scans keep the last good layout; app switches do not hide cats.
- Power levels (`Power.swift`): full/eco/low by smoothed CPU (eco above 45 %, low above 75 %, back below 30 %), Low Power Mode or heat. Animation 30/15/8 fps, scan 1/2/4 s. Measured about 2–5 % of one core.
- Dedicated signing identity **Cats in Menubar Local Signing** (`tools/setup_signing.sh`) keeps the Accessibility grant across rebuilds. Status log: `~/Library/Logs/CatsInMenubar.log`.

## Verification

`zsh tools/test.sh` builds, runs about 337,000 assertions and 30,000 changing-obstacle steps, and renders previews to `build/previews/` (`lineup.png`, `scenario.png`, `motion.gif`, settings and dashboard). Art checks include named-pose coverage, contiguous walk cells, empty reserved cells, eye size and horizontal anchor, and drawn head height within a 2 pt bob across walk and run.

## Open items

- Not yet watched live: the new orange/white/black art, turn frame 31 (drawn about 11 pt further left), pounce art slightly wider than the collision radius, black's contrast on a dark menu bar.
- Silver, cream, tuxedo, calico and Siamese sheets are missing. The coat list is fixed at 8 in `prepare_assets.swift`, Settings and `CatAppearance`; dozens of designs need it data-driven.
- Regenerate `design/cat-behaviors.docx` for the current walk speed and sheet.
- Primary display only; Reduce Motion not implemented; zero transient overlap cannot be promised (sampled detection).
