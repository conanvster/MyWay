#!/usr/bin/env python3
"""Метал для крафту частіше: кожен вид монстра дає метал грейду свого рівня.

П-292, слово замовника 27.11.2026: «дроп матеріалів для крафту речей малий»
→ «так». Було: метал грейду падав з 2–3 видів на смугу рівнів, у середньому
0,02–0,05 за вбивство, а рецепт речі — 10 металу (П-258).

    python3 tools/metal_dropu.py            змінити game/data/mobs.json
    python3 tools/metal_dropu.py --перевір  лише показати, що змінилося б

Правка ТОЧКОВА, текстом, а не json.dump: файл має ручний формат (короткі
списки в рядок), і повне переписування дало б тисячі змінених рядків.
Повторний запуск нічого не міняє. Грейд — за драбиною items.json → грейди →
до рівня (та сама, що в грі: ItemBook.grade_for_level), метал грейду — за
smith.json → зачарування → матеріал. Більший шанс, що вже стояв, лишається.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "game", "data")
CHANCE = 0.2
FROM, TO = 1, 2


def main():
    only_check = "--перевір" in sys.argv[1:]
    items = json.load(open(os.path.join(DATA, "items.json"), encoding="utf-8"))
    ladder = items["грейди"]["до рівня"]
    order = ["E", "D", "C", "B", "A", "S", "SS"]
    smith = json.load(open(os.path.join(DATA, "smith.json"), encoding="utf-8"))
    metal_of = smith["зачарування"]["матеріал"]

    def grade(level):
        for g in order:
            if level <= int(ladder.get(g, 999)):
                return g
        return order[-1]

    path = os.path.join(DATA, "mobs.json")
    text = open(path, encoding="utf-8").read()
    mobs = json.loads(text)
    added = raised = 0
    for key, mob in mobs.items():
        if not isinstance(mob, dict) or "дроп" not in mob:
            continue
        metal = metal_of[grade(int(mob.get("рівень", 1)))]
        have = [d for d in mob["дроп"] if d.get("що") == metal]
        # Межі блоку цього виду в тексті: від `  "N": {` до наступного виду.
        start = re.search(r'^  "%s": \{$' % re.escape(key), text, re.M)
        if start is None:
            print("‼ не знайшов вид %s у тексті" % key)
            continue
        nxt = re.search(r'^  "[^"]+": \{$', text[start.end():], re.M)
        end = start.end() + (nxt.start() if nxt else len(text) - start.end())
        block = text[start.start():end]
        if have:
            if float(have[0].get("шанс", 0)) >= CHANCE:
                continue
            new_block, n = re.subn(
                r'("що": "%s",\n\s*"шанс": )[0-9.]+' % re.escape(metal),
                lambda m: m.group(1) + str(CHANCE), block, count=1)
            if n != 1:
                print("‼ %s (%s): не впізнав запис металу" % (mob.get("назва"), key))
                continue
            raised += 1
        else:
            at = re.search(r'^(\s*)"дроп": \[\n', block, re.M)
            if at is None:
                print("‼ %s (%s): немає «дроп» у тексті" % (mob.get("назва"), key))
                continue
            pad = at.group(1) + "  "
            entry = ('%s{\n%s  "що": "%s",\n%s  "шанс": %s,\n%s  "від": %d,\n'
                     '%s  "до": %d\n%s},\n') % (pad, pad, metal, pad, CHANCE, pad,
                                                FROM, pad, TO, pad)
            new_block = block[:at.end()] + entry + block[at.end():]
            added += 1
        text = text[:start.start()] + new_block + text[end:]
    json.loads(text)  # не зламали
    print("метал: додано %d видам, піднято шанс у %d" % (added, raised))
    if not only_check and (added or raised):
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        print("✓ %s" % os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
