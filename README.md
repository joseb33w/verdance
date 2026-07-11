# VERDANCE — Warden of the Four Reaches

A 3D open-world exploration-adventure for **mobile web** (Godot 4.6, Compatibility/WebGL2,
single-threaded web export). You are a Warden of a living 800×800 m world split into four
connected Reaches — The Forest, The Lake, The Spire City, Frostpeak — slowly being drained
by a grey **Fade**. Relight the four Beacons and restore it.

**Play:** https://preview.myapping.com/cloud-ln4jfbfjx60zaprwslze/

## Two ways to play (title screen)
- **FREE ROAM** — every Reach open, the full vehicle fleet, all six mounts pre-tamed, every
  weapon in hand. Explore, drive, fly, sail, swim, climb, fight optional Fade creatures.
- **THE WARDEN'S CAMPAIGN** — a five-quest chain across all four Reaches: tame your first
  mount, ride to the Forest Beacon, boat to the island museum, drive the highways into the
  city and ascend the Spire Core, climb Frostpeak's switchbacks — then relight the Core with
  all four Lightshards and watch daylight return.
- **CONTINUE** appears when a cloud save exists.

## The world
- One contiguous 50×50-cell streamed chunk world (seamless, no loading doors) with rolling
  terrain, a real swimmable lake, a connected highway network, and a day/night cycle with
  **per-Reach weather** (clear skies over the Forest and Lake, neon city nights, Frostpeak
  snow) — crisp to the horizon, no distance fog.
- 21 Meshy-generated signature assets: the Warden, Fade-stalkers, civilians, a rigged
  Greatstag/Frosthorn ram/Bronzeshell beetle/Skydrake drake, the full vehicle fleet (roadster, buggy, truck,
  tank, motorcycle, speedboat, ferry, plane, helicopter, jet glider), the Reach Beacon and the
  Spire Core monolith.
- Enterable multi-floor interiors: the Grand Mall, two museums (city + lake island), the
  ranger cabin, the summit relay, and the 10-storey Spire Core with auto-stairs to the crown.
- Wildlife herds (stags, foxes, boars, rams), city crowds, LLM-driven NPC conversations
  (shared NPC brain), positional audio beds per biome.

## Getting around
- **On foot**: walk/run, JUMP (button + Space), swim, climb ladders and slopes.
- **Vehicles**: walk up + USE to board. Land/water/air fleet with per-profile handling;
  planes/helicopters take off, fly and land (fly low + slow to touch down).
- **Mounts**: six wild creatures roam the Reaches — ride one to TAME it into your stable,
  then call any tamed mount from the STABLE button. The Skydrake flies; the Mirewyrm swims
  the shallows.
- **Weapons**: found in chests across ruins, museums and beacon sites (blade, spear, hammer,
  bow, pulse caster). DRAW/SHEATHE toggle; attacks auto-aim at the nearest Fade creature.

## Persistence (Supabase)
Progress — weapons + equipped, tamed stable, Beacons lit, campaign step, inventory, gold,
discovered Reaches, position — autosaves every 10 s (and on key events) to Supabase via two
prefixed SECURITY DEFINER RPCs keyed by a per-device token in localStorage. The saves table
is RLS-locked; anon can only reach the two RPCs.

## Development
- Engine: Godot 4.6.3, gl_compatibility renderer, `nothreads` web export.
- `world.json` / `quests.json` are loose data files streamed at runtime (chat-editable).
- `tools/` holds the world generator (`gen_world.py`), the gameplay merge (`merge_world.py`)
  and the terrain height map used to fit the four Reaches onto the noise field.
- `models/meshy/` archives the Meshy-generated GLBs (streamed from R2 at runtime; the
  directory is `.gdignore`d so it never bloats the export).
- Export: open the "Web" preset — or headless:
  `godot --headless --path . --export-release "Web" out/index.html && cp world.json quests.json out/`
- QA hooks on the web build: `gogiVerdance()` (pushed state snapshot), `gogiTeleport(x,z)`,
  `gogiUse()`, `gogiAttack()`, `gogiChooseMode(m)`, `gogiSetTime(t)`, `?mode=free|campaign`
  deep-links.

## Credits
KayKit / Kenney / Quaternius CC0 asset kits; Meshy AI generated signature assets; CC0 audio
library (orchestral + field-recorded ambient tiers).
