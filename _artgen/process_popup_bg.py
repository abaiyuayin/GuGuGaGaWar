# -*- coding: utf-8 -*-
"""Process AI popup background into game-ready nine-patch asset.
Strategy: crop dark vignette edge AND the watermarked bottom band (y>=932)
in one go; trees stay (their base ends ~y930). No clone-stamping.
Result ratio ~996x918, resized to 512x472."""
from PIL import Image
import os

SRC = 'D:/Godot/GuGuGaGaWar/_artgen/Using_exactly_the_same_hand_pa_2026-10-03T23-36-08.png'
OUT = 'D:/Godot/GuGuGaGaWar/assets/ui/campaign/popup_bg.png'

img = Image.open(SRC).convert('RGB')
print('src', img.size)

# crop: sides 14px vignette; bottom cut at y=932 removes watermark band entirely
img = img.crop((14, 14, img.width - 14, 932))
print('cropped', img.size)

# resize to width 512
scale = 512.0 / img.width
img = img.resize((512, int(img.height * scale)), Image.LANCZOS)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print('saved', OUT, img.size)
