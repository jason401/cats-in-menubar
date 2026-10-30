# Cats in Menubar

Native macOS app in Swift/AppKit/SwiftUI, built with Command Line Tools; no third-party dependencies.

- Read README.md and HANDOFF.md before changing behavior.
- Cat artwork: read `design/ART_GUIDE.md` before drawing, generating or importing any cat images, and update it when the art changes. Art lives in `app/macos/Resources/Cats/sheets/`; `zsh tools/test.sh` checks it and renders `build/previews/`.
- Answer the user in Korean; keep technical names in English.
- Preserve bundle ID `local.catsinmenubar` and preferences.
- Do not change sibling AI Face / AI Illuminati projects, installed apps, identities or data.
- Keep menu text and screen contents private. Only read Accessibility geometry and structure.
- The optional scroll reverser (Settings → Scroll, off by default) changes scroll event deltas in an event tap and reads nothing else from them. It pauses while Scroll Reverser itself runs. Keep `THIRD_PARTY_NOTICES.md` (Apache-2.0 attribution) when changing it.
- Never invent free space. While a layout is briefly unreadable, keep the last good one (user's choice, 2026-10-28) instead of hiding cats.
- Cats walk, play and are dragged only inside a connected free interval. If space is taken over a cat, it stays visible and dashes to the nearest free spot within about a second.
- Build: `zsh tools/build_app.sh`. Verify: `zsh tools/test.sh`.
- Build outputs and generated preview images belong in ignored `build/`.
- Public repository. Commit and push tested work to `origin main`. Installed apps follow `origin/stable` (same scheme as AI Illuminati, user's choice 2026-10-29): publish only tested, complete commits with `git push origin main:stable` (fast-forward only; never rewind or force-push stable).
- The installed app is `/Applications/Cats in Menubar.app`. It checks stable 60 s after launch and every 3 h, and installs only when the user clicks Update Now: it tests and builds in `~/Library/Application Support/Cats in Menubar/source`, then `tools/install_app.py` swaps the app and rolls back unless the new app confirms startup. Development builds in `build/` never update themselves; `open "build/Cats in Menubar.app" --args --install-self` installs one explicitly. Only one copy runs at a time (same bundle ID), so quit the installed app before running a development build.
