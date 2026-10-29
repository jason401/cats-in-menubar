# Native 2x walk, 16 phases

The active master is `app/macos/Resources/Cats/sheets/orange.png` (816×1088, 8×16 cells of 102×68) with `orange.json`. There are 70 occupied cells and 58 transparent cells. Existing action IDs remain stable; walk phases are `[4...11, 62...69]`.

## Artwork provenance

- `user-walk-reference.png`, `user-legmap-reference.png`: exact user attachments, 4×4 / 16 phases.
- `rejected-redraw.png`: built-in ImageGen redraw; rejected because it altered the foot sequence.
- `cleanup-source.png`: adopted built-in ImageGen seam repair of the user's original 16 poses. It repairs sliced limb connections while retaining the reference sequence.
- `cleanup-prompt.txt`, `redraw-prompt.txt`: full prompts.
- `walk-2x.png`: final 4×4, 408×272 walk source at actual 2x resolution.
- `registration.json`: measured input eye landmarks; all poses use one shared scale to retain anatomy. Generation returned a larger intermediate image; native size is established by the authoring import, not by falsely claiming the tool returned 102×68 cells.

The other 54 poses were copied from the previous baked adult-2x sheet; they were not redrawn in this pass. The legacy full-size source files are retained as authoring history and are not the active runtime master.

## Reproduce

```
xcrun swift -module-cache-path build/module-cache tools/import_walk16.swift design/native-walk16/cleanup-source.png <previous adult-2x sheet.png> app/macos/Resources/Cats/sheets/orange.png design/native-walk16/walk-2x.png
zsh tools/test.sh
```

The importer is for authoring, not a build dependency. Normal builds read the already registered 2x master directly. Adult slow walk: 6 pt/s, acceleration 12 pt/s², 9.6 pt cycle, 16 phases / 1.6 seconds. All sizes scale speed and stride equally. Run, creep and the other behaviors retain their speeds.

## Verification and limits

`tools/test.sh`: 336,749 assertions, 30,000 changing-obstacle steps, all standard renders. Tests verify 128-cell packing, 70 populated / 58 empty cells, 16 distinct source pictures, complete phase ordering and wrap for all three sizes, native 1x/2x sizes, eye registration/scale, physical-time behavior and notch crossings. Slower walking exposed an entrance-facing bug in the notch tunnel; direction is now selected from the actual entrance and a turn is allowed before crossing. A deterministic regression covers facing away at the entrance.

Inspected the exact baked images in `build/previews/native-walk16/review.html`, including front/hind crops and 16→1 stepping. This is not a proof of pixel-perfect ground locking or of perfect anatomy in every other behavior. At 1x, small phase changes can quantize to the same leg pixels.

The app was restarted with the same identity and existing Accessibility access; its fresh log reports usable free spaces and an open notch tunnel. The live desktop overlay was not captured, to keep other menu/screen contents private. No manual live drag test in this pass.

The behavior-document generators understand the new metadata and current walk. A candidate DOCX was generated in ignored `build/previews/`, but bundled LibreOffice omitted Korean text in its renders, including a host retry. The original `design/cat-behaviors.docx` was preserved and no unverified replacement is delivered.
