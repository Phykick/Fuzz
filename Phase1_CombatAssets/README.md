# Medieval Combat: Phase 1 (assets, R15 rig, animations)

Grounded, KCD-inspired combat foundation for Roblox: one two-handed sword, an English longbow,
arrows, an R15 test rig, and 25 R15 combat animations. There is no gameplay code in this phase.

| Path | What |
|---|---|
| `CombatAssets_Phase1.blend` | The organised Blender project (textures packed). Open it and press Play to see the demo. |
| `export/fbx/` | Roblox-ready FBX: rig, sword, bow, arrows, `ANIM_<clip>.fbx` per animation |
| `textures/` | SurfaceAppearance maps (Color / Normal / Roughness / Metalness) |
| `docs/PHASE1_REPORT.md` | **The report**: assets, animations, markers, structure, export settings, TODO |
| `docs/animation_manifest.json` | Clip lengths, loop flags, marker frames and seconds |
| `docs/attachments.json` | Grip origins, Motor6D C0 values, bow draw table, key points |
| `docs/qc_report.md` | Automated QC per clip (IK, foot slide, clipping, joint ranges) |
| `previews/` | Rendered contact sheets (demo + every clip, front & side views) |
| `blender_scripts/` | The generator. `build_all.py` rebuilds everything. |

## Rebuild

```bash
pip install bpy==4.2.0          # or use Blender 4.2+:  blender -b -P blender_scripts/build_all.py
python3 blender_scripts/build_all.py
python3 blender_scripts/render_previews.py all     # optional: QC renders (Cycles CPU)
```

To edit an animation, change its intent keys in `blender_scripts/clips.py` and rebuild. The
solver in `anim.py` handles IK, foot planting and grip locking, and the QC runs automatically.
