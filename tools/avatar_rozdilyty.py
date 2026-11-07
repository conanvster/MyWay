#!/usr/bin/env python3
"""Аватар .glb → тіло + кожна зачіска окремим файлом (П6, П-276, 06.11.2026).

Заміряно 06.11.2026: у `elf-e1903-mixamo.glb` (79 МБ) зачіски — 50,6 МБ
(п'ять сіток «Волосся-<стиль>», «пряме» само 15 МБ), тіло 10,7, картинки
12,7, рухи 0,9. Межа GitHub — 100 МБ на файл, і моделі вже 62–95 МБ.

Розрізаємо САМ glTF, без Blender: вузли, скелет, рухи й байти геометрії
лишаються ті самі, нічого не перераховується й не зсувається.

  <база>.glb                   — тіло, скелет (з кістками пасом), рухи;
  <база>_волосся-<стиль>.glb   — одна зачіска на тому самому скелеті, без
                                 рухів; гра чіпляє її до скелета тіла
                                 (`SkinnedModel._attach_hair_files`).

Кольорова текстура тіла (без прозорості) — JPEG 92 замість PNG: 4096
лишається (обличчя), файл у рази менший. Волосинки — PNG (прозорість).

    python3 tools/avatar_rozdilyty.py <модель.glb> [ще.glb …] [--сухо]

Оригінал зберігається поруч як `<база>.glb.до-розрізу` (не в git — у
`.gitignore`); `--сухо` лише друкує, що вийде.
"""
import io
import json
import os
import shutil
import struct
import sys

from PIL import Image

HAIR = "Волосся-"


def read_glb(path):
    b = open(path, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack_from("<I", b, off)[0]
    return j, b[off + 8:off + 8 + bl]


def write_glb(path, j, binary):
    js = json.dumps(j, ensure_ascii=False, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binary += b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def view_bytes(j, binary, v):
    bv = j["bufferViews"][v]
    o = bv.get("byteOffset", 0)
    return binary[o:o + bv["byteLength"]]


def compact(j, binary, keep_meshes, keep_anims, jpeg_images=()):
    """Лишити вказані сітки (за іменем) і рухи; решту даних викинути."""
    j = json.loads(json.dumps(j))
    # Вузли з викинутими сітками — порожні (ієрархія й скелет ті самі).
    mesh_map = {}
    meshes = []
    for i, m in enumerate(j["meshes"]):
        if m.get("name") in keep_meshes:
            mesh_map[i] = len(meshes)
            meshes.append(m)
    for n in j["nodes"]:
        if "mesh" in n:
            if n["mesh"] in mesh_map:
                n["mesh"] = mesh_map[n["mesh"]]
            else:
                del n["mesh"]
                n.pop("skin", None)
    j["meshes"] = meshes
    if not keep_anims:
        j.pop("animations", None)
    # Матеріали → текстури → картинки, що лишились.
    mat_used = sorted({p["material"] for m in meshes
                       for p in m["primitives"] if "material" in p})
    mat_map = {o: k for k, o in enumerate(mat_used)}
    j["materials"] = [j["materials"][o] for o in mat_used]
    for m in meshes:
        for p in m["primitives"]:
            if "material" in p:
                p["material"] = mat_map[p["material"]]
    tex_used = []

    def walk_tex(o):
        if isinstance(o, dict):
            if "index" in o and isinstance(o["index"], int) and \
                    set(o) <= {"index", "texCoord", "scale", "strength",
                               "extensions"}:
                if o["index"] not in tex_used:
                    tex_used.append(o["index"])
            for v in o.values():
                walk_tex(v)
        elif isinstance(o, list):
            for v in o:
                walk_tex(v)
    walk_tex(j["materials"])
    tex_used.sort()
    tex_map = {o: k for k, o in enumerate(tex_used)}

    def remap_tex(o):
        if isinstance(o, dict):
            if "index" in o and isinstance(o["index"], int) and \
                    set(o) <= {"index", "texCoord", "scale", "strength",
                               "extensions"}:
                o["index"] = tex_map[o["index"]]
            for v in o.values():
                remap_tex(v)
        elif isinstance(o, list):
            for v in o:
                remap_tex(v)
    remap_tex(j["materials"])
    textures = [j["textures"][o] for o in tex_used] if "textures" in j else []
    img_used = sorted({t["source"] for t in textures})
    img_map = {o: k for k, o in enumerate(img_used)}
    for t in textures:
        t["source"] = img_map[t["source"]]
    j["textures"] = textures
    images = [j["images"][o] for o in img_used] if "images" in j else []
    # Акcесори, що лишились.
    acc_used = set()
    for m in meshes:
        for p in m["primitives"]:
            acc_used.update(p["attributes"].values())
            if "indices" in p:
                acc_used.add(p["indices"])
            for t in p.get("targets", []):
                acc_used.update(t.values())
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            acc_used.add(s["inverseBindMatrices"])
    for a in j.get("animations", []):
        for smp in a["samplers"]:
            acc_used.update([smp["input"], smp["output"]])
    acc_list = sorted(acc_used)
    acc_map = {o: k for k, o in enumerate(acc_list)}
    accessors = [j["accessors"][o] for o in acc_list]
    for m in meshes:
        for p in m["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
            if "targets" in p:
                p["targets"] = [{k: acc_map[v] for k, v in t.items()}
                                for t in p["targets"]]
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    for a in j.get("animations", []):
        for smp in a["samplers"]:
            smp["input"] = acc_map[smp["input"]]
            smp["output"] = acc_map[smp["output"]]
    # Новий буфер: лише вживані bufferView, вирівняні по 4.
    out = bytearray()
    views = []
    view_map = {}

    def add_view(old, data=None, mime=None):
        if data is None:
            if old in view_map:
                return view_map[old]
            data = view_bytes(j, binary, old)
        while len(out) % 4:
            out.append(0)
        bv = {"buffer": 0, "byteOffset": len(out), "byteLength": len(data)}
        if old is not None:
            src = j["bufferViews"][old]
            for k in ("byteStride", "target"):
                if k in src:
                    bv[k] = src[k]
        out.extend(data)
        views.append(bv)
        if old is not None and mime is None:
            view_map[old] = len(views) - 1
        return len(views) - 1
    for a in accessors:
        if "bufferView" in a:
            a["bufferView"] = add_view(a["bufferView"])
        # Розріджені дані (риси обличчя — форм-ключі) мають ще два свої
        # bufferView. До 07.11.2026 їх не переписували: лишались старі
        # номери, Godot читав чужі байти — «Ніс-кирпатий» людини стріляв
        # шпилями на метр, решта рис не робила нічого.
        if "sparse" in a:
            for part in ("indices", "values"):
                sp = a["sparse"][part]
                sp["bufferView"] = add_view(sp["bufferView"])
    for im in images:
        if "bufferView" not in im:
            continue
        raw = view_bytes(j, binary, im["bufferView"])
        if im.get("name") in jpeg_images and im.get("mimeType") == "image/png":
            pic = Image.open(io.BytesIO(raw))
            if pic.mode in ("RGBA", "LA") and pic.getextrema()[-1][0] < 255:
                pass  # справжня прозорість — лишаємо PNG
            else:
                buf = io.BytesIO()
                pic.convert("RGB").save(buf, "JPEG", quality=92,
                                        optimize=True)
                raw = buf.getvalue()
                im["mimeType"] = "image/jpeg"
                im["bufferView"] = add_view(None, raw, "jpeg")
                continue
        im["bufferView"] = add_view(im["bufferView"])
    j["accessors"] = accessors
    j["images"] = images
    j["bufferViews"] = views
    j["buffers"] = [{"byteLength": len(out)}]
    for k in ("images", "textures", "materials", "animations", "samplers"):
        if k in j and not j[k]:
            del j[k]
    return j, bytes(out)


def split(path, dry):
    j, binary = read_glb(path)
    names = [m.get("name", "") for m in j["meshes"]]
    hairs = [n for n in names if n.startswith(HAIR)]
    body = [n for n in names if not n.startswith(HAIR)]
    if not hairs:
        print("%s: зачісок немає — не чіпаю" % path)
        return
    base = os.path.splitext(path)[0]
    plan = []
    body_j, body_b = compact(j, binary, set(body), True,
                             jpeg_images=("аватар-колір", "Image_1",
                                          "Image_2"))
    plan.append((path, body_j, body_b))
    for h in hairs:
        hj, hb = compact(j, binary, {h}, False)
        plan.append(("%s_%s.glb" % (base, h.lower()), hj, hb))
    before = os.path.getsize(path)
    print("%s: було %.1f МБ" % (path, before / 1e6))
    for p, pj, pb in plan:
        print("   → %-60s %.1f МБ" % (os.path.basename(p), (len(pb) + 2000) / 1e6))
    if dry:
        return
    keep = path + ".до-розрізу"
    if not os.path.exists(keep):
        shutil.copy(path, keep)
    for p, pj, pb in plan:
        write_glb(p, pj, pb)


def main():
    args = sys.argv[1:]
    dry = "--сухо" in args
    files = [a for a in args if a != "--сухо"]
    if not files:
        print(__doc__)
        return 1
    for f in files:
        split(f, dry)
    return 0


if __name__ == "__main__":
    sys.exit(main())
