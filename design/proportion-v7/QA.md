# Proportion / connectivity review — incomplete, candidates NOT approved

No generated candidate in this directory has been applied to the app. The original artwork remains active.

## Inputs and acceptance

Read `cat-behaviors.docx` in full (OOXML text), its existing motion/special connection diagrams, `ART_GUIDE.md`, and the actual `SpriteAtlas.frameIndex`, `transition`, and `HabitatView.drawCat` implementation.

Required: preserve character identity, head/body/limb/tail proportions in all 62 poses; fix the long-looking walk limbs; animate both front and both rear limbs; examine each adjacent phase, 11→4 wrap, and the actual connected behavior paths. A successful build is not an animation-quality pass.

## Original baseline

`build/previews/proportion-before/measurements.json` records bounds, solid-pixel area, lowest-row contacts, and adjacent silhouette changes. Walk changes at the current source placement: 14.06, 24.80, 10.64, 25.62, 12.09, 11.99, 16.50, 19.57 percent. Uneven changes are a diagnostic warning, not a sufficient gait metric.

The review script renders these complete paths without crossfade masking: walk loop; run loop; standing→sitting→loaf→sleep and reverse; seated→groom→seated; standing→stretch→standing; seated→yawn→seated; crouch→creep→wiggle→pounce→stand→sit; crouch→bat→crouch; held; turn. Actual app turn additionally mirrors and translates the body's center, which the raw-source viewer does not simulate.

Known anatomy/connection defects remain: walk foreleg movement and compact-leg proportions; head/body changes between standing, sitting, grooming and yawning; crouch/creep height; sitting bat artwork despite a crouch pre-swipe; nonidentical repeated hub artwork.

## Built-in ImageGen attempts

1. `rejected-atlas-01.png`: complete atlas edit, original 62-pose atlas plus Claude walk sample as references. Shorter/consistent anatomy, all five hubs, matching endpoints and a four-beat walk were requested. Output is 1536×1024, not the requested 3072×2048. It has alpha (the displayed brown preview is not an opaque background); alpha/registration still need checking. Foreleg motion and seated batting remain inadequate. Rejected.
2. `walk-attempt-02.png`: isolated 8-phase walk request, explicit foreleg contact/pass/lift phases. Foreground foreleg still too repetitive. Rejected.
3. `walk-attempt-03.png`: standing master plus explicit 8-phase colored foot/contact diagram. Did not follow the specified foreground forepaw phases consistently. Rejected.
4. `atlas-attempt-02.png`: whole-atlas targeted correction of hubs, low creeping and batting, same seated anatomy for grooming/yawn, and repeated stand endpoints. Bat still sits; overall source placement/size continuity is not approved. Rejected.
5. `walk-attempt-04.png`: made the contact diagram the primary edit target to increase pose adherence. Foreground foreleg motion still does not meet the contact diagram. Rejected.
6. `single-pose-attempt-05.png`: isolated foreground-forepaw lift succeeds locally, but changes face angle/character rendering; unsuitable as an interchangeable cycle frame. Rejected.

The original hand-drawn illustration style must not be replaced by a cutout/rig prototype just to get mechanically correct foot positions.

## Reproduce the review

Use the bundled Node runtime with its `NODE_PATH`, then:

```
node tools/audit_sprite_sheet.cjs 'build/Cats in Menubar.app/Contents/Resources/Cats/orange/sheet.png' build/previews/proportion-before
```

Open `review.html` in the generated folder. Space pauses, arrows step, slider selects speed. The small view is source scaled to 1x; it does not replace inspection of the actual renderer's ground fix, transitions, clipping or physical travel. The still strips include the wrap frame for inspection; the HTML loop does not duplicate that frame.

## Build-input work

`prepare_assets.swift` now optionally reads a registered `Resources/Cats/sheets/<coat>.png` directly. It validates the 8×8 / 384×256 layout and reserved empty cells, and creates the existing metadata and six menu-bar sheets. No per-pose crop/fit/rescale occurs. The old strip pipeline remains for existing assets. A fixture using the original runtime atlas produced pixel-identical full and all six small sheets. No new source atlas has been installed.

## Status

The art request is **not complete**. Repeated generation failed the precise pose and identity requirements. Do not report the candidates as a corrected, natural or seamless animation, and do not silently deploy them.

Code validation: direct-atlas fixture outputs are pixel-identical to the previous full sheet and all six menu-bar variants. `tools/test.sh` passed 335,395 assertions and 30,000 changing-obstacle simulation steps, plus standard preview renders. These checks do not approve any new art. Initial sandbox execution could not see the signing identity; the standard check succeeded in the host execution environment without changing keys or permissions.
