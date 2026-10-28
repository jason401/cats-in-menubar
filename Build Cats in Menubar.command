#!/bin/zsh
set -eu
cd "${0:A:h}"
zsh tools/build_app.sh
open "build/Cats in Menubar.app"
