"""Render QC contact sheets from CombatAssets_Phase1.blend (Cycles, CPU).

    python3 blender_scripts/render_previews.py [demo|clips|all] [clip-name-filter]

demo  -> previews/demo_sheet.png (key moments of the showcase timeline)
clips -> previews/clip_<name>.png (one strip per clip at its markers)
"""
import json
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "previews")
SIZE = int(os.environ.get("PREVIEW_SIZE", "360"))


def setup():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "CombatAssets_Phase1.blend"))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("PREVIEW_SAMPLES", "12"))
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.film_transparent = False
    # hide export masters (they sit beside the character)
    for name in ("SWORD", "BOW", "ARROW"):
        bpy.data.collections[name].hide_render = True
    return sc


def render_to_array(sc, path):
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    a = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    return a


def save_sheet(tiles, cols, path):
    h, w = tiles[0].shape[:2]
    rows = int(math.ceil(len(tiles) / cols))
    sheet = np.ones((rows * h, cols * w, 4), dtype=np.float32)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        sheet[(rows - 1 - r) * h:(rows - r) * h, c * w:(c + 1) * w] = t
    img = bpy.data.images.new("sheet", cols * w, rows * h)
    img.pixels.foreach_set(sheet.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def cam_for(sc, name, pos, aim, lens=40):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        sc.collection.objects.link(cam)
    from mathutils import Vector
    cam.location = pos
    cam.rotation_euler = (Vector(aim) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    return cam


def demo(sc):
    frames = [int(m.frame) for m in sc.timeline_markers if not m.name.startswith(" ")]
    extra = [int(m.frame) for m in sc.timeline_markers if m.name.strip() in
             ("Impact", "BlockHold", "FullDraw", "Release", "ArrowGrab", "Nocked")]
    frames = sorted(set(frames + extra))
    tiles = []
    tmp = os.path.join(OUT, "_tmp.png")
    for f in frames:
        sc.frame_set(f)
        # pick the camera bound to the most recent camera marker
        cams = [m for m in sc.timeline_markers if m.camera and m.frame <= f]
        if cams:
            sc.camera = max(cams, key=lambda m: m.frame).camera
        tiles.append(render_to_array(sc, tmp))
    save_sheet(tiles, 6, os.path.join(OUT, "demo_sheet.png"))
    with open(os.path.join(OUT, "demo_sheet_frames.json"), "w") as fh:
        json.dump(frames, fh)
    os.remove(tmp)


def clips(sc, filt=None):
    rig = bpy.data.objects["R15_Rig"]
    sword = bpy.data.objects["Sword_Held"]
    bow = bpy.data.objects["Bow_Rig_Held"]
    arrow = bpy.data.objects["Arrow_Held"]
    manifest = json.load(open(os.path.join(ROOT, "docs", "animation_manifest.json")))
    for m in sc.timeline_markers:
        m.camera = None   # demo camera cuts would override the QC cameras
    tmp = os.path.join(OUT, "_tmp.png")
    front = cam_for(sc, "CAM_QC_Front", (-5.5, -8.5, 4.4), (0, -1.0, 2.8))   # opponent's-eye 3/4
    side = cam_for(sc, "CAM_QC_Side", (9.5, -1.2, 4.2), (0, -0.8, 2.9))     # from the character's left
    for clip in manifest["clips"]:
        name = clip["name"]
        if filt and filt not in name:
            continue
        rig.animation_data.action = bpy.data.actions[name]
        is_bow = clip["category"] == "BOW"
        for ob, act in ((bow, "PROP_BowString_" + name), (arrow, "PROP_Arrow_" + name)):
            ob.animation_data.action = bpy.data.actions.get(act)
        sword.animation_data.action = None
        bow.scale = (1, 1, 1) if is_bow else (1e-4,) * 3
        sword.scale = (1e-4,) * 3 if is_bow else (1, 1, 1)
        if not is_bow:
            arrow.animation_data.action = None
            arrow.scale = (1e-4,) * 3
        marks = [m["frame"] for m in clip["markers"]]
        frames = sorted(set([0, clip["frames"]] + marks))
        if len(frames) < 5:
            frames = sorted(set(frames + [round(clip["frames"] * t) for t in (0.25, 0.5, 0.75)]))
        tiles = []
        for f in frames:
            sc.frame_set(f)
            for cam in (front, side):
                sc.camera = cam
                tiles.append(render_to_array(sc, tmp))
        # two rows: front view on top, side view below
        ordered = tiles[0::2] + tiles[1::2]
        save_sheet(ordered, len(frames), os.path.join(OUT, "clip_%s.png" % name))
        print("sheet", name, frames, flush=True)
    if os.path.exists(tmp):
        os.remove(tmp)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.endswith(".py")]
    what = args[0] if args else "all"
    filt = args[1] if len(args) > 1 else None
    os.makedirs(OUT, exist_ok=True)
    sc = setup()
    if what in ("demo", "all"):
        demo(sc)
    if what in ("clips", "all"):
        clips(sc, filt)
