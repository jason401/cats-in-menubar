# Draft inspection — 2026-10-28

18 PNG sheets, 62 visible poses, matching the requested pose counts. All files decode as RGBA with transparent pixels. Original generated PNGs copied unchanged. No app source or runtime resource was edited for this artwork task.

These are artwork drafts, NOT drop-in animation atlases. All 18 sheets were visually inspected, but no animation playback or 24px rendering has been verified.

Before adoption:
- 01-stand has a visible diffuse halo around the cat despite transparent outer pixels; regenerate without halo before use.
- Walk poses have limited hind-leg variation; verify an actual alternating gait rather than assuming eight poses form a smooth walk.
- Run changes tail angle, body height and compression; registration and loop continuity need review.
- Idle moves the tail substantially; check whether the amplitude is too large at menu-bar scale.
- Standing/seated/loaf/sleep transitions include endpoint-like poses, rather than strictly interior in-between frames. Review the sequence against the existing endpoint art.
- Stalk remains relatively high; compare with the requested low crouch.
- Wiggle changes rear shape and markings; check for apparent body morphing.
- Held-kick provides dangling posture and two hind-leg positions, but no separate left/right torso sway drawings. Sway remains a later art/implementation decision.
- Sheets differ in resolution and scale. Equal-width slicing, baseline, head size, stripe consistency and margins are not production-normalized. Some dimensions do not divide evenly by the requested grid.

Orange is the first review set as specified in ../art-request-v3.md. Other coats remain pending approval of this character and motion. Prompts are preserved in prompts.json for later revisions.
