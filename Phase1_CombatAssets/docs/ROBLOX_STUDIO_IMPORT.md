# Getting Phase 1 into Roblox Studio: step by step

This guide takes the files in `export/fbx/` and `textures/` into Studio. At the end you'll have:

1. an animatable R15 rig that holds the sword and bow correctly,
2. all 25 animations imported, with their combat events, and published,
3. standalone weapon and arrow models for later use (pickups, battlefield arrows).

> Studio renames buttons fairly often. If a label here doesn't match your Studio exactly, look for
> the equivalent. The *order* of the steps and the *settings values* are what matter.

---

## 0. What to import

| File | Use it for |
|---|---|
| `R15_CombatRig_Armed.fbx` | **Start here.** R15 rig + body + sword bound to `SwordHandle` + bow bound to `BowHandle`. Studio builds the weapon joints for you. |
| `R15_CombatRig.fbx` | The same rig without weapons (fallback, or for unarmed use) |
| `ANIM_<clip>.fbx` (25 files) | One animation each, imported through the Animation Editor |
| `Sword_TwoHanded.fbx`, `Bow_Longbow.fbx` | Standalone weapons (world props, later equip scripts) |
| `Arrow*.fbx` / `Arrow*_Battlefield.fbx` | Arrows. Use `_Battlefield` (1 mesh, 1 material) when spawning many. |
| `textures/*.png` | SurfaceAppearance maps: `Sword_*`, `Bow_*`, `Arrow_*` × Color/Normal/Roughness/Metalness |

**Expected sizes.** Check these after every import; they tell you the unit setting is right.

| Model | Size in studs |
|---|---|
| Character | **5.4** tall |
| Sword | **3.9** long |
| Bow | **5.5** long |
| Arrow | **2.7** long |

Why the check matters: the FBX files declare *centimetres*, but the numbers inside are *studs*.
If Studio shows the character at about 0.05 or 540 studs, fix the unit (step 1.3).

---

## 1. Import the armed rig

1. Open a **Baseplate** place. On the **Avatar** tab choose **Import 3D** (also under
   *File → Import 3D*), then pick `R15_CombatRig_Armed.fbx`.
2. In the **3D Importer** preview window, check that the character stands upright and faces
   away from the default camera, with the sword in the right hand.
3. **Settings**, under *File General*:
   - **File Dimensions / Scale unit: Studs.** Check the dimensions readout: it should say about
     5.4 tall. If it doesn't, change the unit until it does.
   - **Set Pivot to Origin: on.**
   - **Merge meshes: off.** You need separate parts.
4. **Settings**, under *Rig General*:
   - **Rig type: R15.** If validation complains about the two extra parts (`SwordHandle`,
     `BowHandle`), choose **Custom** instead. The joints are created the same way.
   - Leave **Rig Scale** at default.
5. Leave the *Geometry / Textures* settings at default. Warnings about the non-body parts are
   fine. Click **Import**.
6. **Verify in the Explorer.** You should see a Model containing:
   - `Humanoid`
   - `HumanoidRootPart`
   - 15 body MeshParts: `Head`, `UpperTorso`, `LowerTorso`, `LeftUpperArm` … `RightFoot`
     (the `_Geo` suffix is stripped)
   - **`SwordHandle`** and **`BowHandle`** MeshParts
   - a **Motor6D** inside each part. Each joint's `Part1` is the part it sits in; its `Part0` is
     the parent part. For example, the Motor6D in `SwordHandle` has `Part0 = RightHand` and
     `Part1 = SwordHandle`.
7. Rename the model **`CombatRig`**, and make sure only `HumanoidRootPart` is **Anchored**.
8. **Feet on the ground.** Put the rig on the baseplate. If the feet float or sink, adjust
   `Humanoid.HipHeight` until the soles just touch. The animations keep the feet planted relative
   to that height.
9. **Weapon display.** `BowHandle` and `SwordHandle` are both visible in every pose. For clean
   previews, set `Transparency = 1` on the weapon you aren't using. The sword clips animate
   `SwordHandle`; the bow clips animate `BowHandle`.

**If the weapon parts or joints didn't get created** (older importer versions):

1. Import `R15_CombatRig.fbx` instead.
2. Import `Sword_TwoHanded.fbx` separately (step 4) and union or weld its four parts into one
   part named `SwordHandle`.
3. Add a `Motor6D` inside `SwordHandle` with `Part0 = RightHand`, `Part1 = SwordHandle`, and
   `C0` from `docs/attachments.json` → `sword.motor6d.C0_rest`:
   `CFrame.new(0, -0.01, 0, 0, 0, -1, 1, 0, 0, 0, -1, 0)`.
   - Set `C1` to the grip's position **inside the sword part**. Once the parts are merged, the
     part's centre is the middle of its bounding box, which sits 1.181 studs up the blade from the
     grip. So `C1 = CFrame.new(0, -1.181, 0)`.
4. Do the same for the bow on `LeftHand`, using `C0` from `bow.motor6d.C0_rest`:
   `CFrame.new(0, -0.01, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)`.
   - For `C1`, the bow's bounding-box centre sits 0.261 studs from the grip, toward the string.
     So `C1` is a 0.261-stud offset along the part's Z axis, pointing from the centre back to the
     grip, i.e. away from the string.
5. If the blade then points backward or mirrored, multiply `C0` by `CFrame.Angles(0, math.pi, 0)`.
   The armed-rig path avoids this guesswork, which is why it's the recommended route.

---

## 2. Textures (SurfaceAppearance)

The importer usually only brings in the colour map. For full PBR:

1. Upload the 12 PNGs: **Asset Manager → Bulk Import**, or *Import 3D* for the images. Each
   becomes an image asset ID.
2. Under `CombatRig.SwordHandle`, add a **SurfaceAppearance** and set:
   - `ColorMap` ← Sword_ColorMap
   - `NormalMap` ← Sword_NormalMap
   - `RoughnessMap` ← Sword_RoughnessMap
   - `MetalnessMap` ← Sword_MetalnessMap
   - `AlphaMode` = Overlay
3. Do the same on `BowHandle` with the `Bow_*` maps.
4. Arrows use the `Arrow_*` maps. All three variants share one atlas, so one SurfaceAppearance
   setup works for every arrow.
5. Note: SurfaceAppearance **cannot be changed by scripts at runtime**. Put it in the assets now.
   Maps are ≤ 1024 px, which is Roblox's limit.

---

## 3. Import the animations

Repeat for each `ANIM_*.fbx`. Start with `Sword_Idle` to prove the pipeline.

1. **Avatar tab → Animation Editor**, then click the `CombatRig` in the viewport and give the new
   animation the clip name, e.g. `Sword_Attack_HighRight`.
2. In the editor's **⋯ menu → Import → From FBX Animation**, pick `ANIM_Sword_Attack_HighRight.fbx`.
   - The importer matches FBX bones to the rig's parts **by name**. That's why names like
     `SwordHandle` must match exactly.
   - Expect a key on every frame. The clips are baked at 30 fps for exact contacts.
3. **Check the length** in the editor against the table below (1.600 s for HighRight). Then scrub:
   - both hands stay on the grip,
   - the feet stay planted,
   - the sword moves with the hands.
4. **Looping.** Toggle it on for clips marked *Loop: Yes*.
5. **Priority.** Set it as suggested below. Default Roblox movement runs at `Core` / `Idle` /
   `Movement`, so combat actions must sit above it.
6. **Add the events.** FBX files can't carry markers. For each event in the table:
   - move the scrubber to the time,
   - right-click the event track (**Add Animation Event Here**),
   - type the exact event name (e.g. `Impact`). These become `KeyframeMarker`s that Phase 2
     listens for with `AnimationTrack:GetMarkerReachedSignal("Impact")`.
7. **Save, then publish.**
   - **⋯ → Save** stores the KeyframeSequence in `ServerStorage.RBX_ANIMSAVES`.
   - **⋯ → Publish to Roblox** gives an asset ID. Record it next to the clip name (a spreadsheet
     or a ModuleScript table in Phase 2).
   - Publish to the **group** if the game belongs to a group. Otherwise the animations won't play
     in-game.

### Clip table: lengths, loop flags, priorities, events

| Clip | Length | Loop | Suggested priority | Events to add (name @ seconds) |
|---|---|---|---|---|
| Sword_Idle | 3.000 s | Yes | Idle | — |
| Sword_Block | 1.000 s | No | Action | BlockStart @ 0.000, BlockActive @ 0.200, BlockHold @ 0.267, BlockEnd @ 1.000 |
| Sword_Block_Hold | 2.000 s | Yes | Action | BlockActive @ 0.000 |
| Sword_Block_Recover | 0.533 s | No | Action | BlockEnd @ 0.000, RecoveryEnd @ 0.533 |
| Sword_Attack_HighRight | 1.600 s | No | Action | AttackStart @ 0.000, AttackActive @ 0.500, Impact @ 0.600, RecoveryStart @ 0.767, AttackEnd @ 1.600 |
| Sword_Attack_HighLeft | 1.600 s | No | Action | AttackStart @ 0.000, AttackActive @ 0.500, Impact @ 0.600, RecoveryStart @ 0.767, AttackEnd @ 1.600 |
| Sword_Attack_HorizontalRL | 1.600 s | No | Action | AttackStart @ 0.000, AttackActive @ 0.500, Impact @ 0.600, RecoveryStart @ 0.767, AttackEnd @ 1.600 |
| Sword_Attack_HorizontalLR | 1.600 s | No | Action | AttackStart @ 0.000, AttackActive @ 0.500, Impact @ 0.600, RecoveryStart @ 0.767, AttackEnd @ 1.600 |
| Sword_Attack_Thrust | 1.533 s | No | Action | AttackStart @ 0.000, AttackActive @ 0.467, Impact @ 0.567, RecoveryStart @ 0.733, AttackEnd @ 1.533 |
| Sword_Recovery_HighRight | 0.833 s | No | Action | RecoveryStart @ 0.000, RecoveryEnd @ 0.833 |
| Sword_Recovery_HighLeft | 0.833 s | No | Action | RecoveryStart @ 0.000, RecoveryEnd @ 0.833 |
| Sword_Recovery_HorizontalRL | 0.833 s | No | Action | RecoveryStart @ 0.000, RecoveryEnd @ 0.833 |
| Sword_Recovery_HorizontalLR | 0.833 s | No | Action | RecoveryStart @ 0.000, RecoveryEnd @ 0.833 |
| Sword_Recovery_Thrust | 0.800 s | No | Action | RecoveryStart @ 0.000, RecoveryEnd @ 0.800 |
| React_Hit_Torso | 0.800 s | No | Action2 | HitStart @ 0.000, HitPeak @ 0.200, RecoveryStart @ 0.333, HitEnd @ 0.800 |
| React_Hit_Arm | 0.933 s | No | Action2 | HitStart @ 0.000, HitPeak @ 0.233, RecoveryStart @ 0.400, HitEnd @ 0.933 |
| React_Hit_Heavy | 1.733 s | No | Action2 | HitStart @ 0.000, HitPeak @ 0.167, RecoveryStart @ 0.733, HitEnd @ 1.733 |
| React_Stagger | 2.333 s | No | Action2 | HitStart @ 0.000, Vulnerable @ 0.133, HitPeak @ 0.367, RecoveryStart @ 1.200, HitEnd @ 2.333 |
| Bow_Idle | 3.000 s | Yes | Idle | — |
| Bow_Nock | 1.533 s | No | Action | NockStart @ 0.000, ArrowGrab @ 0.433, ArrowOnBow @ 1.167, Nocked @ 1.300, NockEnd @ 1.533 |
| Bow_Draw | 0.933 s | No | Action | DrawStart @ 0.000, FullDraw @ 0.933 |
| Bow_FullDraw | 1.000 s | Yes | Action | FullDraw @ 0.000 |
| Bow_Aim | 2.000 s | Yes | Action | FullDraw @ 0.000 |
| Bow_Release | 0.667 s | No | Action | Release @ 0.033, Recovery @ 0.200, ReleaseEnd @ 0.667 |
| Bow_Lower | 1.000 s | No | Action | LowerStart @ 0.000, LowerEnd @ 1.000 |

**What the events mean for Phase 2**

| Event | Meaning |
|---|---|
| `AttackStart` → `AttackActive` | Wind-up. Readable by the opponent; feints and cancels allowed. |
| `AttackActive` → `RecoveryStart` | Hit window. Enable blade hit detection (use `BladeBase` → `BladeTip` from `attachments.json`). |
| `Impact` | The ideal contact frame. Use it for sound, camera shake and hit-reaction sync. |
| `RecoveryStart` → `AttackEnd` | Committed recovery. This is the opening the other fighter can punish. |
| `BlockActive` | The parry/block window opens. |
| `DrawStart` → `FullDraw` | Draw in progress. Drive the bow's string and limbs from `attachments.json › bow.draw_table`. |
| `Release` | Spawn and launch the arrow; snap the string back. |

---

## 4. Standalone weapons and arrows

1. **Import 3D** each of `Sword_TwoHanded.fbx`, `Bow_Longbow.fbx` and `Arrow_Battlefield.fbx`
   (plus the variants), with the same unit setting as the rig. Check the sizes in section 0.
2. **Sword.** It arrives as a Model with `Blade`, `Guard`, `Grip` and `Pommel`. With *Set Pivot
   to Origin* on, the Model's pivot is the **right-hand grip point**, which is the origin used by
   every offset in `attachments.json`. If you add an invisible `Handle` part for a Tool or
   Motor6D, place it at that pivot.
3. **Mesh centres move on import.** Roblox moves every MeshPart's origin to its bounding-box
   centre. **Only the Model pivot keeps the authored origin.** Always measure attachment points
   from the pivot, not from a part's centre.
4. **Bow.** It imports as a skinned mesh with bones `Bow_Root`, `Limb_Upper`, `Limb_Lower` and
   `String_Nock`. Phase 2 moves `String_Nock` back as the draw progresses and rotates the limb
   bones about their local X axis, using the draw table.
5. **Arrows.** The pivot is the nock groove, and the arrow points along **−Z (LookVector)**. So
   `CFrame.lookAt(nockPos, targetPos)` aims it with no extra rotation. Use the `_Battlefield`
   versions for arrows stuck in the ground; each is a single MeshPart.
6. Store the finished models in `ReplicatedStorage/Assets/` (or wherever Phase 2 expects them).

---

## 5. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Rig is tiny or huge | Wrong unit in the importer. Choose the one that gives 5.4 studs tall (the file declares cm with stud values inside). |
| Rig faces backward | Rotate the model 180° about Y. The animations follow the rig, so nothing else changes. |
| Animation imports but the sword doesn't move | The rig has no `SwordHandle` part/Motor6D, or it's named differently. Names must match exactly. |
| Hands don't meet the grip on another avatar | That avatar's joint positions differ (e.g. Classic blocky arms). Use this rig or a similar slim R15 body; retargeting a Classic body will never look right for a two-hander. |
| The animation "fights" something when played in game | The default `Animate` script plays idle and walk at lower priority. Set combat clips to Action or higher, or stop the default tracks while fighting. |
| Feet float or clip in play mode | Adjust `Humanoid.HipHeight`. |
| Colours only, no metal or wear | SurfaceAppearance not set up yet (section 2). |
| Import warns "extra parts / not R15" | Expected with the armed rig. Use Rig type **Custom**; the animation import still maps by name. |

---

## 6. Quick checklist

- [ ] `CombatRig` imported, 5.4 studs tall, 15 body parts + `SwordHandle` + `BowHandle` with Motor6Ds
- [ ] SurfaceAppearance on the weapon parts
- [ ] 25 animations imported, lengths match the table
- [ ] Looping set on the 5 looping clips
- [ ] Priorities set
- [ ] Events added with exact names
- [ ] All animations published (to the group, if the game is group-owned) and their IDs recorded
- [ ] Standalone sword, bow and arrow models imported with correct pivots
