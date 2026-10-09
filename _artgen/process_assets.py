# -*- coding: utf-8 -*-
"""Slice AI sprite sheets into game-ready assets (v2).
Sheets have FAKE transparency: baked checkerboard (two light grays) or white bg.
Strategy: candidate mask by brightness+low-saturation -> border flood fill ->
remove enclosed checker pockets (area>=24) -> alpha feather."""
from PIL import Image, ImageFilter, ImageDraw
from collections import deque
import os

SRC = 'D:/Godot/GuGuGaGaWar/_artgen'
OUT = 'D:/Godot/GuGuGaGaWar/assets/ui/campaign'
os.makedirs(OUT, exist_ok=True)

BG_SRC = os.path.join(SRC, 'Hand_painted_fantasy_strategy__2026-10-03T20-55-37.png')
MARKER_SRC = os.path.join(SRC, 'Game_asset_sprite_sheet__exact_2026-10-03T20-55-31.png')
MISC_SRC = os.path.join(SRC, 'Game_asset_sprite_sheet__exact_2026-10-03T20-55-29.png')
BANNER_SRC = os.path.join(SRC, 'Horizontal_parchment_scroll_ba_2026-10-03T20-55-30.png')
ACH_SRC = os.path.join(SRC, 'Game_asset_sprite_sheet__one_h_2026-10-03T20-55-29.png')
ACHBG_SRC = os.path.join(SRC, 'Game_UI_window_background_pane_2026-10-03T20-55-27.png')


def key_background(img, lo, hi, sat_max=14, pocket=24, global_key=False):
    """Remove light low-saturation background (checker/white) via border flood."""
    rgb = img.convert('RGB')
    w, h = rgb.size
    gray = rgb.convert('L')
    gp = gray.load()
    rp = rgb.load()
    cand = Image.new('L', (w, h), 0)
    cp = cand.load()
    for y in range(h):
        for x in range(w):
            r, g, b = rp[x, y]
            mx, mn = max(r, g, b), min(r, g, b)
            if mn >= lo and mx <= hi and (mx - mn) <= sat_max:
                cp[x, y] = 255
    # pad so border is fully connected, single flood seed
    pad = Image.new('L', (w + 2, h + 2), 255)
    pad.paste(cand, (1, 1))
    ImageDraw.floodfill(pad, (0, 0), 128)
    flood = pad.crop((1, 1, w + 1, h + 1))
    fp = flood.load()
    # enclosed pockets: remaining 255 components with area >= pocket -> background
    visited = Image.new('L', (w, h), 0)
    vp = visited.load()
    total_bg = Image.new('L', (w, h), 0)
    tp = total_bg.load()
    for y in range(h):
        for x in range(w):
            if global_key and cp[x, y] == 255:
                tp[x, y] = 255
            elif fp[x, y] == 128:
                tp[x, y] = 255
    for y in range(h):
        for x in range(w):
            if fp[x, y] == 255 and not vp[x, y]:
                comp = []
                dq = deque([(x, y)])
                vp[x, y] = 1
                while dq:
                    cx, cy = dq.popleft()
                    comp.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and fp[nx, ny] == 255 and not vp[nx, ny]:
                            vp[nx, ny] = 1
                            dq.append((nx, ny))
                if len(comp) >= pocket:
                    for cx, cy in comp:
                        tp[cx, cy] = 255
    alpha = total_bg.point(lambda v: 255 - v)
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    out = rgb.convert('RGBA')
    out.putalpha(alpha)
    return out


def despeckle(img, min_keep=400):
    """Keep the largest opaque component (+ any >=min_keep px); drop floaters."""
    alpha = img.split()[-1]
    w, h = img.size
    mask = alpha.point(lambda v: 255 if v > 40 else 0)
    px = mask.load()
    seen = set()
    comps = []
    for y0 in range(h):
        for x0 in range(w):
            if px[x0, y0] == 255 and (x0, y0) not in seen:
                comp = []
                dq = deque([(x0, y0)])
                seen.add((x0, y0))
                while dq:
                    cx, cy = dq.popleft()
                    comp.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < w and 0 <= ny < h and px[nx, ny] == 255 and (nx, ny) not in seen:
                                seen.add((nx, ny))
                                dq.append((nx, ny))
                comps.append(comp)
    if not comps:
        return img
    comps.sort(key=len, reverse=True)
    keep = set(comps[0])
    for comp in comps[1:]:
        if len(comp) >= min_keep:
            keep.update(comp)
    a2 = Image.new('L', (w, h), 0)
    p2 = a2.load()
    for x, y in keep:
        p2[x, y] = 255
    a2 = a2.filter(ImageFilter.GaussianBlur(0.5))
    out = img.copy()
    out.putalpha(a2)
    return out


def autocrop(img, pad=4, thresh=40):
    alpha = img.split()[-1]
    mask = alpha.point(lambda v: 255 if v > thresh else 0)
    mask = mask.filter(ImageFilter.MedianFilter(7)).point(lambda v: 255 if v > 128 else 0)
    bbox = mask.getbbox()
    if not bbox:
        return img
    l, t, r, b = bbox
    l = max(0, l - pad); t = max(0, t - pad)
    r = min(img.width, r + pad); b = min(img.height, b + pad)
    return despeckle(img.crop((l, t, r, b)))


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path)
    print('%-26s %sx%s' % (name, img.width, img.height))


# ---- 1. markers: 2x2 sheet -> 4 normalized canvases 128x160 ----
sheet = key_background(Image.open(MARKER_SRC), 215, 255)
W, H = sheet.width // 2, sheet.height // 2
quads = {'marker_unlocked': (0, 0), 'marker_locked': (W, 0),
         'marker_boss': (0, H), 'marker_perfect': (W, H)}
for name, (x, y) in quads.items():
    art = autocrop(sheet.crop((x, y, x + W, y + H)))
    canvas = Image.new('RGBA', (128, 160), (0, 0, 0, 0))
    scale = min(150.0 / art.height, 124.0 / art.width)
    nw, nh = max(1, int(art.width * scale)), max(1, int(art.height * scale))
    art = art.resize((nw, nh), Image.LANCZOS)
    canvas.paste(art, ((128 - nw) // 2, 156 - nh), art)
    save(canvas, name + '.png')

# ---- 2. misc: white bg sheet -> sun / stars / boss badge ----
sheet = key_background(Image.open(MISC_SRC), 242, 255)
W, H = sheet.width // 2, sheet.height // 2
sun = autocrop(sheet.crop((0, 0, W, H)))
sun.thumbnail((256, 256), Image.LANCZOS)
save(sun, 'sun.png')
star_on = autocrop(sheet.crop((W, 0, 2 * W, H)))
star_on.thumbnail((64, 64), Image.LANCZOS)
save(star_on, 'star_on.png')
star_off = autocrop(sheet.crop((0, H, W, 2 * H)))
star_off.thumbnail((64, 64), Image.LANCZOS)
save(star_off, 'star_off.png')
badge = autocrop(sheet.crop((W, H, 2 * W, 2 * H)))
badge.thumbnail((64, 64), Image.LANCZOS)
save(badge, 'boss_badge.png')

# ---- 3. banner: checker sheet -> autocrop -> width 768 ----
banner = key_background(Image.open(BANNER_SRC), 215, 255)
banner = autocrop(banner)
scale = 768.0 / banner.width
banner = banner.resize((768, int(banner.height * scale)), Image.LANCZOS)
save(banner, 'banner_title.png')

# ---- 4. achievements: 1x3 checker sheet -> badges + ribbon ----
sheet = Image.open(ACH_SRC).convert('RGB')
third = sheet.width // 3
## 金牌/丝带无银灰元素 -> 全局抠底；铁牌有银挂锁 -> 泛洪 + 小口袋阈值
sheet_u = key_background(sheet.crop((0, 0, third, sheet.height)), 215, 255, global_key=True)
medal_u = autocrop(sheet_u)
medal_u.thumbnail((88, 88), Image.LANCZOS)
save(medal_u, 'ach_badge_unlocked.png')
sheet_l = key_background(sheet.crop((third, 0, 2 * third, sheet.height)), 215, 255, pocket=6)
medal_l = autocrop(sheet_l)
medal_l.thumbnail((88, 88), Image.LANCZOS)
save(medal_l, 'ach_badge_locked.png')
sheet_r = key_background(sheet.crop((2 * third, 0, sheet.width, sheet.height)), 215, 255, global_key=True)
ribbon = autocrop(sheet_r)
ribbon.thumbnail((72, 72), Image.LANCZOS)
save(ribbon, 'ach_ribbon_done.png')

# ---- 5. campaign bg: crop 16:9 band (watermark below y=985 removed) ----
bg = Image.open(BG_SRC).convert('RGB')
bg = bg.crop((0, 70, bg.width, 934))
save(bg, 'campaign_bg.png')

# ---- 6. achievements window bg: crop parchment, clone-stamp watermark ----
p = Image.open(ACHBG_SRC).convert('RGB')
p = p.crop((26, 32, 998, 992))
pw, ph = p.width, p.height
src_box = p.crop((pw - 380, ph - 64, pw - 120, ph - 8)).filter(ImageFilter.GaussianBlur(1.2))
mask = Image.new('L', src_box.size, 0)
mw, mh = mask.size
for yy in range(mh):
    for xx in range(mw):
        d = min(xx, mw - 1 - xx, yy, mh - 1 - yy)
        mask.putpixel((xx, yy), min(255, d * 14))
p.paste(src_box, (pw - 140, ph - 62), mask)
save(p, 'ach_window_bg.png')
print('done')
