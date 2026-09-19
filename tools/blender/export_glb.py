"""Експорт монстра з .blend у .glb для гри — з тими налаштуваннями, без
яких гра моделі не підхопить.

Що важить:
  · кожен рух (Action) іде окремою анімацією з власним ім'ям — гра шукає
    `Idle`, `Walk` (або `Run`), `Attack`, `Death` саме за ім'ям;
  · модифікатори застосовуються (скелет лишається скелетом);
  · вгору — +Y, як чекає glTF і Godot.

Запуск (з каталогу проєкту):
    blender --background art/monsters/мій.blend \\
        --python tools/blender/export_glb.py -- game/models/own/мій.glb
"""
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not args:
    sys.exit("‼ куди писати .glb? — після «--» дай шлях")
out = args[0]
bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    export_yup=True,
    export_apply=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_def_bones=False,
    export_skins=True,
)
names = sorted(a.name for a in bpy.data.actions)
print("[експорт] %s · рухи: %s" % (out, ", ".join(names)))
missing = [n for n in ("Idle", "Attack") if n not in names]
if not ("Walk" in names or "Run" in names):
    missing.append("Walk")
if missing:
    print("[експорт] ‼ бракує рухів: %s — гра їх не програє"
          % ", ".join(missing))
