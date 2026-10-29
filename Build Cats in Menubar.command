#!/bin/zsh
# Builds this checkout and installs it to /Applications. The installed copy then follows the stable branch.
set -eu
cd "${0:A:h}"
zsh tools/build_app.sh
# Only one copy runs at a time; the new build replaces the installed one.
osascript -e 'quit app id "local.catsinmenubar"' 2>/dev/null || true
sleep 1
open "build/Cats in Menubar.app" --args --install-self
