#!/usr/bin/env python3
"""Моделі монстрів копіюванням (П-248, 25.09.2026).

Слово замовника: «на сьогодні достатня кількість та по типам
самодостатня, пропоную просто скопіювати гарні моделі які по типам
схожі, нехай повторюється вигляд а параметри будуть як вирішили».

Вид без своєї доброї моделі дістає в `mobs.json → вигляд.модель` файл
схожого виду; стати, рівень, зріст, дроп, поведінка — свої. Добрі —
скани за референсом (шлях А) і дві моделі з набору. Заглушки «шаблон»
(§7.2 спеки 3D) лишаються: вони вже і є копія схожого виду з його
кольорами. Схожість — поле `конвеєр` бестіарію, всередині — ключові
слова назви; вибір зразка — пропозиція виконавця (two-way).

    python3 tools/kopii_modelej.py              # показати, нічого не міняє
    python3 tools/kopii_modelej.py --застосувати
"""
import collections
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
import scan_profiles as P  # noqa: E402

MOBS = os.path.join(ROOT, "game", "data", "mobs.json")
BEST = os.path.join(ROOT, "spec", "бестіарій.json")
OWN = "res://models/own/"

# Добрі моделі: скани шляху А, перевірені пробою й аркушем.
GOOD = ["заєць", "вовк", "вовк-сіромаха", "лисиця", "рись", "кабан",
        "кабан-мутант", "ведмідь", "олень-рогач", "піщана агама", "кажан",
        "скорпіон", "імп", "паглін", "зомбі", "гнол-мисливець", "скелет",
        "скелет-воїн", "скелет-лучник", "скелет-маг"]
KIT = {"слиз": "res://models/creatures/Slime.fbx",
       "дракон": "res://models/creatures/Dragon.fbx"}

# (слова, зразок): слово збігається з ПОЧАТКУ слова назви («ірбіс» не
# «біс», «зіпсований» не «сова»); `*` — будь-де в слові (кабаноЛЮД).
# Порядок: людиноподібні звірі → звірі (форма тіла важить більше за
# «упир»/«кістяний» — вовк-упир ходить на чотирьох) → двоногі й нежить.
WORDS = [
    (("*люд", "гнол", "вовкулак", "єті", "троль", "берсерк", "анубіс",
      "вендіго", "звіробог"), "гнол-мисливець"),
    (("драконід",), "імп"),
    (("слиз", "желе"), "слиз"),
    (("дракон", "віверн", "виверн", "лускокрил"), "дракон"),
    (("кажан", "летюч", "нетопир"), "кажан"),
    (("беркут", "орел", "гриф", "птах", "жаро-птах", "сова"), "кажан"),
    (("скорпіон", "павук", "каракурт", "жук", "богомол", "панцирник",
      "багатоніжк", "*хеліцер", "скарабей", "кліщ"), "скорпіон"),
    (("ведм", "росомах", "мамонт"), "ведмідь"),
    (("вепр", "кабан", "тур", "зубр", "голкошерст"), "кабан"),
    (("олен", "лось", "козел", "сарн", "архар", "таран", "химер"), "олень-рогач"),
    (("*вовк", "хорт", "гончак", "шакал", "койот"), "вовк-сіромаха"),
    (("лис", "фенек"), "лисиця"),
    (("рис", "ірбіс", "барс", "пантер", "лев", "тигр"), "рись"),
    (("заєць", "кроли", "щур", "бабак", "кріт"), "заєць"),
    (("ящір", "варан", "агам", "хамелеон", "саламандр", "ядозуб",
      "плавун", "гідр", "василіск"), "піщана агама"),
    (("лучник",), "скелет-лучник"),
    (("=маг", "ліч", "некромант", "єпископ", "жрець", "архітектор", "монах",
      "абат", "аббатис", "капелан", "інквізитор", "послушник", "сестр",
      "кардинал", "тінь"), "скелет-маг"),
    (("скелет", "кістяк", "кістян", "центуріон"), "скелет-воїн"),
    (("зомб", "мерц", "мертв", "гуль", "упир", "вампір", "кадавр", "мумі"), "зомбі"),
    (("імп", "біс", "демон", "чорт", "іфрит", "джин", "наг"), "імп"),
    (("паглін", "гоблін", "жаб"), "паглін"),
    (("голем", "колос", "титан"), "зомбі"),
]
# Нічого з назви не впізнано — за типом тіла.
BY_PIPE = {"Л": "гнол-мисливець", "Ч": "вовк-сіромаха", "С": "скорпіон",
           "Д": "кажан", "К": "скелет-воїн", "З": "піщана агама", "": "зомбі"}


def path_of(name, mobs):
    """Шлях зразка — з його ж запису в `mobs.json` (файли названі не
    завжди за видом: олень-рогач лежить як `олень.glb`)."""
    for mob in mobs.values():
        if isinstance(mob, dict) and mob.get("назва") == name:
            return mob["вигляд"]["модель"]
    sys.exit("‼ зразка %s немає в mobs.json" % name)


def hit(word, low):
    parts = re.split(r"[^\w']+", low)
    if word.startswith("*"):
        return any(word[1:] in p for p in parts)
    if word.startswith("="):
        return word[1:] in parts
    return any(p.startswith(word) for p in parts)


def pick(name, pipe):
    low = name.lower()
    for words, model in WORDS:
        if any(hit(w, low) for w in words):
            return model, "назва"
    return BY_PIPE.get(pipe, "зомбі"), "тип «%s»" % pipe


def main():
    apply = "--застосувати" in sys.argv
    mobs = json.load(open(MOBS, encoding="utf-8"))
    best = {x["назва"]: x for x in json.load(open(BEST, encoding="utf-8"))}
    stubs = {n for n, c in P.SPECIES.items() if c.get("template")}
    good = set(GOOD) | set(KIT)
    for n in GOOD:
        f = os.path.join(ROOT, "game", path_of(n, mobs)[len("res://"):])
        if not os.path.exists(f):
            sys.exit("‼ немає доброї моделі %s" % f)
    plan = []
    for key, mob in mobs.items():
        if key == "_про":
            continue
        name = mob.get("назва", key)
        if name in good or name in stubs:
            continue
        pipe = best.get(name, {}).get("конвеєр", "")
        model, why = pick(name, pipe)
        plan.append((name, pipe, model, why, key))
    by = collections.defaultdict(list)
    for name, pipe, model, why, _ in plan:
        by[model].append(name + ("" if why == "назва" else " (%s)" % why))
    print("видів до копіювання: %d (добрих %d, заглушок лишається %d)"
          % (len(plan), len(good), len(stubs)))
    for model in sorted(by, key=lambda m: -len(by[m])):
        print("\n%s ← %d:\n  %s" % (model, len(by[model]), "\n  ".join(by[model])))
    if not apply:
        print("\n(нічого не змінено; застосувати — --застосувати)")
        return
    for name, pipe, model, why, key in plan:
        mobs[key].setdefault("вигляд", {})["модель"] = path_of(model, mobs)
        mobs[key]["вигляд"].pop("в_руці", None)
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    from monster_pipeline import dump_mobs  # формат репозиторію
    dump_mobs(mobs, MOBS)
    print("\nзаписано: %s (%d видів)" % (os.path.relpath(MOBS, ROOT), len(plan)))


if __name__ == "__main__":
    main()
