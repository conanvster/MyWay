"""Аркуш П5: рядки — пори доби, стовпці — варіанти світла. arg1 — тека знімків, arg2 — вихідна тека."""
import sys, glob, os
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
HOURS = ["1-ранок", "2-день", "3-вечір", "4-ніч"]
LIGHTS = ["1-зараз", "2-agx", "3-agx-ssil", "4-agx-ssil-glow", "5-agx-ssil-glow-корекція"]
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
places = sorted({os.path.basename(f).split("-1-ранок-")[0] for f in glob.glob(f"{src}/*-1-ранок-1-зараз.png")})
W, H, PAD, TOP = 480, 270, 140, 40
for place in places:
    sheet = Image.new("RGB", (PAD + W * 5, TOP + H * 4), "#202020")
    d = ImageDraw.Draw(sheet)
    for j, l in enumerate(LIGHTS):
        d.text((PAD + j * W + 8, 10), l, fill="white", font=font)
    for i, h in enumerate(HOURS):
        d.text((8, TOP + i * H + H // 2), h, fill="white", font=font)
        for j, l in enumerate(LIGHTS):
            f = f"{src}/{place}-{h}-{l}.png"
            if os.path.exists(f):
                sheet.paste(Image.open(f).convert("RGB").resize((W, H)), (PAD + j * W, TOP + i * H))
    sheet.save(f"{out}/аркуш-{place}.jpg", quality=88)
    print(f"{out}/аркуш-{place}.jpg")
