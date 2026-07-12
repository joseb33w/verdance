# QA Report — VERDANCE: Warden of the Four Reaches
**Build:** joseb33w/verdance @ f999011 (working tree = deployed export) · export `/workspace/repo/out` (104MB, pck 8.8MB) · Godot 4.6.3 web nothreads
**QA method:** canonical verify.mjs (PASS, exit 0) + 9 custom adversarial playwright probes against the exact export, ~30 screenshots eyeballed. Full logs: `/tmp/verify.log`, `/tmp/probe*.log`; frames in `/workspace/verify/qa/`.

## VERDICT: PASS (0 P0 · 2 P1 · 6 warns)

Both prior P0s are independently re-verified FIXED. No ship-blocker class found. The two P1s below are real, small, player-visible defects worth fixing before (or right after) shipping.

---

## Prior P0s — independently re-verified ✅

| Prior P0 | Result | Evidence |
|---|---|---|
| **P0-1 finale** | ✅ FIXED | Injected 4-beacon save → continue mode → stood on the Spire tower top at **y=65.92** (real footing: first landing attempt fell while the cell streamed, second stood — collider is real, not a floating action point). `use_label="Stabilize the Spire Core"` → `gogiUse()` → `victory:true` + flag `world_restored` + "VERDANCE RESTORED" overlay w/ KEEP EXPLORING (26_victory.png). |
| **P0-2 fog** | ✅ FIXED | Teleported into Frostpeak [712,584]: `fog:false` on arrival and across 5 weather ticks + forced `gogiSetTime("night")` → `gogiSetTime("day")` transitions — 7/7 samples false (probe1 `frost.fogSticky`). |

---

## ❗ P1 — must-fix (not ship-blockers)

**P1-A. Helicopter + Jet Glider seat the rider ON the hull exterior, not in the cockpit.**
- Symptom: `veh_helicopter.png` — the warden perches on the rotor mast/cabin roof of a closed-cab helicopter; `veh_glider.png` — rider sits on the fuselage spine behind the glass canopy. Both read as a boarding bug at a glance. (Contract: driver visible in open vehicles, or plausibly hidden in a closed cab.)
- Root cause: the probed/authored seat marker lands on the hull's dorsal surface for these two closed-canopy aircraft (`vehicle.gd` seat probe / `seat` spec: helicopter `[0,1.1,0.4]` × scale 6).
- Fix direction: for these two entries either hide the driver like the tank's instant board, or drop the seat into the cabin volume (negative-Y seat inside the canopy). All 15 other vehicles/mounts seat correctly (tank/plane/truck driver plausibly in cab; cars/boat/moto/all 6 mounts astride with seat-contact 0.00–0.05).

**P1-B. USE-button exit is silently dead on tall mounts (DISMOUNT button works).**
- Symptom (proven on the Swiftclaw raptor): while riding, repeated `gogiUse()`/USE presses over 40s never dismount — yet the mount drives fine (moved 5.8m on W) and the DISMOUNT button exits instantly (probe5/5b). Mirewyrm showed the same. Stag/drake/frosthorn/bronzeshell USE-exit works.
- Root cause: `interaction.gd _nearest(2.9)` measures 3D distance to the **vehicle origin** (`it.pos = vn.global_position`); the raptor's rider sits ~3.7m above the origin → the driven vehicle is never "nearest" → `try_use()` no-ops. The line-96 comment ("a driven vehicle pins itself as the nearest item") is stale — no pinning actually happens.
- Fix direction: while `main.active_vehicle != null`, pin the driven vehicle's entry to the player position (distance 0) or route USE straight to `active_vehicle.exit()` (mirroring the seated-`stand_player()` guard). Same root cause also makes the ferry prompt hard to find (see W-3).

---

## ⚠️ Warns / polish

- **W-1 Streaming pop-in is slow relative to frame budget.** At the goal cell [19,15] the Spire City content (65m tower, roads, concrete) took 60–90s of SwiftShader time (~2fps → ~150 frames) to appear; the roadster boarding shot shows the city fleet parked on bare grass before the ring filled in. On a 60fps device this is seconds, but verify's FEEL perf flagged a **worst frame of 817ms** during a walk — one frame is doing too much (GLB-parse burst / over-heavy cell build). Worth another amortization pass; not a blocker.
- **W-2 Border containment is racy while the border cell streams.** `_terrain_border_walls` is real, but it only exists once the border cell BUILDS: walking east at [799,400] ~15s after arrival crossed to x=802.16 (probe6b). The world does NOT vanish (terrain + water persist, y stable at 850 and at −60,−60; content re-streams on return) — so this is escape-onto-empty-terrain, not the void-fall P0 class. Belt-and-braces: clamp player XZ to the authored grid bounds in `main.gd`.
- **W-3 Ferry boarding prompt discoverability.** No "Drive Lake Ferry" prompt along most of the scale-9 hull (origin-distance ≤2.9m again, P1-B's cause); boarding works only right beside the hull center — took me 3 attempts to find it (probe3d). Rider then stands on the wheelhouse roof (acceptable for a ferry, slightly comic).
- **W-4 World density (verifier lints):** chunk world is SPARSE (~0.4 weighted content/cell; ~13% of the 2500-cell bbox populated; clusters up to 800m apart). In-game the four settlements read as real places (city streets w/ towers+taxis+streetlights, forest outpost, lighthouse docks, snow relay), and the gaps read as intentional wilderness with scatter — but long rides cross a lot of empty green. Consider thickening content along the roads between reaches.
- **W-5 Lake shallows render green** — around the ferry the water reads as a green field (shallow blend over green lakebed; `veh_ferry.png` looks beached on grass); deepen the bed under the ferry route or tint shallows bluer. Elsewhere the water reads correctly blue (mirewyrm/plane/dialog shots).
- **W-6 Cell build can trap a standing player.** After idling 60s at [797,392] while the cell built around the player, the character was fully immobile (dx=dz=0 across 10 walk attempts w/ camera rotations — likely a scatter collider spawned overlapping the player). Reachable in practice only via teleport/fast-travel-ahead-of-streaming; consider a player-radius exclusion when placing scatter colliders.
- Minor: City Car (parametric) driver's head clips slightly through the cab roof; Mirewyrm snake body renders semi-translucent teal (looks glassy).

---

## Dimension checklist (all with real deltas / eyeballed frames)

| Check | Result | Evidence |
|---|---|---|
| Engine boot, canvas, console | ✅ | verify PASS; **zero** SCRIPT ERROR/Parse/pageerror across all 9 probe sessions; only whitelisted sandbox TLS/404 noise |
| Winnability (qgcheck) | ✅ | "quest-graph OK — world is winnable (2500 areas)" in /tmp/verify.log **+ finale proven end-to-end live** |
| Movement + facing | ✅ | W→back visible / S→face visible (04/05); camera-relative deltas logged |
| Camera orbit / pitch | ✅ | right-half drag orbits (02 vs 01); pitch clamps, never floor-stares; look-up = clean blue sky, **no grey ceiling** (61) |
| Input-binding sanity | ✅ | look-drag beside live enemies: nearest_enemy_hp unchanged (no fire-on-look); attack only via ATTACK/hook; touch halves move/look; Space=jump |
| Combat | ✅ | real path: enemy hp 120→58 in 3 swings, kill (alive 3→2), XP level-up Lv1→2, HP bar + hit feedback; stationary aim-assist in code and no whiff observed |
| Enemy AI + non-modal damage | ✅ | wraiths converged (3 visible mid-frame in veh_drake.png), player hp 100→64 / 100→55 through real damage; `dialog_open:false` throughout — no modal, red-flash + shake in code |
| World richness / ground / roads | ✅ | textured city (concrete+road markings+glass towers w/ lit windows+streetlights+taxi traffic), asphalt roads w/ centerlines (veh_stag), sand/snow/grass grounds, 9.9k scatter — no gray-box anti-pattern anywhere (see W-4 for sparseness between reaches) |
| Character fidelity / sourcing | ✅ | hero warden.glb (gorgeous up close, 05), NPCs civilian_m/f + ranger, enemies fade_stalker — **all Meshy**; no flat-tint blobs (lint's hits are loading-placeholder materials only, and zero GOGI_PLACEHOLDER lines fired in any session); snake/raptor mounts + pig/fox are library **animals**, not humanoid roles |
| No T-pose / clips present | ✅ | walk/attack/ride/wander/speak poses all varied across ~30 frames; mounts gait; zero frozen rigs seen |
| Boarding — all 17 `vehicles[]` | ✅* | all 17 boarded via real USE path + screenshot each; seat-contact telemetry 0.000–0.050; *2 aircraft seat wrong → P1-A; ferry prompt → W-3 |
| Weapon-in-hand | ✅ | frost hammer + Warden's Blade gripped in hand (01/20); stow-on-vehicle / keep-on-mount works (veh shots) |
| Trigger zones / prompts | ✅ | beacon "Relight Frostpeak Beacon", chest "Open Chest", NPC "Talk to Keeper Maren" → talks 1, region discovery toasts, quest tracker w/ live direction+distance |
| Day/night + lighting sanity | ✅ | deterministic gogiSetTime probe: night readable (luma mean 33.5, lamps/window-glow visible, 11_frost_night), day mean 152 with 0.0% clipped — no blown whites, no black night |
| Mobile fill portrait + landscape | ✅ | 390×844 and 860×400: canvas = viewport exactly, all four corners world-filled, title + full HUD inside rect, no overlaps (40/41) |
| World persistence / boundary | ✅/⚠️ | teleports 50m+ past every edge: terrain+water persist, y stable, no void fall, content re-streams on return; racy wall → W-2 |
| Save/continue path | ✅ | gogiInjectSave → continue restored hp/gold/inventory/equipped/flags exactly; "Welcome back, Warden." |
| Audio presence | ✅(warn-only) | AudioManager autoload + bus layout + play_sfx on attack/hurt/door/boarding — infra present per verify |

## Could not verify (sandbox limits)
Real-GPU fidelity & device framerate (SwiftShader ~2fps here), actual audio playback (muted container), true touch feel, Supabase cloud-save round-trip (TLS-proxied — save inject hook proven instead), multiplayer N/A.
