"""R15 combat test rig.

Bone names and hierarchy follow Roblox's R15 skinned-character spec:

    Root
    └── HumanoidRootNode
        └── LowerTorso
            ├── UpperTorso
            │   ├── Head
            │   ├── LeftUpperArm  → LeftLowerArm  → LeftHand  → BowHandle
            │   └── RightUpperArm → RightLowerArm → RightHand → SwordHandle
            ├── LeftUpperLeg  → LeftLowerLeg  → LeftFoot
            └── RightUpperLeg → RightLowerLeg → RightFoot

SwordHandle / BowHandle are weapon joints (become Motor6Ds RightHand→SwordHandle
and LeftHand→BowHandle in Roblox) so the grip can be animated like a real
wrist instead of a rigid weld.

Character faces -Y in Blender (= +Z in the exported FBX, the Roblox
requirement).  Rest pose is an I-pose (arms straight down).  1 BU = 1 stud.
"""
import math

import bpy
from mathutils import Matrix, Vector

import meshes

# joint positions (head of each bone) and tails, armature space
SX, HX = 0.85, 0.35  # shoulder / hip half-spacing
Z_ROOT, Z_WAIST, Z_NECK, Z_TOP = 2.65, 2.85, 4.45, 5.40
Z_SHOULDER, Z_ELBOW, Z_WRIST, Z_FINGER = 4.20, 3.22, 2.30, 1.88
Z_HIP, Z_KNEE, Z_ANKLE = 2.55, 1.40, 0.30
FIST = 0.22          # wrist -> centre of the fist (grip axis), studs
FOOT_BALL = 0.40     # ankle -> ball of the foot (forward), studs

BONES = [
    # name, parent, head, tail
    ("Root", None, (0, 0, 0), (0, 0, 0.6)),
    ("HumanoidRootNode", "Root", (0, 0, Z_ROOT), (0, 0, Z_ROOT + 0.5)),
    ("LowerTorso", "HumanoidRootNode", (0, 0, Z_ROOT), (0, 0, Z_WAIST)),
    ("UpperTorso", "LowerTorso", (0, 0, Z_WAIST), (0, 0, Z_NECK)),
    ("Head", "UpperTorso", (0, 0, Z_NECK), (0, 0, Z_TOP)),
    ("LeftUpperArm", "UpperTorso", (SX, 0, Z_SHOULDER), (SX, 0, Z_ELBOW)),
    ("LeftLowerArm", "LeftUpperArm", (SX, 0, Z_ELBOW), (SX, 0, Z_WRIST)),
    ("LeftHand", "LeftLowerArm", (SX, 0, Z_WRIST), (SX, 0, Z_FINGER)),
    ("RightUpperArm", "UpperTorso", (-SX, 0, Z_SHOULDER), (-SX, 0, Z_ELBOW)),
    ("RightLowerArm", "RightUpperArm", (-SX, 0, Z_ELBOW), (-SX, 0, Z_WRIST)),
    ("RightHand", "RightLowerArm", (-SX, 0, Z_WRIST), (-SX, 0, Z_FINGER)),
    ("LeftUpperLeg", "LowerTorso", (HX, 0, Z_HIP), (HX, 0, Z_KNEE)),
    ("LeftLowerLeg", "LeftUpperLeg", (HX, 0, Z_KNEE), (HX, 0, Z_ANKLE)),
    ("LeftFoot", "LeftLowerLeg", (HX, 0, Z_ANKLE), (HX, -FOOT_BALL, 0.02)),
    ("RightUpperLeg", "LowerTorso", (-HX, 0, Z_HIP), (-HX, 0, Z_KNEE)),
    ("RightLowerLeg", "RightUpperLeg", (-HX, 0, Z_KNEE), (-HX, 0, Z_ANKLE)),
    ("RightFoot", "RightLowerLeg", (-HX, 0, Z_ANKLE), (-HX, -FOOT_BALL, 0.02)),
]

R15_PARTS = [b[0] for b in BONES[2:]]

# Weapon frames at rest (hanging arms).  Columns = weapon local X, Y, Z axes.
# Sword: blade (+Z) points forward, true edge (+X) down, in the right fist.
SWORD_REST_FRAME = Matrix(((0, 1, 0), (0, 0, -1), (-1, 0, 0)))
SWORD_REST_POS = Vector((-SX, 0, Z_WRIST - FIST))
# Bow: carried in the left fist, upper limb (+Z) forward, string (+Y) up.
BOW_REST_FRAME = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
BOW_REST_POS = Vector((SX, 0, Z_WRIST - FIST))


def _frame_cols(m):
    return [Vector((m[0][i], m[1][i], m[2][i])) for i in range(3)]


def build_armature(name="R15_Rig"):
    arm = bpy.data.armatures.new(name)
    arm.display_type = "OCTAHEDRAL"
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    for (n, parent, h, t) in BONES:
        b = eb.new(n)
        b.head, b.tail = Vector(h), Vector(t)
        # consistent rolls: local Z points backwards (+Y) for vertical bones
        b.align_roll(Vector((0, 1, 0)) if abs(b.vector.normalized().z) > 0.7 else Vector((0, 0, 1)))
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
    for (n, parent, pos, frame, length) in (
            ("SwordHandle", "RightHand", SWORD_REST_POS, SWORD_REST_FRAME, 0.6),
            ("BowHandle", "LeftHand", BOW_REST_POS, BOW_REST_FRAME, 0.6)):
        x, y, z = _frame_cols(frame)
        b = eb.new(n)
        b.head = pos
        b.tail = pos + z * length      # bone Y axis = weapon +Z
        b.align_roll(x)                # bone X axis = weapon +X
        b.parent = eb[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for b in arm.bones:
        b.use_deform = True
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def rest_matrices(rig):
    return {b.name: b.matrix_local.copy() for b in rig.data.bones}


# --------------------------------------------------------------------------
# Body meshes (one rigid mesh per R15 part, 100% weighted to its bone)
# --------------------------------------------------------------------------
def build_body(rig):
    skin = meshes.flat_material("M_Rig_Skin", (0.60, 0.46, 0.38), 0.6)
    jack = meshes.flat_material("M_Rig_Gambeson", (0.34, 0.28, 0.20), 0.85)
    belt = meshes.flat_material("M_Rig_Belt", (0.16, 0.11, 0.07), 0.6)
    hose = meshes.flat_material("M_Rig_Hose", (0.20, 0.23, 0.19), 0.85)
    boot = meshes.flat_material("M_Rig_Boots", (0.14, 0.09, 0.06), 0.55)

    parts = {}
    tb = meshes.tapered_box
    parts["Head"] = tb("Head_Geo", Z_TOP, Z_NECK + 0.18, (0.72, 0.80), (0.62, 0.74), mat=skin, bevel=0.2)
    meshes.add_box_to(parts["Head"], (0, -0.40, 4.95), (0.12, 0.14, 0.22), bevel=0.04)      # nose
    meshes.add_box_to(parts["Head"], (0, 0.02, Z_NECK + 0.12), (0.34, 0.34, 0.26), bevel=0.05)  # neck
    parts["UpperTorso"] = tb("UpperTorso_Geo", Z_NECK - 0.02, Z_WAIST, (1.40, 0.66), (1.10, 0.58), mat=jack, bevel=0.14)
    parts["LowerTorso"] = tb("LowerTorso_Geo", Z_WAIST + 0.04, Z_ROOT - 0.22, (1.12, 0.60), (1.18, 0.64), mat=belt, bevel=0.1)
    for side, sx in (("Left", SX), ("Right", -SX)):
        parts[side + "UpperArm"] = tb(side + "UpperArm_Geo", Z_SHOULDER + 0.14, Z_ELBOW - 0.02, (0.40, 0.42), (0.31, 0.32),
                                      center_xy=(sx, 0), mat=jack, bevel=0.1)
        parts[side + "LowerArm"] = tb(side + "LowerArm_Geo", Z_ELBOW + 0.02, Z_WRIST + 0.01, (0.31, 0.32), (0.23, 0.25),
                                      center_xy=(sx, 0), mat=jack, bevel=0.08)
        hand = tb(side + "Hand_Geo", Z_WRIST, Z_FINGER, (0.13, 0.25), (0.12, 0.23), center_xy=(sx, 0), mat=skin, bevel=0.04)
        meshes.add_box_to(hand, (sx - math.copysign(0.03, sx), -0.13, Z_WRIST - 0.14), (0.08, 0.08, 0.2), bevel=0.02)  # thumb
        parts[side + "Hand"] = hand
        hx = HX if side == "Left" else -HX
        parts[side + "UpperLeg"] = tb(side + "UpperLeg_Geo", Z_HIP + 0.12, Z_KNEE - 0.02, (0.52, 0.56), (0.38, 0.40),
                                      center_xy=(hx, 0), mat=hose, bevel=0.12)
        parts[side + "LowerLeg"] = tb(side + "LowerLeg_Geo", Z_KNEE + 0.02, Z_ANKLE + 0.02, (0.37, 0.40), (0.26, 0.28),
                                      center_xy=(hx, 0.02), mat=boot, bevel=0.09)
        foot = tb(side + "Foot_Geo", Z_ANKLE + 0.06, 0.0, (0.28, 0.40), (0.32, 0.86), center_xy=(hx, -0.20), mat=boot, bevel=0.06)
        # slope the top of the foot down toward the toes
        for v in foot.data.vertices:
            if v.co.z > 0.12 and v.co.y < -0.1:
                v.co.z = 0.12 + (v.co.z - 0.12) * max(0.0, 1 + (v.co.y + 0.1) * 1.8)
        parts[side + "Foot"] = foot
    for bone, ob in parts.items():
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        ob.parent = rig
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
    return parts
