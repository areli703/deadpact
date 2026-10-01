#!/usr/bin/env python3
"""
DEADPACT — district hero render.

A real 3D render of the night-time district: perspective-projected
building blocks with emissive window grids, a wet street, street lamps
with light pools and reflections, atmospheric depth fog, a horde
silhouetted on the road, and a player in the foreground.

No meshes, no external assets — everything is generated from the same
kind of numbers the game's Config.lua holds (district size, block
counts, building heights, colour palette).
"""

import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

# --------------------------------------------------------------------------
# OUTPUT
# --------------------------------------------------------------------------
W, H = 1600, 900
SS = 2  # supersample factor

# --------------------------------------------------------------------------
# PALETTE (mirrors the game's art direction)
# --------------------------------------------------------------------------
AMBER = (255, 182, 72)
BLOOD = (200, 50, 31)
COLD = (127, 196, 255)
SKY_TOP = (9, 11, 17)
SKY_HORIZON = (46, 34, 30)
FOG_COLOR = (30, 33, 42)
ASPHALT = (14, 16, 21)
SIDEWALK = (23, 26, 33)
CONCRETE = (26, 29, 37)
CONCRETE_DARK = (17, 19, 25)

# --------------------------------------------------------------------------
# CAMERA — street level, low, looking down the road
# --------------------------------------------------------------------------
EYE = (-7.0, 7.5, -18.0)
TGT = (1.5, 26.0, 52.0)
FOV = 62.0

# --------------------------------------------------------------------------
# WORLD — district geometry
# --------------------------------------------------------------------------
ROAD_HALF = 13.0
WALK_W = 3.5
BUILD_NEAR = -10.0   # z where the block row starts
BUILD_FAR = 230.0    # z where the fog eats it
BLOCK_DEPTH = 16.0

FOG_START = 45.0
FOG_END = 265.0

random.seed(7)


# --------------------------------------------------------------------------
# VECTOR / PROJECTION
# --------------------------------------------------------------------------
def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def norm(a):
    l = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) or 1.0
    return (a[0] / l, a[1] / l, a[2] / l)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


_f = norm(sub(TGT, EYE))
_r = norm(cross(_f, (0.0, 1.0, 0.0)))
_u = cross(_r, _f)
_TAN = math.tan(math.radians(FOV) * 0.5)


def project(p):
    """World point -> (screen_x, screen_y, depth). None if behind camera."""
    d = sub(p, EYE)
    z = dot(d, _f)
    if z < 0.6:
        return None
    x = dot(d, _r)
    y = dot(d, _u)
    aspect = W / float(H)
    sx = (x / (z * _TAN * aspect)) * (W * 0.5) + W * 0.5
    sy = H * 0.5 - (y / (z * _TAN)) * (H * 0.5)
    return (sx, sy, z)


def fog_mix(color, depth, warm_bias=0.0):
    """Blend a colour toward fog by distance."""
    t = (depth - FOG_START) / (FOG_END - FOG_START)
    t = max(0.0, min(1.0, t))
    t = t * t * 0.92
    fc = (
        FOG_COLOR[0] + warm_bias * 16,
        FOG_COLOR[1] + warm_bias * 9,
        FOG_COLOR[2] + warm_bias * 3,
    )
    return tuple(
        int(color[i] + (fc[i] - color[i]) * t) for i in range(3)
    )


def shade(base, n, depth, light_dir, ambient=0.30, warm_bias=0.0):
    l = max(0.0, dot(n, light_dir))
    k = ambient + 0.70 * l
    c = tuple(min(255, int(base[i] * k)) for i in range(3))
    return fog_mix(c, depth, warm_bias)


# --------------------------------------------------------------------------
# GEOMETRY BUFFER
# --------------------------------------------------------------------------
FACES = []  # (depth, polygon_points, fill_color)


def add_quad(p0, p1, p2, p3, color, normal, light_dir, warm_bias=0.0,
             emissive=None, depth_bias=0.0):
    pts = [project(p0), project(p1), project(p2), project(p3)]
    if any(p is None for p in pts):
        return
    depth = sum(p[2] for p in pts) / 4.0 + depth_bias
    fill = emissive if emissive is not None else shade(
        color, normal, depth, light_dir, warm_bias=warm_bias
    )
    FACES.append((depth, [(p[0], p[1]) for p in pts], fill))


def add_box(x, y, z, sx, sy, sz, color, light_dir, warm_bias=0.0):
    """Axis-aligned box anchored at (x, y, z) extending +sx, +sy, +sz."""
    x0, x1 = x, x + sx
    y0, y1 = y, y + sy
    z0, z1 = z, z + sz
    # -z face (facing camera)
    add_quad((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             color, (0, 0, -1), light_dir, warm_bias)
    # +z face
    add_quad((x1, y0, z1), (x0, y0, z1), (x0, y1, z1), (x1, y1, z1),
             color, (0, 0, 1), light_dir, warm_bias)
    # -x side
    add_quad((x0, y0, z1), (x0, y0, z0), (x0, y1, z0), (x0, y1, z1),
             color, (-1, 0, 0), light_dir, warm_bias)
    # +x side
    add_quad((x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0),
             color, (1, 0, 0), light_dir, warm_bias)
    # top
    add_quad((x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1),
             color, (0, 1, 0), light_dir, warm_bias)


# --------------------------------------------------------------------------
# BUILD THE DISTRICT
# --------------------------------------------------------------------------
LIGHT_DIR = norm((-0.35, 0.72, -0.60))

buildings = []   # (x, z, sx, sz, height)
lamps = []       # (x, z)


def emit_windows(x0, x1, y0, y1, z, facing_x, light_dir):
    """Grid of window quads on a street-facing facade at plane z."""
    cols = max(2, int((x1 - x0) / 4.2))
    rows = max(2, int((y1 - y0) / 3.6))
    cw = (x1 - x0) / cols
    ch = (y1 - y0) / rows
    for c in range(cols):
        for r in range(rows):
            wx0 = x0 + c * cw + cw * 0.22
            wx1 = x0 + (c + 1) * cw - cw * 0.22
            wy0 = y0 + r * ch + ch * 0.24
            wy1 = y0 + (r + 1) * ch - ch * 0.24
            roll = random.random()
            if roll < 0.30:
                col = AMBER
                emis = tuple(int(x * random.uniform(0.55, 1.0)) for x in col)
            elif roll < 0.40:
                col = COLD
                emis = tuple(int(x * 0.7) for x in COLD)
            elif roll < 0.55:
                col = (58, 55, 50)
                emis = (70, 66, 60)
            else:
                continue
            add_quad((wx0, wy0, z), (wx1, wy0, z), (wx1, wy1, z), (wx0, wy1, z),
                     col, (0, 0, facing_x), light_dir, emissive=emis,
                     depth_bias=-0.02)


z = BUILD_NEAR
while z < BUILD_FAR:
    gap = random.choice([0.0, 0.0, 5.0, 9.0])
    for side in (-1, 1):
        depth_b = random.uniform(11.0, 19.0)
        # occasionally a wider block or a narrow alley building
        if random.random() < 0.22:
            depth_b *= 1.7
        height = random.choice([16, 22, 27, 33, 40, 48, 58, 72])
        if random.random() < 0.18:
            height = random.randint(70, 104)
        x_edge = side * (ROAD_HALF + WALK_W)
        bx = x_edge if side > 0 else x_edge - depth_b
        shade_mix = random.uniform(0.88, 1.06)
        base = tuple(min(255, int(c * shade_mix)) for c in CONCRETE)
        if random.random() < 0.35:
            base = CONCRETE_DARK
        add_box(bx, 0.0, z, depth_b, float(height), BLOCK_DEPTH, base, LIGHT_DIR)
        # parapet lip
        add_box(bx - 0.4, float(height), z - 0.4, depth_b + 0.8, 1.2,
                BLOCK_DEPTH + 0.8, tuple(int(c * 0.8) for c in base), LIGHT_DIR)
        # rooftop antenna on tall ones
        if height > 55:
            ax = bx + depth_b * 0.5
            add_box(ax - 0.3, float(height) + 1.2, z + BLOCK_DEPTH * 0.5 - 0.3,
                    0.6, float(random.randint(6, 14)), 0.6,
                    (38, 40, 46), LIGHT_DIR)
        # street-facing windows
        if side > 0:
            emit_windows(bx + 0.6, bx + depth_b - 0.6, 2.4, float(height) - 2.0,
                         z - 0.03, -1, LIGHT_DIR)
        buildings.append((bx, z, depth_b, BLOCK_DEPTH, height))
    z += BLOCK_DEPTH + gap
    if random.random() < 0.85:
        lamps.append((-ROAD_HALF - 1.4, z + BLOCK_DEPTH * 0.5))
    if random.random() < 0.85:
        lamps.append((ROAD_HALF + 1.4, z + BLOCK_DEPTH * 0.5))

# distant skyline silhouettes beyond the fog
for i in range(26):
    sx = random.uniform(-190.0, 190.0)
    sz = random.uniform(BUILD_FAR, BUILD_FAR + 190.0)
    sw = random.uniform(14.0, 34.0)
    sh = random.uniform(24.0, 92.0)
    add_box(sx, 0.0, sz, sw, sh, sw, (16, 18, 24), LIGHT_DIR)


# --------------------------------------------------------------------------
# RENDER
# --------------------------------------------------------------------------
img = Image.new("RGB", (W, H), SKY_TOP)
d = ImageDraw.Draw(img)

# --- sky gradient -------------------------------------------------------
for y in range(H):
    t = y / float(H)
    t = t ** 0.75
    # warm glow low near the horizon, cold at the top
    warm = max(0.0, (t - 0.34) / 0.66)
    c = (
        int(SKY_TOP[0] + (SKY_HORIZON[0] - SKY_TOP[0]) * t),
        int(SKY_TOP[1] + (SKY_HORIZON[1] - SKY_TOP[1]) * t),
        int(SKY_TOP[2] + (SKY_HORIZON[2] - SKY_TOP[2]) * t),
    )
    c = (int(c[0] + warm * 34), int(c[1] + warm * 14), int(c[2] + warm * 2))
    d.line([(0, y), (W, y)], fill=c)

# --- ground / road ------------------------------------------------------
gz_near, gz_far = -60.0, BUILD_FAR + 150.0
road_near_l = project((-ROAD_HALF, 0.0, gz_near))
road_near_r = project((ROAD_HALF, 0.0, gz_near))
road_far_r = project((ROAD_HALF, 0.0, gz_far))
road_far_l = project((-ROAD_HALF, 0.0, gz_far))
if all(p is not None for p in (road_near_l, road_near_r, road_far_r, road_far_l)):
    poly = [(road_near_l[0], road_near_l[1]), (road_near_r[0], road_near_r[1]),
            (road_far_r[0], road_far_r[1]), (road_far_l[0], road_far_l[1])]
    d.polygon(poly, fill=ASPHALT)
    # warm wet reflection down the middle of the road
    for band in range(26):
        t0 = band / 26.0
        t1 = (band + 1) / 26.0
        z0 = gz_near + (gz_far - gz_near) * (1 - t0) ** 2.0
        z1 = gz_near + (gz_far - gz_near) * (1 - t1) ** 2.0
        a = project((-ROAD_HALF * 0.7, 0.0, z0))
        b = project((ROAD_HALF * 0.7, 0.0, z0))
        c2 = project((ROAD_HALF * 0.7, 0.0, z1))
        e = project((-ROAD_HALF * 0.7, 0.0, z1))
        if any(p is None for p in (a, b, c2, e)):
            continue
        alpha = max(0.0, 1.0 - t0) * 0.10
        col = (int(120 * alpha), int(72 * alpha), int(30 * alpha))
        d.polygon([(a[0], a[1]), (b[0], b[1]), (c2[0], c2[1]), (e[0], e[1])],
                  fill=col)

# sidewalks (raised strips)
for side in (-1, 1):
    x0 = side * ROAD_HALF
    x1 = side * (ROAD_HALF + WALK_W)
    a = project((x0, 0.06, gz_near))
    b = project((x1, 0.06, gz_near))
    c2 = project((x1, 0.06, BUILD_FAR))
    e = project((x0, 0.06, BUILD_FAR))
    if all(p is not None for p in (a, b, c2, e)):
        d.polygon([(a[0], a[1]), (b[0], b[1]), (c2[0], c2[1]), (e[0], e[1])],
                  fill=SIDEWALK)

# --- all geometry, far to near -----------------------------------------
FACES.sort(key=lambda f: -f[0])
for _depth, pts, fill in FACES:
    d.polygon(pts, fill=fill)

# --------------------------------------------------------------------------
# LIGHT: additive glow layer (lamp pools, reflections, bloom source)
# --------------------------------------------------------------------------
glow = Image.new("RGB", (W, H), (0, 0, 0))
gd = ImageDraw.Draw(glow)


def blob(cx, cy, r, color, power=1.0, squash=1.0):
    steps = 12
    for i in range(steps, 0, -1):
        t = i / float(steps)
        rr = r * t
        a = (1.0 - t) ** 2.0 * power
        c = (int(color[0] * a), int(color[1] * a), int(color[2] * a))
        gd.ellipse([cx - rr, cy - rr * squash, cx + rr, cy + rr * squash],
                   fill=c)


for lx, lz in lamps:
    p = project((lx, 7.6, lz))
    if p is None:
        continue
    sx, sy, depth = p
    fade = max(0.0, 1.0 - depth / (FOG_END + 40.0))
    if fade <= 0.01:
        continue
    # the lamp head
    blob(sx, sy, 30 * SS * (1.0 / max(0.4, depth / 40.0)) * 0.5 + 8,
         AMBER, power=0.85 * fade, squash=1.0)
    # pool of light on the ground
    foot = project((lx, 0.0, lz))
    if foot:
        blob(foot[0], foot[1], 150 * SS / max(1.0, depth / 26.0),
             (255, 150, 60), power=0.42 * fade, squash=0.30)
        # wet reflection smear beneath
        blob(foot[0], foot[1] + 26 * SS, 60 * SS / max(1.0, depth / 30.0),
             (255, 140, 55), power=0.30 * fade, squash=1.9)

# faint warm city haze low on the horizon
blob(W * 0.52, H * 0.52, 620 * SS, (255, 130, 45), power=0.16, squash=0.30)

glow = glow.filter(ImageFilter.GaussianBlur(18 * SS / 2))
img = ImageChops.screen(img, glow)

# tighter bloom pass for the hot cores
core = glow.filter(ImageFilter.GaussianBlur(5 * SS / 2))
img = ImageChops.screen(img, core)

d = ImageDraw.Draw(img)

# --------------------------------------------------------------------------
# THE HORDE — silhouettes shuffling down the road
# --------------------------------------------------------------------------
def zombie_sil(gd2, base, scale, depth, seed):
    rnd = random.Random(seed)
    fx, fy = base
    h = 62.0 * scale
    w = 20.0 * scale
    lean = rnd.uniform(-0.16, 0.16)
    body = (int(6 + rnd.uniform(0, 5)), int(7 + rnd.uniform(0, 5)), int(9 + rnd.uniform(0, 5)))
    sway = rnd.uniform(-0.30, 0.30)
    # legs
    gd2.polygon([(fx - w * 0.35, fy), (fx - w * 0.05, fy),
                 (fx - w * 0.02, fy - h * 0.48), (fx - w * 0.42, fy - h * 0.46)],
                fill=body)
    gd2.polygon([(fx + w * 0.05, fy), (fx + w * 0.38, fy),
                 (fx + w * 0.44, fy - h * 0.48), (fx + w * 0.05, fy - h * 0.46)],
                fill=body)
    # torso
    gd2.polygon([(fx - w * 0.48, fy - h * 0.44), (fx + w * 0.46, fy - h * 0.44),
                 (fx + w * 0.40 + lean * w, fy - h * 0.80),
                 (fx - w * 0.44 + lean * w, fy - h * 0.80)], fill=body)
    # head
    hx = fx + lean * w * 1.4
    hy = fy - h * 0.86
    gd2.ellipse([hx - w * 0.26, hy - w * 0.30, hx + w * 0.26, hy + w * 0.24],
                fill=body)
    # arms
    gd2.polygon([(fx - w * 0.46, fy - h * 0.78),
                 (fx - w * 0.20, fy - h * 0.76),
                 (fx - w * 0.30 + sway * w, fy - h * 0.42),
                 (fx - w * 0.56 + sway * w, fy - h * 0.44)], fill=body)
    gd2.polygon([(fx + w * 0.44, fy - h * 0.78),
                 (fx + w * 0.18, fy - h * 0.76),
                 (fx + w * 0.28 - sway * w, fy - h * 0.42),
                 (fx + w * 0.54 - sway * w, fy - h * 0.44)], fill=body)


horde = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
hd = ImageDraw.Draw(horde)

placements = []
for i in range(26):
    zz = random.uniform(52.0, 150.0)
    xx = random.uniform(-ROAD_HALF * 0.92, ROAD_HALF * 0.92)
    placements.append((xx, zz))
placements.sort(key=lambda p: -p[1])  # far ones first

for i, (xx, zz) in enumerate(placements):
    p = project((xx, 0.0, zz))
    if p is None:
        continue
    sx, sy, depth = p
    # scale: apparent size falls with depth
    scale = (58.0 / depth) * (H * 0.5 / _TAN) / 320.0 * 3.6
    scale = max(0.28, min(2.6, scale))
    zombie_sil(hd, (sx * SS, sy * SS), scale * 2.2, depth, seed=i)
    # a warm rim on the ones closest to the light
    if random.random() < 0.5:
        hd.ellipse([sx * SS - 3 * scale, sy * SS - 66 * scale * 1.35,
                    sx * SS + 3 * scale, sy * SS - 50 * scale * 1.35],
                   fill=(255, 150, 60, 90))

horde_small = horde.resize((W, H), Image.LANCZOS)
img = Image.alpha_composite(img.convert("RGBA"), horde_small).convert("RGB")

# --------------------------------------------------------------------------
# PLAYER — foreground, back to camera, rim lit both sides
# --------------------------------------------------------------------------
ply = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
pd = ImageDraw.Draw(ply)

PCX = int(W * SS * 0.30)
PBY = int(H * SS * 0.985)
PS = SS * 4.05          # player scale
BODY = (5, 7, 10, 255)

# legs
pd.polygon([(PCX - 26 * PS, PBY), (PCX - 4 * PS, PBY),
            (PCX - 2 * PS, PBY - 118 * PS), (PCX - 32 * PS, PBY - 114 * PS)],
           fill=BODY)
pd.polygon([(PCX + 6 * PS, PBY), (PCX + 30 * PS, PBY),
            (PCX + 34 * PS, PBY - 114 * PS), (PCX + 8 * PS, PBY - 118 * PS)],
           fill=BODY)
# torso
pd.polygon([(PCX - 34 * PS, PBY - 110 * PS), (PCX + 34 * PS, PBY - 110 * PS),
            (PCX + 30 * PS, PBY - 196 * PS), (PCX - 30 * PS, PBY - 196 * PS)],
           fill=BODY)
# pack
pd.rounded_rectangle([PCX - 22 * PS, PBY - 186 * PS, PCX + 22 * PS, PBY - 128 * PS],
                     radius=int(5 * PS), fill=(8, 11, 16, 255))
# shoulders / head
pd.polygon([(PCX - 34 * PS, PBY - 196 * PS), (PCX + 34 * PS, PBY - 196 * PS),
            (PCX + 27 * PS, PBY - 214 * PS), (PCX - 27 * PS, PBY - 214 * PS)],
           fill=BODY)
pd.ellipse([PCX - 17 * PS, PBY - 240 * PS, PCX + 17 * PS, PBY - 206 * PS], fill=BODY)
# weapon held low, angled
pd.polygon([(PCX - 40 * PS, PBY - 150 * PS), (PCX + 44 * PS, PBY - 168 * PS),
            (PCX + 45 * PS, PBY - 160 * PS), (PCX - 41 * PS, PBY - 142 * PS)],
           fill=(11, 14, 19, 255))
pd.polygon([(PCX - 62 * PS, PBY - 146 * PS), (PCX - 36 * PS, PBY - 152 * PS),
            (PCX - 36 * PS, PBY - 143 * PS), (PCX - 62 * PS, PBY - 137 * PS)],
           fill=(6, 8, 12, 255))

# rim lights — warm on the right (street lights), cold on the left (city haze)
pd.polygon([(PCX + 30 * PS, PBY - 196 * PS), (PCX + 34 * PS, PBY - 110 * PS),
            (PCX + 27 * PS, PBY - 110 * PS), (PCX + 23 * PS, PBY - 193 * PS)],
           fill=(255, 178, 78, 235))
pd.polygon([(PCX + 8 * PS, PBY - 240 * PS), (PCX + 17 * PS, PBY - 240 * PS),
            (PCX + 17 * PS, PBY - 226 * PS), (PCX + 7 * PS, PBY - 226 * PS)],
           fill=(255, 178, 78, 200))
pd.polygon([(PCX + 44 * PS, PBY - 168 * PS), (PCX + 45 * PS, PBY - 160 * PS),
            (PCX + 40 * PS, PBY - 159 * PS), (PCX + 39 * PS, PBY - 167 * PS)],
           fill=(255, 190, 120, 220))

pd.polygon([(PCX - 34 * PS, PBY - 196 * PS), (PCX - 30 * PS, PBY - 196 * PS),
            (PCX - 26 * PS, PBY - 112 * PS), (PCX - 33 * PS, PBY - 112 * PS)],
           fill=(120, 190, 255, 200))
pd.polygon([(PCX - 17 * PS, PBY - 240 * PS), (PCX - 9 * PS, PBY - 240 * PS),
            (PCX - 10 * PS, PBY - 224 * PS), (PCX - 17 * PS, PBY - 225 * PS)],
           fill=(110, 180, 250, 170))

# ground contact shadow
pd.ellipse([PCX - 120 * PS, PBY - 16 * PS, PCX + 120 * PS, PBY + 12 * PS],
           fill=(0, 0, 0, 150))

ply_small = ply.resize((W, H), Image.LANCZOS)
img = Image.alpha_composite(img.convert("RGBA"), ply_small).convert("RGB")

# --------------------------------------------------------------------------
# POST — atmosphere, rain, colour grade, vignette, grain
# --------------------------------------------------------------------------
overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(overlay)

# volumetric haze bands
for i in range(70):
    yy = random.uniform(H * 0.34, H * 0.62)
    a = random.randint(4, 11)
    od.rectangle([0, yy, W, yy + random.uniform(2, 14)],
                 fill=(150, 160, 185, a))
img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")

# rain
rain = Image.new("RGBA", (W, H), (0, 0, 0, 0))
rd = ImageDraw.Draw(rain)
for i in range(1500):
    rx = random.uniform(-100, W)
    ry = random.uniform(-40, H)
    ln = random.uniform(10, 26)
    a = random.randint(18, 54)
    rd.line([(rx, ry), (rx + ln * 0.30, ry + ln)], fill=(206, 228, 255, a), width=1)
rain = rain.filter(ImageFilter.GaussianBlur(0.6))
img = Image.alpha_composite(img.convert("RGBA"), rain).convert("RGB")

# grade: lift the warm, crush the blacks, cool the shadows
px = img.load()
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        # cool shadows, warm highlights
        r = int(r * 1.06 + lum * 0.05)
        g = int(g * 1.00 + lum * 0.01)
        b = int(b * 1.04 + (1.0 - lum / 255.0) * 16)
        px[x, y] = (min(255, r), min(255, g), min(255, b))

# vignette
vig = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(vig)
vd.ellipse([-int(W * 0.22), -int(H * 0.30), int(W * 1.22), int(H * 1.30)], fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(180))
img = Image.composite(img, Image.new("RGB", (W, H), (0, 0, 0)), vig)

# film grain
grain = Image.effect_noise((W, H), 14).convert("L")
img = ImageChops.overlay(img, Image.merge("RGB", (grain, grain, grain)))

img.save("district_hero.png")
print("wrote district_hero.png", img.size)
