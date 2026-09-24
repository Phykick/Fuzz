"""Bake solved poses into Blender Actions (per-frame FK keys on R15 bones)."""
import bpy
from mathutils import Quaternion

import anim


def bake_clip(rig, clip, rest, offset=0, action=None, extra=None):
    """Solve every frame of `clip` and key it onto `rig`.
    Returns (action, list of (frame, Pose))."""
    if action is None:
        action = bpy.data.actions.new(clip.name)
        action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    poses = []
    prev_q = {}
    state = {}
    fcache = {}

    def fc(path, idx, group):
        key = (path, idx)
        if key not in fcache:
            f = action.fcurves.find(path, index=idx) or action.fcurves.new(path, index=idx, action_group=group)
            fcache[key] = f
        return fcache[key]

    for f in range(clip.start, clip.end + 1):
        params = clip.sample(f)
        pose = anim.solve(params, rest, state)
        poses.append((f, pose))
        basis = anim.local_basis(pose, rest)
        for name, m in basis.items():
            loc, q, _ = m.decompose()
            if name in prev_q and prev_q[name].dot(q) < 0:
                q = -q
            prev_q[name] = q
            path_l = f'pose.bones["{name}"].location'
            path_r = f'pose.bones["{name}"].rotation_quaternion'
            for i in range(3):
                fc(path_l, i, name).keyframe_points.insert(f + offset, loc[i], options={"FAST"})
            for i in range(4):
                fc(path_r, i, name).keyframe_points.insert(f + offset, q[i], options={"FAST"})
    for f in action.fcurves:
        for kp in f.keyframe_points:
            kp.interpolation = "LINEAR"   # every frame is keyed; linear = exact
        f.update()
    for name, frame in clip.markers.items():
        m = action.pose_markers.new(name)
        m.frame = frame + offset
    action.frame_range = (clip.start + offset, clip.end + offset)
    action.use_frame_range = True
    action["loop"] = clip.loop
    action["category"] = clip.category
    return action, poses
