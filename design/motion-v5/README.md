# Motion v5

- `walk.png`: rig-guided ImageGen redraw. `walk-motion-guide.png` shows the ordered four-leg stance/swing phases used as pose reference.
- `stretch.png`: stand → lower → front stretch → rise → stand; no raised hind-leg poses.
- `walk-before.png`, `stretch-before.png`: preserved source images from before this change.
- `registration.json`: reviewed eye landmarks (cell-local source pixels), per-frame scale normalizing eye height to 13 px, walk/run eye height above ground, and stretch supporting-foot root.
- `prompts.json`: built-in ImageGen requests and selected rig-guided prompt.

The app continues using 62 frame IDs. Run art was not regenerated in this pass; its scale and anchoring were corrected. Artwork still requires visual review; neither the motion guide nor numerical checks establish perfect animal biomechanics.
