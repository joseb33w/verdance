# VERDANCE — Mobile Game-Feel / UX Review (re-review after prior 4-P1 fix wave)

**VERDICT: FAIL (0 P0, 1 P1 must-fix)** — touch, HUD-on-phone, rotation relayout and toast transience are now genuinely solid (all four prior P1s verified FIXED live); one camera defect remains in the must-fix class.

Method: drove the real web export (`/workspace/repo/out` served locally, identical to preview) in software-GL Chromium, **touch-only for every verified control** (CDP `dispatchTouchEvent`; no keyboard), portrait **390×844** and landscape **860×400**, including an **in-session rotation both ways with no reload**. State assertions via `gogiGetPlayer()`/`gogiVerdance()` deltas; ~30 screenshots in `/workspace/verify/feel/`. Framerate not judged (SwiftShader).

---

## ❗ P1 — A 4 m enemy at melee range still walls most of the portrait frame; the near-camera fade never fires

**Symptom (rendered):** fighting a `fade_stalker` at melee (`nearest_enemy_d` 1.68), the monster's torso+legs fill ~⅔ of the portrait frame with the hero completely hidden behind it (`e1-melee-frame.png`); in a second, independent encounter its leg walls the left ~40 % of the frame (`w8-beacon-orbit.png`). It reads exactly like the "monster popup" this build already tries to prevent. Transient (bodies move), not on every attack — hence P1, not P0.
**Root cause:** the mitigation exists but its distance test is measured to the wrong point. `main.gd _fade_near_camera_enemies()` → `enemy.gd set_camera_near()` hides the mesh when the camera is within `CAM_FADE_NEAR = 1.6` of **`e.global_position` — the enemy's ORIGIN, at its FEET on the ground**. The camera rides at ~1.5–2 m height, so even with the mesh pressed against the lens the camera-to-feet distance is ≥ ~1.6 m — the fade practically never triggers for a 4 m-tall model (`MAX_ENEMY_H` cap). A 4 m body 2–5 m from the lens legally fills the frame.
**Fix direction:** measure against the body, not the feet — e.g. distance to `e.global_position + Vector3(0, 0.5*model_height, 0)`, and/or scale the threshold with height (`fade when cam_dist < max(1.6, 0.45 * model_height)`). Alternatively (or additionally) drop `MAX_ENEMY_H` to ~2.5–3 m. Keep it a fade/hide — do NOT turn this into any modal treatment.

---

## ⚠️ Polish (non-blocking)

1. **Max pitch-up turns the hero into a wall.** Dragging the camera up (allowed to +34°) drives the SpringArm into the terrain behind, collapsing the camera to ~1.5–3 m; the hero then fills ~80 % of the frame and you can't actually see the sky you pitched up for (`p6-pitch-max.png`, `p9-back-portrait.png`, `l1-landscape-hud.png`). The 1.35 m avatar-hide guard doesn't trigger at that range. Consider raising the orbit pivot as pitch rises, or fading the avatar below ~2.5 m camera distance.
2. **Near-camera vehicle Label3D still blows up/clips.** The perspective-scaled DRIVE label of a close vehicle renders oversized and clipped at the screen edge ("DR…" `w4-dismounted.png`, left-edge DRIVE in `w3-driving.png`). Prior-report item, still present. `fixed_size` or a <4 m fade would fix it (the HUD "USE > Drive X" prompt already covers that range).
3. **Second button column intrudes into the joystick half (portrait).** POTION/SHEATHE/DISMOUNT start at UI x≈281 (< the 360 movement half-line); a move-drag started on them is eaten by the button. Bottom-left remains fully usable, so polish only. (Unchanged from prior review.)
4. **No feedback during the post-mode-select load gap.** After tapping FREE ROAM the screen is pure black (only the grant toast) until terrain streams in (`p3-hud-idle.png`); several seconds even on device-class hardware would show nothing. A tiny "loading…" line or keeping the title art up until first frame would help.
5. **The virtual joystick has no visual affordance** — left-half drag works fine (verified) but nothing on the HUD hints at it after the title-screen hint line is gone. A faint thumb ring at touch origin is the usual treatment.

---

## ✅ Verified good (live, touch-driven evidence)

- **All 4 prior P1s are fixed in the shipped build:**
  - **Landscape short-side rescale works** — after in-session rotation to 860×400 the UI viewport re-derives to 1548×720 (`dismount_rect` telemetry), stats/buttons readable (~15 px CSS, buttons ~128×52 CSS ≥ 44 px), nothing overlaps or overflows (`l1`, `l2`); title screen equally clean at landscape (`c3-landscape-title.png`). Rotation back to portrait relayouts again, no reload (`p9`).
  - **Toasts are full-width centred** — long grant toast word-wraps dead-centre, no edge clipping, no STABLE collision (`p2-toast-early.png`).
  - **USE-to-board works via touch** — "USE > Drive Roadster" label up, touch-tap on USE boarded first try; player visibly seated; contextual **DISMOUNT appears** and touch-dismount works; joystick drove the car 7.2 u (`w2`, `w3`, `w4`). (drive3's one "failure" was my probe standing out of range — the prompt had correctly cleared.)
  - **USE prompt no longer overlaps SHEATHE** — now at 58 % height, clear of both button columns in every capture (`v1`, `e1`, `w7`).
- **Region names are transient toasts, never pinned:** "The Forest -- discovered!", "The Spire City -- discovered!", and the re-entry variant "Entering The Spire City" each faded within ~3–6 s; zero region text in any later idle frame (`v1`→`v2`, `w9`→`w10`). Matches code (`verdance.gd` — no persistent region label by design).
- **Touch joystick moves the player:** clean post-spawn measurements — 6.05 u portrait, 10.15 u landscape, `on_floor` true (no keyboard).
- **Touch drag-look orbits:** right-half drag changed `cam_yaw` 0 → 1.329 rad; pitch clamped (−74°…+34°) — full down-drag gives a bird's-eye that still shows hero+world and recovers (`p5`), never a locked floor/sky stare.
- **Buttons fire via touch:** JUMP (`on_floor`→false, portrait AND landscape), ATTACK (enemy hp 120→58 over touch taps at melee), USE (boarded), DISMOUNT (exited), STABLE (panel opens/closes, readable, `p8-stable.png`).
- **Camera doesn't clip through walls:** pressed against a skyscraper and orbited — no through-mesh frames (`w5`, `w6`); SpringArm collapse guard confirmed live (hero auto-hidden when the arm collapsed at the beacon plinth, restored afterwards — `e2` vs `v2`).
- **Damage is non-modal:** hp 100→28 across real fights; `dialog_open` false throughout; zero banners/dialogs in all ~30 captures; feedback = hurt sfx + 0.15 s camera kick (screen flash intentionally disabled — acceptable).
- **No debug/developer text on screen:** HUD is exactly the Lv/HP/XP/Gold/Wpn/Inv block (Inv self-truncates), buttons, compass/toast; all `GOGI_*` telemetry is console-only.
- **Campaign objective line fits:** "> Speak with Ranger Elda at the outpost [W 16m]" full-width centred under the stats block, clear of STABLE (`c2-campaign-idle.png`) — persistent by design (quest tracker), updates with distance.
- **Thumb reach:** ATTACK/USE/JUMP/POTION/SHEATHE/DISMOUNT all in the bottom-right thumb arc at both aspects; tap-to-play and title buttons big and centred (`p1-title.png`).

## Could not verify (sandbox limits)

- True simultaneous two-thumb multi-touch (move + look at once) — touches driven sequentially via CDP; code paths are index-separated (`move_idx`/`look_idx`) and look correct.
- Real-device notch/safe-area — STABLE sits ~7 CSS px from the top edge and bottom buttons ~10 px from the bottom; worth a safe-area pass on hardware.
- Real GPU framerate/feel (SwiftShader ~1–5 fps; composition/behaviour only was judged).
- CONTINUE flow (save restore) — exercised by QA's pass, not re-driven here.
