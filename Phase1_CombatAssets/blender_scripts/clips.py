"""Animation clip definitions (intent keys).  30 fps.

Conventions (armature space, studs): character faces -Y, left = +X, up = +Z.
Opponent stands ~6-7 studs in front (-Y).  Angles in degrees:
  pelvis_rot / chest_rot / head_rot = (pitch +fwd, roll +left, yaw +left)
  footL/footR = (ball_x, ball_y, yaw, heel_lift, lift)
  sword(...) = grip centre (right fist), blade direction, true-edge direction

Every attack follows PREPARATION -> WEIGHT TRANSFER -> ACCELERATION -> IMPACT
-> FOLLOW-THROUGH -> RECOVERY and carries the markers the Phase 2 combat
code keys off: AttackStart, AttackActive, Impact, RecoveryStart, AttackEnd.
"""
import math

from anim import Clip, sword


def piv(base, yaw, heel, lift=0.0):
    """Foot that turns while its toe tip stays planted (pivot on the toes)."""
    import anim as _a
    bx, by, yaw0 = base[0], base[1], base[2]
    off = _a.TOE_TIP - 0.40
    a0, a1 = math.radians(yaw0), math.radians(yaw)
    tx, ty = bx + off * math.sin(a0), by - off * math.cos(a0)
    return (tx - off * math.sin(a1), ty + off * math.cos(a1), yaw, heel, lift)


def P(*dicts, **kw):
    out = {}
    for d in dicts:
        out.update(d)
    out.update(kw)
    return out


# ==========================================================================
# SWORD - shared stance ("Pflug"-like middle guard, left foot leading)
# ==========================================================================
FEET_GUARD = dict(footL=(0.42, -1.05, 5, 0, 0), footR=(-0.50, 0.60, -50, 0, 0))
GUARD_BODY = dict(pelvis_pos=(0.03, -0.05, -0.27), pelvis_rot=(6, 0, -28), chest_rot=(4, 0, -8),
                  head_rot=(0, 0, 0), elbowL=(0.45, 0.35, -1.0), elbowR=(-0.45, 0.35, -1.0), mode="sword")
GUARD_SWORD = sword(-0.12, -1.05, 2.95, (0.08, -0.80, 0.60), (0.0, -0.6, -0.8))
GUARD = P(GUARD_BODY, FEET_GUARD, GUARD_SWORD)


def sword_idle():
    inhale = P(GUARD, chest_rot=(3.0, 0, -8), pelvis_pos=(0.03, -0.05, -0.26),
               **sword(-0.12, -1.05, 2.965, (0.08, -0.80, 0.60), (0.0, -0.6, -0.8)))
    exhale = P(GUARD, chest_rot=(5.2, 0.4, -8.6), pelvis_pos=(0.035, -0.045, -0.285),
               **sword(-0.11, -1.04, 2.93, (0.10, -0.81, 0.575), (0.0, -0.6, -0.8)))
    mid = P(GUARD, chest_rot=(4.1, -0.3, -7.6), pelvis_pos=(0.025, -0.05, -0.275),
            **sword(-0.125, -1.055, 2.95, (0.065, -0.795, 0.605), (0.0, -0.6, -0.8)))
    keys = [(0, GUARD), (22, inhale), (45, mid), (68, exhale), (90, GUARD)]
    return Clip("Sword_Idle", keys, loop=True, category="SWORD",
                notes="Combat stance loop. Breathing (chest pitch), weight settling and a small point sway.")


# ---- Guard / block --------------------------------------------------------
BLOCK = P(GUARD, pelvis_pos=(0.04, 0.02, -0.31), pelvis_rot=(3, 0, -30), chest_rot=(-1, 1, -14),
          elbowL=(0.6, 0.3, -1.0), elbowR=(-0.7, 0.4, -0.8),
          **sword(-0.30, -1.00, 4.05, (0.62, -0.32, 0.72), (0.0, -1.0, 0.25)))


def sword_block():
    rise = P(GUARD, pelvis_pos=(0.035, -0.02, -0.29), chest_rot=(1, 0.5, -11),
             **sword(-0.22, -1.08, 3.55, (0.40, -0.62, 0.68), (0.0, -0.9, -0.1)))
    held = P(BLOCK, chest_rot=(-0.5, 1, -14.5))
    keys = [(0, GUARD), (4, rise), (8, BLOCK), (18, held), (30, BLOCK)]
    return Clip("Sword_Block", keys, category="SWORD",
                markers={"BlockStart": 0, "BlockActive": 6, "BlockHold": 8, "BlockEnd": 30},
                notes="Raise into a high cover (hilt beside the head, blade slanted across the face). "
                      "Parry window opens at BlockActive; hold the last frame or chain Sword_Block_Hold.")


def sword_block_hold():
    a = P(BLOCK, chest_rot=(-1.4, 1.2, -14.4), **sword(-0.30, -1.00, 4.05, (0.62, -0.32, 0.72), (0.0, -1.0, 0.25)))
    b = P(BLOCK, chest_rot=(-0.4, 0.7, -13.6), pelvis_pos=(0.04, 0.02, -0.325),
          **sword(-0.29, -1.01, 4.02, (0.60, -0.34, 0.72), (0.0, -1.0, 0.25)))
    keys = [(0, a), (30, b), (60, a)]
    return Clip("Sword_Block_Hold", keys, loop=True, category="SWORD", markers={"BlockActive": 0},
                notes="Looping tension while holding the block.")


def sword_block_recover():
    mid = P(GUARD, pelvis_pos=(0.035, -0.03, -0.29), chest_rot=(2, 0.5, -10),
            **sword(-0.20, -1.07, 3.45, (0.30, -0.70, 0.64), (0.0, -0.8, -0.4)))
    keys = [(0, BLOCK), (7, mid), (16, GUARD)]
    return Clip("Sword_Block_Recover", keys, category="SWORD", markers={"BlockEnd": 0, "RecoveryEnd": 16},
                notes="Lower the block back into the middle guard.")


# ---- Attacks --------------------------------------------------------------
def _recovery_clip(attack, name):
    """Standalone recovery = the attack from RecoveryStart to its end."""
    rs = attack.markers["RecoveryStart"]
    first = attack.sample(rs)
    keys = [(0, first)] + [(f - rs, v) for f, v in attack.keys if f > rs]
    return Clip(name, keys, category="SWORD",
                markers={"RecoveryStart": 0, "RecoveryEnd": attack.end - rs},
                notes="Recovery segment of %s as its own clip (use after a hit/miss/parry to control "
                      "the opening window independently)." % attack.name)


def attack_high_right():
    L0 = FEET_GUARD["footL"]
    # 1 preparation: lift into a right-shoulder "vom Tag", weight back, coil
    prep = P(GUARD, pelvis_pos=(0.05, 0.06, -0.29), pelvis_rot=(3, 0, -36), chest_rot=(0, -1, -22),
             elbowR=(-0.8, 0.3, -0.7), elbowL=(0.35, 0.4, -1.0),
             **sword(-0.52, -0.72, 3.75, (-0.15, 0.05, 0.99), (0.0, -1.0, 0.0)))
    wind = P(prep, pelvis_pos=(0.06, 0.13, -0.31), pelvis_rot=(1, 1, -41), chest_rot=(-3, -2, -30),
             **sword(-0.66, -0.32, 3.98, (-0.22, 0.40, 0.89), (0.1, -0.92, 0.4)))
    # 2 weight transfer: front foot starts a short advancing step
    load = P(wind, footL=(0.42, -1.12, 5, 8, 0.05), pelvis_pos=(0.05, 0.08, -0.32), pelvis_rot=(3, 1, -40),
             chest_rot=(-2, -2, -30),
             **sword(-0.68, -0.28, 4.01, (-0.18, 0.48, 0.86), (0.1, -0.87, 0.48)))
    # 3 acceleration: hips unwind first, shoulders follow, blade comes over
    accel = P(load, footL=(0.41, -1.30, 4, 4, 0.10), pelvis_pos=(0.03, -0.12, -0.34), pelvis_rot=(6, 0, -24),
              chest_rot=(4, 0, -12), elbowR=(-0.6, 0.3, -0.9),
              **sword(-0.45, -1.00, 3.92, (0.22, -0.55, 0.80), (0.35, -0.75, -0.55)))
    # 4 impact: diagonal line through the opponent's left shoulder/neck
    impact = P(accel, footL=(0.40, -1.45, 3, 0, 0), pelvis_pos=(0.02, -0.34, -0.38), pelvis_rot=(10, 0, -8),
               chest_rot=(9, 0, 8), elbowR=(-0.4, 0.4, -1.0), elbowL=(0.4, 0.3, -1.0),
               **sword(0.02, -1.62, 3.30, (0.52, -0.80, 0.30), (0.45, 0.0, -0.89)))
    # 5 follow-through: blade continues to low left and is braked by the body
    follow = P(impact, pelvis_pos=(0.02, -0.38, -0.40), pelvis_rot=(12, 1, -2), chest_rot=(12, 2, 16),
               **sword(0.30, -1.30, 2.70, (0.75, -0.40, -0.52), (0.3, 0.3, -0.9)))
    settle = P(follow, pelvis_pos=(0.02, -0.36, -0.39), pelvis_rot=(11, 1, -4), chest_rot=(10, 2, 14),
               **sword(0.36, -1.05, 2.58, (0.60, -0.12, -0.79), (0.2, 0.9, -0.2)))
    # 6 recovery: bring the point back online, then return the front foot
    rec1 = P(settle, pelvis_pos=(0.03, -0.25, -0.35), pelvis_rot=(9, 0, -16), chest_rot=(6, 1, 0),
             **sword(0.05, -1.20, 2.80, (0.30, -0.80, 0.30), (0.2, 0.0, -0.9)))
    rec2 = P(GUARD, footL=(0.41, -1.30, 4, 6, 0.07), pelvis_pos=(0.03, -0.12, -0.30))
    rec3 = P(GUARD, footL=L0)
    keys = [(0, GUARD), (6, prep), (11, wind), (13, load), (16, accel), (18, impact), (22, follow),
            (26, settle), (32, rec1), (38, rec2), (43, rec3), (48, GUARD)]
    return Clip("Sword_Attack_HighRight", keys, category="SWORD",
                markers={"AttackStart": 0, "AttackActive": 15, "Impact": 18, "RecoveryStart": 23, "AttackEnd": 48},
                notes="Oberhau from the right shoulder, diagonal down to the low left. Short advancing step "
                      "with the lead foot; hips lead the shoulders into the cut.")


def attack_high_left():
    L0 = FEET_GUARD["footL"]
    prep = P(GUARD, pelvis_pos=(0.05, 0.03, -0.29), pelvis_rot=(3, 0, -24), chest_rot=(0, 1, 6),
             elbowR=(-0.3, 0.6, -0.9), elbowL=(0.8, 0.3, -0.6),
             **sword(0.30, -0.85, 3.75, (0.18, 0.05, 0.98), (0.0, -1.0, 0.0)))
    wind = P(prep, pelvis_pos=(0.05, 0.10, -0.30), pelvis_rot=(1, -1, -20), chest_rot=(-3, 2, 20),
             **sword(0.52, -0.55, 3.95, (0.25, 0.40, 0.88), (-0.1, -0.9, 0.42)))
    load = P(wind, footL=(0.42, -1.12, 5, 8, 0.05), pelvis_pos=(0.05, 0.07, -0.32), pelvis_rot=(3, -1, -21),
             **sword(0.54, -0.52, 3.98, (0.22, 0.48, 0.85), (-0.1, -0.86, 0.5)))
    accel = P(load, footL=(0.41, -1.30, 4, 4, 0.10), pelvis_pos=(0.03, -0.12, -0.34), pelvis_rot=(6, 0, -30),
              chest_rot=(4, 0, -6), elbowL=(0.8, 0.2, -0.7),
              **sword(0.10, -1.62, 3.80, (-0.20, -0.55, 0.81), (-0.35, -0.75, -0.55)))
    impact = P(accel, footL=(0.40, -1.45, 3, 0, 0), pelvis_pos=(0.02, -0.34, -0.38), pelvis_rot=(10, 0, -38),
               chest_rot=(9, 0, -14), elbowR=(-0.4, 0.4, -1.0), elbowL=(0.4, 0.3, -1.0),
               **sword(-0.25, -1.85, 3.25, (-0.52, -0.80, 0.30), (-0.45, 0.0, -0.89)))
    follow = P(impact, pelvis_pos=(0.02, -0.38, -0.40), pelvis_rot=(12, -1, -44), chest_rot=(12, -2, -18),
               **sword(-0.50, -1.15, 2.72, (-0.75, -0.40, -0.52), (-0.3, 0.3, -0.9)))
    settle = P(follow, pelvis_pos=(0.02, -0.36, -0.39), pelvis_rot=(11, -1, -42), chest_rot=(10, -2, -17),
               **sword(-0.55, -0.92, 2.62, (-0.60, -0.12, -0.79), (-0.2, 0.9, -0.2)))
    rec1 = P(settle, pelvis_pos=(0.03, -0.25, -0.35), pelvis_rot=(9, 0, -34), chest_rot=(6, -1, -12),
             **sword(-0.25, -1.15, 2.80, (-0.20, -0.85, 0.40), (0.0, -0.4, -0.9)))
    rec2 = P(GUARD, footL=(0.41, -1.30, 4, 6, 0.07), pelvis_pos=(0.03, -0.12, -0.30))
    rec3 = P(GUARD, footL=L0)
    keys = [(0, GUARD), (6, prep), (11, wind), (13, load), (16, accel), (18, impact), (22, follow),
            (26, settle), (32, rec1), (38, rec2), (43, rec3), (48, GUARD)]
    return Clip("Sword_Attack_HighLeft", keys, category="SWORD",
                markers={"AttackStart": 0, "AttackActive": 15, "Impact": 18, "RecoveryStart": 23, "AttackEnd": 48},
                notes="Oberhau from the left shoulder, diagonal down to the low right. Hands cross to the left "
                      "during the wind-up; the lead foot advances.")


def attack_horizontal_rl():
    R0 = FEET_GUARD["footR"]
    prep = P(GUARD, pelvis_pos=(0.0, 0.08, -0.29), pelvis_rot=(3, 0, -40), chest_rot=(1, -1, -22),
             elbowR=(-0.9, 0.2, -0.5), elbowL=(0.3, 0.5, -1.0),
             **sword(-0.48, -0.55, 3.45, (-0.35, 0.10, 0.93), (-0.2, -0.97, 0.0)))
    wind = P(prep, pelvis_pos=(-0.04, 0.16, -0.30), pelvis_rot=(2, -2, -46), chest_rot=(0, -2, -34),
             **sword(-0.66, -0.20, 3.55, (-0.55, 0.55, 0.62), (-0.2, -0.9, 0.5)))
    # rear foot pivots on the ball (heel lifts, toes turn) as the hips drive round
    drive = P(wind, footR=piv(FEET_GUARD["footR"], -38, 14), pelvis_pos=(-0.02, 0.05, -0.33), pelvis_rot=(5, -1, -30),
              chest_rot=(3, -1, -20),
              **sword(-0.62, -0.55, 3.55, (-0.60, -0.10, 0.78), (0.0, -0.99, 0.0)))
    impact = P(drive, footR=piv(FEET_GUARD["footR"], -24, 22), pelvis_pos=(0.02, -0.14, -0.36), pelvis_rot=(8, 0, -6),
               chest_rot=(6, 0, 12), elbowR=(-0.4, 0.5, -1.0), elbowL=(0.6, 0.3, -0.9),
               **sword(-0.05, -1.55, 3.40, (0.42, -0.90, 0.10), (0.9, 0.42, 0.0)))
    follow = P(impact, pelvis_pos=(0.04, -0.16, -0.37), pelvis_rot=(8, 1, 6), chest_rot=(7, 1, 24),
               elbowL=(0.9, 0.2, -0.5),
               **sword(0.52, -0.95, 3.20, (0.95, 0.05, -0.28), (0.0, 1.0, 0.0)))
    settle = P(follow, pelvis_rot=(8, 1, 4), chest_rot=(7, 1, 22),
               **sword(0.58, -0.65, 3.05, (0.80, 0.45, -0.38), (-0.45, 0.85, 0.1)))
    rec1 = P(settle, footR=piv(FEET_GUARD["footR"], -38, 10), pelvis_pos=(0.03, -0.10, -0.32), pelvis_rot=(7, 0, -14),
             chest_rot=(5, 0, 2), elbowL=(0.5, 0.35, -1.0),
             **sword(0.15, -1.15, 3.00, (0.30, -0.80, 0.45), (0.0, -0.5, -0.85)))
    rec2 = P(GUARD, footR=R0)
    keys = [(0, GUARD), (6, prep), (11, wind), (15, drive), (18, impact), (22, follow), (26, settle),
            (34, rec1), (44, rec2), (48, GUARD)]
    return Clip("Sword_Attack_HorizontalRL", keys, category="SWORD",
                markers={"AttackStart": 0, "AttackActive": 15, "Impact": 18, "RecoveryStart": 23, "AttackEnd": 48},
                notes="Mittelhau right-to-left. Full-body rotation: rear foot pivots on the ball, hips then "
                      "shoulders unwind; the lead foot stays planted.")


def attack_horizontal_lr():
    L0 = FEET_GUARD["footL"]
    prep = P(GUARD, pelvis_pos=(0.04, 0.0, -0.29), pelvis_rot=(4, 0, -18), chest_rot=(1, 1, 12),
             elbowR=(-0.3, 0.6, -1.0), elbowL=(0.9, 0.2, -0.5),
             **sword(0.28, -0.65, 3.45, (0.35, 0.10, 0.93), (0.2, -0.97, 0.0)))
    wind = P(prep, pelvis_pos=(0.06, -0.02, -0.30), pelvis_rot=(3, 2, -12), chest_rot=(0, 2, 26),
             **sword(0.52, -0.42, 3.50, (0.62, 0.45, 0.64), (0.2, -0.9, 0.5)))
    drive = P(wind, footL=piv(FEET_GUARD["footL"], -6, 10), pelvis_pos=(0.03, -0.06, -0.33), pelvis_rot=(5, 1, -22),
              chest_rot=(3, 1, 14),
              **sword(0.50, -0.75, 3.52, (0.62, -0.15, 0.77), (0.0, -0.99, 0.0)))
    impact = P(drive, footL=piv(FEET_GUARD["footL"], -18, 16), pelvis_pos=(0.0, -0.12, -0.36), pelvis_rot=(8, 0, -42),
               chest_rot=(6, 0, -14), elbowR=(-0.7, 0.3, -0.8), elbowL=(0.4, 0.5, -1.0),
               **sword(-0.25, -1.63, 3.37, (-0.42, -0.90, 0.10), (-0.9, 0.42, 0.0)))
    follow = P(impact, pelvis_pos=(-0.02, -0.10, -0.37), pelvis_rot=(8, -1, -46), chest_rot=(7, -1, -20),
               elbowR=(-0.9, 0.2, -0.5),
               **sword(-0.85, -1.00, 3.15, (-0.95, 0.05, -0.28), (0.0, 1.0, 0.0)))
    settle = P(follow, pelvis_rot=(8, -1, -45), chest_rot=(7, -1, -19),
               **sword(-0.90, -0.78, 3.00, (-0.80, 0.45, -0.38), (0.45, 0.85, 0.1)))
    rec1 = P(settle, footL=piv(FEET_GUARD["footL"], -4, 6), pelvis_pos=(0.02, -0.08, -0.32), pelvis_rot=(7, 0, -36),
             chest_rot=(5, 0, -14), elbowR=(-0.5, 0.35, -1.0),
             **sword(-0.30, -1.10, 3.00, (-0.25, -0.80, 0.50), (0.0, -0.5, -0.85)))
    rec2 = P(GUARD, footL=L0)
    keys = [(0, GUARD), (6, prep), (11, wind), (15, drive), (18, impact), (22, follow), (26, settle),
            (34, rec1), (44, rec2), (48, GUARD)]
    return Clip("Sword_Attack_HorizontalLR", keys, category="SWORD",
                markers={"AttackStart": 0, "AttackActive": 15, "Impact": 18, "RecoveryStart": 23, "AttackEnd": 48},
                notes="Mittelhau left-to-right. Coil to the left, lead foot pivots on the ball as the hips "
                      "turn back to the right; the rear foot anchors.")


def attack_thrust():
    L0 = FEET_GUARD["footL"]
    # chamber: draw the hilt back toward the right hip, point stays on line
    chamber = P(GUARD, pelvis_pos=(0.03, 0.10, -0.29), pelvis_rot=(3, 0, -34), chest_rot=(1, 0, -14),
                elbowR=(-0.7, 0.6, -0.8), elbowL=(0.5, 0.5, -1.0),
                **sword(-0.30, -0.55, 3.05, (0.10, -0.96, 0.25), (0.0, -0.25, -0.97)))
    load = P(chamber, footL=(0.42, -1.10, 5, 10, 0.04), pelvis_pos=(0.03, 0.08, -0.31),
             **sword(-0.30, -0.58, 3.07, (0.09, -0.96, 0.26), (0.0, -0.26, -0.96)))
    # lunge: lead foot steps, hips drive forward, arms extend last
    drive = P(load, footL=(0.41, -1.45, 3, 5, 0.12), pelvis_pos=(0.02, -0.20, -0.35), pelvis_rot=(7, 0, -26),
              chest_rot=(5, 0, -6), elbowR=(-0.4, 0.4, -1.0),
              **sword(-0.18, -1.30, 3.20, (0.05, -0.98, 0.18), (0.0, -0.18, -0.98)))
    impact = P(drive, footL=(0.40, -1.62, 2, 0, 0), pelvis_pos=(0.02, -0.52, -0.42), pelvis_rot=(12, 0, -18),
               chest_rot=(9, 0, 0), elbowR=(-0.3, 0.3, -1.0), elbowL=(0.3, 0.3, -1.0),
               **sword(-0.08, -2.02, 3.35, (0.02, -0.99, 0.12), (0.0, -0.12, -0.99)))
    extend = P(impact, pelvis_pos=(0.02, -0.55, -0.43), chest_rot=(10, 0, 1),
               **sword(-0.07, -2.08, 3.33, (0.02, -0.995, 0.10), (0.0, -0.10, -0.995)))
    withdraw = P(impact, pelvis_pos=(0.02, -0.35, -0.38), pelvis_rot=(9, 0, -22), chest_rot=(6, 0, -6),
                 **sword(-0.15, -1.40, 3.05, (0.06, -0.90, 0.43), (0.0, -0.43, -0.90)))
    rec2 = P(GUARD, footL=(0.41, -1.40, 4, 6, 0.08), pelvis_pos=(0.03, -0.15, -0.31))
    rec3 = P(GUARD, footL=L0)
    keys = [(0, GUARD), (7, chamber), (10, load), (14, drive), (17, impact), (21, extend), (28, withdraw),
            (36, rec2), (42, rec3), (46, GUARD)]
    return Clip("Sword_Attack_Thrust", keys, category="SWORD",
                markers={"AttackStart": 0, "AttackActive": 14, "Impact": 17, "RecoveryStart": 22, "AttackEnd": 46},
                notes="Short chamber, lunging step with the lead foot, hips drive then arms extend. "
                      "Longest reach of the set (~6 studs to the point).")


# ==========================================================================
# REACTIONS (sword in hand)
# ==========================================================================
def follow_pelvis(keys, k=0.95):
    """Carry the hands (sword) with the pelvis when the body is displaced."""
    gy, gz = GUARD["pelvis_pos"][1], GUARD["pelvis_pos"][2]
    out = []
    for f, d in keys:
        d = dict(d)
        dy = d["pelvis_pos"][1] - gy
        dz = d["pelvis_pos"][2] - gz
        x, y, z = d["sword_pos"]
        d["sword_pos"] = (x, y + dy * k, z + dz * 0.8)
        out.append((f, d))
    return out


def hit_torso():
    jolt = P(GUARD, pelvis_pos=(0.03, 0.10, -0.27), pelvis_rot=(2, 0, -30), chest_rot=(-10, 2, -14),
             head_rot=(-8, 3, -4),
             **sword(-0.16, -0.92, 3.10, (0.12, -0.62, 0.78), (0.0, -0.8, -0.6)))
    peak = P(jolt, pelvis_pos=(0.03, 0.13, -0.29), chest_rot=(-12, 3, -16), head_rot=(-10, 4, -6),
             **sword(-0.18, -0.88, 3.12, (0.15, -0.55, 0.82), (0.0, -0.82, -0.55)))
    brace = P(GUARD, pelvis_pos=(0.03, 0.02, -0.30), chest_rot=(8, 0, -9), head_rot=(4, 0, 0),
              **sword(-0.12, -1.00, 2.92, (0.08, -0.82, 0.56), (0.0, -0.56, -0.82)))
    keys = [(0, GUARD), (3, jolt), (6, peak), (13, brace), (24, GUARD)]
    return Clip("React_Hit_Torso", keys, category="REACTIONS",
                markers={"HitStart": 0, "HitPeak": 6, "RecoveryStart": 10, "HitEnd": 24},
                notes="Blow to the chest: upper body driven back, head snaps, then braces forward and resets.")


def hit_arm():
    jolt = P(GUARD, chest_rot=(1, -3, -20), pelvis_rot=(5, 0, -32), elbowR=(-0.9, 0.5, -0.6),
             head_rot=(2, -4, -8),
             **sword(-0.42, -0.80, 2.80, (-0.15, -0.85, 0.50), (-0.2, -0.45, -0.87)))
    peak = P(jolt, chest_rot=(3, -4, -24), head_rot=(4, -6, -10),
             **sword(-0.50, -0.70, 2.62, (-0.35, -0.85, 0.38), (-0.2, -0.3, -0.93)))
    regain = P(GUARD, chest_rot=(4, -1, -12), pelvis_rot=(6, 0, -30),
               **sword(-0.22, -0.98, 2.85, (0.0, -0.83, 0.56), (0.0, -0.56, -0.83)))
    keys = [(0, GUARD), (3, jolt), (7, peak), (15, regain), (28, GUARD)]
    return Clip("React_Hit_Arm", keys, category="REACTIONS",
                markers={"HitStart": 0, "HitPeak": 7, "RecoveryStart": 12, "HitEnd": 28},
                notes="Blow to the right arm: the sword arm is knocked out and down, shoulder pulls back, "
                      "the point drops off line before the guard is regained.")


def hit_heavy():
    L0, R0 = FEET_GUARD["footL"], FEET_GUARD["footR"]
    jolt = P(GUARD, pelvis_pos=(0.03, 0.18, -0.26), pelvis_rot=(-2, 0, -30), chest_rot=(-16, 3, -12),
             head_rot=(-14, 4, -4), elbowR=(-0.6, 0.2, -0.9),
             **sword(-0.20, -0.85, 3.20, (0.25, -0.40, 0.88), (0.0, -0.9, -0.4)))
    # rear foot steps back to catch the weight
    catch = P(jolt, footR=(-0.52, 1.00, -52, 6, 0.10), pelvis_pos=(0.02, 0.38, -0.30), pelvis_rot=(-4, -2, -32),
              chest_rot=(-18, 4, -12), head_rot=(-10, 3, -2),
              **sword(-0.24, -0.70, 3.00, (0.30, -0.35, 0.89), (0.0, -0.9, -0.35)))
    planted = P(catch, footR=(-0.54, 1.10, -54, 0, 0), pelvis_pos=(0.01, 0.46, -0.36), pelvis_rot=(4, -1, -30),
                chest_rot=(-4, 2, -10), head_rot=(-2, 1, 0),
                **sword(-0.20, -0.72, 2.75, (0.15, -0.70, 0.70), (0.0, -0.7, -0.7)))
    # lead foot draws back into a (shifted) stance, then both feet step forward to the original stance
    gather = P(planted, footL=(0.42, -0.70, 5, 6, 0.08), pelvis_pos=(0.02, 0.30, -0.33), chest_rot=(5, 0, -9),
               **sword(-0.15, -0.90, 2.85, (0.10, -0.80, 0.59), (0.0, -0.6, -0.8)))
    gather2 = P(gather, footL=(0.42, -0.65, 5, 0, 0), pelvis_pos=(0.02, 0.25, -0.30))
    step_f = P(gather2, footR=(-0.51, 0.80, -52, 6, 0.08), pelvis_pos=(0.02, 0.12, -0.30))
    step_f2 = P(step_f, footR=R0)
    step_l = P(GUARD, footL=(0.42, -0.85, 5, 6, 0.07), pelvis_pos=(0.03, 0.0, -0.28))
    keys = [(0, GUARD), (3, jolt), (9, catch), (14, planted), (22, gather), (26, gather2), (32, step_f),
            (37, step_f2), (43, step_l), (48, P(GUARD, footL=L0)), (52, GUARD)]
    keys = follow_pelvis(keys)
    return Clip("React_Hit_Heavy", keys, category="REACTIONS",
                markers={"HitStart": 0, "HitPeak": 5, "RecoveryStart": 22, "HitEnd": 52},
                notes="Heavy blow: torso driven back, rear foot steps back to catch balance, then the fighter "
                      "steps back into the original stance (ends where it started - no root drift).")


def stagger():
    L0, R0 = FEET_GUARD["footL"], FEET_GUARD["footR"]
    loose = dict(elbowR=(-0.8, 0.2, -0.8), elbowL=(0.8, 0.2, -0.8))
    k1 = P(GUARD, loose, pelvis_pos=(0.05, 0.20, -0.25), pelvis_rot=(-4, 4, -26), chest_rot=(-14, 6, -16),
           head_rot=(-10, 6, -6), **sword(-0.10, -0.75, 2.95, (0.35, -0.55, 0.76), (0.0, -0.8, -0.6)))
    k2 = P(k1, footR=(-0.55, 1.05, -60, 8, 0.12), pelvis_pos=(0.02, 0.45, -0.29), pelvis_rot=(-6, -5, -34),
           chest_rot=(-10, -6, -8), head_rot=(-6, -5, 2),
           **sword(-0.30, -0.55, 2.55, (0.25, -0.70, 0.67), (0.0, -0.65, -0.76)))
    k3 = P(k2, footR=(-0.58, 1.20, -60, 0, 0), pelvis_pos=(0.0, 0.62, -0.36), pelvis_rot=(2, -6, -30),
           chest_rot=(-2, -5, -10))
    k4 = P(k3, footL=(0.30, -0.25, 12, 10, 0.12), pelvis_pos=(0.06, 0.70, -0.33), pelvis_rot=(-2, 6, -24),
           chest_rot=(-6, 7, -14), head_rot=(-4, 6, -4),
           **sword(-0.05, -0.55, 2.40, (0.30, -0.80, 0.52), (0.0, -0.55, -0.83)))
    k5 = P(k4, footL=(0.34, -0.10, 10, 0, 0), pelvis_pos=(0.05, 0.72, -0.40), pelvis_rot=(8, 2, -26),
           chest_rot=(10, 2, -10), head_rot=(2, 1, 0))
    # regain: settle, raise the guard, walk back into the stance
    k6 = P(k5, pelvis_pos=(0.03, 0.66, -0.36), chest_rot=(6, 0, -9),
           **sword(-0.10, -0.95, 2.85, (0.10, -0.80, 0.59), (0.0, -0.6, -0.8)), elbowR=(-0.45, 0.35, -1.0),
           elbowL=(0.45, 0.35, -1.0))
    k7 = P(k6, footL=(0.40, -0.70, 6, 8, 0.10), pelvis_pos=(0.03, 0.40, -0.32))
    k8 = P(k7, footL=(0.42, -0.85, 5, 0, 0), pelvis_pos=(0.03, 0.30, -0.30))
    k9 = P(k8, footR=(-0.52, 0.85, -54, 8, 0.10), pelvis_pos=(0.03, 0.12, -0.29))
    k10 = P(k9, footR=R0)
    k11 = P(GUARD, footL=(0.42, -0.95, 5, 6, 0.06), pelvis_pos=(0.03, 0.0, -0.28))
    keys = [(0, GUARD), (4, k1), (11, k2), (16, k3), (23, k4), (28, k5), (36, k6), (42, k7), (46, k8),
            (52, k9), (56, k10), (61, k11), (66, P(GUARD, footL=L0)), (70, GUARD)]
    keys = follow_pelvis(keys)
    return Clip("React_Stagger", keys, category="REACTIONS",
                markers={"HitStart": 0, "HitPeak": 11, "Vulnerable": 4, "RecoveryStart": 36, "HitEnd": 70},
                notes="Loss of balance: two stumbling steps back with lateral sway and the guard dropping, "
                      "then the fighter regains the guard and walks back into the original stance.")


# ==========================================================================
# BOW - archer stands side-on (left shoulder toward the target at -Y)
# ==========================================================================
BOW_FEET = dict(footL=(0.18, -0.60, -72, 0, 0), footR=(-0.12, 0.62, -84, 0, 0))
BOW_BODY = dict(mode="bow", pelvis_pos=(0.02, 0.0, -0.12), pelvis_rot=(2, 0, -78), chest_rot=(1, 0, -4.0),
                head_rot=(0, 0, 0), look=1.0)
UP_IDLE = (-0.15, 0.62, 0.77)


def bq(up, x_hint=(1, 0, 0)):
    from anim import weapon_quat
    from mathutils import Vector
    return tuple(weapon_quat(Vector(up), Vector(x_hint)))


BOW_IDLE = P(BOW_BODY, BOW_FEET, bow_pos=(-0.55, -0.72, 2.60), bow_rot=bq(UP_IDLE, (1, 0, 0.2)),
             elbowL=(-0.2, 0.4, -1.0), elbowR=(-0.3, 0.2, -1.0),
             rh_blend=1.0, rh_free=(-0.25, 0.82, 2.10), rh_dir=(0, 0, -1), draw_pos=(-0.4, -0.7, 3.2),
             arrow="none", string_held=0, arrow_dir=(0, 0, -1), string_vib=0.0, arrow_fly=0.0)
def brace_point(pos, up):
    """World position of the nocking point on the braced (undrawn) string."""
    from anim import weapon_quat
    from mathutils import Vector
    import meshes
    q = weapon_quat(Vector(up), Vector((1, 0, 0)))
    top, _ = meshes.bow_string_points()
    return tuple(Vector(pos) + q.to_matrix() @ Vector((0, top.y, meshes.BOW_NOCK_Z)))


# Draw hand on the string at brace height, bow raised half way ("set")
SET_POS, SET_UP = (-0.55, -1.72, 3.66), (-0.04, -0.25, 0.97)
BOW_SET = P(BOW_IDLE, pelvis_pos=(0.02, 0.0, -0.14), chest_rot=(3, 0, -5.0),
            bow_pos=SET_POS, bow_rot=bq(SET_UP),
            elbowL=(0.0, 0.3, -1.0), elbowR=(-0.3, 0.3, -1.0),
            rh_blend=0.0, draw_pos=brace_point(SET_POS, SET_UP), arrow="nocked", string_held=1)
BOW_FULL = P(BOW_SET, pelvis_pos=(0.02, 0.02, -0.14), chest_rot=(-1, 1, -6.0), head_rot=(4, -2, 0),
             bow_pos=(-0.30, -2.66, 4.50), bow_rot=bq((-0.12, -0.04, 0.99)),
             elbowL=(0.0, 0.25, -1.0), elbowR=(-0.3, 1.0, 0.3),
             draw_pos=(-0.26, -0.32, 4.60))


def bow_idle():
    a = BOW_IDLE
    b = P(BOW_IDLE, chest_rot=(2.2, 0.4, -4.5), pelvis_pos=(0.02, 0.0, -0.135),
          bow_pos=(-0.55, -0.73, 2.58), rh_free=(-0.25, 0.83, 2.08))
    keys = [(0, a), (45, b), (90, a)]
    return Clip("Bow_Idle", keys, loop=True, category="BOW",
                notes="Side-on archer's stance, bow held low in the left hand, lower limb forward, "
                      "right hand relaxed. Breathing loop.")


def bow_nock():
    reach = P(BOW_IDLE, chest_rot=(4, -2, -10.0), rh_free=(0.12, 0.72, 2.72), rh_dir=(0.1, 0.1, -1),
              elbowR=(0.2, 1.0, -0.6), bow_pos=(-0.62, -0.95, 2.70), bow_rot=bq((-0.30, 0.35, 0.89)))
    grab = P(reach, arrow="hand", arrow_dir=(0.05, 0.05, -1))
    pull = P(grab, chest_rot=(2, 0, -6.0), rh_free=(-0.28, 0.30, 3.45), rh_dir=(0, -0.3, -1),
             elbowR=(-0.3, 1.0, -0.3), arrow_dir=(-0.1, -0.35, -0.93),
             bow_pos=(-0.55, -1.40, 3.05), bow_rot=bq((-0.25, 0.05, 0.97)))
    swing = P(pull, rh_free=(-0.35, -0.55, 3.55), rh_dir=(-0.2, -0.8, -0.3), elbowR=(-1.0, 0.5, -0.4),
              arrow_dir=(0.02, -1.0, 0.05), bow_pos=(-0.35, -1.80, 3.40), bow_rot=bq((-0.10, -0.20, 0.97)))
    place = P(BOW_SET, rh_blend=0.35, rh_free=(-0.30, -1.10, 3.60), rh_dir=(0, -1, -0.2), arrow="hand",
              arrow_dir=(-0.01, -1.0, 0.0), string_held=0)
    nocked = P(BOW_SET)
    keys = [(0, BOW_IDLE), (10, reach), (13, grab), (21, pull), (28, swing), (35, place), (39, nocked),
            (46, BOW_SET)]
    return Clip("Bow_Nock", keys, category="BOW",
                markers={"NockStart": 0, "ArrowGrab": 13, "ArrowOnBow": 35, "Nocked": 39, "NockEnd": 46},
                notes="Reach back to the hip quiver, draw an arrow, swing it forward onto the bow hand and "
                      "clip the nock onto the string. Ends in the set position (fingers on the string).")


def bow_draw():
    # bow arm raises and pushes toward the target while the draw hand travels
    # back in a slightly high arc into the anchor under the jaw
    k1 = P(BOW_SET, bow_pos=(-0.33, -2.15, 3.95), bow_rot=bq((-0.11, -0.18, 0.98)), chest_rot=(2, 0.5, -5.5),
           draw_pos=(-0.27, -1.30, 4.05), elbowR=(-0.3, 0.5, -0.8))
    k2 = P(BOW_FULL, bow_pos=(-0.30, -2.58, 4.40), draw_pos=(-0.27, -0.85, 4.55), chest_rot=(0, 0.8, -6.0),
           elbowR=(-0.3, 0.9, 0.1))
    k3 = P(BOW_FULL, draw_pos=(-0.26, -0.45, 4.63))
    keys = [(0, BOW_SET), (8, k1), (17, k2), (24, k3), (28, BOW_FULL)]
    return Clip("Bow_Draw", keys, category="BOW", markers={"DrawStart": 0, "FullDraw": 28},
                notes="Raise and draw in one motion: bow arm extends toward the target, shoulder blades "
                      "close, draw hand arcs back to a jaw anchor. Torso stays upright and side-on.")


def bow_full_draw():
    a = BOW_FULL
    b = P(BOW_FULL, bow_pos=(-0.30, -2.66, 4.49), draw_pos=(-0.26, -0.31, 4.595), chest_rot=(-1.3, 1, -6.0))
    keys = [(0, a), (15, b), (30, a)]
    return Clip("Bow_FullDraw", keys, loop=True, category="BOW", markers={"FullDraw": 0},
                notes="Hold at full draw (looping). Very small strain tremor; posture is bone-stacked so "
                      "it reads as sustainable for a few seconds.")


def bow_aim():
    a = BOW_FULL
    d = dict(pelvis_rot=(2, 0, -78))
    b = P(BOW_FULL, chest_rot=(-2.5, 1, -7.2), bow_pos=(-0.38, -2.65, 4.55), draw_pos=(-0.30, -0.33, 4.62))
    c = P(BOW_FULL, chest_rot=(0.5, 1, -5.2), bow_pos=(-0.24, -2.66, 4.44), draw_pos=(-0.22, -0.31, 4.58))
    keys = [(0, a), (20, b), (40, c), (60, a)]
    return Clip("Bow_Aim", keys, loop=True, category="BOW", markers={"FullDraw": 0},
                notes="Aiming sway at full draw: the whole upper body (not just the arms) tracks a small "
                      "ellipse, anchor stays locked to the jaw.")


BOW_RELEASED = P(BOW_FULL, string_held=0, arrow="flying", draw_pos=(-0.28, -0.06, 4.54), chest_rot=(-1.5, 1.2, -7.0),
                 bow_pos=(-0.30, -2.70, 4.44), bow_rot=bq((-0.12, -0.12, 0.985)), rh_blend=0.0)


def bow_release():
    snap = P(BOW_FULL, string_held=0, arrow="flying", arrow_fly=6.0, draw_pos=(-0.27, -0.16, 4.58),
             bow_pos=(-0.30, -2.71, 4.46), bow_rot=bq((-0.12, -0.10, 0.99)), string_vib=1.0)
    follow = P(BOW_RELEASED, arrow_fly=40.0, string_vib=0.0)
    keys = [(0, P(BOW_FULL, string_held=1, arrow="nocked")), (1, P(snap, arrow_fly=0.0, string_vib=1.0)),
            (3, snap), (8, P(follow, arrow_fly=40.0)), (20, follow)]
    return Clip("Bow_Release", keys, category="BOW",
                markers={"Release": 1, "Recovery": 6, "ReleaseEnd": 20},
                notes="Fingers relax off the string; the draw hand slides back along the jaw/neck line as "
                      "back tension releases. Bow arm stays on target with only a small forward drop.")


def bow_lower():
    rel = P(BOW_RELEASED, arrow="none")
    drop = P(rel, chest_rot=(1, 0.8, -5.0), draw_pos=(-0.50, -0.55, 3.70), elbowR=(-0.4, 0.4, -0.9),
             bow_pos=(-0.36, -2.40, 4.05), bow_rot=bq((-0.11, 0.0, 0.99)))
    mid = P(drop, bow_pos=(-0.45, -1.80, 3.40), bow_rot=bq((-0.12, 0.25, 0.96)), rh_blend=0.9,
            rh_free=(-0.35, 0.80, 2.85), elbowR=(-0.3, 0.2, -1.0), elbowL=(-0.1, 0.35, -1.0))
    keys = [(0, rel), (7, drop), (16, mid), (26, BOW_IDLE), (30, BOW_IDLE)]
    return Clip("Bow_Lower", keys, category="BOW", markers={"LowerStart": 0, "LowerEnd": 30},
                notes="Relax out of the shot: bow lowers to the ready position, draw hand drops to the side.")


def all_clips():
    clips = [sword_idle(), sword_block(), sword_block_hold(), sword_block_recover()]
    attacks = [attack_high_right(), attack_high_left(), attack_horizontal_rl(), attack_horizontal_lr(), attack_thrust()]
    clips += attacks
    for a in attacks:
        clips.append(_recovery_clip(a, a.name.replace("Sword_Attack_", "Sword_Recovery_")))
    clips += [hit_torso(), hit_arm(), hit_heavy(), stagger()]
    clips += [bow_idle(), bow_nock(), bow_draw(), bow_full_draw(), bow_aim(), bow_release(), bow_lower()]
    return clips
