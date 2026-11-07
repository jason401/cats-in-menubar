#!/bin/zsh
set -eu
cd "${0:A:h}/.."
case "${1:-}" in
  "") zsh tools/build_app.sh ;;
  --skip-build) ;; # The updater has just built this candidate.
  *) echo "Usage: tools/test.sh [--skip-build]" >&2; exit 2 ;;
esac
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --self-test
mkdir -p build/previews
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-preview "$PWD/build/previews/cats.png"
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-panels "$PWD/build/previews"

"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-lineup "$PWD/build/previews/lineup.png"

"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-motion "$PWD/build/previews/motion.gif"

"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-held "$PWD/build/previews/held.png"
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-scenario "$PWD/build/previews/scenario.png"
