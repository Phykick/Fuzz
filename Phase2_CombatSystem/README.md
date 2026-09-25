# Phase 2: Medieval Combat System (Roblox)

This is a grounded, KCD-inspired combat system for the Phase 1 R15 combat rig. It plays inside Studio right away.

**You don't have to publish any animations.** The 33 animations ship as data (`ReplicatedStorage.Combat.AnimData`), and a
runtime pose driver writes `Motor6D.Transform` itself, so they play for your own avatar, other players and the AI.

---

## Install (about 2 minutes)

1. **Keep your imported `CombatRig` in Workspace.** It's the one made from `R15_CombatRig_Armed.fbx`, and it must
   contain a `Humanoid`, a `HumanoidRootPart` and a `SwordHandle` part.
   - When you press Play, the server clones it into `StarterPlayer.StarterCharacter` (you become the rig).
   - It also uses the clone as the template for sparring partners.
   - The original stays in place as a hittable training mannequin.
2. In Studio, insert the three files from `build/`:

   | File | Right-click this in the Explorer → *Insert from File…* |
   |---|---|
   | `CombatSystem_ReplicatedStorage.rbxmx` | **ReplicatedStorage** |
   | `CombatSystem_ServerScriptService.rbxmx` | **ServerScriptService** |
   | `CombatSystem_StarterPlayerScripts.rbxmx` | **StarterPlayer → StarterPlayerScripts** |

   The result should be `ReplicatedStorage.Combat` (7 modules plus the `AnimData` folder),
   `ServerScriptService.CombatServer` and `StarterPlayer.StarterPlayerScripts.CombatClient`.
3. **Press Play.** The Output window should say `[Combat] Using 'CombatRigTemplate'…`, `[Combat] Server ready.` and
   `[Combat] Client ready.`
4. **Press G** to spawn a sparring partner in front of you.

**Optional:**
- Put an `Arrow` model at `ReplicatedStorage.CombatAssets.Arrow` to use the real arrow mesh (import
  `Arrow_Battlefield.fbx`, pivot at the nock, pointing −Z). Otherwise a simple arrow is built from parts.
- Re-import the updated `R15_CombatRig_Armed.fbx`. Its bow no longer has the string baked into the mesh, because
  the system draws a live string that follows your fingers.

Rojo users: `default.project.json` maps `src/` into the same three places.

---

## Controls

| | Sword | Bow |
|---|---|---|
| **LMB** | Attack from the side shown on the star | Hold: nock, then draw. Release: shoot. |
| **Mouse flick** | Picks the attack side: up-right, up-left, right, left, down = thrust | Aim (crosshair) |
| **F / MMB** | Thrust | – |
| **RMB (hold)** | Block. Press just before a blow lands for a **perfect block** | Let the string down |
| **RMB during your wind-up** | **Feint** (cancel into block) | – |
| **LMB late in recovery** | **Combo** (cancels the rest of the recovery) | – |

Other keys:
- **Q** lock on / off, **Tab** next target
- **1** sword, **2** bow, **Shift** sprint
- **G** spawn a sparring partner (they come back 4 s after dying), **J** toggle partner Spar/Passive, **H** toggle
  the help panel

---

## How a fight works

**Attack timing.** Every attack runs on its baked markers:

```
AttackStart ──(0.50 s wind-up: readable, feint-able)── AttackActive ──(0.27 s hit window)── RecoveryStart ──(0.83 s committed recovery)── AttackEnd
```

A combo may cancel recovery 0.18 s after `RecoveryStart`.

**Hits.** The server sweeps 7 points along the real blade between frames and tests them against the target's
*posed* hitboxes. It uses the same pose math the clients render, so what you see is what hits.
- All five attacks connect between about 3 and 5.4 studs (1–1.8 m). That's verified in `tests/range_test.luau`.
- Damage depends on the body part: head ×1.25, arms ×0.75, legs ×0.8.
- Being hit interrupts the target and plays a reaction (torso, arm, heavy, or stagger on a guard break).

**Blocking.** A block covers ±80° in front of you and becomes solid 0.12 s after you press it.
- **Perfect block** (the blow lands within 0.32 s of pressing): the attacker is parried into a recoil, you gain stamina,
  and your next attack within 1.4 s is a riposte (×1.4 damage).
- **Normal block:** it costs stamina (damage × 0.9). If your stamina runs out, your **guard breaks**: you stagger and
  take 35 % of the damage.

**Stamina** (100) pays for attacks (15–20), feints (7), blocks, sprinting and holding the bow at full draw.
- It regenerates after 0.9 s without spending, and slower while blocking or aiming.
- Under 20 stamina, your attacks are slower and weaker and the bow sways.

**Bow.**
- The full sequence is nock (1.5 s), draw (0.9 s), hold, then release.
- A full-draw arrow flies at about 55 m/s with real gravity.
- Releasing under 35 % draw lets the string down instead of shooting.
- Holding at full draw widens the spread (the crosshair shows it) and drains stamina. At 0 stamina your arms give out
  and the arrow is loosed.
- Arrows stick into the world and into characters. Headshots do ×2 damage.

**Movement.** You move at 7 studs/s in guard with 4-way stepping animations. The playback rate follows your ground speed,
so feet don't skate.
- You can walk while blocking or drawing; the upper-body clips layer over the legs.
- You're committed once an attack starts: you move at 2.5 studs/s during the wind-up and 1.5 studs/s during the swing,
  and turning is limited to 150°/s.

---

## Tuning

Every number lives in `ReplicatedStorage.Combat.Config`:
- stamina costs
- damage and part multipliers
- block and perfect-block windows
- walk speeds per state
- arrow speed, gravity and spread
- AI aggression

Edit it in Studio and press Play.

## Files

| Module | Role |
|---|---|
| `PoseDriver` | Binds any imported R15 rig (reads its C0/C1, detects facing and scale) and turns baked poses into `Motor6D.Transform`, or into posed part frames on the server |
| `CharacterAnimator` | Layers idle, 4-way locomotion and the action clip for one character, from the replicated `Act` attribute |
| `Clips`, `RigData`, `AnimData/*` | Generated from Phase 1 by `Phase1_CombatAssets/blender_scripts/export_roblox.py` |
| `Geometry`, `ArrowModel`, `Config` | Hit tests, arrow visuals, tuning |
| `CombatServer` | Character setup, state machine, stamina, hit detection, blocks, bow ballistics, sparring AI |
| `CombatClient` | Input, lock-on, over-the-shoulder camera, animation playback for everyone, bowstring and arrow visuals, HUD, effects |

## What's verified, and what isn't

- **Verified offline** (`python3 tests/run_tests.py <path-to-luau>`, using the stand-alone Luau runtime):
  - Pose math on a deliberately rotated, scaled rig with random joint frames. Worst joint error: 0.0003 studs.
  - Server-side blade points match the rendered engine path.
  - Attack reach tables.
  - All scripts compile.
- **Not verified:** Studio itself was not available to me, so the in-engine behaviour (camera feel, input edge cases,
  replication timing) is untested.
  - If the Output window shows a `[Combat]` warning, it names the problem (for example, a missing `SwordHandle`).
  - The first thing to check: the rig must be the armed rig from Phase 1.
