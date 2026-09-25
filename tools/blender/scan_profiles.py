"""Профілі типів тіла для шляху А: усе, що до 24.09.2026 підбиралось
заново на кожному звірі, — один раз на тип. Споріднені види (вовк →
сіромаха → вовк-мутант, ведмідь → печерний → мутант, скелет → воїн/
лучник/маг) беруть профіль як є; своє у виду — лише те, чим він справді
відрізняється.

Поля профілю:
- body       — "quadruped" (скелет і рухи зайця) / "humanoid" (свій
               скелет, П-247) / "legacy" (окремий білдер, напр. крилаті);
- faces      — граней після спрощення (кабан: 20-30 тис. гранчасті писок,
               80 тис. — чисто; олень: тонкі роги — 40 тис.);
- fur        — `вигляд.хутро` для mobs.json, None — без ворсу (луска,
               кістяк, панцир);
- fur_rule   — що голе в масці ворсу (`scan_lib.fur_mask`);
- ears       — шукати вуха (False — роги/чубчики лишаються на голові й
               не «вухають» в Idle);
- pose       — чи робити крок пози Kontext за замовчуванням і який
               промт (None — стандартний чотирилапий із monster3d.py).

Вид: profile, who (англійською — для Kontext), і перевизначення будь-
якого поля профілю. `template` — готовий вид-шаблон для швидкого шляху
(`monster_pipeline.py шаблон`: його сітка й рухи + кольори референсу). `зріст` і шлях моделі беруться з game/data/mobs.json.
"""

HUMANOID_POSE = (
    "Change only the camera angle, distance and background. The same {who} keeps "
    "exactly the same appearance, but now stands calmly on both feet, "
    "strict front view: body, head and feet turned straight towards the camera, "
    "symmetric stance, feet side by side shoulder-width apart, "
    "arms slightly away from the body, seen from farther "
    "away with a normal lens, no strong perspective distortion, both feet "
    "flat on the ground and fully visible, the entire body clearly visible in "
    "frame with room to spare at the edges. Replace the background with a "
    "plain uniform light grey studio background, soft even lighting. Keep "
    "exactly the same {who}: same colours, same face, same clothing, same "
    "weapon, same markings, same style.")

# Лучник і маг: HUMANOID_POSE лишав позу стрільби й губив посох (24.09).
# Kontext не розуміє заперечень — зброя описується ствердно й окремо.
ARCHER_POSE = HUMANOID_POSE.replace(
    "arms slightly away from the body,",
    "the bow is relaxed and unstrung-looking, held loosely pointing down in "
    "the left hand beside the left leg, the right arm hangs relaxed slightly "
    "away from the body with an open hand, the arrows stay in the quiver on "
    "the back,")

MAGE_POSE = HUMANOID_POSE.replace(
    "arms slightly away from the body,",
    "the right hand holds a tall wooden staff topped with a small skull, the "
    "staff stands upright on the ground beside the right foot, clearly apart "
    "from the body, the left arm hangs relaxed slightly away from the body, "
    "the robe ends just above the ankles so both bony feet are visible,")

QUADRUPED_DOWN_POSE = (
    "Change only the pose and background. The same {who} now crouches down on "
    "all four legs on flat ground, front legs bent and front paws/feet firmly "
    "planted on the ground directly below the shoulders, weight evenly "
    "distributed on all four limbs, NOT reared up, NOT standing upright on "
    "hind legs only, a normal calm quadruped stance like an ordinary animal "
    "on all fours, full body fully visible, three-quarter view from the "
    "front-left, all four legs touching the ground, relaxed neutral standing "
    "stance, head level. Replace the background with a plain uniform light "
    "grey studio background, soft even lighting. Keep exactly the same "
    "{who}: same colours and texture, same face, same eyes, same markings, "
    "same photorealistic style.")

# Скелет-щур: QUADRUPED_DOWN_POSE двічі лишав його дибки (24.09) — «NOT
# reared up» Kontext не читає. Тут лише ствердно: миша на чотирьох лапах.
RAT_POSE = (
    "Change only the pose and background. The same {who} is now a small "
    "rodent skeleton walking on all four legs like an ordinary mouse, spine "
    "horizontal and parallel to the ground, belly low close to the ground, "
    "both front paws planted flat on the ground directly under the chest, "
    "both hind paws planted flat on the ground under the hips, the head low "
    "and level in front of the front paws, the tail lying along the ground "
    "behind, full body fully visible, three-quarter view from the "
    "front-left. Replace the background with a plain uniform light grey "
    "studio background, soft even lighting. Keep exactly the same {who}: "
    "same bone colour, same skull, same big ears, same glowing eyes, same "
    "ribs, same style.")

PROFILES = {
    "псові": dict(body="quadruped", faces=24000,
                  fur={"довжина": 0.016, "шари": 20, "густота": 1300},
                  fur_rule={"pink": True, "dark": 0.1}, ears=True),
    "котячі": dict(body="quadruped", faces=32000,
                   fur={"довжина": 0.011, "шари": 18, "густота": 1500},
                   fur_rule={"pink": True, "dark": 0.14}, ears=True),
    "ведмеді": dict(body="quadruped", faces=32000,
                    fur={"довжина": 0.022, "шари": 20, "густота": 1100},
                    fur_rule={"pink": True, "dark": 0.06}, ears=True),
    "кабани": dict(body="quadruped", faces=80000,
                   fur={"довжина": 0.02, "шари": 14, "густота": 900},
                   fur_rule={"pink": True, "dark": 0.14}, ears=True),
    "копитні": dict(body="quadruped", faces=40000,
                    fur={"довжина": 0.014, "шари": 18, "густота": 1300},
                    fur_rule={"pink": True, "dark": 0.14}, ears=False),
    "ящірки": dict(body="quadruped", faces=30000, fur=None,
                   fur_rule={"pink": False, "dark": 0}, ears=False),
    "кістяки-звірі": dict(body="quadruped", faces=30000, fur=None,
                          fur_rule={"pink": False, "dark": 0}, ears=True),
    "гуманоїди": dict(body="humanoid", faces=30000, fur=None,
                      fur_rule={"pink": True, "dark": 0.06}, pose=HUMANOID_POSE),
    "гуманоїди-хутряні": dict(body="humanoid", faces=30000,
                              fur={"довжина": 0.014, "шари": 16, "густота": 1200},
                              fur_rule={"pink": True, "dark": 0.08}, pose=HUMANOID_POSE),
    "крилаті": dict(body="legacy", script="make_bat_scan.py"),
    "членистоногі": dict(body="legacy", script="make_scorpion_scan.py"),
}

SPECIES = {
    # готові (для перевірки регресії новим білдером)
    "лисиця": dict(profile="псові", who="red fox", faces=20000,
                   fur={"довжина": 0.013, "шари": 20, "густота": 1400}),
    "рись": dict(profile="котячі", who="lynx with long black ear tufts"),
    "кабан": dict(profile="кабани", who="wild boar"),
    "олень-рогач": dict(profile="копитні", who="red deer stag with large antlers",
                        source="олень"),
    "імп": dict(profile="гуманоїди", who="red horned imp demon", tail=True),
    "паглін": dict(profile="гуманоїди", who="green frog goblin creature"),
    "зомбі": dict(profile="гуманоїди", who="rotting zombie"),
    # черга E
    "вовк-сіромаха": dict(profile="псові", who="large grey wolf with a mane"),
    "вовк-мутант": dict(profile="псові", who="mutant wolf with bone spikes on its back",
                        template="вовк-сіромаха"),
    "ведмідь": dict(profile="ведмеді", who="brown bear"),
    "печерний ведмідь": dict(profile="ведмеді", who="huge grey cave bear",
                             pose=QUADRUPED_DOWN_POSE, template="ведмідь"),
    "ведмідь-мутант": dict(profile="ведмеді", who="mutant bear with bone spikes",
                           pose=QUADRUPED_DOWN_POSE, template="ведмідь"),
    "кабан-мутант": dict(profile="кабани", who="mutant boar with bone plates on its back"),
    "піщана агама": dict(profile="ящірки", who="sand agama lizard"),
    "плащоносна ящірка": dict(profile="ящірки", who="frilled lizard",
                              pose=QUADRUPED_DOWN_POSE, template="піщана агама"),
    "катакомбний скелет-щур": dict(profile="кістяки-звірі", who="skeletal rat",
                                   pose=RAT_POSE),
    "химера": dict(profile="копитні", who="chimera beast with elk body and wolf chest", template="олень-рогач"),
    "кажан-кровопивця": dict(profile="крилаті", who="large vampire bat", template="кажан"),
    "чорний скорпіон": dict(profile="членистоногі", who="black scorpion", template="скорпіон"),
    "павук-тенетник": dict(profile="членистоногі", who="giant orb-weaver spider"),
    # Ліва рука за замірами зрізів (25.09.2026): авто-кисть ішла в плащ
    # позаду (y +0.21…0.31), а меч — попереду, і лезо брало ваги ніг.
    "скелет": dict(profile="гуманоїди", who="undead skeleton", bones_override=[
        ("arm.L", (-0.22, 0.12, 1.45), (-0.33, 0.10, 1.10), "chest"),
        ("arm.L.2", (-0.33, 0.10, 1.10), (-0.35, 0.0, 0.76), "arm.L")],
        # лезо: вісь підігнана по точках попереду тіла (y < −0.2), від
        # виходу з тіла (y −0.12) до вістря; відхилення точок до 6.4 см.
        # Ближче до руків'я трубка забирала б стегно й плащ.
        rigid=[("arm.L.2", (-0.298, -0.12, 0.667), (0.021, -0.934, 0.274), 0.075)]),
    "скелет-воїн": dict(profile="гуманоїди", who="undead skeleton warrior in a rusty cuirass"),
    "скелет-лучник": dict(profile="гуманоїди", who="undead skeleton archer with a quiver",
                          pose=ARCHER_POSE),
    "скелет-маг": dict(profile="гуманоїди", who="undead skeleton mage in a robe",
                       pose=MAGE_POSE, weld_after=True,
                       # Права рука й посох за зрізами (25.09.2026): авто-кисть
                       # сідала на посох на 0.58 м, а хват — біля 1.0 м;
                       # посох гнувся на рухах. Древко (2 см завтовшки — ширша трубка
                       # брала край плаща) й череп — жорсткі.
                       bones_override=[
                           ("arm.R", (0.24, 0.12, 1.38), (0.30, 0.10, 0.98), "chest"),
                           ("arm.R.2", (0.30, 0.10, 0.98), (0.44, -0.22, 1.02), "arm.R")],
                       rigid=[("arm.R.2", (0.44, -0.075, 0.02), (0.445, -0.25, 1.28), 0.035),
                              ("arm.R.2", (0.445, -0.25, 1.28), (0.46, -0.30, 1.52), 0.14)]),
    "зомбі-громило": dict(profile="гуманоїди", who="huge bloated zombie brute", template="зомбі"),
    "щуролюд-злодій": dict(profile="гуманоїди-хутряні", who="ratman thief", tail=True, template="гнол-мисливець"),
    "гнол-мисливець": dict(profile="гуманоїди-хутряні", who="hyena-headed gnoll hunter with a bone-tipped spear", tail=True, yaw=50),
    "гнол-воїн": dict(profile="гуманоїди-хутряні", who="gnoll warrior", template="гнол-мисливець"),
    "лисолюд-шаман": dict(profile="гуманоїди-хутряні", who="foxfolk shaman", tail=True, template="гнол-мисливець"),
    "вовкулака-новак": dict(profile="гуманоїди-хутряні", who="young werewolf", tail=True, template="гнол-мисливець"),
}


# Швидкий шлях для каталогу (spec/бестіарій.json): вид поза SPECIES →
# шаблон за конвеєром і словами назви, перше збіжне правило. «—» — види
# без конвеєра на процедурних humanoids/*.gltf. Змії, дракони, слиз — без
# шаблону (None).
TEMPLATE_RULES = [
    ("Ч", r"ведмід|ведмеж|мамонт|росомах", "ведмідь"),
    ("Ч", r"фенек|щур", "лисиця"),
    ("Ч", r"вовк|хорт|гончак|койот|химер", "вовк-сіромаха"),
    ("Ч", r"рись|барс|ірбіс|пантер", "рись"),
    ("Ч", r"вепр|кабан", "кабан"),
    ("Ч", r"тур|козел|архар|сарна|таран", "олень-рогач"),
    ("Ч", r"ящір|ядозуб|варан|саламандр|хамелеон", "піщана агама"),
    ("Ч", r"бабак|кріт|підкопувач|голкошерст", "заєць"),
    ("Ч", r".", "вовк-сіромаха"),
    ("К", r"хорт", "вовк-сіромаха"),
    ("ЛК—", r"іфрит|джин|демон", "імп"),
    ("ЛК—", r"щуро|гнол|звіро|кабанолюд|ведмедолюд|вовкулак|єті|мавпо|примат|вендіго|анубіс|скорпіонолюд",
     "гнол-мисливець"),
    ("ЛК", r".", "зомбі"),
    ("—", r"гуль|упир|вампір|драконід|наг", "зомбі"),
    ("С", r".", "скорпіон"),
    ("Д", r".", "кажан"),
]


def catalog():
    import json
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "spec", "бестіарій.json")
    return {m["назва"]: m for m in json.load(open(path, encoding="utf-8"))}


def auto_template(m):
    import re
    conv = m.get("конвеєр") or "—"
    if conv == "—" and "humanoids/" not in (m.get("модель") or ""):
        return None
    for convs, rx, tpl in TEMPLATE_RULES:
        if conv in convs and re.search(rx, m["назва"]):
            return tpl
    return None


def config(name):
    """Злитий профіль + вид. `source` — ім'я теки art/monsters/<source>-3d
    (за замовчуванням сама назва). Вид каталогу поза SPECIES — профіль
    свого шаблону (`auto_template`)."""
    if name in SPECIES:
        sp = SPECIES[name]
    else:
        tpl = auto_template(catalog()[name])
        if tpl is None:
            raise KeyError("‼ %s — немає ні в SPECIES, ні шаблону в TEMPLATE_RULES" % name)
        prof = SPECIES[tpl]["profile"] if tpl in SPECIES else \
            {"кажан": "крилаті", "скорпіон": "членистоногі", "заєць": "псові"}[tpl]
        sp = dict(profile=prof, who=name, template=tpl)
    cfg = dict(PROFILES[sp["profile"]])
    cfg.update(sp)
    cfg.setdefault("source", name)
    cfg.setdefault("pose", None)
    return cfg
