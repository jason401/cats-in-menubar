#!/bin/zsh
set -eu
cd "${0:A:h}/.."
zsh tools/build_app.sh
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --self-test
mkdir -p build/previews
"build/Cats in Menubar.app/Contents/MacOS/CatsInMenubar" --render-preview "$PWD/build/previews/cats.png"
