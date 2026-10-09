# -*- coding: utf-8 -*-
"""Compose campaign markers at current Curve2D positions onto the bg,
replicating Godot Curve2D bezier sampling, to verify marker-road alignment."""
from PIL import Image
import os

BG = 'D:/Godot/GuGuGaGaWar/assets/ui/campaign/campaign_bg.png'
MARK = 'D:/Godot/GuGuGaGaWar/assets/ui/campaign'
OUT = 'D:/Godot/GuGuGaGaWar/_artgen/marker_layout_check.png'

# (pos, in_handle, out_handle) — must mirror _setup_path_curve()  [logical 1280x720]
PTS = [
    ((212, 654), (0, 0), (55, -10)),
    ((333, 633), (-55, 10), (50, -5)),
    ((442, 621), (-45, 5), (40, -8)),
    ((517, 604), (-38, 8), (35, -25)),
    ((583, 557), (-33, 24), (40, -30)),
    ((663, 496), (-40, 30), (35, -21)),
    ((733, 454), (-35, 21), (40, -20)),
    ((813, 413), (-40, 20), (35, -19)),
    ((883, 375), (-35, 19), (30, -31)),
    ((942, 313), (-30, 31), (4, -50)),
    ((950, 213), (0, -45), (0, 0)),
]
LEVEL_PROGRESS = [0.03, 0.134, 0.239, 0.343, 0.448, 0.552, 0.657, 0.761, 0.866, 0.97]
BOSS_LEVELS = {3, 6, 10}


def bezier(p0, c0, c1, p1, t):
    mt = 1 - t
    x = mt**3*p0[0] + 3*mt**2*t*c0[0] + 3*mt*t**2*c1[0] + t**3*p1[0]
    y = mt**3*p0[1] + 3*mt**2*t*c0[1] + 3*mt*t**2*c1[1] + t**3*p1[1]
    return x, y


def build_curve_points(sub=48):
    pts = []
    for i in range(len(PTS) - 1):
        p0, _, out0 = PTS[i]
        p1, in1, _ = PTS[i + 1]
        c0 = (p0[0] + out0[0], p0[1] + out0[1])
        c1 = (p1[0] + in1[0], p1[1] + in1[1])
        for s in range(sub):
            pts.append(bezier(p0, c0, c1, p1, s / sub))
    pts.append(PTS[-1][0])
    return pts


def sample_at(points, frac):
    # cumulative arc length
    lens = [0.0]
    for i in range(1, len(points)):
        dx = points[i][0] - points[i-1][0]
        dy = points[i][1] - points[i-1][1]
        lens.append(lens[-1] + (dx*dx + dy*dy) ** 0.5)
    total = lens[-1]
    target = frac * total
    for i in range(1, len(lens)):
        if lens[i] >= target:
            t = (target - lens[i-1]) / max(1e-6, lens[i] - lens[i-1])
            x = points[i-1][0] + (points[i][0] - points[i-1][0]) * t
            y = points[i-1][1] + (points[i][1] - points[i-1][1]) * t
            return x, y
    return points[-1]


bg = Image.open(BG).convert('RGBA')
# logical(1280x720) -> bg px scale = 1536/1280 = 1.2
SCALE = bg.width / 1280.0
curve_pts = [(x * SCALE, y * SCALE) for x, y in build_curve_points()]

tex = {}
for name in ['marker_unlocked', 'marker_locked', 'marker_boss', 'marker_perfect', 'boss_badge']:
    im = Image.open(os.path.join(MARK, name + '.png')).convert('RGBA')
    tex[name] = im.resize((58, 72), Image.LANCZOS) if name.startswith('marker') else im.resize((40, 40), Image.LANCZOS)

report = []
for i, frac in enumerate(LEVEL_PROGRESS):
    level = i + 1
    x, y = sample_at(curve_pts, frac)
    name = 'marker_boss' if level in BOSS_LEVELS else 'marker_unlocked'
    art = tex[name]
    bg.paste(art, (int(x - 29), int(y - 36)), art)
    if level in BOSS_LEVELS:
        b = tex['boss_badge']
        bg.paste(b, (int(x - 20), int(y - 36 - 40 + 4)), b)
    report.append('L%02d progress=%.2f  bg=(%4d,%4d)  logical=(%4d,%4d)' % (
        level, frac, x, y, x / SCALE, y / SCALE))

print('\n'.join(report))
bg.convert('RGB').save(OUT)
print('saved', OUT)
