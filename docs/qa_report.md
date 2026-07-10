# QA REPORT — VERDANCE: Warden of the Four Reaches
QA pass on `/workspace/out` (feat/verdance-world), driven via the real exported web build (headless Chromium + SwiftShader, static server with CDN proxy for `/cloud-.../models` + `/godot-assets` — same semantics as the live preview). All probes in `/workspace/verify/probeA*.mjs, probeB–E.mjs`, logs `/tmp/qaA*.log … /tmp/qaE.log`, screenshots `/workspace/verify/qa-*.png`. Vetted harness run: `/tmp/verify.log`.

## VERDICT: FAIL (1 P0)

The world, art, movement, combat, taming, saves and 15 of 17 rides genuinely work — but **the campaign cannot be won**: the Spire Core finale point is sealed inside a solid building.

---

## ❌ P0 — Campaign finale is physically unreachable (game unwinnable)

**Symptom:** The q_finale step "Ascend the Core floor by floor and stabilize it (USE at the crown)" can never be completed. The Spire Core tower at cell [19,15] (312,248) has **no door, no interior, no stairs** — it is a solid frustum with a whole-AABB box collider.

**Evidence:**
- `world.json` [19,15]: `"profile": "taper"` **with** an `"interior": {door:"arch", door_face:"s", …}` spec.
- `build_structure.gd:56` — interiors are parsed only to be used in the **`"vertical"` profile branch** (`_build_shell` is called only in the default `match` arm, line ~94-99); `"taper"` builds `GShapes.frustum` and leaves `shelled=false`, so line ~117 adds the sealed whole-AABB `box` collider. The file's own schema doc (line ~25) says interior is *"vertical profile only"* — the world data violates it.
- Physical probes (probeD, /tmp/qaD.log): walked against the tower at x=312 from BOTH z-faces (z→254.9 and z→241.1) and around the NE exterior — blocked everywhere, y never rose above 7.8. No archway exists on any face.
- The stabilize USE point registers at `terrain+59.5` (`verdance.gd:288`, world.json beacons "core" `y_off: 59.5`); `interaction._nearest(2.9)` uses full **3D** distance — a ground player is ~59 m away. Flight can't reach it either: `ALT_MAX = 32` above local terrain (~5.5) ≈ y 37.5 — verified in-game with the plane (probeE: y plateaued 34–36). No ladders exist anywhere in world.json (grep: 0).
- `world_restored` (required by q_finale + victory) is set **only** in `_use_beacon` for id "core" (`verdance.gd:416-422`). qgcheck passed (green in /tmp/verify.log) because it checks the flag/item graph, not physics — this is exactly the gap.

**Fix direction (any one):** change [19,15] to `profile:"vertical"` (interior shell then builds 10 storeys of real stairs — the mall proves the shell works); OR support interior shells for taper; OR move the core stabilize point to ground level / add a ladder or lift. After fixing, re-verify by climbing on foot — I could not complete this check (nothing to climb).

---

## ❗ P1 — must-fix

### 1. The Skydrake (dragon mount) is unrideable — wild AND summoned
- Wild spawn (712,568): the dragon renders **comically giant** (~10–15× player height; wingspan spans the frame — `qa-dragon-site.png`). Teleporting to 1.5 m from its origin gets the player pushed to 3.2 m by its collider; `use_label` stays empty (USE radius 2.9 m from origin) → can never board or tame it.
- STABLE summon (probeC2): "Skydrake answers your call" works, a floating **RIDE** prompt renders (`qa-summon-dragon.png`) — but 20 s+ of USE never boards (origin unreachable through the collider).
- Root cause: the spec has no `scale` (all other mounts carry 2.4–4.5) so `monster_Dragon.glb` ships at raw size, and the mount's USE range doesn't scale with body size. Flight code itself is fine (plane climbed 2.8→35.7 and ceilinged correctly), but **dragon flight is unreachable by players**.
- Fix: give the dragon a sane scale (rideable, ~stag-size ×1.5) and/or make vehicle USE range account for body extent.

### 2. Lake Ferry is beached on dry land and unboardable
- `qa-ferry-retry.png`: the ferry sits at (616,296) on a **sand cell above water level**, hull half-buried in the ground. Across 3 sessions (probeB 16 tries, probeC 77 s window, probeE 10 tries with approach) it never boards; `use_label` is empty from anywhere reachable (its scale-11 hull keeps the player > 2.9 m from the origin). 1 of the 2 boats is dead + looks broken.
- Fix: move it into real deep water (the speedboat at (600,280) floats correctly and drives) and check USE range vs the big hull.

### 3. Camera spring-arm collapses INSIDE the hero — the "green mass" root cause
- This is the coordinator's unreproducible "full-screen green mass at (590,282)": it is **not water**. The frames are the warden's leaf-cape/armor at ~0 camera distance. Reproduced 4×: coordinator's `beauty-lake.png` + `beauty-frost.png` (both while enemies were attacking), my `qa-lake-orbit.png` (orbiting at the dock fences — chest armor fills the screen), `qa-swim.png`, `qa-spire-inside.png` (backed against a wall).
- Mechanism: `cam_spring` (mask=L_WORLD, margin 0.3) pulls to ~0 whenever any layer-1 body (fence, crate, wall, prop, beacon) sits between camera and player — then the camera renders from inside the player mesh; the screen becomes an unreadable smear until the player moves. Happens routinely in fights near props (beacon arenas are prop-dense) and against building walls.
- Fix: standard near-camera treatment — fade/hide the player mesh when spring length < ~1.2 m; optionally exclude thin scatter/fence colliders from the camera mask.

### 4. Mobile HUD overlap / overflow (both orientations)
- The centered region label/toast renders **on top of** the top-left stats block in every shot ("THE FOREST" collides with line 1 — `qa-spawn.png`, `qa-edge-after.png`, etc.).
- The stats block's `Inv:` line runs off-screen unwrapped in portrait (truncated mid-word, `qa-spawn.png`), and the HP bar overlaps the text.
- Campaign mode renders the **entire quest chain as one line** running off both sides and through the compass + toast (`vd-landscape-campaign.png`) — unreadable on a phone.
- Debug-looking text is shipped in the player HUD ("Area:c6_5 enemies 0 fps 2").
- Canvas fill itself is correct (400×860 and 860×400 both fill exactly; buttons inside the safe area — probeA/B logs). Fix: real anchored layout for the top strip, show only the current objective, wrap/trim the inventory line, drop the debug fields.

### 5. Boarding poses on modeled vehicles
- **Helicopter:** rider stands ON the rotor hub/roof while "driving" (`qa-board-helicopter.png`) — seat-marker mis-probe on the fused GLB.
- **Motorcycle** (and speedboat): rider is fully hidden — an empty bike visibly driving reads broken (`qa-board-motorcycle.png`); the roadster proves the seated-driver path works (`qa-board-roadster.png` shows the warden at the wheel).
- Fix: clamp the seat probe to cabin interior height for the heli; authored seat markers for motorcycle/speedboat.

---

## ⚠️ Warnings (surface, don't block)
- **Between-hub density:** the verifier lints "SPARSE (~0.4 weighted content/cell; ~13% bbox fill)" — visually the four hubs are genuinely good (city streets with lane markings, window-lit facades, streetlights, plaza + beacon; docks; airfield runway; frost road + snow pines), but long rides cross **large bare flat-green stretches** and the grass ground reads near-flat-color at distance (subtle noise only). Filling connective tissue (paths, scatter variety, waypoints) would lift the amateur-reading vistas (e.g. `vd-stag-mounted.png`).
- **Ranger Elda looks tiny** (waist-high?) in `vd-npc.png` — check ranger.glb scale vs civilians.
- Garage cluster USE label showed "Drive City Car" while beside the **truck** (probeE log) — boarded fine; check label/entry proximity mixup.
- Historical flaky FAILs in the coordinator's `/tmp/vd.log` (S-move, swim, stalkers, NPC dialog) all passed in later runs (vd1/vd2) and in my probes — streaming-timing flakes, not code bugs, but they show probe windows need margins.
- Audio: infra present (AudioManager autoload, bus layout, Music/SFX players; play_sfx on attack/hit/pickup/door/ui; play_music; per-region ambient tracks staged in /audio). Playback itself unverifiable here.
- verify.mjs watchdog cut its feel-probes ("no player-state hook" — the template's `gogiGetPlayer` marshalling is broken as disclosed; `gogiVerdance` covers it). Its core asserts passed (boot, canvas, frames, luma day/night); its flat-tint lint is a false positive (the override is the enemy capsule *fallback* branch only — live enemies render textured Meshy stalkers).

## ✅ What passed (with evidence)
| Check | Result |
|---|---|
| Boot + console | ✅ boots, canvas fills, **zero non-noise page errors across 7 sessions** |
| Movement + facing | ✅ W shows the hero's back, S the masked face (`qa-facing-back/front.png`); W/S deltas 3.4–3.5 m |
| Camera orbit + pitch clamp | ✅ right-half drag orbits (`qa-look-0/1.png`), pitch clamps top-down↔sky, recovers; desktop left-drag look works |
| Input binding sanity | ✅ look-drag causes **no** attack/use/gold/inventory side effects (probeA); attack only via HUD button |
| Combat loop | ✅ stalkers chase (d 610→0.7), kills land (alive 4→3), player takes damage through the real path (hp 100→55) — vd1 + my shots of engaged stalkers |
| World richness (hubs) | ✅ city streets/roads/facades/streetlights (`qa-tower-north.png`), plaza + Meshy beacon (`qa-city-plaza.png`), mall interior with rooms + warm light (`qa-mall-inside.png`), docks, runway, frost road |
| Interiors (vertical shells) | ✅ mall: entered through the arch (z 196→206.3 across the wall line 201.2), walked back OUT (196.6) — no trap geometry (`qa-mall-inside/exit.png`) |
| Character sourcing | ✅ hero warden.glb, NPCs civilian_m/f + ranger, enemies fade_stalker — all Meshy; mounts stag/ram/beetle Meshy + disclosed library animals (snake/raptor/dragon) |
| Weapon-in-hand | ✅ frost hammer gripped in the fist (`qa-mall-inside.png` close-up); hero is the only equipping rig |
| Rides (15/17) | ✅ roadster (visible seated driver), city car, truck, motorcycle, buggy, tank, helicopter, speedboat (boards + drives), stag (tames + gallops, vd2), serpent, raptor, beetle, ram, glider, plane (**real flight: y 2.8→35.7, correct ~32 m ceiling**, `qa-plane-fly.png`) |
| Taming + STABLE | ✅ riding tames (vd2), panel lists all six, summon teleports the mount in ("Skydrake answers your call") |
| Beacons + chest + quests | ✅ chest grants Lightshard, forest beacon relights with visible frame change (vd1); quest chain + compass drive campaign (vd2) |
| Day/night | ✅ deterministic gogiSetTime: night darkens sky, city window-glow reads (`beauty-city-night.png`), day not blown out (no clip warns) |
| World boundary / persistence | ✅ east edge wall stops the player at x=799.1 with world still rendered (`qa-edge-after.png`); outside-grid teleport (900,296) keeps a ground skirt — no void fall; streamed cells persist |
| Swim | ✅ swim engages in deep water (vd1); my dock-side walks stayed in shallows (probe artifact, not a bug) |
| Save/restore | ✅ autosave serializes campaign state; inject + CONTINUE restores mode/stable/flags (vd2) |
| Winnability graph | ✅ qgcheck green — but see P0: physics contradicts the graph at the final node |

## Could not verify (sandbox limits)
- Real Supabase RPC/wss round-trip (TLS proxy blocks; coordinator curl-verified server-side; restore path tested via gogiInjectSave).
- Real-device audio playback, touch feel, true-GPU fidelity/FPS (SwiftShader ~1–2 fps is an artifact, not a perf verdict).
- The full 10-storey Spire ascent + finale USE — structurally impossible until the P0 is fixed; re-run probeD after the fix.
- NPC voice/LLM dialogue content (npc.myapping.com blocked); the talk trigger, "is speaking…" UI and talks counter do fire.
