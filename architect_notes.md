# VERDANCE — Warden of the Four Reaches · Architect notes

Generated programmatically by `/workspace/gen_world.py` (deterministic, seeded per cell) → `/workspace/world.json`.
50×50 grid, `cell_size` 16 (800×800 m), **all 2500 cells authored** — zero voids. Terrain + water blocks copied
verbatim from the delegation (no warp; heights matched against `/workspace/terrain_heights.csv` for every
gameplay placement: every structure/NPC/chest/road/enemy cell verified h ≥ 1.5).

## Reach bounding boxes (biome paint is height-aware inside each box)

| Reach | Box (gx, gz) | Treatment |
|---|---|---|
| **The Forest** (start) | gx 0–27, gz 0–30 (minus city/water) | grass/dirt, dense pine+birch+bush+mushroom scatter; SW crags (gx 0–10, gz 22–30, h≥11) as rocky highlands |
| **The Spire City** | gx 14–24, gz 11–19 (99 cells, CSV-verified min h 2.8) | concrete ground, full street grid, parametric skyline |
| **The Lake** | gx 30–49, gz 8–31 | real water basin (h<1.0), sand beach ring on all water-adjacent cells, reed (cattail) shallows |
| **Frostpeak** | gx 33–49, gz 29–49 (+ North Crag spur gx 38–47, gz 0–6) | snow ≥ h9, rock cliffs h6–9, dirt/pine base below; snow-pine → bare-rock fade with altitude |

Transitions: meadow cells (grass+flowers+lone trees) fill everything between; hills (h 8–11) get rock+pine.
No cell is bare — wilderness carries 2–6 scatter entries, water cells get lakebed rocks/reeds.

## Key sites (cell = [gx,gz]; world centre = gx·16+8, gz·16+8)

| Site | Cell | CSV h | Notes |
|---|---|---|---|
| Ranger **outpost** | **[5,5]** | 5.8 | enterable timber cabin (hinged door, 1 room, lit), well, campfire, lumbermill+watchtower on [4,5]/[5,6]; NPC **elda** |
| **start_cell** | **[6,5]** | 5.4 | clear flower glade beside the outpost, off the road |
| **Forest Beacon** | **[21,5]** | 8.0 | beacon.glb landmark on the east-ridge hill, 4 fade_stalkers, chest [lightshard_forest, warden_blade] |
| **Lake Beacon** | **[36,18]** | 1.5 | beacon.glb on the shore highway next to the docks, 3 fade_stalkers, gold chest |
| **Spire Beacon** | **[22,16]** | 6.4 | = CITY MUSEUM plaza: beacon.glb prop + 2 fade_stalkers + chest [lightshard_spire, pulse_caster]; marble 2-floor museum, interior (arch, 2 rooms, lit) |
| **Frost Beacon** | **[44,36]** | 13.0 | beacon.glb landmark adjacent to relay, 4 frost_wraiths |
| **Spire Core = GOAL** | **[19,15]** | 7.5 | tallest structure: 13×13 taper, 10 floors @ 6.5 m + 18 m spire cap (≈83 m; skyline caps at 18×3.2≈58 m), glass, arch interior, auto-stairs to top |
| **Mall** | **[16,12]** | 5.6 | 14×14, 3 floors, glass, interior (arch, 2 rooms, lit); guide **cass** + crowds on [16,13] |
| **Fair district** | [22,12] [23,12] [23,13] | 4.2–4.7 | canopy stalls, neon "ride" spire (8-floor taper, pink sign_light), vendor **pip**, crowd |
| **Island Museum** | **[46,19]** | 3.7 | 2-floor marble dome, interior (arch, 2 rooms, lit); chest [lightshard_lake, storm_bow]; NPC **curator** (Voss); gem/pillar exhibits |
| **Docks** | [36,17] | 1.6 | dock steps+planks running east into the water; keeper **maren** at lighthouse |
| **Lighthouse** | [40,17] | 1.7 | mod_racetrack decorative lighthouse landmark on the headland |
| **Summit Relay** | **[45,36]** | 14.6 | highest cell in the world; steel spire-cap relay, interior (hinged, 1 room, lit), chest [lightshard_frost, frost_hammer], 2 frost_wraiths |
| **Frost base camp** | [41,43] | 2.7 | tents+campfire, guide **orin**, ram herd nearby |
| Ruin chest sites (6) | [20,7] [7,20] [13,33] [16,47] [33,8] [42,3] | 4.8–12.3 | mod_temple arch/pillars/floors, 3 enemies each, gold chests ([7,20] also holds **warden_spear**) |

Enemies total **41** (≤60): fade_stalker in forest/lake/city, frost_wraith on Frostpeak + snow-ruin; all cells carry
`enemy_model: /cloud-pdunxmcf6r3gqaagf06a/models/fade_stalker.glb`. Interiors: **6** of 7 budget
(cabin, mall, city museum, island museum, spire core, summit relay).

## Road / highway network (169 road cells, one connected component — verified)

- **HWY A** outpost → city west gate: (6,6)→(8,6..11)→(9..13,11)→(14,12..15). Trailhead ends beside the cabin.
- **City grid**: every city cell carries a road — EW streets on all rows, NS avenues (dir `x`) on gx 14/17/20/23, width 7. Plazas (spire, mall, museum, fair, helipad) are pedestrian (no road).
- **HWY B** city east → lake docks: (24,15..11)→(25..30,10/11)→(31..35,12..15)→(36,15..17).
- **HWY C** docks → west+south shore → frost base camp: gx 35–36 down gz 17–31, then SE to (41,43).
- **TRAIL D** base camp → summit switchback: (41,43..37)→(42..45,37) — ends one cell south of the relay.
- **SPUR E** city south → airfield runway (EW width-8 strips on [15–17,21]).
- All road cells CSV-verified h ≥ 1.5; wilderness road cells get a cleared right-of-way (no trees on asphalt).

## 16 vehicle/mount spawn positions (world [x,z]; CSV height at cell centre; all cells kept structure-free / centre-clear)

| Ride | [x, z] | h | Where |
|---|---|---|---|
| roadster | [250, 291] | 4.6 | garage lot [15,18], beside the garage on [14,18] |
| motorcycle | [245, 291] | 4.6 | garage lot |
| truck | [252, 300] | 4.6 | garage lot |
| tank | [392, 179] | 4.7 | cleared city-edge lot [24,11] |
| buggy | [184, 189] | 2.8 | on HWY A forest-city road [11,11] |
| plane | [264, 344] | 1.9 | airfield runway [16,21] |
| glider | [280, 344] | 2.5 | airfield runway [17,21] |
| helicopter | [392, 312] | 4.9 | helipad plaza [24,19] |
| speedboat | [600, 280] | **−0.5 (in water)** | ~16 m east off the dock planks [37,17] |
| ferry | [616, 296] | **0.4 (in water)** | ~30 m off the docks [38,18] |
| stag | [136, 120] | 7.3 | forest glade [8,7] on the trail |
| ram | [659, 701] | 2.7 | Frostpeak base camp [41,43] |
| beetle | [232, 536] | 8.3 | beside hill ruin [13,33] |
| raptor | [344, 504] | 6.3 | open south meadow [21,31] |
| serpent | [752, 440] | 2.5 shore | lake south-east shore [47,27], half-in-water at the cell's west edge |
| dragon | [712, 568] | 13.3 | snow shelf [44,35] below the summit relay |

## Wildlife & crowds (15 populate cells, ≤20 budget)

Stag herds ×4 ([3,6],[6,17],[4,10],[12,21]) · fox ×2 ([7,16],[11,23]) · pig ×2 ([10,26],[9,11]) ·
ram ×3 ([44,41],[46,42],[43,40]) · city civilian crowds ×4 ([16,13],[17,12],[23,13],[22,15]).
Fish props in the shallows at [37,16] and [45,20].

## Scenic POIs

1. **Forest Beacon ridge [21,5]** — h 8 hilltop; the whole city skyline + north lake in one look.
2. **Lighthouse headland [40,17]** — sunrise-over-the-lake vantage; island museum dome visible across the water.
3. **Spire Core top floor [19,15]** — interior stairs to ~65 m; the four Reaches from one balcony.
4. **Summit Relay [45,36]** — highest point (h 14.6); the entire basin + city silhouette at dusk.

## Honest deviations / judgment calls

- **"mist" is not a valid weather state** (weather.md: clear/cloudy/overcast/fog/rain/storm/snow) — the sky cycle
  uses **`fog`** at sunset/sunrise segments for the mist vibe. "dusk"/"dawn" mapped to `sunset`/`sunrise`.
- **Island museum**: the requested cells around [45,18]/[46–47,23–27] are h<1.5 or true underwater; [46,19]
  (h 3.7) is the best "near-island" — water on its N/W sides, wade/swim from the west or walk the east spit.
  Reads as an isle from the lighthouse; structurally safe.
- **Spire "footprint 16×16, floors 10"** as literally specced would be shorter than an 18-floor tower, so the
  Spire Core uses 13×13 (fits the 16 m cell with a walkable plaza rim) and `floor_height` 6.5 → it is
  unambiguously the tallest silhouette while keeping only 10 interior storeys of auto-stairs.
- Lake Beacon carries a gold chest only (its shard is at the island museum per the chest spec).
- Budgets landed: 41 enemies, 11 chests, 6 interiors, 56 distinct model URLs (+6 palette kinds) ≪ 80,
  props ≤ 12/cell, scatter ≤ 40/entry, populate ≤ 5/entry on 15 cells.
- No `vehicles`, no `locks`, no `doors[]` authored (per delegation); goal is `reach_cell [19,15]` — with zero
  locks the reassembled graph is trivially winnable.
