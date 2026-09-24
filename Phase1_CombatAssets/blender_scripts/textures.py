"""Procedural PBR texture atlases for the Phase 1 combat assets.

Everything is generated with numpy (no Blender dependency) so the maps are
deterministic and can be regenerated at any time.  Each asset uses ONE atlas
(one material) so it can become a single Roblox MeshPart + SurfaceAppearance.

Arrays are indexed [v, u] with row 0 = v 0 (bottom of UV space), matching the
way Blender stores image pixels.  Colour maps are authored in sRGB, all other
maps are linear (Non-Color).  Normal maps use the OpenGL (+Y up) convention,
which is what both Blender and Roblox SurfaceAppearance expect.
"""
import os
import struct
import zlib

import numpy as np


# --------------------------------------------------------------------------
# PNG writer (8-bit RGB), avoids any dependency on PIL
# --------------------------------------------------------------------------
def write_png(path, arr):
    """arr: float array [h, w, 3] in 0..1, row 0 = bottom of the image."""
    a = np.clip(arr, 0.0, 1.0)
    a = (a[::-1] * 255.0 + 0.5).astype(np.uint8)  # PNG row 0 = top
    h, w, _ = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


# --------------------------------------------------------------------------
# Noise helpers
# --------------------------------------------------------------------------
def value_noise(h, w, cells_x, cells_y, rng):
    grid = rng.random((cells_y + 2, cells_x + 2))
    ys = np.linspace(0, cells_y, h, endpoint=False)
    xs = np.linspace(0, cells_x, w, endpoint=False)
    yi = ys.astype(int)
    xi = xs.astype(int)
    fy = ys - yi
    fx = xs - xi
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    g00 = grid[yi][:, xi]
    g10 = grid[yi][:, xi + 1]
    g01 = grid[yi + 1][:, xi]
    g11 = grid[yi + 1][:, xi + 1]
    top = g00 + (g10 - g00) * fx[None, :]
    bot = g01 + (g11 - g01) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(h, w, cx, cy, rng, octaves=4, gain=0.5):
    total = np.zeros((h, w))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        f = 2 ** o
        total += amp * value_noise(h, w, max(1, int(cx * f)), max(1, int(cy * f)), rng)
        norm += amp
        amp *= gain
    return total / norm


def height_to_normal(height, strength):
    dy, dx = np.gradient(height)
    n = np.dstack([-dx * strength, -dy * strength, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def lerp(a, b, t):
    return a + (b - a) * t


def colorize(base, t):
    """base: rgb tuple; t: [h,w] multiplier field -> [h,w,3]."""
    return np.dstack([t * c for c in base])


class Atlas:
    def __init__(self, size):
        self.size = size
        self.color = np.zeros((size, size, 3))
        self.rough = np.ones((size, size)) * 0.8
        self.metal = np.zeros((size, size))
        self.height = np.zeros((size, size))

    def region(self, u0, u1, v0, v1):
        s = self.size
        return slice(int(v0 * s), int(v1 * s)), slice(int(u0 * s), int(u1 * s))

    def put(self, reg, color, rough, metal, height):
        self.color[reg] = color
        self.rough[reg] = rough
        self.metal[reg] = metal
        self.height[reg] = height

    def save(self, folder, prefix, normal_strength):
        os.makedirs(folder, exist_ok=True)
        paths = {}
        paths["color"] = os.path.join(folder, prefix + "_ColorMap.png")
        paths["rough"] = os.path.join(folder, prefix + "_RoughnessMap.png")
        paths["metal"] = os.path.join(folder, prefix + "_MetalnessMap.png")
        paths["normal"] = os.path.join(folder, prefix + "_NormalMap.png")
        write_png(paths["color"], self.color)
        write_png(paths["rough"], np.dstack([self.rough] * 3))
        write_png(paths["metal"], np.dstack([self.metal] * 3))
        write_png(paths["normal"], height_to_normal(self.height, normal_strength))
        return paths


# --------------------------------------------------------------------------
# Material generators (each fills a rectangular atlas region)
# --------------------------------------------------------------------------
def worn_steel(h, w, rng, along_v=True):
    """Forged blade steel: grinding scratches along the blade, grey patina,
    small pits, darker stains.  Not chrome: roughness 0.35-0.6."""
    # scratches: high frequency across, very low along the blade
    s1 = value_noise(h, w, w // 2, 6, rng)
    s2 = value_noise(h, w, w // 5, 3, rng)
    scratches = (s1 * 0.6 + s2 * 0.4)
    stains = fbm(h, w, 3, 10, rng, 5)
    stains = np.clip((stains - 0.60) * 2.0, 0, 1)
    pits = value_noise(h, w, w // 3, h // 3, rng)
    pits = np.clip((pits - 0.95) * 10.0, 0, 1) * 0.6
    mottled = fbm(h, w, 6, 24, rng, 4)
    lum = 0.60 + (scratches - 0.5) * 0.10 + (mottled - 0.5) * 0.08
    lum = lum * (1 - 0.14 * stains) * (1 - 0.35 * pits)
    col = np.dstack([lum * 0.97, lum * 0.98, lum * 1.0])
    # slight brown in stains (old oil / light corrosion)
    col = lerp(col, np.dstack([lum * 0.72, lum * 0.62, lum * 0.52]), stains[..., None] * 0.35)
    rough = 0.38 + (scratches - 0.5) * 0.12 + stains * 0.22 + pits * 0.2 + (mottled - 0.5) * 0.08
    metal = 1.0 - stains * 0.25 - pits * 0.3
    height = (scratches - 0.5) * 0.25 - pits * 0.15 + (mottled - 0.5) * 0.15
    return col, rough, metal, height


def dark_steel(h, w, rng):
    """Darkened (heat blued/black-oxide) steel for guard and pommel, with
    hammer marks and rubbed high spots."""
    hammer = fbm(h, w, 10, 10, rng, 3)
    grain = fbm(h, w, 40, 40, rng, 3)
    wear = np.clip((fbm(h, w, 4, 4, rng, 4) - 0.55) * 3.5, 0, 1)
    lum = 0.24 + (hammer - 0.5) * 0.06 + (grain - 0.5) * 0.05
    lum = lerp(lum, 0.45, wear * 0.6)
    col = np.dstack([lum * 0.95, lum * 0.97, lum * 1.03])
    rough = 0.58 + (grain - 0.5) * 0.15 - wear * 0.18
    metal = 0.88 + wear * 0.1
    height = (hammer - 0.5) * 0.6 + (grain - 0.5) * 0.1
    return col, rough, metal, height


def leather_wrap(h, w, rng, wraps=14.0, span_ratio=1.0):
    """Spiral leather wrap: u around the grip, v along it."""
    u = np.linspace(0, 1, w, endpoint=False)[None, :]
    v = np.linspace(0, 1, h, endpoint=False)[:, None]
    phase = (v * wraps + u) % 1.0
    band = np.sin(phase * np.pi)  # 0 at seams, 1 in the middle of each strap
    seam = np.clip(1.0 - band * 6.0, 0, 1)
    grain = fbm(h, w, 60, 60, rng, 3)
    wear = fbm(h, w, 4, 12, rng, 4)
    lum = 0.55 + (grain - 0.5) * 0.25 + band * 0.25
    base = np.array([0.30, 0.18, 0.10])
    col = colorize(base, lum) * (1 - 0.6 * seam[..., None])
    col = lerp(col, colorize(np.array([0.42, 0.30, 0.20]), lum), np.clip((wear - 0.55) * 2, 0, 1)[..., None] * band[..., None])
    rough = 0.72 + (grain - 0.5) * 0.12 - band * 0.08 + seam * 0.1
    metal = np.zeros((h, w))
    height = band ** 0.5 * 0.8 + (grain - 0.5) * 0.12
    return col, rough, metal, height


def wood(h, w, rng, base_light, base_dark, rings=30, warp=2.5, along_v=True):
    u = np.linspace(0, 1, w, endpoint=False)[None, :]
    v = np.linspace(0, 1, h, endpoint=False)[:, None]
    wobble = fbm(h, w, 3, 5, rng, 3)
    lines = np.sin((u * rings + wobble * warp) * 2 * np.pi) * 0.5 + 0.5
    fine = value_noise(h, w, w // 2, 12, rng)
    knots = np.clip((fbm(h, w, 4, 30, rng, 3) - 0.72) * 5.0, 0, 1)
    t = np.clip(lines * 0.6 + (fine - 0.5) * 0.4 + 0.2, 0, 1)
    col = lerp(np.array(base_light)[None, None, :], np.array(base_dark)[None, None, :], t[..., None])
    col = lerp(col, np.array(base_dark)[None, None, :] * 0.7, knots[..., None])
    rough = 0.62 + t * 0.12 + knots * 0.05
    metal = np.zeros((h, w))
    height = (lines - 0.5) * 0.15 + (fine - 0.5) * 0.1 - knots * 0.2
    return col, rough, metal, height


def feather(h, w, rng, base, bars=None):
    """Fletching: u across the vane (0 = quill), v along the shaft."""
    u = np.linspace(0, 1, w, endpoint=False)[None, :]
    v = np.linspace(0, 1, h, endpoint=False)[:, None]
    barbs = np.sin((v * 90 + u * 30) * 2 * np.pi) * 0.5 + 0.5
    breaks = np.clip((value_noise(h, w, 4, 30, rng) - 0.8) * 5, 0, 1)
    lum = 0.9 + (barbs - 0.5) * 0.15 - breaks * 0.2
    col = colorize(np.array(base), lum)
    if bars is not None:
        stripe = (np.sin(v * bars * 2 * np.pi + u * 3) > 0.35).astype(float)
        col = col * (1 - 0.45 * stripe[..., None])
    quill = np.clip(1 - u * 18, 0, 1)
    col = lerp(col, np.array([0.80, 0.76, 0.66])[None, None, :], quill[..., None])
    rough = 0.82 + np.zeros((h, w))
    metal = np.zeros((h, w))
    height = (barbs - 0.5) * 0.3 + quill * 0.5
    return col, rough, metal, height


def iron_forged(h, w, rng):
    scale = fbm(h, w, 12, 12, rng, 4)
    rust = np.clip((fbm(h, w, 6, 6, rng, 4) - 0.6) * 3.0, 0, 1)
    lum = 0.22 + (scale - 0.5) * 0.12
    col = np.dstack([lum, lum * 0.98, lum * 0.97])
    col = lerp(col, np.array([0.30, 0.17, 0.09])[None, None, :], rust[..., None] * 0.6)
    rough = 0.6 + (scale - 0.5) * 0.2 + rust * 0.2
    metal = 0.85 - rust * 0.5
    height = (scale - 0.5) * 0.5
    return col, rough, metal, height


def twisted_cord(h, w, rng, base, twists=160):
    u = np.linspace(0, 1, w, endpoint=False)[None, :]
    v = np.linspace(0, 1, h, endpoint=False)[:, None]
    strands = np.sin((v * twists + u * 3) * 2 * np.pi) * 0.5 + 0.5
    n = fbm(h, w, 20, 40, rng, 3)
    lum = 0.8 + strands * 0.2 + (n - 0.5) * 0.2
    col = colorize(np.array(base), lum)
    rough = 0.85 + np.zeros((h, w))
    metal = np.zeros((h, w))
    return col, rough, metal, strands * 0.6


def horn(h, w, rng):
    streak = fbm(h, w, 30, 3, rng, 4)
    lum = 0.6 + (streak - 0.5) * 0.8
    col = colorize(np.array([0.16, 0.12, 0.09]), lum)
    return col, 0.45 + (streak - 0.5) * 0.2, np.zeros((h, w)), (streak - 0.5) * 0.2


# --------------------------------------------------------------------------
# Atlas layouts (the UV rectangles are also used by meshes.py)
# --------------------------------------------------------------------------
SWORD_ATLAS = {
    "blade": (0.00, 0.30, 0.00, 1.00),
    "guard": (0.30, 0.62, 0.50, 1.00),
    "pommel": (0.30, 0.62, 0.00, 0.50),
    "grip": (0.62, 1.00, 0.00, 1.00),
}

BOW_ATLAS = {
    "wood": (0.00, 0.50, 0.00, 1.00),
    "grip": (0.50, 0.75, 0.00, 0.50),
    "horn": (0.50, 0.75, 0.50, 1.00),
    "string": (0.75, 1.00, 0.00, 1.00),
}

ARROW_ATLAS = {
    "shaft": (0.00, 0.25, 0.00, 1.00),
    "head": (0.25, 0.50, 0.00, 0.50),
    "nock": (0.25, 0.50, 0.50, 1.00),
    "fletch_grey": (0.50, 0.75, 0.50, 1.00),
    "fletch_white": (0.75, 1.00, 0.50, 1.00),
    "fletch_barred": (0.50, 0.75, 0.00, 0.50),
    "binding": (0.75, 1.00, 0.00, 0.50),
}


def _fill(atlas, rect, gen):
    reg = atlas.region(*rect)
    h = reg[0].stop - reg[0].start
    w = reg[1].stop - reg[1].start
    col, rough, metal, height = gen(h, w)
    atlas.put(reg, col, rough, metal, height)


def build_all(folder, seed=1395):
    rng = np.random.default_rng(seed)
    out = {}

    a = Atlas(1024)
    _fill(a, SWORD_ATLAS["blade"], lambda h, w: worn_steel(h, w, rng))
    _fill(a, SWORD_ATLAS["guard"], lambda h, w: dark_steel(h, w, rng))
    _fill(a, SWORD_ATLAS["pommel"], lambda h, w: dark_steel(h, w, rng))
    _fill(a, SWORD_ATLAS["grip"], lambda h, w: leather_wrap(h, w, rng, wraps=13))
    out["Sword"] = a.save(folder, "Sword", normal_strength=3.0)

    b = Atlas(1024)
    # English yew: pale sapwood on the back, orange-brown heartwood belly.
    _fill(b, BOW_ATLAS["wood"], lambda h, w: _yew(h, w, rng))
    _fill(b, BOW_ATLAS["grip"], lambda h, w: leather_wrap(h, w, rng, wraps=9))
    _fill(b, BOW_ATLAS["horn"], lambda h, w: horn(h, w, rng))
    _fill(b, BOW_ATLAS["string"], lambda h, w: twisted_cord(h, w, rng, (0.78, 0.72, 0.58)))
    out["Bow"] = b.save(folder, "Bow", normal_strength=4.0)

    c = Atlas(512)
    _fill(c, ARROW_ATLAS["shaft"], lambda h, w: wood(h, w, rng, (0.74, 0.62, 0.45), (0.58, 0.45, 0.30), rings=6, warp=1.0))
    _fill(c, ARROW_ATLAS["head"], lambda h, w: iron_forged(h, w, rng))
    _fill(c, ARROW_ATLAS["nock"], lambda h, w: horn(h, w, rng))
    _fill(c, ARROW_ATLAS["fletch_grey"], lambda h, w: feather(h, w, rng, (0.48, 0.48, 0.50)))
    _fill(c, ARROW_ATLAS["fletch_white"], lambda h, w: feather(h, w, rng, (0.86, 0.85, 0.80)))
    _fill(c, ARROW_ATLAS["fletch_barred"], lambda h, w: feather(h, w, rng, (0.50, 0.38, 0.24), bars=7))
    _fill(c, ARROW_ATLAS["binding"], lambda h, w: twisted_cord(h, w, rng, (0.45, 0.20, 0.14), twists=60))
    out["Arrow"] = c.save(folder, "Arrow", normal_strength=3.0)
    return out


def _yew(h, w, rng):
    col, rough, metal, height = wood(h, w, rng, (0.80, 0.52, 0.30), (0.62, 0.34, 0.16), rings=18, warp=3.0)
    # u = 0 / 1 is the centre of the flat back; sapwood covers the back.
    u = np.linspace(0, 1, w, endpoint=False)[None, :]
    sap = np.clip((np.cos(u * 2 * np.pi) - 0.35) * 4.0, 0, 1)
    sap = np.repeat(sap, h, axis=0)
    sap_col = col * np.array([1.18, 1.35, 1.55])[None, None, :]
    col = lerp(col, np.clip(sap_col, 0, 0.92), sap[..., None])
    return col, rough, metal, height


if __name__ == "__main__":
    import sys
    build_all(sys.argv[1] if len(sys.argv) > 1 else "textures")
