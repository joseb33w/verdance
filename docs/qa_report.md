# QA REPORT — VERDANCE: Warden of the Four Reaches
**Build:** repo @ fa17b8c (+ uncommitted session changes) · export `/workspace/repo/out` · live `https://preview.myapping.com/cloud-ln4jfbfjx60zaprwslze/index.html`
**Method:** vetted verify.mjs harness (local serve w/ build-prefix symlink; watchdog extended 120s→900s for SwiftShader) + 7 targeted Playwright probes against the **live** URL using the gogi* QA hooks. All screenshots in `/workspace/verify/qa/`. State assertions read `gogiVerdance()` / `gogiGetPlayer()` deltas; no tautological checks.

## VERDICT: FAIL (2 P0)

---

## P0 — SHIP BLOCKERS

### ❌ P0-1: The finale cannot be completed — "Stabilize the Spire Core" is unreachable → campaign/victory is dead
- **Evidence (3 independent runs):**
  - Injected a save with all 4 beacon flags (`gogiInjectSave` + `gogiChooseMode('continue')` — restore itself worked: hp/gold/equip/flags/lit all correct). Teleported to the crown `(312,248,59.2)`: `use_label:""`, `gogiUse()` → `victory:false` (qa4).
  - Height scan `y=59…69` at [312,248] (qa5, qa6): the "Stabilize the Spire Core" prompt **never** appears at any height; the player **falls through** every y between ~59.5 and 69 (no walkable top slab found where one was specced).
  - Highest stable footing found inside the tower: **y≈59.4** (qa3 `tower-top.png` — a dark slab + stair, no beacon in sight).
- **Root cause:** `verdance.gd:_build_beacons()` places the core USE action at `terrain.height(312,248) + y_off(59.5)` ≈ **y 67** (terrain there is ~7.5). `interaction._nearest()` uses **3-D** distance with a 2.9 m range (interaction.gd:364). The intended "top walking slab 58.5 m" either doesn't exist as a collider at terrain+58.5 (≈66 — teleports onto it fall through) or is the floor at ~59.5; either way the action point is **~7.6 m above the best standing surface** → the prompt can never fire. `_use_beacon("core")` → `_do_victory()` is therefore dead code in real play (qgcheck's graph pass can't see this — it's a spatial bug).
- **Fix direction:** seat the core beacon/action ON the actual top slab (compute slab world-y from the built structure, or set the action pos to `slab_y + 1`), and verify a collider exists on the floor-10 walking slab; alternatively give the core action a taller vertical tolerance (XZ distance + |dy| ≤ ~4). Then re-run: label must appear at the slab and `gogiUse` must set `world_restored` → victory overlay.
- Note: ground-level beacons are fine — Frostpeak showed `USE ⟳ Relight Frostpeak Beacon` in-range (qa1 `frostpeak.png`).

### ❌ P0-2: Distance fog returns in Frostpeak — direct acceptance-item #9 violation, whole reach is a white-out
- **Evidence:** `gogiVerdance().fog === true` after entering Frostpeak [712,584] (qa1); `frostpeak.png` and the drake shots are ~90 % white haze — road/buildings barely readable, sky invisible. Fog is correctly **false** at spawn, forest, lake, city.
- **Root cause:** `weather3d.gd:118` — `no_fog = cfg.get("fog", null) == false` is re-evaluated on **every** `apply()`. `verdance.gd:_apply_wx()` (region change + day-cycle segue) calls `weather.apply({time,weather}/{cycle})` **without** a `"fog"` key → `no_fog` resets to `false` → the snow preset (`fog: 0.013`) re-enables distance fog. The world.json `sky {"fog": false}` hard-disable only survives until the first region tick / cycle segment.
- **Fix direction:** make `no_fog` sticky (only update it when the cfg **has** a `"fog"` key), or have `_apply_wx` pass `"fog": false` through. Re-check: `fog:false` at [712,584] and a crisp Frostpeak frame.

---

## P1 — MUST FIX (not ship-blocking)

1. ❗ **Finale tower top floor is near-black** (`tower-top.png`): the highest interior floor reads as a dark void — floor/stairs almost silhouettes. Ground floor is fine (`tower-ground.png`: white walls, readable, stairs). The finale moment happens in the darkest room in the game. Add interior lights/emissive on the upper floors (the spec said "roomy lit interiors" + a beacon at the crown).
2. ❗ **Grand Mall (cell [16,12], ~[264,200]) — interior could not be confirmed.** Two probes teleported to the exact mall centre 25–30 s after arrival and stood on **bare grass** (no sidewalk ground, no 14×14 structure: `mall-inside.png`, `mall-in2.png`); a later probe one cell south after 60 s showed the surrounding city fully built (`mall-far-b/c.png` — real streets, multi-floor buildings, NPCs) but couldn't positively identify the mall building. Likely just very-late streaming of a heavy cell in the 5 fps container, but given a campaign step points there ("Ask guide Cass… Grand Mall"), please walk c16_12 on the preview and confirm the mall + its lit 2-room interior actually build and the S-face arch door opens.
3. ❗ **Lake "deep water" at the user's named spot is only ~0.55 m deep** — at [616,290] the wade/swim gate flip-flops between runs (swimming:true in one, false 2 m away in another; terrain probe: h≈0.43 vs water level 1.0). Swim itself is correct where the water is genuinely ≥1 m (verified floating at surface, y=-0.1, at [656,288] — `deepswim2.png`). Deepen the lake bed around the marked swim spot so "deep water near [616,290]" is actually deep.

---

## Acceptance list (user's 9 items)

| # | Item | Result | Evidence |
|---|------|--------|----------|
| 1 | Stands ON ground while walking | ✅ | `on_floor:true`, y tracks terrain; `stand-side.png` feet on grass; `GOGI_HERO_SEAT 0.015` |
| 2 | Swims in lake, floats at surface | ✅ w/ ❗P1-3 | `swimming:true`, floats at surface in real deep water (`deepswim2.png`); named spot [616,290] is only ~0.55 m deep (flip-flops) |
| 3 | Rider sits ON mount's back (stag + drake) | ✅ | Stag: `stag-defaultcam.png` — astride, hips in contact, riding a road. Drake: boarded (`profile:dragon`), seated per coordinator's default-cam capture; `GOGI_SEAT_CONTACT` 0.000 both. My close-up garbage frames were the spring-arm entering the mount body after a pitch drag (see polish-4) |
| 4 | Car + boat drive + DISMOUNT button | ✅ | Roadster: boarded, motion aligned to camera-forward (dot 1.00), steer yaw 0.02→0.56; Speedboat: boarded, drove (dot 0.74 — slow hull turn), both showed the DISMOUNT button and it **worked** (state → not in_vehicle). `car.png`, `boat.png` |
| 5 | Enemies never one-shot | ✅ | Combat cell [21,5]: nearest enemy 120 hp → **58** after one frost-hammer hit (62 dmg ≤ cap 0.55×120=66), killed on a later hit — always ≥2 hits. `HIT_CAP_FRAC` verified in code + runtime |
| 6 | No popup/red-flash on damage | ✅ | HP driven 100→28 across probes by real enemy attacks; zero overlays/banners in any frame (`combat.png`, `frostpeak.png`); `_flash_hurt()` is a no-op (per explicit user request — damage feedback is camera kick + audio) |
| 7 | Interiors roomy + lit | ⚠️ split | Cabin [5,5]: inside is lit, timber floor, real hinged door (`cabin-in2.png`). Tower ground floor: lit, stairs up (`tower-ground.png`). Tower TOP floor: near-black (❗P1-1). Grand Mall: unconfirmed (❗P1-2) |
| 8 | No gray placeholders / 404 assets | ✅ on live | **Zero** `GOGI_PLACEHOLDER` and zero real 404s across 7 live-URL runs; all 21 committed models resolve. (verify.mjs's local-serve run DID placeholder car/tank/horse/dragon — a local-static-server fetch artifact: the same files curl 200 locally and load clean on the live host. Not a product defect, but see "residual risk" below) |
| 9 | No distance fog anywhere | ❌ **P0-2** | fog:false in forest/lake/city/spawn, **true in Frostpeak** (white-out frames) |

---

## Adversarial sweep (mandatory classes)

- **Engine/console:** boots, canvas renders, **no** GDScript/JS errors on live across all 7 runs (only sandbox Supabase `Failed to fetch` noise, filtered per contract). verify.mjs: engine boot PASS, canvas PASS, input-response PASS. ✅
- **Winnability (qgcheck):** green — "world is winnable (2500 areas)" — but see P0-1: the graph pass can't see the spatial finale bug. ⚠️
- **Movement/facing/camera:** WASD moves camera-relative; right-half drag orbits (yaw −3.33 rad after drag); hero shows BACK to follow-cam (`stag-defaultcam.png`, `boat.png`). ✅
- **Input-binding sanity (auto-fire-on-look):** touch left=joystick, right=orbit, attack is a HUD button only; look-drag with an enemy present left enemy at full 120 hp and player hp unchanged. `emulate_mouse_from_touch=true` is guarded (desktop drag-look ignores emulated motion; no fire binding on pointer). ✅
- **Combat feedback:** hits land through the real `_attack()` path (aim-assist verified in code — stationary attack acquires a nearby foe in any direction); enemy hp deltas real; hit SFX + swing anim invoked. ✅
- **Enemy AI engages:** enemies streamed in, closed distance and damaged the idle player through the real path (hp 100→82→73 while standing still); non-modal feedback. ✅
- **Mobile fill:** canvas = viewport at 400×860 and 860×400 (0,0 origin, no letterbox); UI viewport tracks aspect (720×1548 / 2752×1280); portrait gameplay HUD all on-screen (`hud-portrait.png`). ✅ (polish-6: toast overlaps STABLE)
- **Title/modes:** title renders (`title-visible.png`), FREE ROAM + CAMPAIGN buttons; `?mode=free/campaign` deep links work; campaign starts with rusty_sword (no grant-all leak), Elda dialogue fires (`talks:1`). ✅ (full 5-quest chain not driven end-to-end — see "could not verify")
- **Save/load:** `gogiInjectSave` + continue restores hp/gold/equip/flags/lit-beacons/position. ✅
- **Day/night:** deterministic `gogiSetTime` probe — night is dark but readable with emissive window rows + lit NPCs (`city-night.png`), day clean, no blow-out (verify.mjs luma: night mean 33.9 vs day 156, 0 % clipped). ✅
- **World persistence/boundary:** teleport far off-grid (850,850): terrain skirt + ground persist, no void fall (y stable ≈ terrain), world never vanishes; `_terrain_border_walls` adds invisible walls on true grid edges for on-foot play. ✅ (walk-into-wall not cleanly reproduced — teleports bypass walls by design)
- **Character sourcing (Meshy mandate):** hero (warden.glb), NPCs (ranger/civilian_m/f), enemies (fade_stalker), mounts (stag/drake/ram/beetle) + all vehicles are Meshy per `models/meshy/MANIFEST.md` and render textured in-frame — no KayKit stand-ins in hero/NPC/enemy roles. Two library-animal mounts (Snake, Velociraptor) are creature rides, not characters. ✅
- **Weapon-in-hand:** frost hammer gripped in hand (`stand-side.png`), rusty sword gripped (`cabin-in2.png` close-up), blade visible while mounted. ✅
- **World richness:** 50×50 grid (800 m²), 190 parametric structures w/ real materials + window glow, 169 road cells, ~10 k scatter, populated city with crosswalks/streetlights/NPC crowds (`mall-far-b/c.png`, `city-day.png`); wilderness cells are intentional. verify.mjs "SPARSE" WARNs reflect the wilderness ratio, not a gray-box world. Flat-tint lint is a false positive (it matches the gray *placeholder* fallback pattern; real characters render textured). ✅

## Polish (P2)
4. Camera spring-arm ignores the mount/vehicle body — pitching the camera puts the lens inside the stag/drake (garbage close-ups). Consider adding mounts to the SpringArm collision or a min-distance clamp while mounted.
5. Water body recenters only on the *second* cell-cross after a long warp (tick defers water whenever the far skirt rebuilt; both share the 2-cell gate) — after teleports the lake renders as dry green seabed (`swim2.png`). Invisible in normal walking; worth a `_update_water` force on teleport.
6. Portrait: discovery toast overlaps the STABLE button (`hud-portrait.png`).
7. `GOGI_WHEELS`: all modeled vehicles report fused-static wheels (no spin) — accepted contract, noting for completeness.

## Could not verify (sandbox limits / scope)
- Real audio playback (muted container — infra + `play_sfx`/music/ambient calls verified present), touch feel, true-GPU fidelity/FPS, Supabase `wss`/cloud saves (used the documented `gogiInjectSave` path instead).
- Boarding choreography screenshots for the remaining 13 `vehicles[]` entries (tank/plane/helicopter/glider/ferry/truck/motorcycle/buggy/snake/raptor/ram/beetle + 2nd car): spawn-time `GOGI_SEAT_CONTACT` ≤ 0.05 for all, but only car/boat/stag/drake were boarded and screenshotted. Flight (plane profile) untested end-to-end.
- Full campaign chain (5 quests) end-to-end; verified: campaign start, first talk objective, kill-count plumbing (`notify_kill`), beacon relight path at ground level, and the finale gate — which is where it breaks (P0-1).
- On-foot stair climb of all 9 flights of the Spire Core (SwiftShader too slow); teleport probes stand in.
- **Residual risk worth 5 minutes:** the local-serve verify run produced 5 `TypeError: Failed to fetch` + placeholder vehicles even though the same URLs curl 200 from the same server — models load clean on the live host, so shipping is unaffected, but if the deploy host ever serves slowly the same no-retry fetch path would leave permanent gray vehicles (cache miss → placeholder, no hot-swap on late arrival).

## Bottom line
Core moment-to-moment play (walk/ride/drive/swim/fight, mobile HUD, save/load, day/night, no-popup damage) is solid and looks the part. Ship is blocked by two fixable defects: **the game cannot be won** (core beacon out of reach above the top slab) and **Frostpeak re-enables the banned distance fog** (explicit acceptance item). Fix + re-verify: crown label appears & victory fires; `fog:false` at [712,584].
