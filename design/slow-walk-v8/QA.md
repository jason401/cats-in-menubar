# Slow walk, four separate paw tracks

Superseded for the adopted walk by `design/native-walk16/README.md`: user provided a16-phase reference and approved native2x/128cells. No8-frame candidate from this directory was installed.

User correction: both forelegs AND both hindlegs move incoherently. The walk must be a slow walk. This supersedes prior diagonal-pair instructions.

## Baseline review

Inspected all eight original frames with enlarged crops of all four limb positions (`build/previews/slow-walk-v8/original-four-legs.png`). The near pale foreleg remains a largely straight supporting leg throughout; the near pale hindleg stays bent/lifted across the sampled cycle instead of completing a planted stance. The darker far limbs have discontinuous or occluded positions. A silhouette-change score cannot establish foot identity or a correct support cycle.

## Target, not measured output

The colored guide and `foot-tracks.json` specify a deliberately slow four-beat walk: LH → LF → RH → RF, 75% stance, 25% swing. One cycle 1.6 seconds; eight frames at 0.2 seconds each; 72 source pixels (9.6 pt adult) travel per cycle. These are authored animation parameters, not a claim that every real cat uses those exact durations. During stance, each foot moves -9 source px per frame in body coordinates, yielding no world-space slip at the corresponding 6 pt/s adult speed. During swing, it moves forward with low lift. Three feet support during each mid-swing; contact boundaries have four. No flying phase or diagonal-pair trot.

Acceptance requires checking the ACTUAL four illustrated paws, unchanged limb lengths/body proportions and last→first continuity; an ideal coordinate chart by itself does not validate an image. Missing/occluded feet must not be silently reassigned to another limb.

Primary reference for lateral-sequence cat walking: Smith et al. (1998), https://journals.physiology.org/doi/10.1152/jn.1998.79.4.1702 .

No generated v8 artwork has yet been approved or applied.
