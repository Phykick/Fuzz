"""Procedural, export-clean meshes for the Phase 1 combat assets.

Scale: 1 Blender unit = 1 Roblox stud.  The R15 test character is 5.4 studs
tall and represents a ~1.80 m man, so real-world measurements are converted
with M = 3.0 studs per metre.  All geometry is built vertex-by-vertex with
explicit UVs that land inside the texture-atlas rectangles in textures.py.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from textures import ARROW_ATLAS, BOW_ATLAS, SWORD_ATLAS

M = 3.0  # studs per metre


# --------------------------------------------------------------------------
# Generic builders
# --------------------------------------------------------------------------
class MeshBuilder:
    """Accumulates verts / faces / per-corner UVs, then emits one mesh."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.uvs = []  # list (per face) of list of (u, v)
        self.smooth = []
        self.groups = {}  # vertex group name -> {vert index: weight}

    def add_vert(self, co):
        self.verts.append(Vector(co))
        return len(self.verts) - 1

    def add_face(self, idx, uv, smooth=True):
        self.faces.append(list(idx))
        self.uvs.append(list(uv))
        self.smooth.append(smooth)

    def weight(self, group, vi, w):
        self.groups.setdefault(group, {})[vi] = w

    def build(self, name, material=None, sharp_angle=35.0):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        uvl = me.uv_layers.new(name="UVMap")
        li = 0
        for fi, poly in enumerate(me.polygons):
            for k, loop_index in enumerate(poly.loop_indices):
                uvl.data[loop_index].uv = self.uvs[fi][k]
            li += 1
        for fi, poly in enumerate(me.polygons):
            poly.use_smooth = self.smooth[fi]
        me.validate(clean_customdata=False)
        me.update()
        # Hard edges where the angle is sharp (bevels / edges), smooth elsewhere.
        me.set_sharp_from_angle(angle=math.radians(sharp_angle))
        if material is not None:
            me.materials.append(material)
        ob = bpy.data.objects.new(name, me)
        for g, ws in self.groups.items():
            vg = ob.vertex_groups.new(name=g)
            for vi, w in ws.items():
                vg.add([vi], w, "REPLACE")
        return ob


def atlas_uv(rect, u, v):
    u0, u1, v0, v1 = rect
    # small inset so bilinear filtering never bleeds into a neighbour region
    pad_u = (u1 - u0) * 0.01
    pad_v = (v1 - v0) * 0.004
    return (u0 + pad_u + u * (u1 - u0 - 2 * pad_u), v0 + pad_v + v * (v1 - v0 - 2 * pad_v))


def loft(mb, rings, rect, cap_start=None, cap_end=None, smooth=True, v_range=(0.0, 1.0)):
    """rings: list of closed rings (lists of Vector, equal length).
    UV u follows the ring perimeter, v the accumulated length.
    cap_start / cap_end: None, 'fan' (to ring centroid) or a Vector apex."""
    n = len(rings[0])
    # v coordinate from centroid path length
    cents = [sum(r, Vector()) / n for r in rings]
    acc = [0.0]
    for i in range(1, len(rings)):
        acc.append(acc[-1] + (cents[i] - cents[i - 1]).length)
    total = acc[-1] if acc[-1] > 0 else 1.0
    vv = [v_range[0] + (a / total) * (v_range[1] - v_range[0]) for a in acc]
    # u from perimeter of the largest ring
    ref = max(rings, key=lambda r: sum((r[(k + 1) % n] - r[k]).length for k in range(n)))
    per = [0.0]
    for k in range(n):
        per.append(per[-1] + (ref[(k + 1) % n] - ref[k]).length)
    uu = [p / per[-1] for p in per]
    idx = [[mb.add_vert(p) for p in ring] for ring in rings]
    for i in range(len(rings) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            face = [idx[i][k], idx[i][k2], idx[i + 1][k2], idx[i + 1][k]]
            uv = [atlas_uv(rect, uu[k], vv[i]), atlas_uv(rect, uu[k + 1], vv[i]),
                  atlas_uv(rect, uu[k + 1], vv[i + 1]), atlas_uv(rect, uu[k], vv[i + 1])]
            mb.add_face(face, uv, smooth)
    for cap, ring_i, flip in ((cap_start, 0, True), (cap_end, len(rings) - 1, False)):
        if cap is None:
            continue
        ring = idx[ring_i]
        apex = cents[ring_i] if cap == "fan" else cap
        ai = mb.add_vert(apex)
        for k in range(n):
            k2 = (k + 1) % n
            face = [ring[k], ring[k2], ai]
            uvs = [atlas_uv(rect, uu[k], vv[ring_i]), atlas_uv(rect, uu[k + 1], vv[ring_i]),
                   atlas_uv(rect, (uu[k] + uu[k + 1]) * 0.5, vv[ring_i])]
            if flip:
                face.reverse()
                uvs.reverse()
            mb.add_face(face, uvs, smooth)
    return idx


def ellipse_ring(center, ax_x, ax_y, rx, ry, n, phase=0.0):
    return [center + ax_x * (rx * math.cos(phase + 2 * math.pi * k / n)) +
            ax_y * (ry * math.sin(phase + 2 * math.pi * k / n)) for k in range(n)]


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------
def pbr_material(name, maps, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (200, 0)
    nt.links.new(bsdf.outputs[0], out.inputs[0])

    def tex(path, y, noncolor):
        img = bpy.data.images.load(path, check_existing=True)
        if noncolor:
            img.colorspace_settings.name = "Non-Color"
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.location = (-500, y)
        return t

    c = tex(maps["color"], 300, False)
    nt.links.new(c.outputs[0], bsdf.inputs["Base Color"])
    m = tex(maps["metal"], 0, True)
    nt.links.new(m.outputs[0], bsdf.inputs["Metallic"])
    r = tex(maps["rough"], -300, True)
    nt.links.new(r.outputs[0], bsdf.inputs["Roughness"])
    nrm = tex(maps["normal"], -600, True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.location = (-150, -600)
    nt.links.new(nrm.outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
    return mat


def flat_material(name, rgb, rough=0.7, metal=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    mat.diffuse_color = (*rgb, 1.0)
    return mat


# --------------------------------------------------------------------------
# SWORD  (late 14th/15th c. two-handed "great" longsword, Oakeshott XVIIIa)
# Local frame: origin = centre of the RIGHT-HAND grip position (just under the
# guard); +Z = towards the point; +X = true edge; ±Y = flats.
# --------------------------------------------------------------------------
SWORD = dict(
    grip_top=0.15,               # guard underside, studs above origin
    guard_h=0.075,               # guard block height at centre
    blade_len=0.97 * M,          # 97 cm blade
    blade_w0=0.052 * M,          # width at the shoulders
    blade_w1=0.030 * M,          # width before the point section
    blade_t0=0.0068 * M,         # thickness at base (distal taper)
    blade_t1=0.0022 * M,         # thickness near the point
    fuller_len=0.42,             # fraction of the blade
    fuller_w=0.020 * M,
    fuller_d=0.0014 * M,
    grip_len=0.24 * M,
    grip_rx=0.030 * M / 2,
    grip_ry=0.025 * M / 2,
    guard_span=0.27 * M,
    pommel_r=0.066 * M / 2,
    left_hand_offset=-0.30,      # left-hand grip centre on the grip (studs, Z)
)


def blade_section(t, s):
    """Cross-section of the blade at fraction t (0 base .. 1 tip).
    16 points in the X (edge) / Y (flat) plane, fuller when t < fuller_len."""
    point_start = 0.86
    if t < point_start:
        hw = (s["blade_w0"] + (s["blade_w1"] - s["blade_w0"]) * (t / point_start)) / 2
    else:
        k = (t - point_start) / (1 - point_start)
        hw = s["blade_w1"] / 2 * (1 - k) ** 0.85 * math.cos(k * math.pi / 2) ** 0.3
    ht = (s["blade_t0"] + (s["blade_t1"] - s["blade_t0"]) * t) / 2
    hw = max(hw, 0.0015)
    fl = s["fuller_len"]
    if t < fl:
        fade = 1.0 if t < fl - 0.08 else (fl - t) / 0.08
        fw = s["fuller_w"] / 2 * (0.4 + 0.6 * fade)
        fd = s["fuller_d"] * fade
    else:
        fw, fd = hw * 0.18, 0.0
    fw = min(fw, hw * 0.55)
    top = [
        (hw, 0.0),                   # true edge (+X)
        (hw * 0.93, ht * 0.30),      # small edge bevel (not razor sharp)
        (hw * 0.60, ht * 0.86),
        (fw * 1.25, ht),
        (fw * 0.55, ht - fd * 0.85),
        (0.0, ht - fd),              # fuller bottom
        (-fw * 0.55, ht - fd * 0.85),
        (-fw * 1.25, ht),
        (-hw * 0.60, ht * 0.86),
        (-hw * 0.93, ht * 0.30),
        (-hw, 0.0),                  # false edge (-X)
    ]
    # the -Y flat mirrors the interior points (edge points are shared)
    bottom = [(x, -y) for (x, y) in reversed(top[1:-1])]
    return top + bottom


def build_sword(mat):
    s = SWORD
    parts = {}

    # ---- Blade
    mb = MeshBuilder()
    z0 = s["grip_top"] + s["guard_h"] - 0.01  # blade base sits inside the guard
    rings = []
    ts = [0.0, 0.03, 0.08, 0.15, 0.22, 0.30, 0.34, 0.38, 0.42, 0.50, 0.60, 0.70,
          0.78, 0.86, 0.90, 0.94, 0.97, 0.99]
    for t in ts:
        pts = blade_section(t, s)
        z = z0 + t * s["blade_len"]
        rings.append([Vector((x, y, z)) for (x, y) in pts])
    tip = Vector((0, 0, z0 + s["blade_len"]))
    loft(mb, rings, SWORD_ATLAS["blade"], cap_start="fan", cap_end=tip, smooth=True)
    parts["Blade"] = mb.build("Blade", mat, sharp_angle=40)

    # ---- Crossguard: bar along X, rectangular bevelled section in YZ
    mb = MeshBuilder()
    gb = s["grip_top"]
    half = s["guard_span"] / 2
    xs = [-half, -half * 0.97, -half * 0.8, -half * 0.45, -0.07, -0.045, 0.045, 0.07,
          half * 0.45, half * 0.8, half * 0.97, half]
    rings = []
    for x in xs:
        ax = abs(x) / half
        if ax < 0.2:            # central block (ecusson) wraps the blade base
            hz, hy = s["guard_h"] / 2, 0.030
        else:
            k = (ax - 0.2) / 0.8
            hz = 0.021 + 0.006 * k ** 3          # slight flare at the terminals
            hy = 0.021 + 0.004 * k ** 3
        if ax > 0.99:
            hz *= 0.8
            hy *= 0.8
        cz = gb + s["guard_h"] / 2 + (0.012 * (ax ** 2.2) if ax > 0.2 else 0.0)  # faint upswept quillons
        b = 0.35  # bevel fraction
        sec = [(hy, -hz * (1 - b)), (hy, hz * (1 - b)), (hy * (1 - b), hz), (-hy * (1 - b), hz),
               (-hy, hz * (1 - b)), (-hy, -hz * (1 - b)), (-hy * (1 - b), -hz), (hy * (1 - b), -hz)]
        rings.append([Vector((x, y, cz + z)) for (y, z) in sec])
    loft(mb, rings, SWORD_ATLAS["guard"], cap_start="fan", cap_end="fan", smooth=True)
    parts["Guard"] = mb.build("Guard", mat, sharp_angle=50)

    # ---- Grip: waisted oval, wrapped leather
    mb = MeshBuilder()
    rings = []
    n = 14
    zt, zb = gb + 0.005, gb - s["grip_len"]
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        z = zt + (zb - zt) * t
        swell = 1.0 - 0.07 * math.sin(math.pi * t) + 0.05 * t
        rings.append(ellipse_ring(Vector((0, 0, z)), Vector((1, 0, 0)), Vector((0, 1, 0)),
                                  s["grip_rx"] * swell, s["grip_ry"] * swell, n))
    loft(mb, rings, SWORD_ATLAS["grip"], cap_start=None, cap_end=None, smooth=True)
    parts["Grip"] = mb.build("Grip", mat, sharp_angle=80)

    # ---- Wheel pommel: revolved around Y (faces aligned with the flats)
    mb = MeshBuilder()
    R = s["pommel_r"]
    prof = [(0.012, 0.060), (0.034, 0.060), (0.046, 0.048), (R * 0.88, 0.042), (R, 0.026),
            (R, -0.026), (R * 0.88, -0.042), (0.046, -0.048), (0.034, -0.060), (0.012, -0.060)]
    pc = Vector((0, 0, zb - R + 0.02))
    seg = 20
    rings = []
    for (r, y) in prof:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            ring.append(pc + Vector((r * math.cos(a), y, r * math.sin(a))))
        rings.append(ring)
    # caps close the boss centres
    loft(mb, rings, SWORD_ATLAS["pommel"], cap_start=pc + Vector((0, 0.064, 0)),
         cap_end=pc + Vector((0, -0.064, 0)), smooth=True)
    # peen block on the bottom where the tang is riveted over
    peen = [ellipse_ring(pc + Vector((0, 0, -R + 0.004 - d)), Vector((1, 0, 0)), Vector((0, 1, 0)),
                         0.018 - d * 0.3, 0.014 - d * 0.3, 8) for d in (0.0, 0.018)]
    loft(mb, peen, SWORD_ATLAS["pommel"], cap_end="fan", smooth=True)
    parts["Pommel"] = mb.build("Pommel", mat, sharp_angle=45)
    return parts


# --------------------------------------------------------------------------
# BOW (English war longbow, yew, braced / un-drawn)
# Local frame: origin = centre of the grip (bow hand); +Z = upper limb;
# -Y = back of the bow (faces the target); +Y = belly / string side.
# --------------------------------------------------------------------------
BOW = dict(
    half_len=1.83 * M / 2,     # 6 ft bow
    grip_half=0.10 * M,        # stiff handle section (does not bend)
    tip_deflect=0.19 * M,      # braced shape: tips sit 19 cm toward the archer
    w_grip=0.032 * M, d_grip=0.036 * M,
    w_fade=0.034 * M, d_fade=0.031 * M,
    w_tip=0.013 * M, d_tip=0.012 * M,
    nock_len=0.05 * M,
    string_r=0.0028 * M,
    serving_r=0.0042 * M,
)


BOW_NOCK_Z = 0.15                         # nocking point, just above the bow hand
ARROW_REST = (0.055, 0.0, 0.15)           # arrow passes on the left of the bow, over the fist


def bow_centerline(z):
    b = BOW
    az = abs(z)
    if az <= b["grip_half"]:
        return 0.0
    k = (az - b["grip_half"]) / (b["half_len"] - b["grip_half"])
    return b["tip_deflect"] * k ** 1.9


def bow_center_slope(z):
    e = 1e-3
    return (bow_centerline(z + e) - bow_centerline(z - e)) / (2 * e)


def d_profile(hw, hd, n=12):
    """D-section: flat-ish back at -Y (u = 0), deep rounded belly at +Y."""
    pts = []
    for k in range(n):
        th = 2 * math.pi * k / n
        x = hw * math.sin(th)
        c = math.cos(th)
        if c > 0:   # back
            y = -hd * 0.42 * c ** 0.35
        else:       # belly
            y = hd * 0.58 * (-c) ** 0.9
        pts.append((x, y))
    return pts


def bow_string_points():
    """Where the string sits in the nocks (rest / braced)."""
    b = BOW
    zt = b["half_len"] - b["nock_len"] * 0.55
    yt = bow_centerline(zt) + b["d_tip"] * 0.5
    return Vector((0, yt, zt)), Vector((0, yt, -zt))


def build_bow(mat):
    b = BOW
    L = b["half_len"]
    g = b["grip_half"]
    mb = MeshBuilder()

    def section_at(z, hw, hd):
        yc = bow_centerline(z)
        slope = bow_center_slope(z)
        tangent = Vector((0, slope, 1)).normalized()
        nrm = Vector((0, 1, -slope)).normalized()  # points toward the belly
        c = Vector((0, yc, z))
        return [c + Vector((1, 0, 0)) * x + nrm * y for (x, y) in d_profile(hw, hd)]

    def dims(z):
        az = abs(z)
        if az <= g:
            return b["w_grip"] / 2, b["d_grip"]
        k = (az - g) / (L - b["nock_len"] - g)
        k = min(max(k, 0.0), 1.0)
        fade = min(1.0, (az - g) / 0.12)
        w0 = b["w_grip"] + (b["w_fade"] - b["w_grip"]) * fade
        d0 = b["d_grip"] + (b["d_fade"] - b["d_grip"]) * fade
        w = w0 + (b["w_tip"] - w0) * k ** 1.1
        d = d0 + (b["d_tip"] - d0) * k ** 1.2
        return w / 2, d

    wood_top = L - b["nock_len"]
    zs = []
    # dense near the grip transitions and the tips
    for i in range(0, 25):
        t = i / 24.0
        zs.append(-wood_top + t * (wood_top - g))
    for z in (-g * 0.99, -g * 0.5, 0.0, g * 0.5, g * 0.99):
        zs.append(z)
    for i in range(0, 25):
        t = i / 24.0
        zs.append(g + t * (wood_top - g))
    zs = sorted(set(round(z, 5) for z in zs))
    rings = [section_at(z, *dims(z)) for z in zs]
    loft(mb, rings, BOW_ATLAS["wood"], smooth=True)
    nwood = len(mb.verts)

    # leather grip wrap (slightly proud of the wood)
    rings = [section_at(z, dims(z)[0] * 1.10, dims(z)[1] * 1.10)
             for z in (-g * 0.95, -g * 0.5, 0.0, g * 0.5, g * 0.95)]
    loft(mb, rings, BOW_ATLAS["grip"], smooth=True)

    # horn nocks at both tips
    for sign in (1, -1):
        zz = [wood_top - 0.02, wood_top + 0.03, wood_top + 0.07, L - 0.01]
        scale = [1.05, 1.18, 0.95, 0.35]
        rings = []
        for z, sc in zip(zz, scale):
            w, d = dims(wood_top)
            rings.append(section_at(sign * z, w * sc, d * sc))
        if sign < 0:
            rings = rings[::-1]
        apex = Vector((0, bow_centerline(L), sign * L))
        if sign > 0:
            loft(mb, rings, BOW_ATLAS["horn"], cap_end=apex, smooth=True)
        else:
            loft(mb, rings, BOW_ATLAS["horn"], cap_start=apex, smooth=True)

    # skin weights: handle rigid, limbs blend toward the tips (limb bending)
    for vi, co in enumerate(mb.verts):
        az = abs(co.z)
        limb = "Limb_Upper" if co.z > 0 else "Limb_Lower"
        if az <= g:
            mb.weight("Bow_Root", vi, 1.0)
        else:
            w = min(1.0, (az - g) / (L - b["nock_len"] - g)) ** 1.0
            if vi >= nwood and az > wood_top - 0.03:
                w = 1.0
            mb.weight(limb, vi, w)
            if w < 1.0:
                mb.weight("Bow_Root", vi, 1.0 - w)
    bow = mb.build("Bow", mat, sharp_angle=60)

    # ---- String: separate object. Rings at the nocks, serving and centre.
    ms = MeshBuilder()
    top, bot = bow_string_points()
    ys = top.y
    serv = 0.12
    nz = BOW_NOCK_Z
    spec = [(top.z, b["string_r"], "Limb_Upper"),
            (nz + serv + 0.02, b["string_r"], "String_Nock"),
            (nz + serv, b["serving_r"], "String_Nock"),
            (nz, b["serving_r"], "String_Nock"),
            (nz - serv, b["serving_r"], "String_Nock"),
            (nz - serv - 0.02, b["string_r"], "String_Nock"),
            (bot.z, b["string_r"], "Limb_Lower")]
    rings = [ellipse_ring(Vector((0, ys, z)), Vector((1, 0, 0)), Vector((0, 1, 0)), r, r, 6) for (z, r, _) in spec]
    idx = loft(ms, rings, BOW_ATLAS["string"], smooth=True)
    for ring, (_, _, grp) in zip(idx, spec):
        for vi in ring:
            ms.weight(grp, vi, 1.0)
    string = ms.build("String", mat, sharp_angle=80)
    return bow, string


# --------------------------------------------------------------------------
# ARROW  (English war arrow, 32" shaft). Local frame: origin = string groove
# of the nock, arrow points along -Y (= Roblox LookVector after export).
# --------------------------------------------------------------------------
ARROW = dict(
    length=0.81 * M,          # nock groove -> head socket
    r_mid=0.0115 * M / 2,
    r_end=0.0090 * M / 2,
    fletch_len=0.20 * M,
    fletch_h=0.016 * M,
    fletch_start=0.035 * M,
)


def build_arrow(mat, head_type="bodkin_long", fletch="fletch_grey", name="Arrow"):
    a = ARROW
    L = a["length"]
    parts = {}
    ax = Vector((0, -1, 0))  # arrow direction
    X, Z = Vector((1, 0, 0)), Vector((0, 0, 1))

    def P(d, x=0.0, z=0.0):
        return ax * d + X * x + Z * z

    # ---- Shaft (6-sided, barrelled taper)
    mb = MeshBuilder()
    rings = []
    for t in (0.0, 0.2, 0.45, 0.7, 0.9, 1.0):
        d = 0.05 + t * (L - 0.05)
        r = a["r_end"] + (a["r_mid"] - a["r_end"]) * math.sin(math.pi * min(1.0, t * 1.1)) ** 0.6
        if t == 1.0:
            r = a["r_mid"] * 0.95
        rings.append(ellipse_ring(P(d), X, Z, r, r, 6))
    loft(mb, rings, ARROW_ATLAS["shaft"], smooth=True)
    # thread bindings at both ends of the fletching
    for d0 in (a["fletch_start"] - 0.01, a["fletch_start"] + a["fletch_len"]):
        rr = a["r_end"] * 1.18
        rings = [ellipse_ring(P(d0 + dd), X, Z, rr, rr, 6) for dd in (0.0, 0.035)]
        loft(mb, rings, ARROW_ATLAS["binding"], smooth=True)
    parts["Shaft"] = mb.build(name + "_Shaft", mat, sharp_angle=70)

    # ---- Nock: horn insert with a groove (inset cap)
    mb = MeshBuilder()
    rn = a["r_end"] * 1.12
    rings = [ellipse_ring(P(d), X, Z, rn * s, rn * s, 6) for d, s in ((0.0, 0.9), (0.012, 1.0), (0.06, 1.0))]
    loft(mb, rings, ARROW_ATLAS["nock"], cap_start=P(0.018), cap_end="fan", smooth=True)
    parts["Nock"] = mb.build(name + "_Nock", mat, sharp_angle=40)

    # ---- Arrowhead
    mb = MeshBuilder()
    rect = ARROW_ATLAS["head"]
    sock0 = L - 0.01
    if head_type in ("bodkin_long", "bodkin_short"):
        sock_len = 0.10 if head_type == "bodkin_long" else 0.09
        blade = 0.20 if head_type == "bodkin_long" else 0.10
        w = 0.020 if head_type == "bodkin_long" else 0.030
        rings = [ellipse_ring(P(sock0), X, Z, a["r_mid"] * 1.15, a["r_mid"] * 1.15, 6),
                 ellipse_ring(P(sock0 + sock_len * 0.6), X, Z, a["r_mid"] * 1.05, a["r_mid"] * 1.05, 6),
                 ellipse_ring(P(sock0 + sock_len), X, Z, w * 0.75, w * 0.75, 4, phase=math.pi / 4),
                 ellipse_ring(P(sock0 + sock_len + blade * 0.25), X, Z, w, w, 4, phase=math.pi / 4)]
        # Re-sample the first two rings to 4 corners so the loft is consistent
        rings[0] = ellipse_ring(P(sock0), X, Z, a["r_mid"] * 1.2, a["r_mid"] * 1.2, 4, phase=math.pi / 4)
        rings[1] = ellipse_ring(P(sock0 + sock_len * 0.6), X, Z, a["r_mid"] * 1.08, a["r_mid"] * 1.08, 4, phase=math.pi / 4)
        loft(mb, rings, rect, cap_start="fan", cap_end=P(sock0 + sock_len + blade), smooth=False)
    else:  # "type16": barbed war head, flat blade with two swept-back barbs
        rings = [ellipse_ring(P(sock0 + d), X, Z, r, r, 6)
                 for d, r in ((0.0, a["r_mid"] * 1.2), (0.07, a["r_mid"] * 1.0))]
        loft(mb, rings, rect, cap_start="fan", smooth=False)
        th = 0.006
        outline = [(0.0, 0.07), (0.045, 0.05), (0.03, 0.10), (0.012, 0.12), (0.0, 0.20),
                   (-0.012, 0.12), (-0.03, 0.10), (-0.045, 0.05)]
        top = [mb.add_vert(P(sock0 + d, x, th)) for (x, d) in outline]
        bot = [mb.add_vert(P(sock0 + d, x, -th)) for (x, d) in outline]
        cz = mb.add_vert(P(sock0 + 0.12, 0, th * 1.6))
        cb = mb.add_vert(P(sock0 + 0.12, 0, -th * 1.6))
        nn = len(outline)
        for k in range(nn):
            k2 = (k + 1) % nn
            uv = [atlas_uv(rect, 0.2, 0.2), atlas_uv(rect, 0.8, 0.2), atlas_uv(rect, 0.5, 0.8)]
            mb.add_face([top[k], top[k2], cz], uv, False)
            mb.add_face([bot[k2], bot[k], cb], uv, False)
            mb.add_face([top[k], bot[k], bot[k2], top[k2]], uv + [atlas_uv(rect, 0.2, 0.8)], False)
    parts["Arrowhead"] = mb.build(name + "_Arrowhead", mat, sharp_angle=30)

    # ---- Fletching: 3 low, long shield-cut vanes with a slight helical cant
    mb = MeshBuilder()
    rect = ARROW_ATLAS[fletch]
    segs = 6
    for vane in range(3):
        ang = math.radians(90 + vane * 120)
        for side in (1, -1):
            base, topv, uvb, uvt = [], [], [], []
            for i in range(segs + 1):
                t = i / segs
                d = a["fletch_start"] + t * a["fletch_len"]
                # shield cut: tall at the back, sweeping low to the front
                hgt = a["fletch_h"] * (0.35 + 0.65 * math.sin(math.pi * min(1.0, (1 - t) * 0.9 + 0.1)) ** 0.8) * (1 - t ** 3)
                hgt = max(hgt, 0.003)
                cant = math.radians(4.0) * t
                rdir = Vector((math.cos(ang + cant), 0, math.sin(ang + cant)))
                off = Vector((-math.sin(ang), 0, math.cos(ang))) * 0.0012 * side
                r0 = a["r_end"] * 0.95
                base.append(mb.add_vert(P(d) + rdir * r0 + off))
                topv.append(mb.add_vert(P(d) + rdir * (r0 + hgt) + off))
                uvb.append(atlas_uv(rect, 0.0, t))
                uvt.append(atlas_uv(rect, hgt / a["fletch_h"] * 0.95, t))
            for i in range(segs):
                f = [base[i], base[i + 1], topv[i + 1], topv[i]]
                uv = [uvb[i], uvb[i + 1], uvt[i + 1], uvt[i]]
                if side < 0:
                    f.reverse()
                    uv.reverse()
                mb.add_face(f, uv, False)
    parts["Fletching"] = mb.build(name + "_Fletching", mat, sharp_angle=89)
    return parts


# --------------------------------------------------------------------------
# R15 test body (rigid parts, one per R15 limb). Realistic "Normal"-scale
# proportions rather than 1-stud Classic blocks so real weapons fit the hands.
# --------------------------------------------------------------------------
def tapered_box(name, z_top, z_bot, top_wh, bot_wh, center_xy=(0, 0), mat=None, bevel=0.06,
                y_top=None, z_top_front=None):
    bm = bmesh.new()
    cx, cy = center_xy
    tw, td = top_wh
    bw, bd = bot_wh
    vs = []
    for (z, w, d) in ((z_bot, bw, bd), (z_top, tw, td)):
        for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            vs.append(bm.verts.new((cx + sx * w / 2, cy + sy * d / 2, z)))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    for f in faces:
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(50))
    if mat:
        me.materials.append(mat)
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = ((co.x + co.y) * 0.5 % 1.0, co.z / 6.0)
    return bpy.data.objects.new(name, me)


def add_box_to(ob, center, size, bevel=0.03):
    """Merge an extra bevelled box (nose, thumb...) into ob's mesh."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    bmesh.ops.scale(bm, vec=size, verts=verts)
    bmesh.ops.translate(bm, vec=center, verts=verts)
    edges = list({e for v in verts for e in v.link_edges})
    bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES", profile=0.5)
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = True
