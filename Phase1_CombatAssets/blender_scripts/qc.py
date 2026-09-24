"""Numeric quality control for every clip.

Checks: IK reach (hands really on the grip / feet really on their targets),
planted-foot sliding, ground penetration (feet, sword tip, bow tip),
weapon-vs-body clipping (capsule test), joint ranges (knee, elbow, wrist,
head), and frame-to-frame angular speed spikes (snapping).
"""
import math

from mathutils import Vector

import anim
import meshes
import rig as R

# body capsules: (bone, start offset along bone, end offset, radius)
CAPSULES = {
    "Head": 0.40, "UpperTorso": 0.34, "LowerTorso": 0.32,
    "LeftUpperLeg": 0.24, "RightUpperLeg": 0.24, "LeftLowerLeg": 0.17, "RightLowerLeg": 0.17,
    "LeftUpperArm": 0.18, "RightUpperArm": 0.18, "LeftLowerArm": 0.13, "RightLowerArm": 0.13,
}
BONE_LEN = {b[0]: (Vector(b[3]) - Vector(b[2])).length for b in R.BONES}


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def bone_seg(pose, name):
    m = pose.mats[name]
    a = m.translation
    b = m @ Vector((0, BONE_LEN[name], 0))
    return a, b


def blade_points(pose):
    pos, rot = pose.info["sword_world"]
    z0 = meshes.SWORD["grip_top"] + meshes.SWORD["guard_h"]
    L = meshes.SWORD["blade_len"]
    return [pos + rot @ Vector((0, 0, z0 + L * t)) for t in [i / 11 for i in range(12)]]


def bow_points(pose):
    pos, rot = pose.info["bow_world"]
    pts = []
    for i in range(-10, 11):
        z = meshes.BOW["half_len"] * i / 10 * 0.98
        pts.append(pos + rot @ Vector((0, meshes.bow_centerline(z), z)))
    return pts


def foot_corners(pose, side):
    m = pose.mats[side + "Foot"]
    d = pose.delta[side + "Foot"]
    a = m.translation
    out = []
    for dx in (-0.16, 0.16):
        for dy in (0.23, -anim.TOE_TIP):   # heel, toe (relative to ankle, rest frame)
            out.append(a + d @ Vector((dx, dy, -R.Z_ANKLE)))
    return out


def analyse(clip, poses):
    rep = dict(name=clip.name, frames=len(poses), ik_arm=0.0, ik_leg=0.0, foot_slide=0.0,
               min_foot_z=9.0, min_weapon_z=9.0, blade_clear=9.0, blade_clear_part="",
               bow_clear=9.0, knee_max=0.0, elbow_max=0.0, wrist_max=0.0, head_rel_max=0.0,
               max_ang_speed=0.0, max_ang_speed_bone="")
    prev_ball = {}
    prev_delta = {}
    for f, pose in poses:
        P = pose.info["P"]
        rep["ik_arm"] = max(rep["ik_arm"], pose.ik_error["LeftArm"], pose.ik_error["RightArm"])
        rep["ik_leg"] = max(rep["ik_leg"], pose.ik_error["LeftLeg"], pose.ik_error["RightLeg"])
        for side, key in (("Left", "footL"), ("Right", "footR")):
            bx, by, yaw, heel, lift = P[key]
            ankle = pose.mats[side + "Foot"].translation
            ball = ankle + pose.delta[side + "Foot"] @ Vector((0, -anim.TOE_TIP, -R.Z_ANKLE))  # toe tip
            planted = lift < 1e-4
            if planted and side in prev_ball and prev_ball[side][1]:
                rep["foot_slide"] = max(rep["foot_slide"], (ball - prev_ball[side][0]).length)
            prev_ball[side] = (ball, planted)
            for c in foot_corners(pose, side):
                rep["min_foot_z"] = min(rep["min_foot_z"], c.z)
        for k in ("Left_knee_deg", "Right_knee_deg"):
            rep["knee_max"] = max(rep["knee_max"], pose.info[k])
        for k in ("Left_elbow_deg", "Right_elbow_deg"):
            rep["elbow_max"] = max(rep["elbow_max"], pose.info[k])
        for k in ("Left_wrist_deg", "Right_wrist_deg"):
            if P["mode"] == "sword" or k.startswith("Left"):
                rep["wrist_max"] = max(rep["wrist_max"], pose.info[k])
        rep["head_rel_max"] = max(rep["head_rel_max"], pose.info["head_rel_deg"])
        segs = {n: bone_seg(pose, n) for n in CAPSULES}
        if P["mode"] == "sword":
            pts = blade_points(pose)
            rep["min_weapon_z"] = min(rep["min_weapon_z"], min(p.z for p in pts))
            for i, p in enumerate(pts):
                for n, r in CAPSULES.items():
                    if "LowerArm" in n and i < 3:
                        continue
                    d = seg_dist(p, *segs[n]) - r - 0.03
                    if d < rep["blade_clear"]:
                        rep["blade_clear"], rep["blade_clear_part"] = d, n
        else:
            pts = bow_points(pose)
            rep["min_weapon_z"] = min(rep["min_weapon_z"], min(p.z for p in pts))
            for i, p in enumerate(pts):
                if 8 <= i <= 12:
                    continue  # grip region inside the bow hand
                for n, r in CAPSULES.items():
                    if n.startswith("Left") and "Arm" in n:
                        continue
                    d = seg_dist(p, *segs[n]) - r - 0.02
                    rep["bow_clear"] = min(rep["bow_clear"], d)
        for n, d in pose.delta.items():
            if n in prev_delta:
                ang = math.degrees((prev_delta[n].inverted() @ d).to_quaternion().angle)
                if ang > rep["max_ang_speed"]:
                    rep["max_ang_speed"], rep["max_ang_speed_bone"] = ang, n
            prev_delta[n] = d
    for k, v in rep.items():
        if isinstance(v, float):
            rep[k] = round(v, 4)
    rep["max_ang_speed_deg_per_s"] = round(rep.pop("max_ang_speed") * anim.FPS, 1)
    flags = []
    if rep["ik_arm"] > 0.01:
        flags.append("hand off grip %.3f" % rep["ik_arm"])
    if rep["ik_leg"] > 0.01:
        flags.append("leg over-extended %.3f" % rep["ik_leg"])
    if rep["foot_slide"] > 0.002:
        flags.append("foot slide %.4f" % rep["foot_slide"])
    if rep["min_foot_z"] < -0.02:
        flags.append("foot below ground %.3f" % rep["min_foot_z"])
    if rep["min_weapon_z"] < 0.03:
        flags.append("weapon in ground %.3f" % rep["min_weapon_z"])
    if rep["blade_clear"] < 0.0:
        flags.append("blade clips %s %.3f" % (rep["blade_clear_part"], rep["blade_clear"]))
    if rep["bow_clear"] < 0.0:
        flags.append("bow clips body %.3f" % rep["bow_clear"])
    if rep["knee_max"] > 125 or rep["elbow_max"] > 150:
        flags.append("joint range")
    if rep["wrist_max"] > 70:
        flags.append("wrist bend %.0f" % rep["wrist_max"])
    rep["flags"] = flags
    return rep
