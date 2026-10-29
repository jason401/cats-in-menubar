# Cats in Menubar

Native macOS app in Swift/AppKit/SwiftUI, built with Command Line Tools; no third-party dependencies.

- Read README.md and HANDOFF.md before changing behavior.
- Cat artwork: read `design/ART_GUIDE.md` before drawing, generating or importing any cat images, and update it when the art changes. Art lives in `app/macos/Resources/Cats/sheets/`; `zsh tools/test.sh` checks it and renders `build/previews/`.
- Answer the user in Korean; keep technical names in English.
- Preserve bundle ID `local.catsinmenubar` and preferences.
- Do not change sibling AI Face / AI Illuminati projects, installed apps, identities or data.
- Keep menu text and screen contents private. Only read Accessibility geometry and structure.
- Never invent free space. While a layout is briefly unreadable, keep the last good one (user's choice, 2026-10-28) instead of hiding cats.
- Cats walk, play and are dragged only inside a connected free interval. If space is taken over a cat, it stays visible and dashes to the nearest free spot within about a second.
- Build: `zsh tools/build_app.sh`. Verify: `zsh tools/test.sh`.
- Build outputs and generated preview images belong in ignored `build/`.
- This is a development bundle. Do not add automatic installation, login registration, updates or public releases without user scope.
