#!/bin/zsh
set -eu
cd "${0:A:h}/.."
zsh tools/build_app.sh
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --self-test
mkdir -p build/previews
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-preview "$PWD/build/previews/cats.png"
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-panels "$PWD/build/previews"

"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-lineup "$PWD/build/previews/lineup.png"

"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-motion "$PWD/build/previews/motion.gif"

"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-held "$PWD/build/previews/held.png"
