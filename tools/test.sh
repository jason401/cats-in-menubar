#!/bin/zsh
# Builds the app and checks that it runs without errors (--self-test: logic only, no windows on screen).
# The updater runs it with --skip-build on the candidate it has just built.
# --previews also renders the preview pictures into build/previews and drives the real panels on screen
# (--test-panel), for checking the look and the hover panel by hand; it is never part of an update.
set -eu
cd "${0:A:h}/.."
build=1 previews=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) build=0 ;;
    --previews) previews=1 ;;
    *) echo "Usage: tools/test.sh [--skip-build] [--previews]" >&2; exit 2 ;;
  esac
done
(( build )) && zsh tools/build_app.sh
APP="build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar"
"$APP" --self-test
(( previews )) || exit 0
"$APP" --test-panel
mkdir -p build/previews
"$APP" --render-preview "$PWD/build/previews/cats.png"
"$APP" --render-panels "$PWD/build/previews"
"$APP" --render-lineup "$PWD/build/previews/lineup.png"
"$APP" --render-motion "$PWD/build/previews/motion.gif"
"$APP" --render-held "$PWD/build/previews/held.png"
"$APP" --render-scenario "$PWD/build/previews/scenario.png"
"$APP" --render-wheel "$PWD/build/previews/wheel.png"
