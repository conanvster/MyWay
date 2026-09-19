"""Значок «зілля лікування» (19.09.2026) — у стилі решти значків речей:
64×64, темне тло, одна світна річ посередині. Червона рідина в круглій
колбі з шийкою й коркомою.

    python3 tools/potion_icon.py
"""
from PIL import Image, ImageDraw, ImageFilter

OUT = "game/assets/icons/items/зілля лікування.png"
S = 256  # малюємо вчетверо більше й зменшуємо — рівні краї


def main():
    img = Image.new("RGB", (S, S), (6, 4, 5))
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse((58, 92, 198, 232), fill=(150, 20, 24))
    glow = glow.filter(ImageFilter.GaussianBlur(26))
    img = Image.blend(img, glow, 0.55)
    d = ImageDraw.Draw(img)
    # Колба: рідина знизу до двох третин, над нею порожнє темне скло.
    # (Перша спроба з білою плямою й смугою посередині читалась як
    # покебол.)
    d.ellipse((78, 108, 178, 208), fill=(205, 24, 32))
    d.chord((78, 108, 178, 208), 180, 360, fill=(36, 26, 30))
    d.chord((78, 108, 178, 208), 0, 20, fill=(205, 24, 32))
    d.chord((78, 108, 178, 208), 160, 180, fill=(205, 24, 32))
    d.ellipse((78, 108, 178, 208), outline=(160, 150, 160), width=5)
    # Шийка й корок.
    d.rectangle((112, 70, 144, 112), fill=(36, 26, 30), outline=(160, 150, 160),
                width=5)
    d.rectangle((106, 52, 150, 72), fill=(128, 86, 48), outline=(70, 45, 25),
                width=3)
    # Тонкий відблиск на склі.
    d.arc((90, 120, 166, 196), 200, 250, fill=(235, 220, 225), width=6)
    img = img.resize((64, 64), Image.LANCZOS)
    img.save(OUT)
    print("[значок]", OUT)


if __name__ == "__main__":
    main()
