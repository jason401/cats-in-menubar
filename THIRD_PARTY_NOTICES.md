# Third-party notices

## Scroll Reverser

The scroll direction feature (`app/macos/ScrollDirection.swift`) is a derivative work of Scroll Reverser:
its event tap, scroll source identification and reversing rule follow Scroll Reverser's `MouseTap`,
`ScrollSource` and `SourceTable` (https://github.com/pilotmoon/Scroll-Reverser).

Changes: rewritten in Swift for Cats in Menubar; the event tap runs on its own thread; settings are shown
in this app's Settings window. No Scroll Reverser source files or icons are included.

Scroll Reverser's NOTICE file:

> Scroll Reverser
> Copyright 2011 Nicholas Moore
>
> This software is released under the the Apache 2.0 License (see LICENSE).
>
> The name "Scroll Reverser" and the application icon are
> trademarks and may not be used by derivatve works (except as required to
> describe the origin of the work).

Licensed under the Apache License, Version 2.0. A copy is in `LICENSES/Apache-2.0.txt`
and at http://www.apache.org/licenses/LICENSE-2.0 .

## Hidden Bar

The menu bar tidy feature (Settings → Menu Bar) uses code from Hidden Bar
(https://github.com/dwarvesf/hidden):

- `app/macos/MenuBarVisibilityShim.h` and `.m` are Hidden Bar's `HBNativeVisibilityShim`, the bridge to
  macOS 27's menu bar visibility restriction. Changes: renamed, always built in.
- `app/macos/MenuBarItemPresser.swift` is Hidden Bar's `PaletteItemPresser`, which presses a menu bar
  icon through Accessibility. Changes: renamed, frame lookup inlined.
- In `app/macos/MenuBarTidy.swift`, `CaptureActivity` and `SystemClock` are based on Hidden Bar's
  `CaptureActivityMonitor` and `SystemMenuBarClock` (polled instead of listened to, trimmed). The
  show-press-rehide flow follows `PaletteRevealSession`, and the handling of the clock, the microphone
  and camera indicator and apps run from outside /Applications follows `NativeVisibilityEngine`;
  that code was written anew for Cats in Menubar.

The original copyright lines are kept at the top of the files taken from Hidden Bar.

Copyright (c) 2019 Dwarves Foundation
Copyright (c) 2026 Console Labs

Licensed under the MIT License. A copy is in `LICENSES/MIT-HiddenBar.txt`.
