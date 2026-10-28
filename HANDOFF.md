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
- Ad-hoc development signature: rebuilt executable can lose its Accessibility grant. Persistent dedicated signing identity is follow-up work; do not silently reuse other apps' identities.
- App artwork is a first procedural prototype, not finished commissioned sprites.
