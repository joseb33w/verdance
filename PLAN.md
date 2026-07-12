# Goal
Re-sync the engine against the latest published godot-tmpl-rpg starter, rebuild the web
export, run the full QA gate (canonical verify.mjs + qgcheck + finale gate + independent
QA & Game-Feel specialist passes) on the final export, redeploy the preview on this
session's build id, and open a PR.

# Sync finding
File-by-file diff of the latest starter vs the repo shows the repo is a strict SUPERSET:
all 9 differing shared modules (main.gd, chunk_manager.gd, interaction.gd, vehicle.gd,
weather3d.gd, enemy.gd, quest.gd, build_structure.gd, export_presets.cfg) carry repo-side
QA fixes the starter lacks (sticky no-fog, scatter mesh-xform bake, skeleton-span mount
sizing, finale tower lighting, aim assist, responsive HUD relayout, ASCII prompts,
viewport-fit=cover). The only starter-unique code is a dead _hurt_flash ColorRect feeding
a disabled no-op. Overlay therefore adopts NOTHING (a blind overlay would regress shipped
fixes); parity is verified and documented instead. 20 remaining shared modules are
byte-identical.

# Files to touch
PLAN.md, docs/qa_report.md (fresh QA-specialist verdict), docs/gamefeel_report.md
(fresh Game-Feel verdict), plus any P0/P1 fixes those passes demand.

# Verification approach
Pre-import static scans; headless --import + Web nothreads export; tools/finale_gate.gd
(winnable finale slab/stair gate); canonical verify.mjs (boot, frames, pck-size,
placeholder gates, qgcheck winnability); deploy preview at cloud-0wenkpzrifygsnclmgvn
(export + loose world.json/quests.json + streamed meshy models); delegate QA +
Game-Feel specialists against the live preview; remediation loop on any P0; final
verify.mjs re-run on the exact shipped export.

# Out of scope
New regions/quests/content, art-style changes, multiplayer, backend schema changes
(session is scoped no-backend; save RPCs already exist and are untouched).
