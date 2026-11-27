#!/usr/bin/env python3
"""Аркуш-референс гуманоїда для 3D-моделювання (25.11.2026).

Слово замовника: «створити для кожного монстра деталізований референс з освітленням з усіх
боків з виглядами спереду, під кутом 45, кутом 90, ззаду в позах А та Т, з основними
кольорами, розмірами … оптимізованими для полегшення створення 3D моделей». Обсяг — лише
гуманоїди (види, що взяли модель-копію гнол-мисливець / зомбі / скелет-маг / імп /
скелет-воїн, П-248), ракурс задає рендер-каркас.

Рецепт — як фото-вигляди людини П-289 («рівне світло 360°»):
  каркас  — `art/monsters/_аркуш-каркас/` (звідки — `ЗВІДКИ.txt`): А — рендер манекена
            `6-суглоби/людина-авто.blend` у позі скульптури тіло-4, 0/45/90/180°
            (`tools/blender/karkas_at.py`); Т — фото першого ряду `кіраса-4-проекції.jpg`
            (`пози-рівне-світло/Р0-s9941`, `Р45/Р90/Р180-s9942`), обидва — слово замовника;
  А-0     — Qwen-Edit 2511: перша картинка каркас А-0, друга — референс виду з вікі;
  решта 7 — перша картинка каркас потрібного кадру, друга — готовий А-0 виду (зразок);
  26.11.2026 — Т-0 лише текстом (+ кістяк запасним) з перевіркою розмаху рук, ракурси —
            з перевіркою «не копія свого 0°», до 3 сідів; ремонт готових аркушів — remont_t_riadu;
  аркуш   — 2 ряди (А, Т) × 4 ракурси, лінійка в метрах за зростом із бестіарію,
            основні кольори (k-середні з А-0 і А-180), опис моделі з бестіарію.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/monstr_arkush.py --список
    ~/Програми/cv-venv/bin/python -u tools/comfyui/monstr_arkush.py <вид> [<вид> …] | --усі
    ~/Програми/cv-venv/bin/python -u tools/comfyui/monstr_arkush.py --зібрати [<вид> …]

Вихід — `art/monsters/<вид>-3d/аркуш/<поза>-<кут>.png` і `аркуш.jpg` (лише диск, .gitignore).
"""
import json
import os
import shutil
import sys
import textwrap

import numpy as np
from PIL import Image, ImageDraw, ImageFont

KORIN = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(KORIN, "tools"))
import kopii_modelej as km  # noqa: E402

KARKAS = os.path.join(KORIN, "art/monsters/_аркуш-каркас")
SHABLONY = ("гнол-мисливець", "зомбі", "скелет-маг", "імп", "скелет-воїн")
KADRY = [(p, k) for p in "АТ" for k in (0, 45, 90, 180)]
PORIADOK = [("А", 0), ("Т", 0)] + [(p, k) for p in "АТ" for k in (45, 90, 180)]
SID = 9942
KUT_OPYS = {0: "strict front view",
            45: "three-quarter view, the body turned 45 degrees to the side",
            90: "exact side view in profile",
            180: "strict back view from behind"}
POZA_OPYS = {"А": "A-pose: relaxed neutral stance, arms hanging down straight, slightly away from "
                  "the body, hands open by the thighs",
             "Т": "T-pose: arms straight out to the sides at shoulder height, palms down"}
SVITLO = ("Lighting: perfectly even flat diffuse light from all directions, like inside a "
          "360-degree white light dome: no shadows anywhere on the body or on the floor, no dark "
          "sides, no rim light, no highlights; matte surfaces showing their true colours. Plain "
          "light grey seamless background, whole body from head to feet (and tail tip, wings, "
          "horns) in frame with margin, photorealistic, sharp detail.")


def bestiarii():
    return {b["назва"]: b for b in json.load(open(km.BEST))}


def gumanoidy():
    """[(вид, шаблон)] — види, що взяли модель-копію гуманоїда."""
    mobs = json.load(open(km.MOBS))
    svoia = {v["назва"] for k, v in mobs.items() if not k.startswith("_")
             and v["вигляд"].get("модель", "").endswith("/" + v["назва"] + ".glb")}
    rez = []
    for b in json.load(open(km.BEST)):
        if b["назва"] in km.GOOD or b["назва"] in SHABLONY or b["назва"] in svoia:
            continue
        shablon, _ = km.pick(b["назва"], b.get("конвеєр", ""))
        if shablon in SHABLONY:
            rez.append((b.get("рівень", 999), b["назва"], shablon))
    return [(v, s) for _, v, s in sorted(rez)]  # за рівнем: E → SS


def teka(vyd):
    return os.path.join(KORIN, "art/monsters", vyd + "-3d", "аркуш")


def instr(poza, kut, pershyi, b=None):
    """Перша картинка — сам монстр (референс вікі або вже готовий А-0), друга — каркас: лише
    зразок пози й ракурсу. Навпаки (каркас першим) Qwen лишав людину-манекен і тільки
    перефарбовував шкіру — проба гуля 25.11.2026, `_аркуш-каркас/проба-ролей/`."""
    khto = ("the creature from the first image" if pershyi else
            "exactly the same creature as in the first image")
    return ("Show " + khto + " as a clean full-body character turnaround reference for 3D "
            "modeling. Keep its identity exactly: the same head, skull and face shape, mouth and "
            "teeth, eyes, horns, ears, skin, fur or bone, the same colours and markings, the same "
            "clothing, armour and ornaments, tail and wings if it has them, the same body build, "
            "limb length and proportions — it must not become a human. Change only its pose, "
            "camera and lighting: it stands upright in the same pose as the grey mannequin in the "
            "second image — " + POZA_OPYS[poza] + ", legs straight — seen from the same camera "
            "angle as the second image: " + KUT_OPYS[kut] + "; show the parts visible from this "
            "side. The mannequin is only a pose guide: do not copy its body, face or shorts. "
            "Empty open hands: no weapon, no staff, no shield, nothing held. " + opys(b) + SVITLO)


def opys(b):
    """Опис тіла з бестіарію (українською — Qwen2.5-VL її читає) і явні «немає»: без них Qwen
    домальовував гулю хвіст (проба 25.11.2026)."""
    if not b:
        return ""
    om = b.get("опис моделі", {})
    chastyny = []
    for kl in ("голова", "тулуб", "кінцівки", "амуніція"):
        if om.get(kl):
            chastyny.append(om[kl].strip())
    tekst = ("Description of this creature (in Ukrainian): " + " ".join(chastyny) + " "
             if chastyny else "")
    khvist = (om.get("хвіст") or "").strip().rstrip(".").lower()
    if khvist in ("", "немає", "нема"):
        tekst += "It has NO tail. "
    else:
        tekst += "Tail (in Ukrainian): " + om["хвіст"].strip() + " "
    vse = " ".join(v for v in om.values() if isinstance(v, str)).lower()
    if "крил" not in vse:
        tekst += "It has NO wings. "
    return tekst


def zbroia(b):
    z = (b.get("опис моделі", {}).get("зброя") or "").strip().rstrip(".")
    return "" if z.lower() in ("", "немає", "нема") else z


def instr_zbroia(z):
    return ("From the image take only the weapon or held item of the creature (described in "
            "Ukrainian as: «" + z + "») and show it alone as a clean prop reference for 3D "
            "modeling: the whole item, upright, front view next to a side view of the same item, "
            "nothing else, no hands, no creature. " + SVITLO.split(" Plain")[0] + " Plain light "
            "grey seamless background, photorealistic, sharp detail.")


def zapustyty(m, b2, persha, druha, promt, kudy, seed=SID):
    g = b2.graf_qwen(m.stage(persha), m.stage(druha or persha), promt, seed, "arkush")
    g["1"]["inputs"]["unet_name"] = "qwen-image-edit-2511-Q4_K_M.gguf"
    g["2"]["inputs"]["lora_name"] = "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
    if druha is None:
        for n in ("9", "10"):
            g[n]["inputs"].pop("image2", None)
    g["7"]["inputs"]["resolution_steps"] = 1
    done = m.run(g)
    out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
    syryi = os.path.join(os.path.dirname(kudy), "сирі", os.path.basename(kudy))
    os.makedirs(os.path.dirname(syryi), exist_ok=True)
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), syryi)
    chyste_tlo(m, syryi, kudy)


FON = (200, 200, 202)


def chyste_tlo(m, dzherelo, kudy):
    """Постать на рівному сірому тлі: при великому повороті камери Qwen-Edit з Lightning сипле
    сміття по тлу (проба гуля Т-90, 26.11.2026) — маска birefnet, м'який край."""
    from PIL import ImageFilter
    maska = kudy + "-maska.png"
    m.cutout(dzherelo, maska)
    im = Image.open(dzherelo).convert("RGB")
    mk = Image.open(maska).convert("L").resize(im.size).filter(ImageFilter.GaussianBlur(1.5))
    Image.composite(im, Image.new("RGB", im.size, FON), mk).save(kudy)
    os.remove(maska)


# ---------- Т-0 і перевірки кадрів (рішення 26.11.2026, spec/log.md «…рішення щодо Т-пози») ----------
# Проба `tools/comfyui/proby/t0_sposoby.py` (`_аркуш-каркас/проба-т0/підсумок.jpg`): фото манекена
# другою картинкою — Т-поза 0/12 (Qwen береже позу першої картинки); лише текст — 12/12 зі
# збереженою статурою; кістяк OpenPose — 12/12, але часом тягне в людські пропорції → запасний.
T_SYLNO = ("POSE CHANGE IS REQUIRED: raise both arms straight out sideways, fully horizontal at "
           "shoulder height, elbows straight, palms down, hands open — a strict T-pose; the arms "
           "must NOT hang down. ")
KISTIAK_T0 = os.path.join(KARKAS, "кістяк", "Т-0.png")   # tools/blender/kistiak_openpose.py
SPROB = 3                      # сідів на кадр, доки не пройде перевірку
ROZMAKH_T = 1.3                # Т-0: розмах рук ≥ 1,3 × розмаху А-0
POVTOR_D = 8.0                 # ракурс ≈ свій 0° (різниця в межах постаті < 8) — не повернуто


def instr_t0(b, kistiak=False):
    p = instr("Т", 0, False, b)
    if kistiak:
        p = p.replace("the grey mannequin in the second image",
                      "the coloured OpenPose stick-figure skeleton in the second image")
        p = p.replace("The mannequin is only a pose guide: do not copy its body, face or shorts.",
                      "The skeleton is only a pose guide: do not draw any lines or dots of it.")
    else:
        p = p.replace("in the same pose as the grey mannequin in the second image — ", "in ")
        p = p.replace("seen from the same camera angle as the second image: ", "seen from ")
        p = p.replace("The mannequin is only a pose guide: do not copy its body, face or shorts. ",
                      "")
    return T_SYLNO + p


def _mal(f):
    return np.asarray(Image.open(f).convert("RGB").resize((256, 256))).astype(np.int16)


def rozmakh(f):
    """Ширина постаті в смузі плечей і рук (рядки 40–110 з 256), px."""
    mk = np.abs(_mal(f) - np.array(FON)).sum(2) > 25
    xs = np.where(mk[40:110].any(0))[0]
    return int(xs[-1] - xs[0]) if len(xs) else 0


def t_pidniato(t0, a0):
    return rozmakh(t0) >= ROZMAKH_T * max(1, rozmakh(a0))


def povtor(f, nul):
    """Кадр ракурсу майже не відрізняється від свого 0° — Qwen не повернув. Різниця — лише в межах
    постаті (обох масок): по всьому кадру тонка постать (гуль) давала «повтор» і на добрих кадрах.
    Заміри 26.11: не повернуті 45°/90° — 3,1…7,5; добрі 45°/90° — 77…88; добрі 180° — 9,9…21,7.
    «Ззаду» анфасом цим не розрізнити (базальтовий А-180 — 9,9, як добрий Т-180 гуля)."""
    a, b = _mal(f), _mal(nul)
    mk = (np.abs(a - np.array(FON)).sum(2) > 25) | (np.abs(b - np.array(FON)).sum(2) > 25)
    return float(np.abs(a - b).sum(2)[mk].mean() / 3) < POVTOR_D


def znyaty_t0(m, b2, t, b):
    """Т-0 лише текстом (сіди SID…SID+2), потім — кістяк; лишається найкраща спроба."""
    a0, kudy = os.path.join(t, "А-0.png"), os.path.join(t, "Т-0.png")
    sproby = [(False, SID + i) for i in range(SPROB)] + [(True, SID)]
    najkr = None
    for kistiak, seed in sproby:
        tmch = os.path.join(t, "Т-0-спроба.png")
        zapustyty(m, b2, a0, KISTIAK_T0 if kistiak else None, instr_t0(b, kistiak), tmch, seed)
        k = rozmakh(tmch) / max(1, rozmakh(a0))
        if najkr is None or k > najkr[0]:
            najkr = (k, kistiak, seed)
            shutil.copy(tmch, kudy)
        os.remove(tmch)
        if k >= ROZMAKH_T:
            print("  Т-0 %s s%d розмах ×%.2f ✓" % ("кістяк" if kistiak else "текст", seed, k),
                  flush=True)
            return
        print("  ↻ Т-0 %s s%d розмах ×%.2f — руки не підняті" % (
            "кістяк" if kistiak else "текст", seed, k), flush=True)
    print("‼ Т-0 не піднявся жодною спробою, лишаю найкращу (×%.2f) — перевір очима" % najkr[0],
          flush=True)


def remont_t_riadu(t, vyd):
    """Готовий аркуш (до 26.11.2026): старий Т-0 (фото манекена) з опущеними руками → Т-0 і весь
    Т-ряд геть (рішення 4); ракурс, що лишився копією свого 0°, — геть (рішення 3). Перезніметься
    в циклі кадрів; добрі кадри не чіпаються."""
    t0, a0 = os.path.join(t, "Т-0.png"), os.path.join(t, "А-0.png")
    if not (os.path.exists(t0) and os.path.exists(a0)):
        return
    if not t_pidniato(t0, a0):
        print("↻ %s: Т-0 з опущеними руками (×%.2f) — перезнімаю Т-ряд" % (
            vyd, rozmakh(t0) / max(1, rozmakh(a0))), flush=True)
        for k in (0, 45, 90, 180):
            f = os.path.join(t, "Т-%d.png" % k)
            if os.path.exists(f):
                os.remove(f)
    # ракурси, що лишились копією свого 0° (перевірка povtor), — теж перезняти
    for poza in "АТ":
        nul = os.path.join(t, "%s-0.png" % poza)
        for k in (45, 90, 180):
            f = os.path.join(t, "%s-%d.png" % (poza, k))
            # «‼» — уже тричі не повернувся: на кожному перезапуску не перезнімати знову
            if os.path.exists(f[:-4] + ".‼"):
                continue
            if os.path.exists(f) and os.path.exists(nul) and povtor(f, nul):
                print("↻ %s: %s-%d ≈ свій 0° — перезнімаю" % (vyd, poza, k), flush=True)
                os.remove(f)


def zheneruvaty(vydy):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import monster3d as m  # noqa: E402
    import bronia_2var as b2  # noqa: E402
    best = bestiarii()
    for vyd in vydy:
        ref = os.path.join(KORIN, "wiki/img/monstry", vyd + ".png")
        if not os.path.exists(ref):
            print("‼ немає референсу", ref, flush=True)
            continue
        t = teka(vyd)
        os.makedirs(t, exist_ok=True)
        remont_t_riadu(t, vyd)
        for poza, kut in PORIADOK:
            kudy = os.path.join(t, "%s-%d.png" % (poza, kut))
            if os.path.exists(kudy):
                continue
            pershyi = (poza, kut) == ("А", 0)
            # ланцюжок: реф → А-0 → (А-45/90/180, Т-0) ; Т-0 → Т-45/90/180. Поза міняється лише
            # раз (А-0 → Т-0): від А-0 одразу в Т збоку Qwen лишав руки опущені (проба гуля)
            persha = (ref if pershyi else
                      os.path.join(t, "Т-0.png") if poza == "Т" and kut else
                      os.path.join(t, "А-0.png"))
            if (poza, kut) == ("Т", 0):
                znyaty_t0(m, b2, t, best[vyd])
                print("готово", vyd, poza, kut, flush=True)
                continue
            druha = os.path.join(KARKAS, "%s-%d.png" % (poza, kut))
            nul = os.path.join(t, "%s-0.png" % poza)
            for i in range(1 if kut == 0 else SPROB):
                zapustyty(m, b2, persha, druha, instr(poza, kut, pershyi, best[vyd]), kudy,
                          SID + i)
                if kut == 0 or not povtor(kudy, nul):
                    break
                print("  ↻ %s-%d s%d ≈ свій 0° — не повернуто" % (poza, kut, SID + i), flush=True)
            else:
                print("‼ %s %s-%d не повернувся за %d спроби — перевір очима" % (
                    vyd, poza, kut, SPROB), flush=True)
                open(kudy[:-4] + ".‼", "w").write("не повернувся за %d спроби\n" % SPROB)
            print("готово", vyd, poza, kut, flush=True)
        z = zbroia(best[vyd])
        kudy = os.path.join(t, "зброя.png")
        if z and not os.path.exists(kudy):
            zapustyty(m, b2, ref, None, instr_zbroia(z), kudy)
            print("готово", vyd, "зброя", flush=True)
        zibraty(vyd)
    m.free()


# ---------- аркуш (лише CPU) ----------

def shryft(r, zhyr=False):
    return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
                              % ("-Bold" if zhyr else ""), r)


def maska(a):
    """Постать без тла: тло — медіана країв, відстань > 30."""
    tlo = np.median(np.concatenate([a[:6].reshape(-1, 3), a[-6:].reshape(-1, 3),
                                    a[:, :6].reshape(-1, 3), a[:, -6:].reshape(-1, 3)]), 0)
    return np.abs(a.astype(np.int16) - tlo).sum(2) > 30


def mezhi_postati(a):
    m_ = maska(a)
    ys = np.where(m_.any(1))[0]
    return (ys[0], ys[-1]) if len(ys) else (0, a.shape[0] - 1)


PIDPYSY = {0: "СПЕРЕДУ", 45: "3/4 · 45°", 90: "ЗБОКУ · 90°", 180: "ЗЗАДУ · 180°"}
CHORNYI, SIRYI, TLO = (30, 30, 34), (90, 90, 98), (238, 237, 233)


def klastery(x, k=6):
    rng = np.random.default_rng(0)
    c = x[rng.choice(len(x), k, replace=False)]
    for _ in range(25):
        lab = ((x[:, None] - c[None]) ** 2).sum(2).argmin(1)
        c = np.array([x[lab == i].mean(0) if (lab == i).any() else c[i] for i in range(k)])
    return c, lab


def latky(shliakh, k=6, r=256, vikno=20):
    """Основні кольори й латка матеріалу для кожного: місце кадру, де цей колір найгустіший."""
    im = Image.open(shliakh).convert("RGB")
    a = np.asarray(im.resize((r, r))).astype(np.float32)
    mk = maska(a.astype(np.uint8))
    c, lab = klastery(a[mk], k)
    mapa = np.full((r, r), -1)
    mapa[mk] = lab
    chastka = np.bincount(lab, minlength=k) / len(lab)
    rez = []
    for i in chastka.argsort()[::-1]:
        if chastka[i] < 0.03:
            continue
        f = (mapa == i).astype(np.float32)
        ii = np.pad(f.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
        s = ii[vikno:, vikno:] - ii[:-vikno, vikno:] - ii[vikno:, :-vikno] + ii[:-vikno, :-vikno]
        y, x = np.unravel_index(s.argmax(), s.shape)
        sk = im.width / r
        latka = im.crop((int(x * sk), int(y * sk), int((x + vikno) * sk), int((y + vikno) * sk)))
        rez.append((tuple(int(v) for v in c[i]), chastka[i], latka))
    return rez


def holova(shliakh):
    """Квадрат голови: верх постаті, ширина — постать у верхніх 12 % зросту."""
    im = Image.open(shliakh).convert("RGB")
    a = np.asarray(im)
    mk = maska(a)
    ys = np.where(mk.any(1))[0]
    if not len(ys):
        return im
    y0, y1 = ys[0], ys[-1]
    h = y1 - y0
    smuha = mk[y0:y0 + int(0.12 * h)]
    xs = np.where(smuha.any(0))[0]
    cx = (xs[0] + xs[-1]) // 2 if len(xs) else a.shape[1] // 2
    st = int(0.2 * h)
    top = max(0, y0 - int(0.02 * h))
    return im.crop((cx - st // 2, top, cx + st // 2, top + st))


def rozbyty(tekst, shr, shyryna, d):
    sl, ry = tekst.split(), []
    r = ""
    for w in sl:
        t = (r + " " + w).strip()
        if d.textlength(t, font=shr) > shyryna and r:
            ry.append(r)
            r = w
        else:
            r = t
    if r:
        ry.append(r)
    return ry


def zibraty(vyd):
    t = teka(vyd)
    kadry = [os.path.join(t, "%s-%d.png" % pk) for pk in KADRY]
    if not all(os.path.exists(k) for k in kadry):
        print("… ще не всі кадри", vyd, flush=True)
        return
    b = bestiarii()[vyd]
    om = b.get("опис моделі", {})
    zrist = float(b.get("вигляд", {}).get("розмір") or 0)
    C, LIV, POLE = 520, 110, 30
    W = LIV + 4 * C + POLE
    tymch = Image.new("RGB", (10, 10))
    dd = ImageDraw.Draw(tymch)
    oznaky = []
    for kl, nazva in (("голова", "Голова"), ("тулуб", "Тулуб"), ("кінцівки", "Кінцівки"),
                      ("хвіст", "Хвіст"), ("амуніція", "Амуніція"), ("зброя", "Зброя")):
        if om.get(kl) and om[kl].strip().rstrip(".").lower() not in ("немає", "нема"):
            oznaky.append((nazva, om[kl]))
    ryadky = []
    for nazva, tx in oznaky:
        r = rozbyty(tx, shryft(17), W - 2 * POLE - 150, dd)
        ryadky.append((nazva, r))
    vys_oznak = 50 + sum(len(r) * 24 + 8 for _, r in ryadky)
    Y_RIAD = 120
    RIAD = C + 46
    Y_NYZ = Y_RIAD + 2 * RIAD + 20
    NYZ = 380
    H = Y_NYZ + NYZ + vys_oznak + POLE
    ark = Image.new("RGB", (W, H), TLO)
    d = ImageDraw.Draw(ark)
    # шапка
    d.text((POLE, 22), vyd.upper(), font=shryft(42, True), fill=CHORNYI)
    sub = "референс для 3D · рівень %s · зріст %.2f м · модель зараз: копія «%s»" % (
        b.get("рівень", "?"), zrist, dict(gumanoidy()).get(vyd, "—"))
    d.text((POLE + 2, 76), sub, font=shryft(19), fill=SIRYI)
    d.line((POLE, Y_RIAD - 12, W - POLE, Y_RIAD - 12), fill=(200, 198, 192), width=2)
    # два ряди поворотів
    for i, (poza, kut) in enumerate(KADRY):
        im = Image.open(kadry[i]).convert("RGB")
        im = im.resize((C, round(C * im.height / im.width)))
        if im.height > C:
            im = im.crop((0, (im.height - C) // 2, C, (im.height - C) // 2 + C))
        x, y = LIV + (i % 4) * C, Y_RIAD + (i // 4) * RIAD
        ark.paste(im, (x, y + 34))
        pd = PIDPYSY[kut]
        d.text((x + (C - d.textlength(pd, font=shryft(20, True))) / 2, y + 4), pd,
               font=shryft(20, True), fill=CHORNYI)
        if i % 4:
            d.line((x, y + 40, x, y + 34 + C - 6), fill=(214, 212, 206), width=1)
        if i % 4 == 0:
            d.text((POLE, y + 4), "%s-ПОЗА · м" % poza, font=shryft(18, True), fill=(150, 40, 40))
        if i % 4 == 0 and zrist:
            y0, y1 = mezhi_postati(np.asarray(im))
            y0 += y + 34
            y1 += y + 34
            xl = LIV - 22
            d.line((xl, y0, xl, y1), fill=CHORNYI, width=3)
            krok = 0.5 if zrist > 1.5 else 0.25
            v = 0.0
            while v <= zrist + 1e-6:
                yy = y1 - (y1 - y0) * v / zrist
                d.line((xl - 10, yy, xl, yy), fill=CHORNYI, width=2)
                d.text((POLE - 4, yy - 9), "%.2f" % v, font=shryft(15), fill=CHORNYI)
                v += krok
            if zrist - (v - krok) > krok * 0.3:     # маківка — червона позначка зросту
                d.line((xl - 10, y0, xl, y0), fill=(150, 40, 40), width=3)
                d.text((POLE - 4, y0 - 9), "%.2f" % zrist, font=shryft(15, True),
                       fill=(150, 40, 40))
            for xx in range(LIV, LIV + 4 * C, 14):
                d.line((xx, y0, xx + 6, y0), fill=(170, 168, 160))
                d.line((xx, y1, xx + 6, y1), fill=(170, 168, 160))
    # нижня смуга: голова | матеріали й кольори | зброя
    y = Y_NYZ
    d.line((POLE, y - 10, W - POLE, y - 10), fill=(200, 198, 192), width=2)
    d.text((POLE, y), "ГОЛОВА", font=shryft(20, True), fill=CHORNYI)
    HS = 210
    for j, k in enumerate((0, 1, 2, 3)):
        h = holova(kadry[k]).resize((HS, HS))
        ark.paste(h, (POLE + j * (HS + 8), y + 34))
        d.text((POLE + j * (HS + 8) + 4, y + 34 + HS + 4), PIDPYSY[KADRY[k][1]],
               font=shryft(14), fill=SIRYI)
    xm = POLE + 4 * (HS + 8) + 30
    d.text((xm, y), "МАТЕРІАЛИ Й ОСНОВНІ КОЛЬОРИ (частка поверхні)", font=shryft(20, True),
           fill=CHORNYI)
    LT = 104
    for j, (rgb, ch, latka) in enumerate(latky(kadry[0])[:6]):
        xx, yy = xm + (j % 3) * 250, y + 34 + (j // 3) * (LT + 40)
        ark.paste(latka.resize((LT, LT)), (xx, yy))
        d.rectangle((xx + LT + 6, yy, xx + LT + 66, yy + LT), fill=rgb, outline=(80, 80, 80))
        d.text((xx, yy + LT + 6), "#%02x%02x%02x · %d%%" % (*rgb, round(ch * 100)),
               font=shryft(15), fill=CHORNYI)
    zb = os.path.join(t, "зброя.png")
    xz = xm + 3 * 250 + 20
    if os.path.exists(zb):
        d.text((xz, y), "ЗБРОЯ (окрема модель, кістка руки)", font=shryft(20, True),
               fill=CHORNYI)
        zi = Image.open(zb).convert("RGB")
        zi.thumbnail((W - POLE - xz, NYZ - 50))
        ark.paste(zi, (xz, y + 34))
    # головні ознаки
    y = Y_NYZ + NYZ
    d.line((POLE, y - 10, W - POLE, y - 10), fill=(200, 198, 192), width=2)
    d.text((POLE, y), "ГОЛОВНІ ОЗНАКИ (бестіарій)", font=shryft(20, True), fill=CHORNYI)
    y += 38
    for nazva, ry in ryadky:
        d.text((POLE, y), "• " + nazva, font=shryft(17, True), fill=(150, 40, 40))
        for r in ry:
            d.text((POLE + 150, y), r, font=shryft(17), fill=(50, 50, 56))
            y += 24
        y += 8
    kudy = os.path.join(t, "аркуш.jpg")
    ark.save(kudy, quality=92)
    print("аркуш", kudy, flush=True)


def main():
    a = sys.argv[1:]
    if "--список" in a:
        for v, s in gumanoidy():
            print("%-45s ← %s" % (v, s))
        print(len(gumanoidy()), "видів")
        return
    if "--зібрати" in a:
        for v in [x for x in a if not x.startswith("--")] or [v for v, _ in gumanoidy()]:
            zibraty(v)
        return
    vydy = [v for v, _ in gumanoidy()] if "--усі" in a else [x for x in a if not x.startswith("--")]
    zheneruvaty(vydy)


if __name__ == "__main__":
    main()
