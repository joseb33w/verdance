#!/usr/bin/env python3
"""Merge the Verdance gameplay layer (weapons, vehicles/mounts, beacons, regions) into the
Architect's world.json. Site coordinates come from sites.json (hand-written from
architect_notes.md). Run: python3 merge_world.py"""
import json

BUILD = "cloud-pdunxmcf6r3gqaagf06a"
M = f"/{BUILD}/models"

world = json.load(open("/workspace/world.json"))
sites = json.load(open("/workspace/tools/sites.json"))

world["title"] = "VERDANCE — Warden of the Four Reaches"
world["hero_model"] = f"{M}/warden.glb"
world.setdefault("default_npc_model", f"{M}/civilian_m.glb")
world["start_weapon"] = "rusty_sword"

world["weapons"] = {
    "warden_blade": {"name": "Warden's Blade", "kind": "melee", "damage": 32, "rate": 1.5,
                      "model": "props/kk_weapons/sword_B.glb"},
    "warden_spear": {"name": "Verdant Spear", "kind": "melee", "damage": 40, "rate": 1.1,
                      "model": "props/kk_weapons/spear_A.glb"},
    "frost_hammer": {"name": "Frostbreaker Hammer", "kind": "melee", "damage": 62, "rate": 0.8,
                      "model": "props/kk_weapons/hammer_B.glb"},
    "storm_bow": {"name": "Stormcaller Bow", "kind": "ranged", "damage": 34, "rate": 1.5,
                   "range": 26.0, "projectile": {"speed": 26.0, "arc": False},
                   "model": "props/kk_weapons/bow_A_withString.glb"},
    "pulse_caster": {"name": "Pulse Caster", "kind": "ranged", "damage": 48, "rate": 2.4,
                      "range": 24.0, "projectile": {"speed": 32.0, "arc": False},
                      "model": "parametric:rifle"},
}

V = sites["vehicles"]  # name -> [x, z]
world["vehicles"] = [
    # --- land ---
    {"pos": V["roadster"],   "profile": "car",  "model": f"{M}/roadster.glb",   "name": "Roadster"},
    {"pos": V["citycar"],    "profile": "car",  "name": "City Car", "color": [0.85, 0.3, 0.25]},
    {"pos": V["buggy"],      "profile": "car",  "model": f"{M}/buggy.glb",      "name": "Dune Buggy"},
    {"pos": V["truck"],      "profile": "car",  "model": f"{M}/truck.glb",      "name": "Utility Truck"},
    {"pos": V["motorcycle"], "profile": "car",  "model": f"{M}/motorcycle.glb", "name": "Motorcycle", "scale": 2.4,
     "seat": [0.0, 0.95, -0.1]},
    {"pos": V["tank"],       "profile": "tank", "model": f"{M}/tank.glb",       "name": "Tank"},
    # --- water ---
    {"pos": V["speedboat"],  "profile": "boat", "model": f"{M}/speedboat.glb",  "name": "Speedboat",
     "seat": [0.0, 0.8, -0.8]},
    {"pos": V["ferry"],      "profile": "boat", "model": f"{M}/ferry.glb",      "name": "Lake Ferry", "scale": 9.0,
     "seat": [0.0, 2.3, 0.0]},
    # --- air ---
    {"pos": V["plane"],      "profile": "plane", "model": f"{M}/plane.glb",     "name": "Bush Plane", "scale": 7.0},
    {"pos": V["helicopter"], "profile": "plane", "model": f"{M}/helicopter.glb", "name": "Helicopter", "scale": 6.0,
     "seat": [0.0, 1.1, 0.4]},
    {"pos": V["glider"],     "profile": "plane", "model": f"{M}/glider.glb",    "name": "Jet Glider", "scale": 6.5},
    # --- wild mounts (tame by riding) ---
    {"pos": V["stag"],    "profile": "horse",  "model": f"{M}/stag.glb",  "name": "Wild Greatstag",
     "stable_id": "stag", "tamed_name": "Greatstag", "scale": 2.6},
    {"pos": V["dragon"],  "profile": "dragon", "name": "Wild Skydrake",
     "stable_id": "dragon", "tamed_name": "Skydrake", "scale": 4.2},
    {"pos": V["serpent"], "profile": "horse",  "model": "animals/easy_Snake.glb", "name": "Wild Mirewyrm",
     "stable_id": "serpent", "tamed_name": "Mirewyrm", "scale": 4.5},
    {"pos": V["raptor"],  "profile": "horse",  "model": "animals/dinosaur_Velociraptor.glb", "name": "Wild Swiftclaw",
     "stable_id": "raptor", "tamed_name": "Swiftclaw", "scale": 3.0},
    {"pos": V["ram"],     "profile": "horse",  "model": f"{M}/ram.glb",   "name": "Wild Frosthorn",
     "stable_id": "ram", "tamed_name": "Frosthorn", "scale": 2.4},
    {"pos": V["beetle"],  "profile": "horse",  "model": f"{M}/beetle.glb", "name": "Wild Bronzeshell",
     "stable_id": "beetle", "tamed_name": "Bronzeshell", "scale": 2.8},
]

B = sites["beacons"]  # id -> {pos:[x,z]}
world["beacons"] = [
    {"id": "forest", "name": "Forest Beacon",    "pos": B["forest"], "flag": "beacon_forest_lit", "shard": "lightshard_forest"},
    {"id": "lake",   "name": "Lake Beacon",      "pos": B["lake"],   "flag": "beacon_lake_lit",   "shard": "lightshard_lake"},
    {"id": "spire",  "name": "Spire Beacon",     "pos": B["spire"],  "flag": "beacon_spire_lit",  "shard": "lightshard_spire"},
    {"id": "frost",  "name": "Frostpeak Beacon", "pos": B["frost"],  "flag": "beacon_frost_lit",  "shard": "lightshard_frost"},
    {"id": "core",   "name": "Spire Core",       "pos": B["core"],   "flag": "world_restored",    "shard": "",
     "y_off": 59.5,   # the stabilize point sits on the tower's TOP floor — climb the interior stairs
     "requires": ["beacon_forest_lit", "beacon_lake_lit", "beacon_spire_lit", "beacon_frost_lit"]},
]

world["regions"] = sites["regions"]

# P0 (QA): interiors only shell on the "vertical" profile — a taper Spire Core is a sealed
# solid and the campaign finale is unreachable. Vertical keeps it the tallest tower AND
# builds the 10 storeys of auto-stairs to the crown.
for c in world["cells"]:
    if c.get("cell") == [19, 15]:
        for s in c.get("structures", []):
            if s.get("interior") and s.get("profile") != "vertical":
                s["profile"] = "vertical"

# Meshy hero skyline piece on the helipad plaza (offset off the helicopter spawn at centre)
for c in world["cells"]:
    if c.get("cell") == [24, 19] and not c.get("landmark"):
        c["landmark"] = {"url": f"{M}/spire_core.glb", "pos": [-5, -5], "collider": "box", "scale": 24.0}

# Meshy statics ship ~1.9m-normalized — scale the beacons up to their intended ~9m presence
# (prop/landmark "scale" is a multiplier, unlike the vehicles' target-length metres)
for c in world["cells"]:
    lm = c.get("landmark")
    if lm and "beacon.glb" in str(lm.get("url", "")):
        lm["scale"] = 4.7
    if lm and "spire_core.glb" in str(lm.get("url", "")):
        lm["scale"] = 24.0
    for p in c.get("props", []) or []:
        if "beacon.glb" in str(p.get("url", "")):
            p["scale"] = 4.7

# the director owns time-of-day + region weather; the sky block only sets the pre-title look
world["sky"] = {"time": "day", "weather": "clear"}

json.dump(world, open("/workspace/world.json", "w"), separators=(",", ":"))
print("merged: cells=%d vehicles=%d beacons=%d regions=%d" % (
    len(world.get("cells", [])), len(world["vehicles"]), len(world["beacons"]), len(world["regions"])))
