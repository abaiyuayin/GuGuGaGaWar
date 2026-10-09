# -*- coding: utf-8 -*-
"""Achievements window art v2: style matched to campaign map (bright honey/cream chibi).
Reuses the checkerboard/white keying pipeline from process_assets.py."""
from PIL import Image, ImageFilter, ImageDraw
from collections import deque
import os

SRC = 'D:/Godot/GuGuGaGaWar/_artgen'
OUT = 'D:/Godot/GuGuGaGaWar/assets/ui/campaign'

ACH_SRC = os.path.join(SRC, 'Game_asset_sprite_sheet__one_h_2026-10-03T21-48-36.png')
ACHBG_SRC = os.path.join(SRC, 'Game_UI_window_background_pane_2026-10-03T21-48-58.png')


def key_background(img, lo, hi, sat_max=14, pocket=24, global_key=False):
    rgb = img.convert('RGB')
    w, h = rgb.size
    rp = rgb.load()
    cand = Image.new('L', (w, h), 0)
    cp = cand.load()
    for y in range(h):
        for x in range(w):
            r, g, b = rp[x, y]
            mx, mn = max(r, g, b), min(r, g, b)
            if mn >= lo and mx <= hi and (mx - mn) <= sat_max:
                cp[x, y] = 255
    pad = Image.new('L', (w + 2, h + 2), 255)
    pad.paste(cand, (1, 1))
    ImageDraw.floodfill(pad, (0, 0), 128)
    flood = pad.crop((1, 1, w + 1, h + 1))
    fp = flood.load()
    visited = Image.new('L', (w, h), 0)
    vp = visited.load()
    total_bg = Image.new('L', (w, h), 0)
    tp = total_bg.load()
    for y in range(h):
        for x in range(w):
            if (global_key and cp[x, y] == 255) or fp[x, y] == 128:
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
    img.save(os.path.join(OUT, name))
    print('%-26s %sx%s' % (name, img.width, img.height))


sheet = Image.open(ACH_SRC).convert('RGB')
third = sheet.width // 3
## 金牌/印章无银灰元素 -> 全域抠底 lo=200（棋盘深格 ~210-225 也在射程内）
sheet_u = key_background(sheet.crop((0, 0, third, sheet.height)), 200, 255, global_key=True)
medal_u = autocrop(sheet_u)
medal_u.thumbnail((88, 88), Image.LANCZOS)
save(medal_u, 'ach_badge_unlocked.png')
## 木牌+锁链：锁链是低饱和银灰，全域/低阈值会误吃 -> 手动裁到木牌矩形 + 高阈值泛洪
plaque = sheet.crop((third + 30, 340, 2 * third - 10, 650))
sheet_l = key_background(plaque, 215, 255, pocket=6)
medal_l = autocrop(sheet_l)
medal_l.thumbnail((88, 88), Image.LANCZOS)
save(medal_l, 'ach_badge_locked.png')
sheet_r = key_background(sheet.crop((2 * third, 0, sheet.width, sheet.height)), 200, 255, global_key=True)
ribbon = autocrop(sheet_r)
ribbon.thumbnail((72, 72), Image.LANCZOS)
save(ribbon, 'ach_ribbon_done.png')

p = Image.open(ACHBG_SRC).convert('RGB')
## 底部裁到 955：去掉「AI生成」水印（位于 ~y 960+）
p = p.crop((26, 32, 998, 955))
save(p, 'ach_window_bg.png')
print('done')
