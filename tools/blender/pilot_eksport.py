"""Пілот Б+Г (П-281): з'єднану модель — у переглядач моделей гри.

Бере сцену з `pilot_zyednannia.py` (тіло MPFB + одяг і волосся з моделі
Hunyuan на скелеті `game_engine`), переносить на скелет рухи UAL1 тим
самим `perenapravyty()`, що й `mpfb_avatar.py`, і пише один GLB. Маски
`ховати_*` експортер застосовує сам (export_apply): тіло під одягом
вирізається, скін лишається.

    blender -b <з-єднання.blend> -P tools/blender/pilot_eksport.py -- \
        <вихід.glb> [--рухи Idle,Walk] [--з-формами]
"""
import os
import sys

import bpy

TUT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TUT)
# `--з-формами` (крок 3, риси): форм-ключі рис лишаються в GLB — сітки з
# ними вже без модифікаторів, крім скелета (`pilot_rysy.py`).
Z_FORMAMY = "--з-формами" in sys.argv
if Z_FORMAMY:
    sys.argv.remove("--з-формами")
ARGS = sys.argv[sys.argv.index("--") + 1:]
KUDY = os.path.abspath(ARGS[0])
import mpfb_avatar as ma  # noqa: E402  (читає ті самі ARGS: вихід, --рухи)

arm = bpy.data.objects["Human.rig"]
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
# Сітки без форм (shape keys), інакше export_apply не застосує маски.
for o in bpy.data.objects:
    if o.type == "MESH" and o.data.shape_keys and not (
            Z_FORMAMY and all(md.type == "ARMATURE" for md in o.modifiers)):
        bpy.context.view_layer.objects.active = o
        o.shape_key_add(name="змішано", from_mix=True)
        for k in list(o.data.shape_keys.key_blocks):
            if k.name != "змішано":
                o.shape_key_remove(k)
        o.shape_key_remove(o.data.shape_keys.key_blocks["змішано"])
ma.perenapravyty(arm)
os.makedirs(os.path.dirname(KUDY), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=KUDY, export_format="GLB",
                          export_animations=True,
                          export_animation_mode="NLA_TRACKS",
                          export_skins=True, export_apply=True)
print("[пілот] →", KUDY, flush=True)
