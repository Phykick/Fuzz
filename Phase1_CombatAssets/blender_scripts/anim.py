"""Pose solver + keyframe interpolation for the R15 combat animations.

Animations are authored as a small number of *intent* keys (pelvis, chest,
feet, weapon path ...).  For every frame the solver:

  1. interpolates the intent channels with monotone cubic Hermite curves
     (smooth, no overshoot, and a held channel stays EXACTLY still - which is
     what keeps planted feet from sliding),
  2. builds the torso chain (LowerTorso -> UpperTorso -> Head, head keeps its
     eyes on the opponent),
  3. places the feet from a ball-of-foot contact model (heel lift pivots on
     the ball, so a planted toe never slides),
  4. derives hand targets from the WEAPON (both fists wrap the sword grip,
     the bow hand wraps the bow grip, the draw hand hooks the string),
  5. solves arms and legs with analytic two-bone IK + pole vectors,
  6. converts everything to local FK keys on the standard R15 bones.

The output is plain FK on R15 bones, which is what Roblox animation import
needs (no constraints, no custom skeleton).
"""
import math

from mathutils import Matrix, Quaternion, Vector

import rig as R

FPS = 30
TOE_TIP = 0.63  # ankle -> toe tip (forward), studs
OPPONENT_HEAD = Vector((0, -7.0, 4.9))


# --------------------------------------------------------------------------
# small math helpers
# --------------------------------------------------------------------------
def rx(a):
    return Matrix.Rotation(math.radians(a), 3, "X")


def ry(a):
    return Matrix.Rotation(math.radians(a), 3, "Y")


def rz(a):
    return Matrix.Rotation(math.radians(a), 3, "Z")


def body_rot(pitch, roll, yaw):
    """yaw about Z (+ = turn left), then pitch about X (+ = lean forward),
    then roll about Y (+ = lean to the character's left)."""
    return rz(yaw) @ rx(pitch) @ ry(roll)


def perp(v, axis):
    return v - axis * v.dot(axis)


def safe_norm(v, fallback):
    return v.normalized() if v.length > 1e-6 else fallback.normalized()


def frame(a, b):
    """Orthonormal 3x3 with col0 = a, col1 = b orthogonalised, col2 = a x b."""
    a = a.normalized()
    b = safe_norm(perp(b, a), Vector((1, 0, 0)) if abs(a.x) < 0.9 else Vector((0, 1, 0)))
    c = a.cross(b)
    return Matrix(((a.x, b.x, c.x), (a.y, b.y, c.y), (a.z, b.z, c.z)))


def weapon_quat(z_axis, x_hint):
    """Weapon orientation from its +Z axis (blade / upper limb) and a hint
    for +X (true edge for the sword, target side for the bow)."""
    z = z_axis.normalized()
    x = safe_norm(perp(Vector(x_hint), z), Vector((1, 0, 0)))
    y = z.cross(x)
    return Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z))).to_quaternion()


def sword(dx, dy, dz, blade, edge):
    """Key helper: grip position + blade direction + true-edge direction."""
    return {"sword_pos": (dx, dy, dz), "sword_rot": tuple(weapon_quat(Vector(blade), Vector(edge)))}


def two_bone_ik(root, target, la, lb, pole):
    """Returns (mid, end, reach_error)."""
    d_vec = target - root
    d = d_vec.length
    dmax = la + lb - 1e-4
    dmin = abs(la - lb) + 1e-4
    err = max(0.0, d - dmax)
    d = min(max(d, dmin), dmax)
    u = d_vec.normalized()
    q = safe_norm(perp(pole, u), Vector((0, 1, 0)))
    cos_a = (la * la + d * d - lb * lb) / (2 * la * d)
    cos_a = min(1.0, max(-1.0, cos_a))
    sin_a = math.sqrt(1 - cos_a * cos_a)
    mid = root + (u * cos_a + q * sin_a) * la
    end = root + u * d
    return mid, end, err


# --------------------------------------------------------------------------
# interpolation (monotone cubic Hermite, Fritsch-Carlson), per component
# --------------------------------------------------------------------------
def _monotone(ts, ys, t):
    n = len(ts)
    if n == 1 or t <= ts[0]:
        return ys[0]
    if t >= ts[-1]:
        return ys[-1]
    d = [(ys[i + 1] - ys[i]) / (ts[i + 1] - ts[i]) for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        m[i] = 0.0 if d[i - 1] * d[i] <= 0 else (d[i - 1] + d[i]) / 2
    for i in range(n - 1):
        if d[i] == 0:
            m[i] = m[i + 1] = 0.0
        else:
            a, b = m[i] / d[i], m[i + 1] / d[i]
            s = a * a + b * b
            if s > 9:
                tau = 3 / math.sqrt(s)
                m[i], m[i + 1] = tau * a * d[i], tau * b * d[i]
    # clip endpoints: ease in/out of the clip (no velocity at first/last key)
    m[0] = m[-1] = 0.0
    for i in range(n - 1):
        if ts[i] <= t <= ts[i + 1]:
            h = ts[i + 1] - ts[i]
            s = (t - ts[i]) / h
            h00 = 2 * s ** 3 - 3 * s ** 2 + 1
            h10 = s ** 3 - 2 * s ** 2 + s
            h01 = -2 * s ** 3 + 3 * s ** 2
            h11 = s ** 3 - s ** 2
            return h00 * ys[i] + h10 * h * m[i] + h01 * ys[i + 1] + h11 * h * m[i + 1]
    return ys[-1]


DISCRETE = {"mode", "arrow", "string_held"}
QUATS = {"sword_rot", "bow_rot"}


class Clip:
    def __init__(self, name, keys, loop=False, markers=None, category="SWORD", notes=""):
        self.name = name
        self.loop = loop
        self.markers = markers or {}
        self.category = category
        self.notes = notes
        self.keys = sorted(keys, key=lambda k: k[0])
        self.start = self.keys[0][0]
        self.end = self.keys[-1][0]
        self.channels = {}
        for f, vals in self.keys:
            for ch, v in vals.items():
                self.channels.setdefault(ch, []).append((f, v))
        for ch in QUATS:
            if ch in self.channels:  # hemisphere continuity
                fixed, prev = [], None
                for f, q in self.channels[ch]:
                    q = Quaternion(q)
                    if prev is not None and prev.dot(q) < 0:
                        q = -q
                    fixed.append((f, tuple(q)))
                    prev = q
                self.channels[ch] = fixed

    @property
    def length(self):
        return self.end - self.start

    def sample(self, f):
        out = {}
        for ch, kv in self.channels.items():
            if ch in DISCRETE:
                val = kv[0][1]
                for kf, v in kv:
                    if kf <= f + 1e-6:
                        val = v
                out[ch] = val
                continue
            ts = [k[0] for k in kv]
            first = kv[0][1]
            if isinstance(first, (int, float)):
                out[ch] = _monotone(ts, [k[1] for k in kv], f)
            else:
                out[ch] = tuple(_monotone(ts, [k[1][i] for k in kv], f) for i in range(len(first)))
        for ch in QUATS:
            if ch in out:
                out[ch] = Quaternion(out[ch]).normalized()
        return out


# --------------------------------------------------------------------------
# The pose solver
# --------------------------------------------------------------------------
LA_ARM = R.Z_SHOULDER - R.Z_ELBOW
LB_ARM = R.Z_ELBOW - R.Z_WRIST
LA_LEG = R.Z_HIP - R.Z_KNEE
LB_LEG = R.Z_KNEE - R.Z_ANKLE
LEFT_GRIP_OFFSET = -0.30  # left fist centre along the sword grip (studs)

REST_DIR = Vector((0, 0, -1))
ARM_BEND_REST = Vector((0, -1, 0))   # forearm folds forward
LEG_BEND_REST = Vector((0, 1, 0))    # shin folds backward
HAND_Y_REST = Vector((0, 0, -1))     # wrist -> knuckles
THUMB_REST = Vector((0, -1, 0))

DEFAULTS = {
    "pelvis_pos": (0, 0, 0), "pelvis_rot": (0, 0, 0), "chest_rot": (0, 0, 0),
    "head_rot": (0, 0, 0), "look": 1.0,
    "footL": (R.HX, -R.FOOT_BALL, 0, 0, 0), "footR": (-R.HX, -R.FOOT_BALL, 0, 0, 0),
    "elbowL": (0.45, 0.35, -1.0), "elbowR": (-0.45, 0.35, -1.0),
    "mode": "sword",
    "sword_pos": tuple(R.SWORD_REST_POS), "sword_rot": tuple(R.SWORD_REST_FRAME.to_quaternion()),
    "bow_pos": tuple(R.BOW_REST_POS), "bow_rot": tuple(R.BOW_REST_FRAME.to_quaternion()),
    "draw_pos": (-0.6, -0.2, 2.2), "rh_free": (-0.85, 0.0, 2.08), "rh_blend": 1.0,
    "rh_dir": (0, 0, -1), "arrow": "none", "arrow_dir": (0, 0, -1), "string_held": 0,
    "arrow_fly": 0.0, "string_vib": 0.0,
}


def rot_about_pivot(pos, pivot, rot):
    return pivot + rot @ (pos - pivot)


class Pose:
    """Result of solving one frame: armature-space bone matrices + extras."""

    def __init__(self):
        self.mats = {}        # bone -> 4x4 armature-space matrix
        self.delta = {}       # bone -> 3x3 world delta rotation from rest
        self.ik_error = {}
        self.info = {}


def foot_pose(p, side_x):
    bx, by, yaw, heel, lift = p
    # (bx, by) = ball of the foot when flat.  A rigid R15 foot has no toe
    # joint, so heel lift pivots on the toe tip: nothing sinks into the floor.
    ball = Vector((bx, by, 0.0))
    toe = ball + rz(yaw) @ Vector((0, -(TOE_TIP - R.FOOT_BALL), 0))
    d = rz(yaw) @ rx(heel)
    ankle = toe + d @ Vector((0, TOE_TIP, R.Z_ANKLE)) + Vector((0, 0, lift))
    return ankle, d, rz(yaw) @ Vector((0, -1, 0))


def solve(params, rest, state=None):
    if state is None:
        state = {}
    P = dict(DEFAULTS)
    P.update(params)
    pose = Pose()
    RR = {n: m.to_3x3() for n, m in rest.items()}
    head_of = {n: m.translation.copy() for n, m in rest.items()}

    def setb(name, pos, delta):
        pose.delta[name] = delta
        m = (delta @ RR[name]).to_4x4()
        m.translation = pos
        pose.mats[name] = m

    setb("Root", head_of["Root"], Matrix.Identity(3))
    setb("HumanoidRootNode", head_of["HumanoidRootNode"], Matrix.Identity(3))

    # ---- torso chain
    d_pel = body_rot(*P["pelvis_rot"])
    pel_pos = head_of["LowerTorso"] + Vector(P["pelvis_pos"])
    setb("LowerTorso", pel_pos, d_pel)

    def child_pos(parent, child):
        return pel_pos if False else pose.mats[parent] @ (rest[parent].inverted() @ head_of[child])

    ut_pos = child_pos("LowerTorso", "UpperTorso")
    d_chest = d_pel @ body_rot(*P["chest_rot"])
    setb("UpperTorso", ut_pos, d_chest)

    hd_pos = child_pos("UpperTorso", "Head")
    look = OPPONENT_HEAD - (hd_pos + d_chest @ Vector((0, 0, 0.45)))
    yaw_w = math.degrees(math.atan2(look.x, -look.y))
    pitch_w = math.degrees(math.atan2(-look.z, Vector((look.x, look.y)).length)) * 0.6
    d_look = rz(yaw_w) @ rx(pitch_w)
    rel = d_chest.inverted() @ d_look
    q_rel = Quaternion().slerp(rel.to_quaternion(), P["look"])
    d_head = d_chest @ q_rel.to_matrix() @ body_rot(*P["head_rot"])
    setb("Head", hd_pos, d_head)
    pose.info["head_rel_deg"] = math.degrees((d_chest.inverted() @ d_head).to_quaternion().angle)

    # ---- legs
    for side, key in (("Left", "footL"), ("Right", "footR")):
        ankle_t, d_foot, fwd = foot_pose(P[key], None)
        hip = child_pos("LowerTorso", side + "UpperLeg")
        lat = Vector((1, 0, 0)) if side == "Left" else Vector((-1, 0, 0))
        pole = fwd + d_pel @ lat * 0.15
        knee, ankle, err = two_bone_ik(hip, ankle_t, LA_LEG, LB_LEG, pole)
        pose.ik_error[side + "Leg"] = err
        _limb(pose, setb, side + "UpperLeg", side + "LowerLeg", hip, knee, ankle, LEG_BEND_REST, pole)
        setb(side + "Foot", ankle, d_foot)
        pose.info[side + "_knee_deg"] = math.degrees((knee - hip).angle(ankle - knee))

    # ---- weapon frames
    s_q = Quaternion(P["sword_rot"]).to_matrix()
    s_pos = Vector(P["sword_pos"])
    b_q = Quaternion(P["bow_rot"]).to_matrix()
    b_pos = Vector(P["bow_pos"])

    shoulders = {s: child_pos("UpperTorso", s + "UpperArm") for s in ("Left", "Right")}

    def elbow_pole(side):
        return d_chest @ Vector(P["elbow" + side[0]])

    targets = {}
    if state.get("mode") != P["mode"]:
        state.clear()
        state["mode"] = P["mode"]
    if P["mode"] == "sword":
        blade = s_q @ Vector((0, 0, 1))
        edge = s_q @ Vector((1, 0, 0))
        targets["Right"] = ("grip", s_pos, blade, edge, 0)
        targets["Left"] = ("grip", s_pos + blade * LEFT_GRIP_OFFSET, blade, edge, 0)
    else:
        up = b_q @ Vector((0, 0, 1))
        back = b_q @ Vector((0, -1, 0))
        targets["Left"] = ("grip", b_pos, up, back, 0.5)
        targets["Right"] = ("draw", Vector(P["draw_pos"]), None, None, 0.0)

    for side in ("Left", "Right"):
        S = shoulders[side]
        pole = elbow_pole(side)
        kind, G, axis, ref, k = targets[side]
        if side == "Right" and P["mode"] == "bow":
            hand_d, W, E, err = _draw_hand(P, S, pole)
        else:
            hand_d, W, E, err, hy = _grip_hand(S, G, axis, ref, pole, state.get(side))
            state[side] = hy
        pose.ik_error[side + "Arm"] = err
        # forearm pronation follows half of the hand roll
        _limb(pose, setb, side + "UpperArm", side + "LowerArm", S, E, W, ARM_BEND_REST, pole, hand_d=hand_d)
        setb(side + "Hand", W, hand_d)
        pose.info[side + "_elbow_deg"] = math.degrees((E - S).angle(W - E))
        fa = (W - E).normalized()
        pose.info[side + "_wrist_deg"] = math.degrees(fa.angle(hand_d @ HAND_Y_REST))

    # weapon joints: world frames -> deltas relative to their rest frames
    d_sword = s_q @ R.SWORD_REST_FRAME.inverted()
    d_bow = b_q @ R.BOW_REST_FRAME.inverted()
    if P["mode"] == "sword":
        setb("SwordHandle", s_pos, d_sword)
        # bow stays at its rest offset in the left hand
        _attach_rest(pose, setb, rest, "BowHandle", "LeftHand")
    else:
        setb("BowHandle", b_pos, d_bow)
        _attach_rest(pose, setb, rest, "SwordHandle", "RightHand")
    pose.info["sword_world"] = (s_pos, s_q)
    pose.info["bow_world"] = (b_pos, b_q)
    pose.info["P"] = P
    return pose


def _attach_rest(pose, setb, rest, child, parent):
    rel = rest[parent].inverted() @ rest[child]
    m = pose.mats[parent] @ rel
    d = m.to_3x3() @ rest[child].to_3x3().inverted()
    setb(child, m.translation.copy(), d)


def _limb(pose, setb, upper, lower, root, mid, end, bend_rest, pole, hand_d=None):
    du = (mid - root).normalized()
    dl = (end - mid).normalized()
    bend = perp(dl, du)
    if bend.length < 1e-3:
        bend = -perp(pole, du)
    bend = safe_norm(bend, bend_rest)
    hinge = du.cross(bend).normalized()
    hinge_rest = REST_DIR.cross(bend_rest)
    f_rest_u = Matrix((REST_DIR, bend_rest, hinge_rest)).transposed()
    f_pose_u = Matrix((du, bend, hinge)).transposed()
    setb(upper, root, f_pose_u @ f_rest_u.inverted())
    bend_l = hinge.cross(dl)
    f_rest_l = Matrix((REST_DIR, hinge_rest.cross(REST_DIR), hinge_rest)).transposed()
    f_pose_l = Matrix((dl, bend_l, hinge)).transposed()
    d_low = f_pose_l @ f_rest_l.inverted()
    if hand_d is not None:
        # forearm twists half-way toward the hand's roll (pronation / supination)
        h_axis = perp(hand_d @ hinge_rest, dl)
        if h_axis.length > 1e-4:
            ang = hinge.angle(h_axis.normalized())
            if hinge.cross(h_axis).dot(dl) < 0:
                ang = -ang
            # bounded & continuous (sin wraps smoothly through +-180 deg)
            d_low = Matrix.Rotation(0.55 * math.sin(ang), 3, dl) @ d_low
    setb(lower, mid, d_low)


def _hand_delta(hy, thumb):
    f_rest = frame(HAND_Y_REST, THUMB_REST)
    f_pose = frame(hy, thumb)
    return f_pose @ f_rest.inverted()


def _grip_hand(S, G, axis, ref, pole, prev=None):
    """Fist wraps a grip (axis `axis`) at point G.  The thumb/pinky line lies
    along the grip; the hand axis (wrist -> knuckles) follows the forearm,
    projected perpendicular to the grip and tilted back toward the forearm
    like a real diagonal grip.  When the forearm is nearly parallel to the
    grip the direction is ill-defined, so it eases toward the previous frame's
    hand axis (temporal coherence) instead of flipping."""
    ref = safe_norm(perp(ref, axis), Vector((1, 0, 0)))
    E, W, err = two_bone_ik(S, G - ref * R.FIST, LA_ARM, LB_ARM, pole)
    first = prev is None
    if first:
        fa = (W - E).normalized()
        prev = ref if ref.dot(fa) >= 0 else -ref
    hy = prev
    for _ in range(5):
        E, W, err = two_bone_ik(S, G - hy * R.FIST, LA_ARM, LB_ARM, pole)
        fa = (W - E).normalized()
        p = perp(fa, axis)
        if p.length < 1e-4:
            hy = prev
            continue
        c = max(-0.5, min(0.5, fa.dot(axis)))
        target = (p.normalized() + axis * c * 0.8).normalized()
        w = min(1.0, p.length / 0.35)
        hy = prev.slerp(target, w) if prev.dot(target) > -0.95 else target
        hy.normalize()
    # a real wrist cannot re-seat the grip instantly: cap at 30 deg/frame
    if first is False:
        ang = prev.angle(hy) if prev.dot(hy) < 0.99999 else 0.0
        if ang > math.radians(30):
            hy = prev.slerp(hy, math.radians(30) / ang).normalized()
    # the grip must stay across the palm: hand axis >= 60 deg from the grip
    c2 = hy.dot(axis)
    if abs(c2) > 0.5:
        hp = perp(hy, axis)
        if hp.length < 1e-3:
            hp = perp(prev, axis)
        hy = (safe_norm(hp, ref) * 0.866 + axis * math.copysign(0.5, c2)).normalized()
    E, W, err = two_bone_ik(S, G - hy * R.FIST, LA_ARM, LB_ARM, pole)
    return _hand_delta(hy, axis), W, E, err, hy


def _draw_hand(P, S, pole):
    """Right hand in bow mode: blend between hooking the string (draw_pos,
    fingers on the string, straight wrist, thumb down) and a free reach
    target (rh_free, e.g. the arrow at the hip)."""
    blend = P["rh_blend"]
    results = []
    for mode in ("draw", "free"):
        if mode == "draw":
            G = Vector(P["draw_pos"])
            hy = safe_norm(G - S, Vector((0, 0, -1)))
            reach = 0.30
            for _ in range(3):
                E, W, err = two_bone_ik(S, G - hy * reach, LA_ARM, LB_ARM, pole)
                hy = (W - E).normalized()
            thumb = safe_norm(perp(Vector((0, 0, -1)), hy), THUMB_REST)
        else:
            G = Vector(P["rh_free"])
            hy = Vector(P["rh_dir"]).normalized()
            reach = R.FIST
            E, W, err = two_bone_ik(S, G - hy * reach, LA_ARM, LB_ARM, pole)
            fa = (W - E).normalized()
            hy = fa.slerp(hy, 0.5).normalized()
            E, W, err = two_bone_ik(S, G - hy * reach, LA_ARM, LB_ARM, pole)
            thumb = safe_norm(perp(Vector((0, -1, 0.3)), hy), THUMB_REST)
        results.append((G - hy * reach, _hand_delta(hy, thumb)))
    (w0, h0), (w1, h1) = results
    W_t = w0.lerp(w1, blend)
    q = h0.to_quaternion().slerp(h1.to_quaternion(), blend)
    E, W, err = two_bone_ik(S, W_t, LA_ARM, LB_ARM, pole)
    return q.to_matrix(), W, E, err


# --------------------------------------------------------------------------
# pose -> local FK basis
# --------------------------------------------------------------------------
PARENT = {b[0]: b[1] for b in R.BONES}
PARENT["SwordHandle"] = "RightHand"
PARENT["BowHandle"] = "LeftHand"


def local_basis(pose, rest):
    out = {}
    for name, m in pose.mats.items():
        par = PARENT.get(name)
        if par is None:
            rel_rest = rest[name]
            loc = rest[name].inverted() @ m
        else:
            rel_rest = rest[par].inverted() @ rest[name]
            loc = rel_rest.inverted() @ pose.mats[par].inverted() @ m
        out[name] = loc
    return out
