#!/usr/bin/env python3
"""Стиснути текстури в .glb без Blender (П-297, 28.11.2026).

Модель монстра з рухами важила 35–56 МБ: 3/4 — текстури зброї TRELLIS (4096², PNG). Тут кожне
зображення зменшується до межі й перекодовується в JPEG (крім тих, що мають справжню прозорість);
сітка, скелет і рухи не чіпаються — буфер просто перескладається.

    python3 tools/glb_stysk.py <вхід.glb> <вихід.glb> [--тіло 2048] [--решта 1024] [--якість 88]
Тіло — зображення, чия назва починається з «hmv-» або містить «запечено».
"""
import io
import json
import struct
import sys

from PIL import Image


def chytaty(p):
    b = open(p, "rb").read()
    assert b[:4] == b"glTF"
    i, js, binr = 12, None, b""
    while i < len(b):
        n, t = struct.unpack("<II", b[i:i + 8])
        d = b[i + 8:i + 8 + n]
        if t == 0x4E4F534A:
            js = json.loads(d)
        elif t == 0x004E4942:
            binr = d
        i += 8 + n
    return js, binr


def zapysaty(p, js, binr):
    j = json.dumps(js, ensure_ascii=False, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    binr += b"\0" * (-len(binr) % 4)
    tot = 12 + 8 + len(j) + 8 + len(binr)
    with open(p, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, tot))
        f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
        f.write(struct.pack("<II", len(binr), 0x004E4942) + binr)


def main():
    a = sys.argv[1:]
    vh, vy = a[0], a[1]
    op = lambda k, d: int(a[a.index(k) + 1]) if k in a else d  # noqa: E731
    tilo, reshta, yakist = op("--тіло", 2048), op("--решта", 1024), op("--якість", 88)
    js, binr = chytaty(vh)
    bvs = js["bufferViews"]
    novi = {}
    for im in js.get("images", []):
        if "bufferView" not in im:
            continue
        v = bvs[im["bufferView"]]
        dani = binr[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        img = Image.open(io.BytesIO(dani))
        imia = im.get("name", "")
        mezha = tilo if (imia.startswith("hmv-") or "запечено" in imia) else reshta
        if max(img.size) > mezha:
            k = mezha / max(img.size)
            img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))),
                             Image.LANCZOS)
        prozore = img.mode in ("RGBA", "LA") and img.getchannel("A").getextrema()[0] < 250
        out = io.BytesIO()
        if prozore:
            img.save(out, "PNG", optimize=True)
            im["mimeType"] = "image/png"
        else:
            img.convert("RGB").save(out, "JPEG", quality=yakist, optimize=True)
            im["mimeType"] = "image/jpeg"
        novi[im["bufferView"]] = out.getvalue()
    # перескласти буфер: кожен вид — із вирівнюванням на 4 (8 для надійності)
    nb = bytearray()
    for i, v in enumerate(bvs):
        d = novi.get(i)
        if d is None:
            o = v.get("byteOffset", 0)
            d = binr[o:o + v["byteLength"]]
        nb += b"\0" * (-len(nb) % 8)
        v["byteOffset"] = len(nb)
        v["byteLength"] = len(d)
        v["buffer"] = 0
        nb += d
    js["buffers"] = [{"byteLength": len(nb)}]
    zapysaty(vy, js, bytes(nb))
    print("[стиск] %s: %.1f → %.1f МБ" % (vh.split("/")[-1], len(binr) / 1e6, len(nb) / 1e6))


if __name__ == "__main__":
    main()
