#!/usr/bin/env python3
"""VERDANCE — Warden of the Four Reaches : world.json macro-layout generator.
50x50 chunk grid, four contiguous biome reaches painted from /workspace/terrain_heights.csv.
Deterministic (seeded per-cell RNG). Emits /workspace/world.json + a verification report.
"""
import csv, json, random, heapq, sys, collections

W = 50
H = [[float(x) for x in r] for r in csv.reader(open('/workspace/terrain_heights.csv'))]
assert len(H) == W and all(len(r) == W for r in H)

def h(gx, gz): return H[gz][gx]
def in_grid(gx, gz): return 0 <= gx < W and 0 <= gz < W
def dry(gx, gz, th=1.5): return in_grid(gx, gz) and h(gx, gz) >= th
def is_water(gx, gz): return in_grid(gx, gz) and h(gx, gz) < 1.0
def near_water(gx, gz):
    return any(is_water(gx+dx, gz+dz) for dx, dz in ((1,0),(-1,0),(0,1),(0,-1)))

MESHY = "/cloud-pdunxmcf6r3gqaagf06a/models"

# ---------------- model registry (track distinct URLs, budget <= 80) ----------------
URLS = set()
def U(path):
    URLS.add(path); return path

PINE    = [U("props/q_unature/PineTree_1.glb"), U("props/q_unature/PineTree_2.glb"), U("props/q_unature/PineTree_3.glb")]
BIRCH   = [U("props/q_unature/BirchTree_1.glb"), U("props/q_unature/BirchTree_2.glb")]
BUSH    = [U("props/q_unature/Bush_1.glb"), U("props/q_unature/BushBerries_1.glb")]
ROCKM   = [U("props/q_unature/Rock_Moss_1.glb"), U("props/q_unature/Rock_Moss_2.glb")]
ROCK    = [U("props/q_unature/Rock_1.glb"), U("props/q_unature/Rock_2.glb")]
GRASS   = [U("props/q_unature/Grass.glb"), U("props/q_unature/Grass_Short.glb")]
FLOWERS = U("props/q_unature/Flowers.glb")
MUSH    = [U("props/kenney_nature/Mushroom_Red_Spotted.glb"), U("props/kenney_nature/Mushroom_Brown.glb")]
CATTAIL = [U("props/kenney_nature/Cattail_1.glb"), U("props/kenney_nature/Cattail_2.glb")]
PINE_SNOW = [U("props/q_unature/PineTree_Snow_1.glb"), U("props/q_unature/PineTree_Snow_2.glb")]
ROCK_SNOW = [U("props/q_unature/Rock_Snow_1.glb"), U("props/q_unature/Rock_Snow_2.glb")]
BUSH_SNOW = U("props/q_unature/Bush_Snow_1.glb")

STREETLIGHT = U("props/q_street/Streetlight_Single.glb")
TRAFFICLIGHT = U("props/q_street/TrafficLight.glb")
BENCH   = U("props/kk_city/bench.glb")
CARS    = [U("props/q_cars/NormalCar1.glb"), U("props/q_cars/NormalCar2.glb"), U("props/q_cars/Taxi.glb"), U("props/q_cars/SUV.glb")]
DOCK_STRAIGHT = U("props/mod_terrain/Beach_Prop_Docks_Straight.glb")
DOCK_STEPS    = U("props/mod_terrain/Beach_Prop_Docks_Steps.glb")
LIGHTHOUSE    = U("props/mod_racetrack/Prop_Decorative_Lighthouse.glb")
CANOPY  = [U("props/mod_village/Canopy_Full.glb"), U("props/mod_village/Canopy_Side.glb")]
TENT    = U("props/kk_hex/tent.glb")
CAMPFIRE = U("props/kenney_nature/Campfire_Teepee.glb")
TEMPLE_ARCH = U("props/mod_temple/Pillar_Large_Arch.glb")
TEMPLE_BASE = U("props/mod_temple/Pillar_Large_Base.glb")
TEMPLE_FLOOR = U("props/mod_temple/Floor_Ruined_Straight_1.glb")
KK_LUMBER = U("props/kk_hex/building_lumbermill_blue.glb")
KK_TOWER  = U("props/kk_hex/building_tower_A_blue.glb")
KK_WELL   = U("props/kk_hex/building_well_blue.glb")
GEMS    = [U("props/q_uplatformer/Gem_Blue.glb"), U("props/q_uplatformer/Gem_Green.glb")]

BEACON   = U(f"{MESHY}/beacon.glb")
ENEMY_M  = U(f"{MESHY}/fade_stalker.glb")
CIV_M    = U(f"{MESHY}/civilian_m.glb")
CIV_F    = U(f"{MESHY}/civilian_f.glb")
RANGER   = U(f"{MESHY}/ranger.glb")
HERO     = U(f"{MESHY}/warden.glb")
STAG     = U(f"{MESHY}/stag.glb")
RAM      = U(f"{MESHY}/ram.glb")
FOX      = U("animals/fox.glb")
PIG      = U("animals/farm_Pig.glb")
FISH     = U("animals/fish_Fish1.glb")
# palette kinds used (each resolves to one library GLB in the engine palette)
PALETTE_KINDS_USED = ["stump", "log", "barrel", "crate", "torch", "banner"]

# ---------------- region definitions ----------------
CITY = {(gx, gz) for gx in range(14, 25) for gz in range(11, 20)}
NS_COLS = {14, 17, 20, 23}          # city north-south avenues
FROST_BBOX = lambda gx, gz: gx >= 33 and gz >= 29
NORTH_CRAG = lambda gx, gz: 38 <= gx <= 47 and gz <= 6
LAKE_BBOX = lambda gx, gz: gx >= 30 and 8 <= gz <= 31
FOREST_BBOX = lambda gx, gz: gx <= 27 and gz <= 30

def biome(gx, gz):
    hh = h(gx, gz)
    if (gx, gz) in CITY: return 'city'
    if hh < 1.0: return 'water'
    if near_water(gx, gz) and hh < 3.5: return 'shore'
    if FROST_BBOX(gx, gz) or NORTH_CRAG(gx, gz):
        if hh >= 9.0: return 'snow'
        if hh >= 6.0: return 'frost_rock'
        return 'frost_base'
    if hh >= 11.0: return 'crag'
    if hh >= 8.0: return 'hills'
    if FOREST_BBOX(gx, gz): return 'forest'
    return 'meadow'

GROUND = {'city': 'concrete', 'water': 'sand', 'shore': 'sand', 'snow': 'snow',
          'frost_rock': 'rock', 'frost_base': 'dirt', 'crag': 'rock',
          'hills': 'grass', 'forest': 'grass', 'meadow': 'grass'}

def scatter_for(b, gx, gz, rng):
    hh = h(gx, gz)
    if b == 'forest':
        s = [{"url": rng.choice(PINE), "count": rng.randint(10, 15)},
             {"url": rng.choice(PINE), "count": rng.randint(4, 7)},
             {"url": rng.choice(BIRCH), "count": rng.randint(4, 7)},
             {"url": rng.choice(BUSH), "count": 4},
             {"url": rng.choice(GRASS), "count": 12, "collider": False},
             {"url": rng.choice(ROCKM), "count": 3}]
        if rng.random() < 0.5: s.append({"url": rng.choice(MUSH), "count": 3, "collider": False})
        if rng.random() < 0.35: s.append({"url": FLOWERS, "count": 5, "collider": False})
        return s
    if b == 'meadow':
        return [{"url": rng.choice(GRASS), "count": 14, "collider": False},
                {"url": FLOWERS, "count": 6, "collider": False},
                {"url": rng.choice(BUSH), "count": 3},
                {"url": rng.choice(BIRCH if rng.random() < 0.5 else PINE), "count": 2},
                {"url": rng.choice(ROCKM), "count": 2}]
    if b == 'hills':
        return [{"url": rng.choice(PINE), "count": 5},
                {"url": rng.choice(ROCK), "count": 4},
                {"url": rng.choice(GRASS), "count": 8, "collider": False},
                {"url": rng.choice(BUSH), "count": 3}]
    if b == 'crag':
        return [{"url": rng.choice(ROCK), "count": 7},
                {"url": rng.choice(PINE_SNOW), "count": 2},
                {"url": rng.choice(BUSH), "count": 2}]
    if b == 'shore':
        return [{"url": rng.choice(CATTAIL), "count": 6, "collider": False},
                {"url": rng.choice(ROCK), "count": 2},
                {"url": rng.choice(GRASS), "count": 4, "collider": False}]
    if b == 'water':
        s = [{"url": rng.choice(ROCK), "count": 2}]
        if hh >= 0.2: s.append({"url": rng.choice(CATTAIL), "count": 4, "collider": False})
        return s
    if b == 'snow':
        return [{"url": rng.choice(PINE_SNOW), "count": 6 if hh < 10.5 else 2},
                {"url": rng.choice(ROCK_SNOW), "count": 5},
                {"url": BUSH_SNOW, "count": 2}]
    if b == 'frost_rock':
        return [{"url": rng.choice(ROCK_SNOW), "count": 5},
                {"url": rng.choice(PINE_SNOW), "count": 4},
                {"url": BUSH_SNOW, "count": 2}]
    if b == 'frost_base':
        return [{"url": rng.choice(PINE), "count": 7},
                {"url": rng.choice(PINE_SNOW), "count": 3},
                {"url": rng.choice(ROCK), "count": 3},
                {"url": rng.choice(GRASS), "count": 6, "collider": False}]
    return []

# ---------------- roads: Dijkstra highway routing over dry cells ----------------
def route(a, b):
    """min-cost path over cells h>=1.5, cost 1 + 3*|dh| (prefers gentle grades -> switchbacks)."""
    dist = {a: 0.0}; prev = {}; pq = [(0.0, a)]
    while pq:
        d, cur = heapq.heappop(pq)
        if cur == b: break
        if d > dist.get(cur, 1e18): continue
        cx, cz = cur
        for dx, dz in ((1,0),(-1,0),(0,1),(0,-1)):
            nx, nz = cx+dx, cz+dz
            if not dry(nx, nz): continue
            nd = d + 1.0 + 3.0*abs(h(nx,nz)-h(cx,cz))
            if nd < dist.get((nx,nz), 1e18):
                dist[(nx,nz)] = nd; prev[(nx,nz)] = cur
                heapq.heappush(pq, (nd, (nx,nz)))
    if b not in prev and a != b:
        raise RuntimeError(f"no route {a}->{b}")
    path = [b]
    while path[-1] != a: path.append(prev[path[-1]])
    return list(reversed(path))

OUTPOST=(5,5); START=(6,5)
FOREST_BEACON=(21,5)
SPIRE=(19,15); MALL=(16,12); CITY_MUSEUM=(22,16)
FAIR=[(22,12),(23,12),(23,13)]
GARAGE=(14,18); GARAGE_LOT=(15,18); HELIPAD=(24,19)
AIRFIELD=[(15,21),(16,21),(17,21)]
DOCKS=(36,17); LAKE_BEACON=(36,18); LIGHTHOUSE_CELL=(40,17)
ISLAND_MUSEUM=(46,19)
SUMMIT_RELAY=(45,36); FROST_BEACON=(44,36); BASE_CAMP=(41,43)
RUINS=[(20,7),(7,20),(13,33),(16,47),(33,8),(42,3)]

road_dirs = collections.defaultdict(set)   # (gx,gz) -> set of 'ns'/'ew'
def lay_path(path):
    for i, (gx, gz) in enumerate(path):
        nb = []
        if i > 0: nb.append(path[i-1])
        if i < len(path)-1: nb.append(path[i+1])
        for (nx, nz) in nb:
            road_dirs[(gx, gz)].add('ns' if nx == gx else 'ew')

HWY_A = route(OUTPOST, (14,15))          # Forest outpost -> city west gate
HWY_B = route((24,15), DOCKS)            # city east gate -> lake docks
HWY_C = route(DOCKS, BASE_CAMP)          # docks -> around lake west+south shore -> Frostpeak base camp
TRAIL_D = route(BASE_CAMP, (45,37))      # base camp -> switchback trail to summit relay approach
SPUR_E = route((15,19), (16,21))         # city south -> airfield
for p in (HWY_A, HWY_B, HWY_C, TRAIL_D, SPUR_E): lay_path(p)
road_dirs.pop(OUTPOST, None); road_dirs.pop((5, 6), None)   # trailhead: highway ends beside the outpost cluster

PLAZAS = {SPIRE, MALL, CITY_MUSEUM, HELIPAD} | set(FAIR)   # pedestrian cells, no roads
def roads_for(gx, gz):
    if (gx, gz) in PLAZAS: return None
    if (gx, gz) in CITY:
        ns = gx in NS_COLS
        return [{"dir": "x" if ns else "ew", "width": 7}]
    if (gx, gz) in [tuple(a) for a in AIRFIELD]:
        return [{"dir": "ew", "width": 8}]              # runway strip
    ds = road_dirs.get((gx, gz))
    if not ds: return None
    d = 'x' if len(ds) > 1 else next(iter(ds))
    return [{"dir": d, "width": 6}]

# ---------------- city skyline ----------------
MATERIALS = ["glass", "concrete", "steel", "brick"]
def city_structures(gx, gz, rng):
    """two towers flanking the ew street (or corners on avenue crossings)."""
    d = abs(gx - SPIRE[0]) + abs(gz - SPIRE[1])          # taxicab dist to spire core
    lo, hi = (10, 18) if d <= 3 else (7, 13) if d <= 6 else (5, 9)
    out = []
    spots = [(-4.5, -5.2), (4.5, 5.2)] if gx not in NS_COLS else [(-5.75, -5.2), (5.75, 5.2)]
    wmax = 6 if gx not in NS_COLS else 4
    for i, (sx, sz) in enumerate(spots):
        fl = rng.randint(lo, hi)
        st = {"pos": [sx, sz], "footprint": [rng.choice([wmax - 1, wmax]), 4.5],
              "floors": fl, "profile": rng.choice(["vertical", "vertical", "taper", "setback"]),
              "cap": "flat", "facade": "windows",
              "material": rng.choice(MATERIALS if d > 3 else ["glass", "glass", "steel", "concrete"])}
        if rng.random() < 0.6:
            st["window_glow"] = rng.choice([[1.0, 0.85, 0.5], [0.6, 0.85, 1.0]])
        out.append(st)
    return out

SIGN_CELLS = {(15,13): [1.0,0.2,0.6], (18,12): [0.2,0.9,1.0], (21,14): [1.0,0.5,0.1],
              (17,17): [0.7,0.3,1.0], (20,18): [0.2,1.0,0.5], (23,15): [1.0,0.2,0.3]}

def city_props(gx, gz, rng):
    p = [{"url": STREETLIGHT, "pos": [-6, 5]}, {"url": STREETLIGHT, "pos": [6, -5]}]
    if rng.random() < 0.3: p.append({"url": rng.choice(CARS), "pos": [rng.choice([-5, 5]), rng.uniform(-2, 2)], "rot": 90})
    if rng.random() < 0.2: p.append({"url": BENCH, "pos": [rng.choice([-6, 6]), rng.choice([-6, 6])]})
    if gx in NS_COLS and rng.random() < 0.35: p.append({"url": TRAFFICLIGHT, "pos": [5, 5]})
    return p

# ---------------- special cells ----------------
special = {}
def spec(cell, **kw):
    special.setdefault(cell, {}).update(kw)

# -- Forest Reach: ranger outpost + start glade
spec(OUTPOST,
     ground="dirt",
     structures=[{"pos": [-4, -4], "footprint": [7, 6], "floors": 1, "profile": "vertical",
                  "cap": "gable", "facade": "windows", "material": "timber",
                  "roof_material": "roof_tile", "interior": {"door": "hinged", "door_face": "e", "rooms": 1, "lit": True}}],
     props=[{"url": KK_WELL, "pos": [3, 3]}, {"url": CAMPFIRE, "pos": [4, -3]},
            {"kind": "barrel", "pos": [1, -6]}, {"kind": "crate", "pos": [0, -5]},
            {"kind": "banner", "pos": [-2, 1]}, {"kind": "log", "pos": [5, -1]},
            {"url": STREETLIGHT, "pos": [-6, 5]}],
     scatter=[{"url": PINE[0], "count": 6}, {"url": GRASS[0], "count": 8, "collider": False},
              {"url": FLOWERS, "count": 4, "collider": False}],
     npc={"id": "elda", "name": "Ranger Elda", "pos": [2, -2], "model": RANGER,
          "persona": "Elda, the steady ranger-warden of the Greenveil outpost; speaks in short, warm trail-wisdom and worries about the Fade creeping into the Reaches.",
          "lines": ["Elda: The Forest Beacon on the east ridge has gone dark — climb the hill past the pines and relight our courage.",
                    "Elda: Four beacons, four Reaches. Start with ours, then follow the highway east to the Spire City."]})
spec((4,5), ground="dirt",
     props=[{"url": KK_LUMBER, "pos": [0, 0], "collider": "mesh"}, {"kind": "log", "pos": [5, 3]},
            {"kind": "stump", "pos": [-5, 4]}, {"kind": "barrel", "pos": [4, -4]}],
     scatter=[{"url": PINE[1], "count": 8}, {"url": GRASS[1], "count": 8, "collider": False}])
spec((5,6),
     props=[{"url": KK_TOWER, "pos": [2, 2], "collider": "mesh"}, {"kind": "torch", "pos": [0, 4]}],
     scatter=[{"url": PINE[2], "count": 8}, {"url": BUSH[0], "count": 3},
              {"url": GRASS[0], "count": 8, "collider": False}])
spec(START,   # clear start glade
     scatter=[{"url": GRASS[0], "count": 10, "collider": False}, {"url": FLOWERS, "count": 6, "collider": False},
              {"url": BUSH[1], "count": 2}])

# -- Forest Beacon hill
spec(FOREST_BEACON,
     landmark={"url": BEACON, "collider": "box"},
     props=[{"kind": "torch", "pos": [3, 3]}, {"kind": "torch", "pos": [-3, 3]},
            {"url": ROCK[0], "pos": [5, -4]}, {"url": TEMPLE_BASE, "pos": [-5, -4]}],
     scatter=[{"url": PINE[0], "count": 5}, {"url": ROCKM[0], "count": 4},
              {"url": GRASS[1], "count": 8, "collider": False}],
     enemies=4, enemy_type="fade_stalker", enemy_model=ENEMY_M,
     chest={"pos": [0, -5], "contents": ["lightshard_forest", "warden_blade"], "gold": 25})

# -- Spire City specials
spec(SPIRE, ground="sidewalk", roads=None,
     structures=[{"pos": [0, 0], "footprint": [13, 13], "floors": 10, "floor_height": 6.5,
                  "profile": "taper", "cap": "spire", "roof_height": 18, "facade": "windows",
                  "material": "glass", "window_glow": [0.75, 0.9, 1.0],
                  "sign_light": {"color": [0.4, 0.9, 1.0], "energy": 3},
                  "interior": {"door": "arch", "door_face": "s", "rooms": 0, "lit": True}}],
     props=[{"url": STREETLIGHT, "pos": [-7, 7]}, {"url": STREETLIGHT, "pos": [7, 7]}])
spec(MALL, ground="sidewalk", roads=None,
     structures=[{"pos": [0, 0], "footprint": [14, 14], "floors": 3, "profile": "vertical",
                  "cap": "flat", "facade": "windows", "material": "glass",
                  "window_glow": [1.0, 0.9, 0.6], "sign_light": {"color": [1.0, 0.3, 0.5], "energy": 3},
                  "interior": {"door": "arch", "door_face": "s", "rooms": 2, "lit": True}}],
     props=[{"url": STREETLIGHT, "pos": [-7.6, -7.6]}, {"url": STREETLIGHT, "pos": [7.6, -7.6]}])
spec((16,13),  # mall forecourt: city guide + crowd
     npc={"id": "cass", "name": "Cass", "pos": [-3, -3], "model": CIV_F,
          "persona": "Cass, an upbeat Spire City guide with a tablet full of trivia; loves the skyline, nervous about the dark beacon at the museum plaza.",
          "lines": ["Cass: Welcome to Spire City! The Grand Mall is right there — and the Spire Core is the tall one, you can't miss it.",
                    "Cass: Fade creatures have been prowling the museum plaza east of here. Someone should relight that beacon."]},
     populate=[{"set": [CIV_M, CIV_F], "count": 5, "vary": True, "behaviour": "wander", "radius": 7, "speed": 1.3}])
spec((17,12), populate=[{"set": [CIV_M, CIV_F], "count": 5, "vary": True, "behaviour": "wander", "radius": 7, "speed": 1.3}])
spec(CITY_MUSEUM, ground="sidewalk", roads=None,
     structures=[{"pos": [-1, -3], "footprint": [12, 9], "floors": 2, "profile": "vertical",
                  "cap": "flat", "facade": "windows", "material": "marble",
                  "window_glow": [1.0, 0.9, 0.7],
                  "interior": {"door": "arch", "door_face": "s", "rooms": 2, "lit": True}}],
     props=[{"url": BEACON, "pos": [5, 5], "collider": "box"},
            {"url": TEMPLE_BASE, "pos": [-6, 5]}, {"url": GEMS[0], "pos": [-3, 5]},
            {"url": BENCH, "pos": [2, 6]}, {"url": STREETLIGHT, "pos": [7, -6]}],
     enemies=2, enemy_type="fade_stalker", enemy_model=ENEMY_M,
     chest={"pos": [6, -5], "contents": ["lightshard_spire", "pulse_caster"], "gold": 25})
spec((22,15), populate=[{"set": [CIV_M, CIV_F], "count": 5, "vary": True, "behaviour": "wander", "radius": 7, "speed": 1.3}])
# fair district
spec(FAIR[0], ground="sidewalk", roads=None,
     props=[{"url": CANOPY[0], "pos": [-4, -4]}, {"url": CANOPY[1], "pos": [4, -4], "rot": 180},
            {"url": CANOPY[0], "pos": [-4, 4], "rot": 90}, {"kind": "crate", "pos": [0, -6]},
            {"url": STREETLIGHT, "pos": [7, 0]}, {"url": BENCH, "pos": [0, 7]}])
spec(FAIR[1], ground="sidewalk", roads=None,
     structures=[{"pos": [3, 3], "footprint": [4, 4], "floors": 8, "profile": "taper",
                  "cap": "spire", "facade": "windows", "material": "steel",
                  "window_glow": [1.0, 0.4, 0.8], "sign_light": {"color": [1.0, 0.3, 0.9], "energy": 3}}],
     props=[{"url": CANOPY[0], "pos": [-5, -3], "rot": 45}, {"url": CANOPY[1], "pos": [-4, 5]},
            {"url": STREETLIGHT, "pos": [7, -7]}],
     npc={"id": "pip", "name": "Pip", "pos": [-5, 0], "model": CIV_F,
          "persona": "Pip, a cheery fair vendor under the canopies; sells sweets, gossips about everything.",
          "lines": ["Pip: Candied plums! Oh — and if you're the new Warden, the museum beacon's been dark for weeks."]})
spec(FAIR[2], ground="sidewalk", roads=None,
     props=[{"url": CANOPY[1], "pos": [-4, -4]}, {"url": CANOPY[0], "pos": [4, 0], "rot": 270},
            {"kind": "crate", "pos": [0, 4]}, {"kind": "barrel", "pos": [1, 6]},
            {"url": STREETLIGHT, "pos": [-7, 6]}],
     populate=[{"set": [CIV_M, CIV_F], "count": 5, "vary": True, "behaviour": "wander", "radius": 7, "speed": 1.3}])
# garage / helipad / airfield
spec(GARAGE,
     structures=[{"pos": [-4, -5.8], "footprint": [7, 4], "floors": 1, "profile": "vertical",
                  "cap": "flat", "facade": "plain", "material": "concrete"}],
     props=[{"url": CARS[0], "pos": [3, -4], "rot": 90}, {"url": CARS[3], "pos": [3, -1], "rot": 90},
            {"url": STREETLIGHT, "pos": [-6, 5]}])
spec(GARAGE_LOT, structures=[], props=[{"url": STREETLIGHT, "pos": [-7, -7]}])   # kept clear: vehicle spawns
spec(HELIPAD, ground="concrete", roads=None, structures=[],
     props=[{"url": STREETLIGHT, "pos": [-7, -7]}, {"url": STREETLIGHT, "pos": [7, 7]}])
for i, c in enumerate(AIRFIELD):
    spec(c, ground="concrete", structures=[],
         props=[{"url": STREETLIGHT, "pos": [-7, 6]}] + ([{"kind": "banner", "pos": [7, 6]}] if i == 2 else []),
         scatter=[{"url": GRASS[1], "count": 5, "collider": False}])

# -- Lake Reach: docks, lighthouse, beacon, island museum
spec(DOCKS, ground="sand",
     props=[{"url": DOCK_STEPS, "pos": [3.4, 0], "rot": 90}, {"url": DOCK_STRAIGHT, "pos": [5.4, 0], "rot": 90},
            {"url": DOCK_STRAIGHT, "pos": [7.4, 0], "rot": 90}, {"kind": "barrel", "pos": [-4, 3]},
            {"kind": "crate", "pos": [-4.5, -3]}, {"kind": "torch", "pos": [-5, 4]},
            {"url": ROCK[1], "pos": [-6, -6]}],
     scatter=[{"url": CATTAIL[0], "count": 6, "collider": False}, {"url": GRASS[0], "count": 4, "collider": False}])
spec(LAKE_BEACON, ground="sand",
     landmark={"url": BEACON, "pos": [5, 0], "collider": "box"},
     props=[{"kind": "torch", "pos": [5, -3.5]}, {"url": ROCK[0], "pos": [-5, 3]}],
     scatter=[{"url": CATTAIL[1], "count": 6, "collider": False}, {"url": ROCK[0], "count": 2}],
     enemies=3, enemy_type="fade_stalker", enemy_model=ENEMY_M,
     chest={"pos": [-4, -4], "gold": 40, "contents": []})
spec(LIGHTHOUSE_CELL, ground="sand",
     landmark={"url": LIGHTHOUSE, "pos": [2, 2], "collider": "box"},
     props=[{"kind": "barrel", "pos": [-3, 0]}, {"url": BENCH, "pos": [-1, -4]},
            {"kind": "torch", "pos": [0, 5]}],
     scatter=[{"url": CATTAIL[0], "count": 5, "collider": False}, {"url": ROCK[1], "count": 2}],
     npc={"id": "maren", "name": "Keeper Maren", "pos": [-3, -2], "model": CIV_F,
          "persona": "Maren, the lake's weathered lighthouse keeper; dry humour, reads the water like a book, misses the ferry traffic.",
          "lines": ["Maren: Lake Beacon's just west by the docks — mind the Fade things skulking in the reeds.",
                    "Maren: The old museum sits out on the isle. Curator's still there; swim or wade the east spit."]})
spec(ISLAND_MUSEUM, ground="sand",
     structures=[{"pos": [-2, -2], "footprint": [10, 9], "floors": 2, "profile": "vertical",
                  "cap": "dome", "facade": "windows", "material": "marble",
                  "window_glow": [1.0, 0.9, 0.7],
                  "interior": {"door": "arch", "door_face": "s", "rooms": 2, "lit": True}}],
     props=[{"url": TEMPLE_ARCH, "pos": [5, 4]}, {"url": GEMS[1], "pos": [4, -4]},
            {"url": GEMS[0], "pos": [6, -1]}, {"url": BENCH, "pos": [-6, 5]},
            {"kind": "torch", "pos": [2, 5]}],
     scatter=[{"url": CATTAIL[1], "count": 5, "collider": False}, {"url": ROCK[0], "count": 2}],
     npc={"id": "curator", "name": "Curator Voss", "pos": [5, 1], "model": CIV_M,
          "persona": "Voss, the island museum's meticulous curator, marooned by choice among relics of the old Wardens; speaks in catalogue entries.",
          "lines": ["Voss: Exhibit twelve: the Lake Lightshard. Take it, Warden — it was always meant for you.",
                    "Voss: The Spire City museum holds its sister shard. Do sign the guest book."]},
     chest={"pos": [0, 4], "contents": ["lightshard_lake", "storm_bow"], "gold": 25})
spec((37,16), props=[{"url": FISH, "pos": [2, 6], "collider": False}, {"url": FISH, "pos": [-1, 7], "collider": False}])
spec((45,20), props=[{"url": FISH, "pos": [-6, 0], "collider": False}])

# -- Frostpeak: base camp, summit relay, beacon
spec(BASE_CAMP, ground="dirt",
     props=[{"url": TENT, "pos": [-5, -3]}, {"url": TENT, "pos": [-5.5, -6], "rot": 40},
            {"url": CAMPFIRE, "pos": [4.5, -2]}, {"kind": "crate", "pos": [5.5, -4]},
            {"kind": "log", "pos": [5, 0]}, {"kind": "torch", "pos": [-4.5, 1]}],
     scatter=[{"url": PINE_SNOW[0], "count": 5}, {"url": ROCK[0], "count": 3},
              {"url": GRASS[1], "count": 5, "collider": False}],
     npc={"id": "orin", "name": "Guide Orin", "pos": [4, 2], "model": CIV_M,
          "persona": "Orin, a gruff Frostpeak mountain guide wrapped in furs; counts avalanches like sheep and respects the mountain more than people.",
          "lines": ["Orin: Summit relay's up the switchbacks — frost wraiths thick near the top. Beacon's beside the relay mast.",
                    "Orin: A ram carries you up faster than boots. There's one grazing by the camp."]})
spec(SUMMIT_RELAY, ground="snow",
     structures=[{"pos": [2, 2], "footprint": [6, 6], "floors": 2, "profile": "vertical",
                  "cap": "spire", "roof_height": 8, "facade": "windows", "material": "steel",
                  "window_glow": [0.7, 0.9, 1.0],
                  "interior": {"door": "hinged", "door_face": "w", "rooms": 1, "lit": True}}],
     props=[{"kind": "torch", "pos": [-2, 4]}, {"url": ROCK_SNOW[0], "pos": [-5, -4]},
            {"kind": "crate", "pos": [-1, -5]}],
     scatter=[{"url": ROCK_SNOW[1], "count": 4}, {"url": PINE_SNOW[1], "count": 2}],
     enemies=2, enemy_type="frost_wraith", enemy_model=ENEMY_M,
     chest={"pos": [-4, 1], "contents": ["lightshard_frost", "frost_hammer"], "gold": 25})
spec(FROST_BEACON,
     landmark={"url": BEACON, "collider": "box"},
     props=[{"kind": "torch", "pos": [3, 3]}, {"url": ROCK_SNOW[0], "pos": [-4, 4]}],
     scatter=[{"url": ROCK_SNOW[0], "count": 4}, {"url": PINE_SNOW[0], "count": 2}],
     enemies=4, enemy_type="frost_wraith", enemy_model=ENEMY_M)
for c, n in [((43,34), 3), ((46,39), 3), ((42,32), 2)]:
    spec(c, enemies=n, enemy_type="frost_wraith", enemy_model=ENEMY_M)

# -- Ruin sites (chest sites, Fade-corrupted)
for i, rc in enumerate(RUINS):
    contents = ["warden_spear"] if i == 1 else []
    b = biome(*rc)
    spec(rc,
         props=[{"url": TEMPLE_ARCH, "pos": [0, -2], "collider": "mesh"}, {"url": TEMPLE_BASE, "pos": [-4, 2]},
                {"url": TEMPLE_BASE, "pos": [4, 2]}, {"url": TEMPLE_FLOOR, "pos": [0, 2]},
                {"url": TEMPLE_FLOOR, "pos": [0, -5]}, {"kind": "torch", "pos": [2, 4]}],
         enemies=3, enemy_type=("frost_wraith" if b in ("snow", "frost_rock", "frost_base") else "fade_stalker"),
         enemy_model=ENEMY_M,
         chest={"pos": [0, 0], "contents": contents, "gold": 40 + 10*i})

# -- wildlife populate
for c in [(3,6), (6,17), (4,10), (12,21)]:
    spec(c, populate=[{"set": [STAG], "count": 4, "vary": True, "behaviour": "wander", "radius": 10, "speed": 1.6}])
for c in [(7,16), (11,23)]:
    spec(c, populate=[{"set": [FOX], "count": 2, "vary": True, "behaviour": "wander", "radius": 8, "speed": 1.4}])
for c in [(10,26), (9,11)]:
    spec(c, populate=[{"set": [PIG], "count": 3, "vary": True, "behaviour": "wander", "radius": 8, "speed": 1.2}])
for c in [(44,41), (46,42), (43,40)]:
    spec(c, populate=[{"set": [RAM], "count": 3, "vary": True, "behaviour": "wander", "radius": 9, "speed": 1.4}])

spec((24,11), structures=[], props=[{"url": STREETLIGHT, "pos": [-7, 6]}, {"url": STREETLIGHT, "pos": [7, -6]}])

# vehicle-spawn cells kept clear of structures/central props (scenery light)
CLEAR_CELLS = {GARAGE_LOT, (24,11), (11,11), HELIPAD, (8,7), (14,33), (21,31), (47,27), (44,35)} | set(AIRFIELD)
for c in CLEAR_CELLS:
    if c not in special and biome(*c) != 'city':
        b = biome(*c)
        spec(c, scatter=[{"url": GRASS[0], "count": 8, "collider": False},
                         {"url": FLOWERS, "count": 4, "collider": False}]
             if b in ("forest", "meadow", "hills") else
             [{"url": ROCK_SNOW[1], "count": 3}] if b in ("snow", "frost_rock") else
             [{"url": GRASS[1], "count": 4, "collider": False}])

# ---------------- assemble cells ----------------
cells = []
enemy_total = 0
for gz in range(W):
    for gx in range(W):
        rng = random.Random(gx * 1009 + gz * 9176 + 7)
        b = biome(gx, gz)
        cell = {"cell": [gx, gz], "ground": GROUND[b]}
        # scatter
        cell["scatter"] = scatter_for(b, gx, gz, rng)
        # roads
        r = roads_for(gx, gz)
        if r:
            cell["roads"] = r
            if b not in ('city',):   # cleared right-of-way: no trees standing on the highway
                light = {'snow': [{"url": rng.choice(ROCK_SNOW), "count": 3}, {"url": BUSH_SNOW, "count": 2}],
                         'frost_rock': [{"url": rng.choice(ROCK_SNOW), "count": 3}, {"url": BUSH_SNOW, "count": 2}],
                         'shore': [{"url": rng.choice(CATTAIL), "count": 4, "collider": False},
                                   {"url": rng.choice(ROCK), "count": 2}],
                         'water': [{"url": rng.choice(ROCK), "count": 2}]}
                cell["scatter"] = light.get(b, [{"url": rng.choice(GRASS), "count": 8, "collider": False},
                                                {"url": rng.choice(BUSH), "count": 2},
                                                {"url": rng.choice(ROCKM), "count": 2}])
        # city content
        if b == 'city':
            cell["structures"] = city_structures(gx, gz, rng)
            cell["props"] = city_props(gx, gz, rng)
            cell["scatter"] = []
            if (gx, gz) in SIGN_CELLS:
                cell["structures"][0]["sign_light"] = {"color": SIGN_CELLS[(gx, gz)], "energy": 3}
        elif b == 'forest' and (gx + gz) % 5 == 0 and (gx, gz) not in special:
            cell["props"] = [{"kind": rng.choice(["stump", "log"]), "pos": [rng.uniform(-6, 6), rng.uniform(-6, 6)]}]
        elif b == 'meadow' and (gx * 7 + gz) % 9 == 0 and (gx, gz) not in special:
            cell["props"] = [{"url": rng.choice(ROCKM), "pos": [rng.uniform(-6, 6), rng.uniform(-6, 6)]}]
        # special overlay
        if (gx, gz) in special:
            for k, v in special[(gx, gz)].items():
                if v is None:
                    cell.pop(k, None)
                else:
                    cell[k] = v
        if "roads" in cell and cell["roads"] is None: del cell["roads"]
        if cell.get("scatter") == []: del cell["scatter"]
        if cell.get("structures") == []: del cell["structures"]
        enemy_total += cell.get("enemies", 0)
        cells.append(cell)

world = {
    "mode": "chunk",
    "title": "VERDANCE — Warden of the Four Reaches",
    "grid": {"cell_size": 16},
    "terrain": {"amplitude": 13, "frequency": 0.0042, "seed": 7, "octaves": 4,
                "floor": 5.5, "material": "grass", "resolution": 8},
    "water": {"level": 1.0, "depth": 6, "shallow": [0.20, 0.52, 0.55],
              "deep": [0.03, 0.12, 0.26], "wave_amp": 0.2},
    "sky": {"loop": True, "cycle": [
        {"time": "day", "weather": "clear", "seconds": 150},
        {"time": "sunset", "weather": "fog", "seconds": 60},
        {"time": "night", "weather": "clear", "seconds": 90},
        {"time": "sunrise", "weather": "fog", "seconds": 60}]},
    "hero_model": HERO,
    "default_npc_model": CIV_M,
    "start_cell": list(START),
    "goal": {"type": "reach_cell", "target": list(SPIRE)},
    "items": {"lightshard_forest": {"consumed": False}, "lightshard_lake": {"consumed": False},
              "lightshard_spire": {"consumed": False}, "lightshard_frost": {"consumed": False}},
    "cells": cells,
}

# ---------------- verification report ----------------
def fail(msg): print("FAIL:", msg); sys.exit(1)

# grid completeness + budgets
seen = {tuple(c["cell"]) for c in cells}
if len(cells) != 2500 or len(seen) != 2500: fail("grid not complete 50x50")
for c in cells:
    gx, gz = c["cell"]
    if len(c.get("props", [])) > 12: fail(f"props>12 at {gx},{gz}")
    for s in c.get("scatter", []):
        if s["count"] > 40: fail(f"scatter>40 at {gx},{gz}")
    if len(c.get("populate", [])) > 2: fail(f"populate entries>2 at {gx},{gz}")
    for p in c.get("populate", []):
        if p["count"] > 5: fail(f"populate count>5 at {gx},{gz}")
    # gameplay tokens on dry ground
    for key in ("npc", "chest"):
        if key in c and h(gx, gz) < 1.5: fail(f"{key} on wet cell {gx},{gz} h={h(gx,gz)}")
    if c.get("enemies") and h(gx, gz) < 1.5: fail(f"enemies on wet cell {gx},{gz}")
    if "structures" in c and h(gx, gz) < 1.5: fail(f"structure on wet cell {gx},{gz} h={h(gx,gz)}")
    if "roads" in c and h(gx, gz) < 1.5: fail(f"road on wet cell {gx},{gz} h={h(gx,gz)}")
    # structure overlap check (same cell): footprints must not intersect
    sts = c.get("structures", [])
    for i in range(len(sts)):
        for j in range(i+1, len(sts)):
            a, b2 = sts[i], sts[j]
            ax, az = a.get("pos", [0, 0]); aw, ad = a.get("footprint", [8, 8])
            bx, bz = b2.get("pos", [0, 0]); bw, bd = b2.get("footprint", [8, 8])
            if abs(ax-bx) < (aw+bw)/2 and abs(az-bz) < (ad+bd)/2:
                fail(f"structure overlap at {gx},{gz}")
if enemy_total > 60: fail(f"enemy total {enemy_total} > 60")
if h(*START) < 1.5: fail("start cell wet")
pop_cells = sum(1 for c in cells if c.get("populate"))
if pop_cells > 20: fail(f"populate cells {pop_cells} > 20")
n_urls = len(URLS)
if n_urls + len(PALETTE_KINDS_USED) > 80: fail(f"distinct URLs {n_urls}+palette > 80")

# road connectivity: all road cells form one connected component (via adjacency of road cells)
road_cells = {tuple(c["cell"]) for c in cells if "roads" in c}
start_rc = next(iter(road_cells))
seen_rc = {start_rc}; stack = [start_rc]
while stack:
    cx, cz = stack.pop()
    for dx, dz in ((1,0),(-1,0),(0,1),(0,-1)):
        n = (cx+dx, cz+dz)
        if n in road_cells and n not in seen_rc:
            seen_rc.add(n); stack.append(n)
print(f"road cells: {len(road_cells)}, connected component: {len(seen_rc)}",
      "(plaza gaps are walkable)" if len(seen_rc) != len(road_cells) else "OK")

interiors = sum(1 for c in cells for s in c.get("structures", []) if s.get("interior"))
chests = sum(1 for c in cells if "chest" in c)
npcs = [c["npc"]["id"] for c in cells if "npc" in c]
print(f"cells: {len(cells)}  enemies: {enemy_total}  chests: {chests}  interiors: {interiors}")
print(f"npcs: {npcs}")
print(f"populate cells: {pop_cells}  distinct model URLs: {n_urls} (+{len(PALETTE_KINDS_USED)} palette kinds)")
print(f"highways: A={len(HWY_A)} B={len(HWY_B)} C={len(HWY_C)} D={len(TRAIL_D)} E={len(SPUR_E)} cells")
print("HWY_A:", HWY_A)
print("HWY_B:", HWY_B)
print("HWY_C:", HWY_C)
print("TRAIL_D:", TRAIL_D)

with open('/workspace/world.json', 'w') as f:
    json.dump(world, f, separators=(',', ':'))
print("written /workspace/world.json,", len(json.dumps(world)) // 1024, "KB")

# vehicle spawn verification
def wc(gx, gz, ox=0.0, oz=0.0): return [round(gx*16+8+ox, 1), round(gz*16+8+oz, 1)]
V = [
    ("roadster",   wc(*GARAGE_LOT, 2, -5), h(*GARAGE_LOT)),
    ("motorcycle", wc(*GARAGE_LOT, -3, -5), h(*GARAGE_LOT)),
    ("truck",      wc(*GARAGE_LOT, 4, 4), h(*GARAGE_LOT)),
    ("tank",       wc(24, 11, 0, -5), h(24, 11)),
    ("buggy",      wc(11, 11, 0, 5), h(11, 11)),
    ("plane",      wc(16, 21), h(16, 21)),
    ("glider",     wc(17, 21), h(17, 21)),
    ("helicopter", wc(*HELIPAD), h(*HELIPAD)),
    ("speedboat",  wc(37, 17), h(37, 17)),
    ("ferry",      wc(38, 18), h(38, 18)),
    ("stag",       wc(8, 7), h(8, 7)),
    ("ram",        wc(41, 43, -5, 5), h(41, 43)),
    ("beetle",     wc(14, 33), h(14, 33)),
    ("raptor",     wc(21, 31), h(21, 31)),
    ("serpent",    wc(47, 27, -8, 0), h(47, 27)),
    ("dragon",     wc(44, 35), h(44, 35)),
]
print("\nvehicle spawns (name, [x,z], terrain h at cell centre):")
for name, pos, hh in V:
    wet_ok = name in ("speedboat", "ferry")
    status = "WATER" if hh < 1.0 else f"{hh:.1f}"
    if not wet_ok and hh < 1.5: fail(f"vehicle {name} on wet/low cell h={hh}")
    if wet_ok and hh >= 1.0: fail(f"boat {name} NOT in water h={hh}")
    print(f"  {name:11s} {pos}  h={status}")

# site height sanity echo
sites = {"outpost": OUTPOST, "start": START, "forest_beacon": FOREST_BEACON, "spire": SPIRE,
         "mall": MALL, "city_museum": CITY_MUSEUM, "docks": DOCKS, "lake_beacon": LAKE_BEACON,
         "lighthouse": LIGHTHOUSE_CELL, "island_museum": ISLAND_MUSEUM, "summit_relay": SUMMIT_RELAY,
         "frost_beacon": FROST_BEACON, "base_camp": BASE_CAMP}
print("\nsite cells:")
for k, (gx, gz) in sites.items():
    print(f"  {k:14s} [{gx},{gz}]  h={h(gx,gz):.1f}  biome={biome(gx,gz)}")
for rc in RUINS:
    print(f"  ruin           [{rc[0]},{rc[1]}]  h={h(*rc):.1f}  biome={biome(*rc)}")
print("\nALL CHECKS PASSED")
