# Phase 1: Combat Assets, R15 Rig & Animations: Report

Everything in this folder is produced by one reproducible script
(`blender_scripts/build_all.py`, Blender 4.2). Numbers below come from the generated
`docs/*.json` files.

Scale: **1 Blender unit = 1 Roblox stud**. The test character is 5.4 studs tall (≈1.80 m), so
real measurements use **3.0 studs per metre**.

---

## 1. Assets created

| Asset | Objects | Tris | Material / textures | Pivot |
|---|---|---|---|---|
| **Two-handed sword** (late-14th/15th c., Oakeshott XVIIIa-style) | `Sword` (root) → `Blade`, `Guard`, `Grip`, `Pommel` + attach empties | ~1.7 k | 1 atlas `M_Sword_Steel_Leather` (1024²): worn forged steel blade, darkened guard/pommel, spiral leather wrap | Centre of the **right-hand grip**, just under the guard |
| **English war longbow** (yew, braced, not drawn) | `Bow_Rig` (armature) → `Bow` (skinned), `String` (separate, skinned) + attach empties | ~1.6 k | 1 atlas `M_Bow_Yew` (1024²): sapwood back / heartwood belly, leather grip, horn nocks, linen string | Centre of the **bow-hand grip** |
| **Arrow** (primary: long bodkin, grey goose) | `Arrow` → `Shaft`, `Arrowhead`, `Fletching`, `Nock` | 224 | 1 atlas `M_Arrow` (512²) shared by all variants | String groove of the nock; points **−Y (= Roblox LookVector)** |
| Arrow variants | `Arrow_BodkinShort` (white fletch), `Arrow_Type16` (barbed head, barred fletch) | 224 / 242 | same atlas | same |
| Battlefield arrows | `*_Battlefield`: each variant merged to **1 mesh, 1 material** for mass spawning | 224–242 | same atlas | same |
| **R15 combat test rig** | `R15_Rig` armature + 15 `*_Geo` rigid parts | ~2 k | flat colours (test mannequin) | Root at the floor, character faces −Y |

Physical sanity check for the sword: **130 cm overall, 97 cm blade, 24 cm grip, ≈2.6 kg, point of
balance 7.9 cm above the guard.** That matches a real two-hander: heavy, but a controllable
point of balance. The blade has a lenticular section with a fuller over the first 42 %, distal
taper (6.8 → 2.2 mm), a slightly dulled edge bevel, and a waisted grip. None of it is chrome:
roughness is 0.35–0.6 and the steel carries grinding scratches and patina.

Bow: 183 cm, D-section limbs, 16 cm brace height. Arrows are 81 cm (32″), with a 6-sided barrelled
shaft, thread bindings, 3 shield-cut vanes with a slight helical cant, and a horn nock.

Textures (Roblox **SurfaceAppearance** ready) are in `textures/`:
`<Asset>_ColorMap.png`, `_NormalMap.png` (OpenGL), `_RoughnessMap.png`, `_MetalnessMap.png`.

## 2. R15 rig

Bone hierarchy is exactly Roblox's skinned R15 spec, plus two weapon joints:

```
Root
└─ HumanoidRootNode
   └─ LowerTorso
      ├─ UpperTorso
      │  ├─ Head
      │  ├─ LeftUpperArm → LeftLowerArm → LeftHand → BowHandle
      │  └─ RightUpperArm → RightLowerArm → RightHand → SwordHandle
      ├─ LeftUpperLeg → LeftLowerLeg → LeftFoot
      └─ RightUpperLeg → RightLowerLeg → RightFoot
```

- Rest pose is an I-pose with arms down, facing −Y in Blender, which exports as facing +Z in the
  FBX as Roblox requires.
- Mesh parts use the `_Geo` suffix. Each is a rigid part, 100 % weighted to its bone.
- **SwordHandle / BowHandle** are weapon joints. In Roblox they become Motor6Ds
  (`RightHand → SwordHandle`, `LeftHand → BowHandle`), so the animations drive the weapon's grip
  angle like a real wrist. A rigid weld would force broken wrists.
- **Why the body isn't Classic blocky:** Classic R15 hands are 1 stud wide, so two of them cover
  0.67 m of grip. A real two-hander grip is 0.24 m. The test body therefore uses Normal-scale
  limb thickness (0.26-stud hands), keeps the R15 part set, hierarchy and joint layout, and
  leaves the skeleton unchanged. The animations are joint rotations and play on any R15 avatar.
  Realistic or Rthro-style bodies will look closest.

## 3. Animations (30 fps)

Every attack follows **preparation → weight transfer → acceleration → impact → follow-through →
recovery**. Each attack is a complete clip that ends back in guard. Its recovery segment is also
exported as its own `Sword_Recovery_*` clip, so Phase 2 can control the opening window on its own.

| Animation | Frames | Length | Loop | Markers (frame) |
|---|---|---|---|---|
| Sword_Idle | 90 | 3.00 s | ✔ | – |
| Sword_Block | 30 | 1.00 s | | BlockStart 0 · BlockActive 6 · BlockHold 8 · BlockEnd 30 |
| Sword_Block_Hold | 60 | 2.00 s | ✔ | BlockActive 0 |
| Sword_Block_Recover | 16 | 0.53 s | | BlockEnd 0 · RecoveryEnd 16 |
| Sword_Attack_HighRight | 48 | 1.60 s | | AttackStart 0 · AttackActive 15 · Impact 18 · RecoveryStart 23 · AttackEnd 48 |
| Sword_Attack_HighLeft | 48 | 1.60 s | | same as above |
| Sword_Attack_HorizontalRL | 48 | 1.60 s | | same as above |
| Sword_Attack_HorizontalLR | 48 | 1.60 s | | same as above |
| Sword_Attack_Thrust | 46 | 1.53 s | | AttackStart 0 · AttackActive 14 · Impact 17 · RecoveryStart 22 · AttackEnd 46 |
| Sword_Recovery_HighRight / HighLeft / HorizontalRL / HorizontalLR | 25 | 0.83 s | | RecoveryStart 0 · RecoveryEnd 25 |
| Sword_Recovery_Thrust | 24 | 0.80 s | | RecoveryStart 0 · RecoveryEnd 24 |
| React_Hit_Torso | 24 | 0.80 s | | HitStart 0 · HitPeak 6 · RecoveryStart 10 · HitEnd 24 |
| React_Hit_Arm | 28 | 0.93 s | | HitStart 0 · HitPeak 7 · RecoveryStart 12 · HitEnd 28 |
| React_Hit_Heavy | 52 | 1.73 s | | HitStart 0 · HitPeak 5 · RecoveryStart 22 · HitEnd 52 |
| React_Stagger | 70 | 2.33 s | | HitStart 0 · Vulnerable 4 · HitPeak 11 · RecoveryStart 36 · HitEnd 70 |
| Bow_Idle | 90 | 3.00 s | ✔ | – |
| Bow_Nock | 46 | 1.53 s | | NockStart 0 · ArrowGrab 13 · ArrowOnBow 35 · Nocked 39 · NockEnd 46 |
| Bow_Draw | 28 | 0.93 s | | DrawStart 0 · FullDraw 28 |
| Bow_FullDraw | 30 | 1.00 s | ✔ | FullDraw 0 |
| Bow_Aim | 60 | 2.00 s | ✔ | FullDraw 0 |
| Bow_Release | 20 | 0.67 s | | Release 1 · Recovery 6 · ReleaseEnd 20 |
| Bow_Lower | 30 | 1.00 s | | LowerStart 0 · LowerEnd 30 |

**Timing design (attacks):** about 0.5 s of readable startup where feints and interrupts are
possible (0 → AttackActive), a 0.27 s hit window (AttackActive → RecoveryStart), and about 0.83 s
of recovery that serves as the punishable opening. Clips chain seamlessly: every sword clip starts
and ends on the same guard pose, and every bow clip starts on the previous clip's last pose. The
exact marker times in seconds are in `docs/animation_manifest.json`.

### How the motion is built (why it doesn't look like arm-only swinging)

Clips are authored as intent keys: pelvis, chest, feet and the weapon path. Each frame is solved
by `anim.py`:

- **Body.** Hips lead and the shoulders follow, the head stays on the opponent, and the knees
  flex to lower the centre of mass.
- **Feet.** A ball-of-foot contact model keeps planted feet exactly still. Heel lifts and pivots
  rotate about the toe, so the foot never sinks into the ground. Steps have a lift arc.
- **Hands.** Both fists stay locked to the weapon grip through analytic two-bone IK. The hand
  orientation follows the forearm across the grip, with a wrist-rate limit and temporal coherence
  so it never snaps.
- **Output.** The result is baked as plain FK keys on the R15 bones.

### Automated QC: all 25 clips pass (`docs/qc_report.md`)

- Hand-on-grip IK error: **0.000** in every clip. Leg IK error: 0.000.
- Planted-foot slide: **≤ 0.001 studs** per frame, and exactly 0 in 21 clips.
- Nothing goes below the ground: feet, sword tip and bow tips all stay above it.
- No blade/body or bow/body intersection (capsule test).
- Joint ranges stay human: knee ≤ 79°, elbow ≤ 145°, wrist ≤ 68°, head turn ≤ 90° (archery).
- No single-frame snaps. The fastest rotation is the sword itself during a cut (≈1,500–2,700°/s),
  which is realistic.
- FBX round-trip: re-importing `ANIM_*.fbx` reproduces bone positions with 0.00000 error.

## 4. Weapon attachment / hand positions (`docs/attachments.json`)

| | Part0 → Part1 | C0 at rest (Roblox CFrame components) | Notes |
|---|---|---|---|
| Sword | `RightHand` → `SwordHandle` | `CFrame.new(0, -0.01, 0, 0,0,-1, 1,0,0, 0,-1,0)` | Sword origin = right-fist grip centre. Left fist sits 0.30 studs toward the pommel. |
| Bow | `LeftHand` → `BowHandle` | `CFrame.new(0, -0.01, 0, 1,0,0, 0,0,1, 0,-1,0)` | Bow origin = grip centre. The arrow rests at (0.055, 0, 0.15) bow-local; the nocking point is 0.15 above the grip. |

- The fist centre is 0.22 studs from the wrist. The files also document key points in the
  weapon's local space (blade base and tip for hitboxes, left-hand grip, arrow rest, nocking
  point, upper and lower nocks) and the Blender → Roblox axis mapping.
- **Bow draw table** (`attachments.json › bow.draw_table`): string pull 0 → 2.4 studs maps to
  limb rotation 0 → ~25°. Phase 2 can drive the `String_Nock` / `Limb_*` bones from it.

## 5. Blender collection structure (`CombatAssets_Phase1.blend`)

```
COMBAT_ASSETS
├── SWORD        Sword (root empty) ─ Blade, Guard, Grip, Pommel,
│                Sword_Attach_RightHand/LeftHand, Sword_BladeBase/Tip
├── BOW          Bow_Rig (armature) ─ Bow, String, Bow_Attach_LeftHand, Bow_ArrowRest, Bow_NockPoint
├── ARROW        Arrow ─ Shaft, Arrowhead, Fletching, Nock;  Arrow_BodkinShort*, Arrow_Type16*
│   └── ARROW_Battlefield   single-mesh versions
├── R15_RIG      R15_Rig + 15 *_Geo parts
├── ANIMATIONS
│   ├── ANIM_SWORD / ANIM_BOW / ANIM_REACTIONS   one ANIM_<clip> node per clip
│   │     (custom props: action, frames, seconds, loop, markers, prop actions)
└── DEMO_SCENE   held sword/bow/arrow instances (linked data), ground, sun, cameras, Opponent_Reference
```

- **Actions:** one per clip, named exactly like the clip, with markers stored as action pose
  markers. Bow clips also have `PROP_BowString_<clip>` and `PROP_Arrow_<clip>`, which drive the
  string, limb flex and arrow in the preview.
- **Demo:** `DEMO_CombatShowcase` (564 frames, 18.8 s) is the active action on `R15_Rig`. It
  plays sword idle → high-right attack → block → recover → thrust → idle, then cuts to bow idle →
  nock → draw → full draw → release → lower. Timeline markers name each clip and event, and the
  cameras cut automatically. Press Play.
- **No default names remain.** There is no `Cube`, `Plane` or `Armature.001`.

## 6. Export settings used (FBX)

| Setting | Value |
|---|---|
| Scene units | Metric, **Unit Scale 0.01** (1 BU = 1 stud) |
| Apply Scalings | **FBX Units Scale**, Apply Unit ✔, Use Space Transform ✔ |
| Forward / Up | **−Z Forward, Y Up** (character faces +Z in the FBX, per Roblox's spec) |
| Armature | Add Leaf Bones ✘, Only Deform Bones ✘ (all bones are real joints), Primary Y / Secondary X |
| Geometry | Smoothing: Face, Apply Modifiers ✔ |
| Animation | Bake ✔, All Bones ✔, NLA ✘, All Actions ✘, Force Start/End ✔, Step 1, Simplify **0** (exact) |
| Textures | Weapons: Path Mode **Copy + Embed Textures**. Animation files contain no textures. |

Files in `export/fbx/`:
- `R15_CombatRig.fbx`: rig and body in rest pose.
- `R15_CombatRig_Armed.fbx`: the same rig with the sword and bow bound to `SwordHandle` / `BowHandle`, so Studio creates the weapon Motor6Ds itself. Use this one. The step-by-step import is in `docs/ROBLOX_STUDIO_IMPORT.md`.
- `ANIM_<clip>.fbx` × 25: rig and body with one take, named after the clip.
- `Sword_TwoHanded.fbx`, `Bow_Longbow.fbx`.
- `Arrow*.fbx` and `Arrow*_Battlefield.fbx`.

## 7. Still to do before / during Roblox Studio integration

1. **Test the import in Studio.** This build could not run Studio.
   - Import `R15_CombatRig.fbx` with the Avatar/3D importer and confirm it stands 5.4 studs tall,
     faces −Z and has all 15 parts plus the two handle joints. If the scale is off, set the
     importer's file unit or scale so 1 unit = 1 stud.
   - Then use Animation Editor → Import → *From FBX Animation* for each `ANIM_*.fbx`, and publish.
2. **Re-create markers in Studio.** FBX cannot carry animation events. Add them as
   `KeyframeMarker`s with the Animation Editor, using the names and times in
   `animation_manifest.json`, or have Phase 2 read the times from the manifest.
3. **Assemble the weapons in Studio.**
   - Import the weapon FBXs and create the `SwordHandle` / `BowHandle` root parts at the documented
     grip origins (MeshParts are re-centred to their bounding boxes on import).
   - Weld the components to the handle part.
   - Add the Motor6Ds with the C0 values above, and apply the texture maps as SurfaceAppearance.
4. **Decide the avatar body.** Animations are joint rotations and work on any R15, but a slim or
   realistic body will match the hand placement best. Classic blocky hands will visually overlap
   on the grip.
5. **Script the bow (Phase 2).** String and limb deformation and arrow flight are previewed in
   Blender but are not part of R15 animation tracks. Drive the bow bones from the draw table, and
   spawn and launch arrows at the `Release` marker.
6. **Content not in scope for this phase:**
   - quiver and scabbard props (the nock animation reaches to the right hip)
   - guard-stance locomotion (walk, strafe and turn in guard)
   - directional blocks (only one high block exists)
   - feint/cancel variants and a "blocked / bounced off" recoil
   - death and knockdown
   - the transition clips between sword and bow (draw/sheathe, sling bow)
   - hand poses (R15 hands have no finger joints)
