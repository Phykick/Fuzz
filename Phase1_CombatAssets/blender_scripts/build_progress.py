"""Quick progress build: weapons + R15 rig in rest pose (no animation yet)."""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import bpy
from mathutils import Matrix
bpy.ops.wm.read_factory_settings(use_empty=True)
import meshes, rig
ROOT = os.path.dirname(HERE); T = os.path.join(ROOT, "textures")
def mp(p): return {k: os.path.join(T, f"{p}_{v}.png") for k, v in (("color","ColorMap"),("rough","RoughnessMap"),("metal","MetalnessMap"),("normal","NormalMap"))}
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"; sc.unit_settings.scale_length = 0.01
def coll(name, parent=None):
    c = bpy.data.collections.new(name); (parent or sc.collection).children.link(c); return c
root = coll("COMBAT_ASSETS")
cs, cb, ca, cr = coll("SWORD", root), coll("BOW", root), coll("ARROW", root), coll("R15_RIG", root)
sm, bm, am = meshes.pbr_material("M_Sword", mp("Sword")), meshes.pbr_material("M_Bow", mp("Bow")), meshes.pbr_material("M_Arrow", mp("Arrow"))
sw = bpy.data.objects.new("Sword", None); cs.objects.link(sw); sw.location.x = -3
for ob in meshes.build_sword(sm).values(): cs.objects.link(ob); ob.parent = sw
bw = bpy.data.objects.new("Bow_Root", None); cb.objects.link(bw); bw.location = (-4.5, 0, 3)
bow, st = meshes.build_bow(bm)
for ob in (bow, st): cb.objects.link(ob); ob.parent = bw
for i, (h, f) in enumerate([("bodkin_long","fletch_grey"),("bodkin_short","fletch_white"),("type16","fletch_barred")]):
    e = bpy.data.objects.new(f"Arrow_{['A','B','C'][i]}", None); ca.objects.link(e); e.location = (3 + 0.3*i, 0, 0.1); e.rotation_euler = (math.radians(-90), 0, 0)
    for ob in meshes.build_arrow(am, h, f, e.name).values(): ca.objects.link(ob); ob.parent = e
r = rig.build_armature(); sc.collection.objects.unlink(r); cr.objects.link(r)
for ob in rig.build_body(r).values(): cr.objects.link(ob)
out = os.path.join(ROOT, "CombatAssets_Phase1_PROGRESS.blend")
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
print("saved", out)
