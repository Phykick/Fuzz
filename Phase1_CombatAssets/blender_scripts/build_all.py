"""Phase 1 combat-asset build: everything from scratch, deterministically.

Run with Blender 4.2+ (or the `bpy` 4.2 wheel):
    blender -b -P blender_scripts/build_all.py
    python3 blender_scripts/build_all.py          # with `pip install bpy==4.2.0`

Outputs (relative to Phase1_CombatAssets/):
    CombatAssets_Phase1.blend        organised project (textures packed)
    textures/*.png                   PBR maps (ColorMap/NormalMap/RoughnessMap/MetalnessMap)
    export/fbx/*.fbx                 Roblox-ready FBX (rig, weapons, one file per animation)
    docs/animation_manifest.json     clip lengths, loop flags, marker frames/times
    docs/attachments.json            weapon grip offsets, Motor6D C0 values
    docs/qc_report.json / .md        automated quality-control results
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)

import bpy  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

import anim  # noqa: E402
import bake  # noqa: E402
import clips as C  # noqa: E402
import meshes  # noqa: E402
import qc  # noqa: E402
import rig as R  # noqa: E402
import textures  # noqa: E402

TEX = os.path.join(ROOT, "textures")
FBX = os.path.join(ROOT, "export", "fbx")
DOCS = os.path.join(ROOT, "docs")
BLEND = os.path.join(ROOT, "CombatAssets_Phase1.blend")
HIDE = 1e-4  # scale used to hide props in the demo timeline


# ==========================================================================
# helpers
# ==========================================================================
def coll(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def link(ob, c):
    for old in list(ob.users_collection):
        old.objects.unlink(ob)
    c.objects.link(ob)
    return ob


def empty(name, c, size=0.2, kind="PLAIN_AXES"):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    c.objects.link(e)
    return e


def maps(prefix):
    return {k: os.path.join(TEX, "%s_%s.png" % (prefix, v)) for k, v in
            (("color", "ColorMap"), ("rough", "RoughnessMap"), ("metal", "MetalnessMap"), ("normal", "NormalMap"))}


def bone_parent(ob, rig_ob, bone, world):
    """Parent `ob` to `bone` so that its rest world matrix is `world`."""
    ob.parent = rig_ob
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    b = rig_ob.data.bones[bone]
    tail = b.matrix_local.copy()
    tail.translation = b.tail_local
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_basis = tail.inverted() @ world


def linked_copy(src, name, c):
    ob = bpy.data.objects.new(name, src.data)
    c.objects.link(ob)
    return ob


def fcurve_key(action, path, idx, frame, value, group):
    fc = action.fcurves.find(path, index=idx) or action.fcurves.new(path, index=idx, action_group=group)
    kp = fc.keyframe_points.insert(frame, value, options={"FAST"})
    kp.interpolation = "LINEAR"


def key_matrix(action, frame, m, group, quat_prev=None):
    loc, q, s = m.decompose()
    if quat_prev is not None and quat_prev.dot(q) < 0:
        q = -q
    for i in range(3):
        fcurve_key(action, "location", i, frame, loc[i], group)
        fcurve_key(action, "scale", i, frame, s[i], group)
    for i in range(4):
        fcurve_key(action, "rotation_quaternion", i, frame, q[i], group)
    return q


def key_scale(action, frame, s, group="Visibility"):
    for i in range(3):
        fc = action.fcurves.find("scale", index=i) or action.fcurves.new("scale", index=i, action_group=group)
        kp = fc.keyframe_points.insert(frame, s, options={"FAST"})
        kp.interpolation = "CONSTANT"


# ==========================================================================
# 1. scene + textures
# ==========================================================================
def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.name = "CombatAssets"
    # Roblox guidance: unit scale 0.01 so 1 Blender unit exports as 1 stud
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 0.01
    sc.unit_settings.length_unit = "CENTIMETERS"
    sc.render.fps = anim.FPS
    sc.frame_start = 0
    return sc


# ==========================================================================
# 2. assets
# ==========================================================================
def build_assets(cols):
    mats = {"Sword": meshes.pbr_material("M_Sword_Steel_Leather", maps("Sword")),
            "Bow": meshes.pbr_material("M_Bow_Yew", maps("Bow")),
            "Arrow": meshes.pbr_material("M_Arrow", maps("Arrow"))}
    out = {}

    # ---- sword master: "Sword" empty = grip origin (right-hand grip centre)
    sw = empty("Sword", cols["SWORD"], 0.3, "ARROWS")
    parts = meshes.build_sword(mats["Sword"])
    for n in ("Blade", "Guard", "Grip", "Pommel"):
        link(parts[n], cols["SWORD"])
        parts[n].parent = sw
    s = meshes.SWORD
    blade_base = s["grip_top"] + s["guard_h"]
    for name, pos in (("Sword_Attach_RightHand", (0, 0, 0)),
                      ("Sword_Attach_LeftHand", (0, 0, C_LEFT_GRIP)),
                      ("Sword_BladeBase", (0, 0, blade_base)),
                      ("Sword_BladeTip", (0, 0, blade_base + s["blade_len"]))):
        e = empty(name, cols["SWORD"], 0.12, "SPHERE")
        e.location = pos
        e.parent = sw
    out["sword"] = sw
    out["sword_parts"] = parts

    # ---- bow master: armature "Bow" (skinned limbs + string nock bone)
    bow_arm = bpy.data.armatures.new("Bow_Armature")
    bow_rig = bpy.data.objects.new("Bow_Rig", bow_arm)
    cols["BOW"].objects.link(bow_rig)
    bpy.context.view_layer.objects.active = bow_rig
    bpy.ops.object.mode_set(mode="EDIT")
    b = meshes.BOW
    top, _ = meshes.bow_string_points()
    eb = bow_arm.edit_bones
    root = eb.new("Bow_Root")
    root.head, root.tail = Vector((0, 0, 0)), Vector((0, 0, b["grip_half"]))
    for n, sgn in (("Limb_Upper", 1), ("Limb_Lower", -1)):
        e = eb.new(n)
        e.head = Vector((0, 0, sgn * b["grip_half"]))
        e.tail = Vector((0, top.y - b["d_tip"] * 0.5, sgn * b["half_len"]))
        e.align_roll(Vector((1, 0, 0)))
        e.parent = root
    nk = eb.new("String_Nock")
    nk.head = Vector((0, top.y, meshes.BOW_NOCK_Z))
    nk.tail = nk.head + Vector((0, 0.25, 0))
    nk.align_roll(Vector((1, 0, 0)))
    nk.parent = root
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in bow_rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    bow_mesh, string_mesh = meshes.build_bow(mats["Bow"])
    for ob in (bow_mesh, string_mesh):
        link(ob, cols["BOW"])
        ob.parent = bow_rig
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = bow_rig
    for name, pos in (("Bow_Attach_LeftHand", (0, 0, 0)), ("Bow_ArrowRest", meshes.ARROW_REST),
                      ("Bow_NockPoint", (0, top.y, meshes.BOW_NOCK_Z))):
        e = empty(name, cols["BOW"], 0.1, "SPHERE")
        e.location = pos
        e.parent = bow_rig
    out["bow_rig"] = bow_rig
    out["bow_meshes"] = (bow_mesh, string_mesh)

    # ---- arrows: primary + two variants, plus merged single-mesh versions
    variants = [("Arrow", "bodkin_long", "fletch_grey"),
                ("Arrow_BodkinShort", "bodkin_short", "fletch_white"),
                ("Arrow_Type16", "type16", "fletch_barred")]
    out["arrows"] = {}
    opt = coll("ARROW_Battlefield", cols["ARROW"])
    for i, (name, head, fl) in enumerate(variants):
        root_e = empty(name, cols["ARROW"], 0.15, "ARROWS")
        parts = meshes.build_arrow(mats["Arrow"], head, fl, name)
        for k, ob in parts.items():
            if name == "Arrow":
                ob.name = k            # Shaft / Arrowhead / Fletching / Nock
                ob.data.name = "Arrow_" + k
            link(ob, cols["ARROW"])
            ob.parent = root_e
        out["arrows"][name] = (root_e, parts)
        # merged copy: one mesh, one material - the one to spawn in bulk
        merged = bpy.data.meshes.new(name + "_Battlefield")
        import bmesh
        bm = bmesh.new()
        for ob in parts.values():
            bm.from_mesh(ob.data)
        bm.to_mesh(merged)
        bm.free()
        merged.materials.append(mats["Arrow"])
        for p in merged.polygons:
            p.material_index = 0
        mo = bpy.data.objects.new(name + "_Battlefield", merged)
        opt.objects.link(mo)
        out["arrows"][name + "_Battlefield"] = (mo, {})
    return out, mats


C_LEFT_GRIP = anim.LEFT_GRIP_OFFSET


def layout_masters(assets):
    """Spread the export masters out so they are all visible side by side.
    (Their exported pivot is their own origin; see export_weapons.)"""
    assets["sword"].location = (3.0, 0, 0.8)
    assets["bow_rig"].location = (4.5, 0, 3.0)
    assets["bow_rig"].rotation_mode = "XYZ"
    for i, name in enumerate(("Arrow", "Arrow_BodkinShort", "Arrow_Type16")):
        e = assets["arrows"][name][0]
        e.location = (5.4 + 0.3 * i, 0.2, 0.05)
        e.rotation_euler = (math.radians(-90), 0, 0)
    for i, name in enumerate(("Arrow_Battlefield", "Arrow_BodkinShort_Battlefield", "Arrow_Type16_Battlefield")):
        o = assets["arrows"][name][0]
        o.location = (6.5 + 0.3 * i, 0.2, 0.05)
        o.rotation_euler = (math.radians(-90), 0, 0)


# ==========================================================================
# 3. held (demo) instances of the weapons
# ==========================================================================
def build_held(assets, rig_ob, c):
    held = {}
    sw = empty("Sword_Held", c, 0.2, "ARROWS")
    for n, ob in assets["sword_parts"].items():
        o = linked_copy(ob, n + "_Held", c)
        o.parent = sw
    w = R.SWORD_REST_FRAME.to_4x4()
    w.translation = R.SWORD_REST_POS
    bone_parent(sw, rig_ob, "SwordHandle", w)
    held["sword"] = sw

    br = bpy.data.objects.new("Bow_Rig_Held", assets["bow_rig"].data)
    c.objects.link(br)
    bpy.context.view_layer.update()   # creates the pose
    for pb in br.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for ob in assets["bow_meshes"]:
        o = linked_copy(ob, ob.name + "_Held", c)
        o.parent = br
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = br   # vertex groups live on the (shared) mesh data
    w = R.BOW_REST_FRAME.to_4x4()
    w.translation = R.BOW_REST_POS
    bone_parent(br, rig_ob, "BowHandle", w)
    held["bow"] = br

    ar = empty("Arrow_Held", c, 0.15, "ARROWS")
    ar.rotation_mode = "QUATERNION"
    ar.parent = rig_ob
    for n, ob in assets["arrows"]["Arrow"][1].items():
        o = linked_copy(ob, "Arrow_%s_Held" % n, c)
        o.parent = ar
    held["arrow"] = ar
    return held


# ==========================================================================
# 4. bow string / limb solve + arrow placement (per frame)
# ==========================================================================
_top, _bot = meshes.bow_string_points()
STRING_REST = Vector((0, _top.y, meshes.BOW_NOCK_Z))
HALF_STRING = (_top - Vector((0, _top.y, meshes.BOW_NOCK_Z))).length


def limb_angle(nock, sign):
    """Rotation (rad, about bow-local X) of a limb so the string stays taut.
    Positive pull toward the archer (+Y) bends both tips toward +Y."""
    g = meshes.BOW["grip_half"]
    pivot = Vector((0, 0, sign * g))
    tip = Vector((0, _top.y, sign * _top.z))
    half = (tip - STRING_REST).length

    def f(a):
        t = pivot + Matrix.Rotation(a, 3, "X") @ (tip - pivot)
        return (t - nock).length - half

    if f(0.0) <= 0:
        return 0.0
    lo, hi = 0.0, -0.9 * sign   # upper limb bends with a < 0, lower with a > 0
    for _ in range(40):
        mid = (lo + hi) / 2
        if f(mid) > 0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def draw_table():
    """nock pull (studs behind the braced string) -> limb angles, for Phase 2."""
    rows = []
    for i in range(0, 13):
        pull = i * 0.2
        n = STRING_REST + Vector((0, pull, 0))
        rows.append({"pull_studs": round(pull, 2), "limb_upper_deg": round(math.degrees(limb_angle(n, 1)), 2),
                     "limb_lower_deg": round(math.degrees(limb_angle(n, -1)), 2)})
    return rows


class PropKeyer:
    """Keys the held bow rig (string + limbs) and the arrow for bow clips."""

    def __init__(self, held, rest_bow):
        self.held = held
        self.rest_bow = rest_bow
        self.release = None
        self.qprev = None
        self.vib_t = None

    def key(self, frame, pose, bow_act, arrow_act):
        P = pose.info["P"]
        b_pos, b_rot = pose.info["bow_world"]
        inv = b_rot.inverted()
        nock = STRING_REST.copy()
        if P["string_held"]:
            local = inv @ (Vector(P["draw_pos"]) - b_pos)
            if local.y > STRING_REST.y:
                nock = local
            self.vib_t = None
        else:
            if self.vib_t is None and P["arrow"] == "flying":
                self.vib_t = 0
            if self.vib_t is not None:
                t = self.vib_t
                nock = STRING_REST + Vector((0, 0.10 * math.cos(t * 2.2) * math.exp(-t / 2.5), 0))
                self.vib_t += 1
        # bone basis: String_Nock translation, limb rotations about their heads
        rb = self.rest_bow
        loc = rb["String_Nock"].to_3x3().inverted() @ (nock - STRING_REST)
        for i in range(3):
            fcurve_key(bow_act, 'pose.bones["String_Nock"].location', i, frame, loc[i], "String_Nock")
        for bn, sgn in (("Limb_Upper", 1), ("Limb_Lower", -1)):
            a = limb_angle(nock, sgn)
            r3 = rb[bn].to_3x3()
            q = (r3.inverted() @ Matrix.Rotation(a, 3, "X") @ r3).to_quaternion()
            for i in range(4):
                fcurve_key(bow_act, 'pose.bones["%s"].rotation_quaternion' % bn, i, frame, q[i], bn)
        # arrow
        state = P["arrow"]
        rest_pt = b_pos + b_rot @ Vector(meshes.ARROW_REST)
        nock_w = b_pos + b_rot @ nock
        hand = pose.mats["RightHand"]
        up = b_rot @ Vector((0, 0, 1))
        visible = True
        if state == "nocked":
            d = (rest_pt - nock_w).normalized()
            origin = nock_w
            self.release = (origin.copy(), d.copy())
        elif state == "hand":
            origin = hand @ Vector((0, R.FIST + 0.04, 0))
            d = Vector(P["arrow_dir"]).normalized()
            up = hand.to_3x3() @ Vector((1, 0, 0))
        elif state == "flying" and self.release is not None:
            origin = self.release[0] + self.release[1] * P["arrow_fly"]
            d = self.release[1]
            visible = P["arrow_fly"] < 30
        else:
            origin, d, visible = hand.translation, Vector((0, -1, 0)), False
        yv = -d
        zv = anim.safe_norm(anim.perp(up, yv), Vector((0, 0, 1)))
        xv = yv.cross(zv)
        m = Matrix((xv, yv, zv)).transposed().to_4x4()
        m.translation = origin
        if not visible:
            m = m @ Matrix.Scale(HIDE, 4)
        self.qprev = key_matrix(arrow_act, frame, m, "Arrow", self.qprev)


# ==========================================================================
# 5. bake all clips (+ per-clip prop actions)
# ==========================================================================
def bake_everything(rig_ob, held, rest, bow_rest):
    all_clips = C.all_clips()
    results = []
    import time
    for clip in all_clips:
        t0 = time.time()
        act, poses = bake.bake_clip(rig_ob, clip, rest)
        print("   baked %-30s %.2fs" % (clip.name, time.time() - t0), flush=True)
        act.name = clip.name
        entry = {"clip": clip, "action": act, "poses": poses}
        if clip.category == "BOW":
            ba = bpy.data.actions.new("PROP_BowString_" + clip.name)
            aa = bpy.data.actions.new("PROP_Arrow_" + clip.name)
            ba.use_fake_user = aa.use_fake_user = True
            pk = PropKeyer(held, bow_rest)
            for f, pose in poses:
                pk.key(f, pose, ba, aa)
            entry["bow_action"], entry["arrow_action"] = ba, aa
        results.append(entry)
    rig_ob.animation_data.action = None
    return results


# ==========================================================================
# 6. demo showcase timeline
# ==========================================================================
DEMO_SEQUENCE = ["Sword_Idle", "Sword_Attack_HighRight", "Sword_Block", "Sword_Block_Recover",
                 "Sword_Attack_Thrust", "Sword_Idle",
                 "Bow_Idle", "Bow_Nock", "Bow_Draw", "Bow_FullDraw", "Bow_Release", "Bow_Lower"]


def build_demo(sc, rig_ob, held, rest, bow_rest, baked, cams):
    by_name = {e["clip"].name: e["clip"] for e in baked}
    act = bpy.data.actions.new("DEMO_CombatShowcase")
    act.use_fake_user = True
    ba = bpy.data.actions.new("DEMO_BowString")
    aa = bpy.data.actions.new("DEMO_Arrow")
    sa = bpy.data.actions.new("DEMO_SwordVisibility")
    for a in (ba, aa, sa):
        a.use_fake_user = True
    offset = 0
    pk = PropKeyer(held, bow_rest)
    sc.timeline_markers.clear()
    prev_mode = None
    for name in DEMO_SEQUENCE:
        clip = by_name[name]
        start = offset
        _, poses = bake.bake_clip(rig_ob, clip, rest, offset=offset, action=act)
        mode = clip.keys[0][1].get("mode", "sword")
        for f, pose in poses:
            fr = f + offset
            key_scale(sa, fr, 1.0 if mode == "sword" else HIDE)
            if mode == "bow":
                pk.key(fr, pose, ba, aa)
            else:
                # bow hidden / arrow hidden during the sword section
                pk.key(fr, anim.solve(dict(C.BOW_IDLE), rest), ba, aa)
        bowvis = bpy.data.actions.get("DEMO_BowVisibility") or bpy.data.actions.new("DEMO_BowVisibility")
        bowvis.use_fake_user = True
        for f, _ in poses:
            key_scale(bowvis, f + offset, 1.0 if mode == "bow" else HIDE)
        m = sc.timeline_markers.new(name, frame=start)
        if mode != prev_mode:
            m.camera = cams[mode]
            prev_mode = mode
        for mk, fr in clip.markers.items():
            sc.timeline_markers.new("  %s" % mk, frame=start + fr)
        offset = start + clip.length   # next clip starts on this clip's last (shared) pose
    act.frame_range = (0, offset)
    rig_ob.animation_data.action = act
    held["bow"].animation_data_create()
    held["bow"].animation_data.action = ba
    held["arrow"].animation_data_create()
    held["arrow"].animation_data.action = aa
    held["sword"].animation_data_create()
    held["sword"].animation_data.action = sa
    # bow visibility is keyed on the bow rig object's scale in a separate
    # action; merge it into DEMO_BowString (same object)
    bv = bpy.data.actions["DEMO_BowVisibility"]
    for fc in bv.fcurves:
        nf = ba.fcurves.new(fc.data_path, index=fc.array_index, action_group="Visibility")
        for kp in fc.keyframe_points:
            k = nf.keyframe_points.insert(kp.co[0], kp.co[1], options={"FAST"})
            k.interpolation = "CONSTANT"
    bpy.data.actions.remove(bv)
    sc.frame_start, sc.frame_end = 0, offset
    return offset


# ==========================================================================
# 7. environment, cameras
# ==========================================================================
def build_environment(c):
    sc = bpy.context.scene
    g = bpy.data.meshes.new("Ground")
    s = 60
    g.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    go = bpy.data.objects.new("Ground_Plain", g)
    g.materials.append(meshes.flat_material("M_Ground_Grass", (0.16, 0.24, 0.09), 0.95))
    c.objects.link(go)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = (math.radians(52), math.radians(12), math.radians(-35))
    c.objects.link(sun)
    w = bpy.data.worlds.new("Sky")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.52, 0.64, 0.82, 1)
    bg.inputs[1].default_value = 0.9
    sc.world = w
    tgt = empty("Opponent_Reference", c, 0.4, "SPHERE")
    tgt.location = anim.OPPONENT_HEAD
    cams = {}
    for mode, pos, aim in (("sword", (-8.5, -8.0, 4.4), (0, -1.0, 2.8)),
                           ("bow", (-10.0, -4.0, 4.6), (0, -1.1, 3.4))):
        cam = bpy.data.objects.new("CAM_Demo_" + mode.capitalize(), bpy.data.cameras.new("CAM_" + mode))
        cam.data.lens = 38
        cam.location = pos
        cam.rotation_euler = (Vector(aim) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        c.objects.link(cam)
        cams[mode] = cam
    sc.camera = cams["sword"]
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 32
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    return cams


# ==========================================================================
# 8. docs: manifest, attachments
# ==========================================================================
B2R = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Blender (char faces -Y) -> Roblox (faces -Z)


def roblox_cframe(pos_b, rot_b_cols):
    """Blender position + local axis matrix -> Roblox CFrame components.
    Local axes convert the same way (an imported mesh's local X/Y/Z follow the
    identical axis mapping)."""
    p = B2R @ Vector(pos_b)
    m = B2R @ rot_b_cols @ B2R.transposed()
    return [round(p.x, 4), round(p.y, 4), round(p.z, 4)] + [round(m[i][j], 4) for i in range(3) for j in range(3)]


def write_docs(baked, qc_reports, assets):
    os.makedirs(DOCS, exist_ok=True)
    manifest = {"fps": anim.FPS, "rig": "R15 (Root > HumanoidRootNode > LowerTorso ...)",
                "weapon_joints": {"SwordHandle": "Motor6D RightHand -> SwordHandle",
                                  "BowHandle": "Motor6D LeftHand -> BowHandle"},
                "clips": []}
    for e in baked:
        c = e["clip"]
        manifest["clips"].append({
            "name": c.name, "category": c.category, "file": "export/fbx/ANIM_%s.fbx" % c.name,
            "frames": c.length, "seconds": round(c.length / anim.FPS, 3), "loop": c.loop,
            "markers": [{"name": k, "frame": v, "time": round(v / anim.FPS, 3)}
                        for k, v in sorted(c.markers.items(), key=lambda kv: kv[1])],
            "notes": c.notes})
    with open(os.path.join(DOCS, "animation_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    # attachments: part-centre relative offsets (Roblox Motor6D C0 uses the
    # Part0 CFrame, i.e. the centre of the RightHand / LeftHand part)
    hand_c = {s: Vector((sx, 0, (R.Z_WRIST + R.Z_FINGER) / 2)) for s, sx in (("Right", -R.SX), ("Left", R.SX))}
    s = meshes.SWORD
    blade_base = s["grip_top"] + s["guard_h"]
    att = {
        "units": "studs (1 Blender unit = 1 stud)",
        "axis_conversion": "Roblox = (-X_blender, Z_blender, Y_blender); character faces -Y in Blender / -Z (LookVector) in Roblox",
        "cframe_format": "[x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22] (CFrame.new(...) component order)",
        "sword": {
            "origin": "centre of the right-hand grip, just under the guard",
            "local_axes": "Blender: +Z blade/point, +X true edge, +/-Y flats. Roblox (after import): +Y point, -X true edge, +/-Z flats",
            "points_blender_local": {
                "RightHandGrip": [0, 0, 0], "LeftHandGrip": [0, 0, C_LEFT_GRIP],
                "BladeBase": [0, 0, round(blade_base, 4)],
                "BladeTip": [0, 0, round(blade_base + s["blade_len"], 4)],
                "Pommel_bottom": [0, 0, round(s["grip_top"] - s["grip_len"] - 2 * s["pommel_r"] + 0.02, 4)]},
            "motor6d": {"Part0": "RightHand", "Part1": "SwordHandle (sword root part, pivot at the grip origin)",
                        "C0_rest": roblox_cframe(R.SWORD_REST_POS - hand_c["Right"], R.SWORD_REST_FRAME),
                        "C1": "identity"},
        },
        "bow": {
            "origin": "centre of the bow-hand grip",
            "local_axes": "Blender: +Z upper limb, -Y back of the bow (faces target), +Y string side. "
                          "Roblox: +Y upper limb, +Z back of the bow, -Z string side",
            "points_blender_local": {"Grip": [0, 0, 0], "ArrowRest": list(meshes.ARROW_REST),
                                     "NockPoint_braced": [0, round(_top.y, 4), meshes.BOW_NOCK_Z],
                                     "UpperNock": [0, round(_top.y, 4), round(_top.z, 4)],
                                     "LowerNock": [0, round(_top.y, 4), round(-_top.z, 4)]},
            "bones": {"Bow_Root": "static handle", "Limb_Upper/Limb_Lower": "rotate about local X at the fades",
                      "String_Nock": "translate to the draw-hand fingers while drawn"},
            "draw_table": draw_table(),
            "brace_height_studs": round(_top.y - meshes.BOW["d_grip"] * 0.58, 4),
            "motor6d": {"Part0": "LeftHand", "Part1": "BowHandle (bow root, pivot at the grip)",
                        "C0_rest": roblox_cframe(R.BOW_REST_POS - hand_c["Left"], R.BOW_REST_FRAME),
                        "C1": "identity"},
        },
        "arrow": {
            "origin": "string groove of the nock",
            "local_axes": "points along -Y in Blender = -Z (LookVector) in Roblox",
            "length_studs": round(meshes.ARROW["length"] + 0.3, 3),
            "held": "during Bow_Nock the nock sits at RightHand + (0, FIST+0.04) along the hand; when nocked the "
                    "nock follows the string point and the shaft aims at the bow's ArrowRest",
        },
        "hands": {"fist_centre_from_wrist": R.FIST, "RightHand_part_centre": list(hand_c["Right"]),
                  "LeftHand_part_centre": list(hand_c["Left"])},
    }
    # sword balance estimate (steel 7850, grip wood/leather 800 kg/m^3)
    att["sword"]["physical_estimate"] = sword_mass(assets)
    with open(os.path.join(DOCS, "attachments.json"), "w") as f:
        json.dump(att, f, indent=2)

    with open(os.path.join(DOCS, "qc_report.json"), "w") as f:
        json.dump(qc_reports, f, indent=2)
    lines = ["| Clip | s | hand IK err | leg IK err | planted slide | min foot z | min weapon z | "
             "blade/bow clearance | max knee | max elbow | max wrist | head turn | peak ang. speed | flags |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in qc_reports:
        clear = r["blade_clear"] if r["blade_clear"] < 9 else r["bow_clear"]
        lines.append("| %s | %.2f | %.3f | %.3f | %.4f | %.3f | %.2f | %.2f | %.0f° | %.0f° | %.0f° | %.0f° | %.0f°/s | %s |" % (
            r["name"], (r["frames"] - 1) / anim.FPS, r["ik_arm"], r["ik_leg"], r["foot_slide"], r["min_foot_z"],
            r["min_weapon_z"], clear, r["knee_max"], r["elbow_max"], r["wrist_max"], r["head_rel_max"],
            r["max_ang_speed_deg_per_s"], ", ".join(r["flags"]) or "OK"))
    with open(os.path.join(DOCS, "qc_report.md"), "w") as f:
        f.write("# Automated QC report\n\nUnits: studs. Generated by build_all.py.\n\n" + "\n".join(lines) + "\n")
    return manifest, att


def sword_mass(assets):
    import bmesh
    dens = {"Blade": 7850, "Guard": 7850, "Pommel": 7850}
    k = (1 / meshes.M) ** 3
    total, moment = 0.0, 0.0
    for n, d in dens.items():
        ob = assets["sword_parts"][n]
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        vol = abs(bm.calc_volume()) * k
        cz = sum((v.co.z for v in bm.verts), 0.0) / len(bm.verts)
        bm.free()
        total += vol * d
        moment += vol * d * cz
    s = meshes.SWORD
    grip_vol = math.pi * s["grip_rx"] * s["grip_ry"] * s["grip_len"] * k
    grip_cz = s["grip_top"] - s["grip_len"] / 2
    tang = 0.015 * 0.006 * 0.25 * 7850
    for m_, cz in ((grip_vol * 800, grip_cz), (tang, grip_cz)):
        total += m_
        moment += m_ * cz
    pob = moment / total
    return {"mass_kg": round(total, 2),
            "point_of_balance_above_guard_cm": round((pob - (s["grip_top"] + s["guard_h"])) / meshes.M * 100, 1),
            "overall_length_cm": round((s["grip_top"] + s["guard_h"] + s["blade_len"] - (s["grip_top"] - s["grip_len"] - 2 * s["pommel_r"])) / meshes.M * 100, 1)}


# ==========================================================================
# 9. manifest empties in the ANIMATIONS collections
# ==========================================================================
def clip_nodes(baked, cols):
    for e in baked:
        c = e["clip"]
        target = cols["ANIM_" + c.category]
        n = empty("ANIM_" + c.name, target, 0.05)
        n["action"] = e["action"].name
        n["frames"] = c.length
        n["seconds"] = round(c.length / anim.FPS, 3)
        n["loop"] = c.loop
        n["markers"] = json.dumps(c.markers)
        if "bow_action" in e:
            n["prop_bow_action"] = e["bow_action"].name
            n["prop_arrow_action"] = e["arrow_action"].name
        n.hide_viewport = True
        n.hide_render = True


# ==========================================================================
# 10. FBX export
# ==========================================================================
FBX_COMMON = dict(apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                  add_leaf_bones=False, use_armature_deform_only=False, mesh_smooth_type="FACE",
                  use_mesh_modifiers=True, primary_bone_axis="Y", secondary_bone_axis="X", use_space_transform=True)


def select_only(obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


def bound_weapon(name, root, parts, frame3, pos, bone, rig_ob):
    """Merge a weapon's meshes (rest geometry) into one mesh placed in the
    hand at rest and weighted 100% to `bone`."""
    import bmesh
    rest_world = frame3.to_4x4()
    rest_world.translation = pos
    to_local = root.matrix_world.inverted()
    bm = bmesh.new()
    for ob in parts:
        tmp = bmesh.new()
        tmp.from_mesh(ob.data)
        tmp.transform(rest_world @ to_local @ ob.matrix_world)
        me = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(parts[0].data.materials[0])
    ob = bpy.data.objects.new(name, me)
    rig_ob.users_collection[0].objects.link(ob)
    ob.parent = rig_ob
    vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    ob.modifiers.new("Armature", "ARMATURE").object = rig_ob
    return ob


def export_all(sc, rig_ob, body, baked, assets, held):
    os.makedirs(FBX, exist_ok=True)
    # hide props so they are never picked up
    for o in list(held.values()) + [c for h in held.values() for c in h.children]:
        o.select_set(False)
    rig_objs = [rig_ob] + list(body.values())

    # rig in rest pose (no animation)
    rig_ob.animation_data.action = None
    for pb in rig_ob.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    select_only(rig_objs)
    bpy.ops.export_scene.fbx(filepath=os.path.join(FBX, "R15_CombatRig.fbx"), use_selection=True,
                             object_types={"ARMATURE", "MESH"}, bake_anim=False, path_mode="AUTO", **FBX_COMMON)

    # armed rig: sword / bow merged and bound 100% to their handle bones, so
    # Studio's rig importer creates SwordHandle / BowHandle parts + Motor6Ds
    # at exactly the right grip offset (no manual C0 entry)
    bound = [bound_weapon("SwordHandle_Geo", assets["sword"], list(assets["sword_parts"].values()),
                          R.SWORD_REST_FRAME, R.SWORD_REST_POS, "SwordHandle", rig_ob),
             # bow limbs only: the string is drawn live in Roblox (Beams to the draw hand)
             bound_weapon("BowHandle_Geo", assets["bow_rig"], [assets["bow_meshes"][0]],
                          R.BOW_REST_FRAME, R.BOW_REST_POS, "BowHandle", rig_ob)]
    select_only(rig_objs + bound)
    bpy.ops.export_scene.fbx(filepath=os.path.join(FBX, "R15_CombatRig_Armed.fbx"), use_selection=True,
                             object_types={"ARMATURE", "MESH"}, bake_anim=False, path_mode="COPY",
                             embed_textures=True, **FBX_COMMON)
    for ob in bound:
        me = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)

    # animations: one FBX per clip (rig + body so it previews on import)
    for e in baked:
        c = e["clip"]
        rig_ob.animation_data.action = e["action"]
        sc.frame_start, sc.frame_end = c.start, c.end
        sc.name = c.name                    # FBX take name = clip name
        select_only(rig_objs)
        bpy.ops.export_scene.fbx(filepath=os.path.join(FBX, "ANIM_%s.fbx" % c.name), use_selection=True,
                                 object_types={"ARMATURE", "MESH"}, bake_anim=True, bake_anim_use_all_bones=True,
                                 bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
                                 bake_anim_force_startend_keying=True, bake_anim_step=1.0,
                                 bake_anim_simplify_factor=0.0, path_mode="AUTO", **FBX_COMMON)
    rig_ob.animation_data.action = None
    sc.name = "CombatAssets"

    # weapons: exported around their own origin (temporarily zero the layout offsets)
    def export_group(root, objs, fname, types):
        saved = root.matrix_world.copy()
        root.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        select_only(objs)
        bpy.ops.export_scene.fbx(filepath=os.path.join(FBX, fname), use_selection=True, object_types=types,
                                 bake_anim=False, path_mode="COPY", embed_textures=True, **FBX_COMMON)
        root.matrix_world = saved

    sw = assets["sword"]
    export_group(sw, [sw] + list(assets["sword_parts"].values()), "Sword_TwoHanded.fbx", {"EMPTY", "MESH"})
    br = assets["bow_rig"]
    export_group(br, [br] + list(assets["bow_meshes"]), "Bow_Longbow.fbx", {"ARMATURE", "MESH"})
    for name in ("Arrow", "Arrow_BodkinShort", "Arrow_Type16"):
        root, parts = assets["arrows"][name]
        export_group(root, [root] + list(parts.values()), "%s.fbx" % name, {"EMPTY", "MESH"})
        mo = assets["arrows"][name + "_Battlefield"][0]
        export_group(mo, [mo], "%s_Battlefield.fbx" % name, {"MESH"})


# ==========================================================================
# main
# ==========================================================================
def main():
    sc = setup_scene()
    print("[1/9] textures")
    textures.build_all(TEX)

    top = coll("COMBAT_ASSETS", sc.collection)
    cols = {n: coll(n, top) for n in ("SWORD", "BOW", "ARROW", "R15_RIG", "ANIMATIONS")}
    for n in ("SWORD", "BOW", "REACTIONS", "LOCOMOTION"):
        cols["ANIM_" + n] = coll("ANIM_" + n, cols["ANIMATIONS"])
    cols["DEMO"] = coll("DEMO_SCENE", top)

    print("[2/9] assets")
    assets, mats = build_assets(cols)

    print("[3/9] R15 rig")
    rig_ob = R.build_armature("R15_Rig")
    link(rig_ob, cols["R15_RIG"])
    body = R.build_body(rig_ob)
    for ob in body.values():
        cols["R15_RIG"].objects.link(ob)
    rest = R.rest_matrices(rig_ob)
    bow_rest = {b.name: b.matrix_local.copy() for b in assets["bow_rig"].data.bones}

    held = build_held(assets, rig_ob, cols["DEMO"])
    layout_masters(assets)

    print("[4/9] bake %d clips" % len(C.all_clips()))
    baked = bake_everything(rig_ob, held, rest, bow_rest)

    print("[5/9] QC")
    reports = [qc.analyse(e["clip"], e["poses"]) for e in baked]
    for r in reports:
        print("   %-30s %s" % (r["name"], ", ".join(r["flags"]) or "OK"))

    print("[6/9] docs")
    write_docs(baked, reports, assets)
    clip_nodes(baked, cols)

    print("[7/9] export FBX")
    export_all(sc, rig_ob, body, baked, assets, held)

    print("[8/9] demo scene")
    cams = build_environment(cols["DEMO"])
    end = build_demo(sc, rig_ob, held, rest, bow_rest, baked, cams)
    print("   demo length %d frames (%.1f s)" % (end, end / anim.FPS))

    print("[9/9] save")
    sc.frame_set(0)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
    print("saved", BLEND)


if __name__ == "__main__":
    main()
