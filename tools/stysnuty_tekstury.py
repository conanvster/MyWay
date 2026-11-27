#!/usr/bin/env python3
"""Стиснути текстури 3D-моделей гри (game/models/own/**): VRAM Compressed і
не більше 2048×2048 замість Lossless 4096×4096.

Слово замовника 27.11.2026: «перевір чому виросло в 2 рази, також цікаво що на
моему iMac попередньо все працювало без зависань, зараз картинка якби вдвічі
повільніше стала» → «так» на стиснення. Причина: 885 текстур моделей
(аватари, монстри) імпортовані без стиснення — Godot сам перемикає текстуру
на стиснену, лише коли бачить її в 3D у редакторі, а ці імпортувались без
вікна. Одна 4K без стиснення — ~20–26 МБ у .pck і ~89 МБ відеопам'яті.

    python3 tools/stysnuty_tekstury.py            змінити й позначити до переімпорту
    python3 tools/stysnuty_tekstury.py --перевір  лише показати, скільки ще не стиснуто

Повторний запуск нічого не міняє (стиснені пропускає). Щоб Godot справді
переімпортував, у змінених прибирається .md5 імпортованого — далі
`godot --headless --path game --import` (це робить tools/server/myway-server.sh
update-game перед збіркою). Лише importer="texture" з compress/mode=0 у
models/own: значки, інтерфейс, земля й карта (інші теки) не чіпаються.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
LIMIT = 2048


def main():
    only_check = "--перевір" in sys.argv[1:]
    changed = 0
    left = 0
    for imp in sorted(glob.glob(os.path.join(GAME, "models", "own", "**", "*.import"),
                                recursive=True)):
        with open(imp, encoding="utf-8") as handle:
            text = handle.read()
        if 'importer="texture"' not in text:
            continue
        mode = re.search(r"^compress/mode=(\d+)", text, re.M)
        limit = re.search(r"^process/size_limit=(\d+)", text, re.M)
        if not mode or not limit:
            print("‼ не впізнав налаштувань: %s" % os.path.relpath(imp, ROOT))
            continue
        if mode.group(1) != "0" and limit.group(1) != "0":
            continue
        left += 1
        if only_check:
            continue
        text = re.sub(r"^compress/mode=\d+", "compress/mode=2", text, flags=re.M)
        text = re.sub(r"^process/size_limit=\d+", "process/size_limit=%d" % LIMIT,
                      text, flags=re.M)
        with open(imp, "w", encoding="utf-8") as handle:
            handle.write(text)
        # Без .md5 Godot вважає імпорт застарілим і переробить його.
        for dest in re.findall(r'"res://(\.godot/imported/[^"]+?)\.(?:[a-z0-9]+\.)?ctex"', text):
            for md5 in glob.glob(os.path.join(GAME, glob.escape(dest) + "*.md5")):
                os.remove(md5)
        changed += 1
    if only_check:
        print("нестиснутих текстур моделей: %d" % left)
    else:
        print("✓ текстур переведено на VRAM Compressed ≤%d: %d (решта вже стиснені)"
              % (LIMIT, changed))
        if changed:
            print("  далі: godot --headless --path game --import")


if __name__ == "__main__":
    main()
