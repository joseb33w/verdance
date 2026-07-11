# Goal
Re-sync VERDANCE to the latest godot-tmpl-rpg engine batch (never-one-shot enemy HIT_CAP,
sky {"fog":false} hard-disable, cloth-bone-aware avatar seating + GOGI_HERO_SEAT gate,
rider seat plausibility band 0.72, dedicated DISMOUNT button, swim depth-OR-below gate,
no-op hurt flash, /cloud-<id>/ asset-path self-heal, GOGI_PLACEHOLDER verify gates,
parapet roofs + warm lit interiors) while KEEPING Verdance's own layer (director, HUD
relayout, aim assist, hit spark, skel-span mount sizing, scatter mesh-xform bake,
enemy->main damage fallback). Game-side: kill distance fog, resolve every model on this
build id, Meshy drake for the Skydrake, Structures-specialist re-spec of all 6 enterable
buildings (no cone roofs, roomy lit interiors, finale stairwell to the y=59.5 beacon),
confirm winnability + Supabase save round-trip.

# Files to touch
main.gd, vehicle.gd, enemy.gd, weather3d.gd, area_builder.gd, build_structure.gd (engine
merge), verdance.gd (fog + dismount state for verify), world.json (sky.fog, build-id
normalize, drake model, 6 enterable specs), models/meshy/drake.glb (new).

# Verification approach
qgcheck winnability; smoke verify (boot/frames/pck); targeted playwright suite via
?mode=free + gogi knobs (fog flag, hero seat, on_floor walk, enemy engage + multi-hit +
player damage, stag board + seat gap + DISMOUNT button tap, car drive/steer, boat sail,
swim float, zero placeholders / zero glb 404); live Supabase RPC round-trip + isolation;
QA specialist final gate; redeploy preview cloud-ln4jfbfjx60zaprwslze.

# Out of scope
New regions/quests, multiplayer, authoritative server, art-style changes.
