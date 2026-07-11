# VERDANCE — Mobile Game-Feel / UX Review

**VERDICT: FAIL (0 P0, 4 P1 must-fix)** — touch, camera and layout fundamentals are solid; four phone-UX defects must be fixed before this feels shippable on a phone.

Method: drove the real web export (local server mirroring the preview host, `/godot-assets/*` proxied) in software-GL Chromium at **portrait 400×860** and **landscape 860×400**, touch-first (CDP `dispatchTouchEvent` + touchscreen taps — no keyboard for any verified control), using the `gogiVerdance`/`gogiGetPlayer` state knobs plus 15 targeted screenshots (`/tmp/feel/*.png`).

---

## ❗ P1 — Landscape phones get a ~31%-scale, unreadable HUD

**Symptom (rendered at 860×400):** the game fills the screen and `_relayout_ui` keeps every button on-screen and unoverlapped — but the entire UI renders at **0.3125× design scale**. Measured from the live export (`dismount_rect` vpW/vpH): UI viewport = **2752×1280**. Stats text (22 UI px) → **6.9 CSS px** — unreadable (confirmed in `l3-hud.png`). Button labels (28 UI px) → ~9 px; buttons 72×41 CSS px (below the ~44 px touch-target minimum). Title-screen mode buttons → 144×26 CSS px, the hint line ~5 px (`l1-title.png`).
**Root cause:** portrait-only base (720×1280, `canvas_items` + `expand` in project.godot) — in landscape the scale factor collapses to `min(860/720, 400/1280)=0.3125`. `main.gd _relayout_ui()` repositions rects but nothing rescales content for a landscape aspect.
**Fix direction:** on resize, set `get_window().content_scale_factor` (or `content_scale_size`) so the SHORT edge maps to ~720 design px regardless of orientation — i.e. in landscape scale by `min(w,h)/720` instead of letting `expand` shrink everything; or derive font sizes/button sizes from `min(vp.x, vp.y)` in `_relayout_ui` + title screen.

## ❗ P1 — Toasts are left-anchored at screen centre: long ones clip off the right edge and run behind STABLE

**Symptom:** in portrait the boot toast renders as "Free Roam: the Four Reaches" and is **cut at the screen edge** (rest of the message never visible), passing behind the STABLE button (`p10-grant-toast.png`, `b1-after-use.png`). "The Spire City -- discovered!" ends exactly at the edge (`p3-toast.png`). Every toast starts at x = screen centre and grows rightward instead of being centred.
**Root cause:** `verdance.gd _build_overlay_ui()` — `_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)` is applied while the label's size is 0, and a Label grows rightward from its rect position; `horizontal_alignment = CENTER` only aligns within that rect.
**Fix direction:** anchor the label full-width (`PRESET_TOP_WIDE`, offsets for the y) and keep `HORIZONTAL_ALIGNMENT_CENTER`, or set `grow_horizontal = Control.GROW_DIRECTION_BOTH`. **Same defect in `_compass`** (the campaign objective line, `PRESET_CENTER_TOP`, offset_top 132) — that one is *persistent* HUD in campaign mode, so long objective lines will sit half off-screen (inferred from identical geometry; campaign not driven in this pass).
**Transience itself is correct:** the toast faded fully within ~6 s and nothing stays pinned (`p3b-toast-gone.png`, `p9-idle.png` — no region label, no stale text). Do NOT pin it as part of the fix.

## ❗ P1 — USE-to-board a vehicle intermittently does nothing

**Symptom:** standing at the Roadster with the "USE ▸ Drive Roadster" prompt and floating DRIVE label showing, firing USE (same `try_use()` path as the on-screen button) boarded the car in ~1 s on 3 attempts, but **no-opped on 2 attempts even after 10–15 s of polling** (one on a fresh session, one on a repeat board after a previous mount/exit). No state change, no feedback — to a player the button feels dead until they mash it again. (Logs: `landscape.log` BOARDED:false after 15 s; `board2.log` attempt C false after a prior board/exit cycle; successes in `board.log`/`board2.log` A+B.)
**Likely root cause:** `vehicle.gd use()` silently swallows the press while `_state` is `S_ENTERING/S_EXITING`, and `enter()` requires exactly `S_IDLE` — a lingering exit choreography (or a vehicle stuck out of IDLE after streaming) eats the tap.
**Fix direction:** queue/retry the board request when the guard rejects it (or return the state to `S_IDLE` promptly on exit completion), and give audible/visual feedback when USE is swallowed. Boarding otherwise verified good: player visibly seated, contextual **DISMOUNT button appears in the stack correctly** (`b1-after-use.png`), driving camera eases behind, `use_label` clears while driving.

## ❗ P1 — USE-hint text overlaps the SHEATHE button in portrait

**Symptom:** the yellow "USE ▸ Drive Roadster" prompt renders directly across the SHEATHE button (text-on-text, both illegible) whenever an interactable is near — this is the core loop (chests, NPCs, vehicles) (`p5-board-prompt.png`).
**Root cause:** `interaction.gd _build_ui()` — `prompt` at `PRESET_CENTER_BOTTOM` + `position(-160, -270)` lands at UI (200, ~1278); the weapon/potion button column occupies x 280–482, y 1212–1342 in the portrait 720×1548 viewport.
**Fix direction:** move the prompt above the button rows (e.g. y ≈ −560 from bottom, or centre it over the joystick half), and centre rather than left-anchor it.

---

## ⚠️ Polish

- **Near-camera boarding label blows up to ~⅓ screen width and clips** — the Label3D DRIVE/RIDE prompt is perspective-scaled, so the label of the car you're standing next to renders as a giant clipped "DRI…" (`p6-mounted.png`, `p9-idle.png`), while distant labels are perfect (`l4-mounted.png`). Consider `fixed_size = true` with distance attenuation, or fade the label out under ~4 m (the HUD USE prompt already covers that range).
- **Second button column intrudes into the joystick half in portrait** — POTION/SHEATHE/DISMOUNT start at UI x=281 (< 360 half-line), so drags starting on those buttons don't move the player; bottom-left corner remains fully usable. Consider narrowing buttons or moving the movement half-line.
- **HP bar width is hardcoded 220 px** (`main.gd _update_stats`) while `_relayout_ui` scales buttons — harmless today, just inconsistent.

## ✅ Verified good (real touch/render evidence)

- **Canvas fills both aspects, zero letterbox:** canvas rect exactly 400×860 and 860×400; world renders edge-to-edge (`p2-hud.png`, `l3-hud.png`).
- **Title screen works by touch at both aspects:** FREE ROAM tapped successfully first try in portrait AND landscape (audio tap-gate then mode select); layout centred and clean (`p1b-title.png`, `l1-title.png` — size issue filed under P1 #1).
- **Touch joystick moves the player:** left-half touch drag-hold moved 10.4 u portrait / 4.8 u landscape, `on_floor` true throughout — grounded walk, no keyboard involved.
- **Touch drag-look orbits:** right-half horizontal drags changed `cam_yaw` by 1.40 rad (portrait) / 2.88 rad (landscape); pitch is clamped in code (−74°…+34°), no floor/sky lock observed.
- **Buttons fire via touch:** JUMP (on_floor→false, both aspects), ATTACK (enemy hp 120→58 across 3 taps at melee range), STABLE (panel opened, `p8-stable-panel.png`). DISMOUNT is the same Button widget, appears on board, rect on-screen at both aspects.
- **Camera never walled at melee range:** two demons at 1.8–2.4 m — hero and both enemies fully framed, no full-screen mesh popup (`p4-enemy-close.png`); near-camera enemy fade (`_fade_near_camera_enemies`) + SpringArm hero-hide collapse guard present in code; no mesh smear in any of 15 captures.
- **Damage is non-modal:** hp 100→19 during a real fight with zero dialogs/banners (`dialog_open` false throughout); feedback = hurt sfx + 0.15 s camera kick. (The red flash overlay is intentionally a no-op "by request" — acceptable, the shake still lands the hit.)
- **No debug text ships:** all GOGI_* telemetry goes to the JS console only; the on-screen HUD is exactly Lv/HP/XP/Gold/Wpn/Inv + bar; the Inv line self-truncates at 46 chars ("…, V..." — `p2-hud.png`).
- **Stable panel fits portrait**, centred, 6 mounts + CLOSE, readable (`p8-stable-panel.png`).

## Could not verify (sandbox limits)

- True simultaneous two-thumb multi-touch (move + look at once) — touches were driven sequentially via CDP; the code paths are index-separated (`move_idx`/`look_idx`) and look correct.
- Real-device notch/home-indicator intrusion — bottom/right margins are ~5–10 CSS px in places; worth a safe-area pass on a physical phone.
- Real GPU frame-rate feel (container is SwiftShader ~5 fps; layout/framing only was judged).
- Campaign-mode compass line rendering (flagged above from code geometry, not a live campaign render).
- In-container cert errors on direct `https://preview.myapping.com` fetches are a sandbox artifact (same-origin in production), not a game defect.
