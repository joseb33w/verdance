# Goal
Re-sync VERDANCE to the latest godot-tmpl-rpg engine (batch fixes: swim depth, point-and-go
vehicle steering, rider seat plausibility band, direct-hit melee, enemy scale-cap + camera-near
fade, GLB fetch retry / neutral-gray placeholders, GLB cache 48 + FAR_CAP 96 mobile-OOM headroom,
MIN_STOREY interior reconcile, skeleton-aware avatar seating, poll-JSON hardening) while keeping
VERDANCE's own layer (director, HUD relayout, hit-spark, char-height helper, skel-span mount
sizing, enemy->main damage fallback, scatter mesh-xform bake). Fix game-side issues: drop the
pinned region label (keep the fading "Entering X" toast), make the Spire Core finale reachable,
confirm Supabase saves round-trip. Re-verify and redeploy the preview.

# Files to touch
main.gd, vehicle.gd, enemy.gd, chunk_manager.gd, area_builder.gd, build_structure.gd (engine
overlay + re-integration), verdance.gd (region label), world.json (finale, only if verification
shows it unreachable), tools/.gdignore, docs/.gdignore.

# Verification approach
qgcheck winnability gate; headless smoke verify (boot + frames); in-engine targeted checks
(spire door + stairs reachability, melee direct-hit delta + spark, mount seat above the back
line, vehicle point-and-go turn, swim trigger); live Supabase RPC round-trip (done: 204/200,
cross-device isolated); redeploy preview; PR + merge.

# Out of scope
New content/areas, art changes, multiplayer, authoritative server.
