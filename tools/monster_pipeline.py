#!/usr/bin/env python3
"""Оркестратор шляху А: один звір або пакет — від референсу до вікі,
зі станом кожного виду і аркушами-зведеннями замість десятків окремих
картинок. Над `tools/comfyui/monster3d.py` і `tools/blender/scan_build.py`.

    python3 tools/monster_pipeline.py черга                 # що де стоїть
    python3 tools/monster_pipeline.py стан <вид>
    python3 tools/monster_pipeline.py gpu                   # звільнити LM Studio, підняти ComfyUI
    python3 tools/monster_pipeline.py поза <вид>... [--сіди 11 22 33 44]
    python3 tools/monster_pipeline.py вибрати <вид> <сід|реф>
    python3 tools/monster_pipeline.py сітка <вид>...
    python3 tools/monster_pipeline.py огляд <вид>           # сира сітка з 4 боків, одним аркушем
    python3 tools/monster_pipeline.py збірка <вид>... [--чернетка]
    python3 tools/monster_pipeline.py фініш <вид>...        # mobs.json, Godot, хутро, вікі
    python3 tools/monster_pipeline.py шаблон <вид>...       # швидкий шлях: готова модель `template` + кольори референсу

Що це виправляє (звіт `art/monsters/звіт-24-09-2026-E-ранг.md`):
- «загадкова» смерть 4-го сіда пози: це `timeout 480` на 4 сіди по ~2 хв;
  тут кожен сід — окремий запит, без зовнішнього таймауту, вивід без
  буфера;
- пакетна черга: `поза вовк-сіромаха вовк-мутант ведмідь` вантажить
  Kontext у відеопам'ять ОДИН раз (перемикання Kontext↔Pixal3D — 1-3 хв
  щоразу); так само `сітка` для кількох видів поспіль;
- 2×2 аркуш варіантів пози, аркуш сирої сітки, аркуш збірки — одна
  картинка на рішення замість чотирьох-восьми;
- `фініш` робить усе після збірки за один виклик (імпорт Godot, проба,
  хутро з профілю, 3 знімки `fur_look`, вікі-рендер із автосвітлом,
  перегенерація вікі) — раніше 8-10 окремих команд на звіра.
Стан виду: `art/monsters/<тека>-3d/стан.json`.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
sys.path.insert(0, os.path.join(ROOT, "tools", "comfyui"))
import scan_profiles as P  # noqa: E402

BLENDER = shutil.which("blender") or "blender"
GODOT = shutil.which("godot") or "godot"


def say(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------- стан

def folder(name):
    return os.path.join(ROOT, "art", "monsters", P.config(name)["source"] + "-3d")


def load_state(name):
    p = os.path.join(folder(name), "стан.json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}


def save_state(name, **kv):
    os.makedirs(folder(name), exist_ok=True)
    st = load_state(name)
    st.update(kv)
    st["оновлено"] = time.strftime("%Y-%m-%d %H:%M")
    json.dump(st, open(os.path.join(folder(name), "стан.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    return st


def dump_mobs(mobs, path):
    """Той самий формат, що в репозиторії: indent 2, а `хутро` — в один
    рядок (json.dump розгортав би всі 49 таких рядків — зайвий diff)."""
    text = json.dumps(mobs, ensure_ascii=False, indent=2)
    text = re.sub(r'"хутро": \{[^{}]*?\}',
                  lambda m: '"хутро": ' + json.dumps(json.loads(m.group(0)[len('"хутро": '):]),
                                                     ensure_ascii=False), text, flags=re.S)
    open(path, "w", encoding="utf-8").write(text + "\n")


def mob(name):
    mobs = json.load(open(os.path.join(ROOT, "game", "data", "mobs.json"), encoding="utf-8"))
    for k, v in mobs.items():
        if isinstance(v, dict) and v.get("назва") == name:
            return k, v
    return None, None


def stem(name):
    _, v = mob(name)
    m = (v or {}).get("вигляд", {}).get("модель", "")
    return os.path.splitext(os.path.basename(m))[0] if m.endswith(".glb") else name


def reference(name):
    return os.path.join(ROOT, "wiki", "img", "monstry", name + ".png")


def status(name):
    """Етап з файлів на диску, а не з пам'яті: що вже є — те й зроблено."""
    f, cfg = folder(name), P.config(name)
    st = load_state(name)
    poses = sorted(glob.glob(os.path.join(f, "поза-s*.png")))
    s = {
        "вид": name, "профіль": cfg["profile"], "тип": cfg["body"],
        "референс": os.path.exists(reference(name)),
        "пози": [os.path.basename(p)[5:-4] for p in poses],
        "обрано": st.get("обрано"),
        "сітка": os.path.exists(os.path.join(f, "pixal3d-01.glb")),
        "чернетка": os.path.exists(os.path.join(f, "чернетка", "звіт.json")),
        "модель": os.path.exists(os.path.join(ROOT, "game", "models", "own", stem(name) + ".glb"))
        and os.path.exists(os.path.join(f, "звіт.json")),
        "вікі": os.path.exists(os.path.join(ROOT, "wiki", "img", "monstry", name + "-модель.png")),
    }
    if s["вікі"]:
        s["етап"] = "готово"
    elif s["модель"]:
        s["етап"] = "фініш"
    elif s["сітка"]:
        s["етап"] = "збірка"
    elif s["обрано"]:
        s["етап"] = "сітка"
    elif s["пози"]:
        s["етап"] = "вибрати позу"
    elif cfg["body"] == "legacy":
        s["етап"] = "окремий білдер (%s)" % cfg.get("script")
    else:
        s["етап"] = "поза або сітка з референсу"
    return s


# ---------------------------------------------------------------- аркуші

def sheet(paths, out, cols=4, w=384, labels=True):
    from PIL import Image, ImageDraw
    paths = [p for p in paths if os.path.exists(p)]
    if not paths:
        return None
    rows = (len(paths) + cols - 1) // cols
    img = Image.new("RGB", (cols * w, rows * (w + 20)), (32, 32, 32))
    for i, p in enumerate(paths):
        x, y = (i % cols) * w, (i // cols) * (w + 20)
        img.paste(Image.open(p).convert("RGB").resize((w, w)), (x, y + 20))
        if labels:
            ImageDraw.Draw(img).text((x + 5, y + 4), os.path.basename(p)[:-4], fill=(255, 255, 255))
    img.save(out)
    return out


# ---------------------------------------------------------------- GPU

def gpu():
    """Звільнити відеокарту від LM Studio (слово замовника 23.09: тримати
    не треба), підняти ComfyUI, якщо не піднятий."""
    lms = os.path.expanduser("~/.lmstudio/bin/lms")
    if os.path.exists(lms):
        subprocess.run([lms, "unload", "--all"], capture_output=True)
    import urllib.request
    try:
        urllib.request.urlopen("http://127.0.0.1:8188/", timeout=3)
        say("ComfyUI вже працює")
        return
    except Exception:
        pass
    comfy = os.path.expanduser("~/ComfyUI")
    log = open(os.path.join(ROOT, "art", "monsters", "comfyui.log"), "a")
    subprocess.Popen([os.path.join(comfy, "venv", "bin", "python"), "main.py", "--listen",
                      "127.0.0.1", "--port", "8188"], cwd=comfy, stdout=log, stderr=log,
                     start_new_session=True)
    for _ in range(90):
        time.sleep(2)
        try:
            urllib.request.urlopen("http://127.0.0.1:8188/", timeout=3)
            say("ComfyUI піднято")
            return
        except Exception:
            pass
    sys.exit("‼ ComfyUI не піднявся за 3 хв — див. art/monsters/comfyui.log")


def pose(names, seeds):
    """Усі види пакетом: Kontext вантажиться раз. Кожен сід — окремий
    запит; після кожного виду — аркуш 2×2 `поза-варіанти.png`."""
    import monster3d as M
    gpu()
    for name in names:
        cfg = P.config(name)
        prompt = cfg.get("pose")
        say("[поза] %s (%s) сіди %s" % (name, cfg["who"], seeds))
        # monster3d.pose пише в art/monsters/<name>-3d — наша тека за source
        for s in seeds:
            t = time.time()
            M.pose(reference(name), cfg["source"], [s], cfg["who"], prompt)
            say("[поза] %s s%d — %.0f с" % (name, s, time.time() - t))
        out = sheet([os.path.join(folder(name), "поза-s%d.png" % s) for s in seeds],
                    os.path.join(folder(name), "поза-варіанти.png"), cols=2, w=512)
        save_state(name, пози=seeds)
        say("[поза] аркуш: %s" % os.path.relpath(out, ROOT))


def choose(name, which):
    src = reference(name) if which in ("реф", "ref") else os.path.join(folder(name), "поза-s%s.png" % which)
    if not os.path.exists(src):
        sys.exit("‼ немає %s" % src)
    save_state(name, обрано=which, джерело_сітки=os.path.relpath(src, ROOT))
    say("[вибір] %s → %s" % (name, os.path.relpath(src, ROOT)))


def mesh(names):
    """Pixal3D пакетом. Попередня pixal3d-01.glb не затирається — стає
    pixal3d-NN (розділ А4: «одразу перейменувати»)."""
    import monster3d as M
    gpu()
    for name in names:
        st = load_state(name)
        src = os.path.join(ROOT, st["джерело_сітки"]) if st.get("джерело_сітки") else reference(name)
        f = folder(name)
        cur = os.path.join(f, "pixal3d-01.glb")
        if os.path.exists(cur):
            n = 2
            while os.path.exists(os.path.join(f, "pixal3d-%02d.glb" % n)):
                n += 1
            os.rename(cur, os.path.join(f, "pixal3d-%02d.glb" % n))
            say("[сітка] попередня → pixal3d-%02d.glb" % n)
        t = time.time()
        M.mesh(src, P.config(name)["source"], 150000)
        os.rename(os.path.join(f, "pixal3d.glb"), cur)
        save_state(name, сітка_з=os.path.relpath(src, ROOT))
        say("[сітка] %s — %.0f с → %s" % (name, time.time() - t, os.path.relpath(cur, ROOT)))
    M.free()


def inspect(name):
    f = folder(name)
    out = os.path.join(f, "огляд")
    subprocess.run([BLENDER, "-b", "--python", os.path.join(ROOT, "tools", "blender", "scan_inspect.py"),
                    "--", os.path.join(f, "pixal3d-01.glb"), out], capture_output=True)
    s = sheet(sorted(glob.glob(os.path.join(out, "*.png"))), os.path.join(f, "огляд-аркуш.png"), cols=4, w=384)
    say("[огляд] %s" % os.path.relpath(s, ROOT))


def build(names, draft):
    for name in names:
        t = time.time()
        args = [BLENDER, "-b", "--python", os.path.join(ROOT, "tools", "blender", "scan_build.py"), "--", name]
        if draft:
            args.append("--чернетка")
        r = subprocess.run(args, capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if line.startswith("[скан]") or "Error" in line or "‼" in line:
                say(line)
        if r.returncode or "Traceback" in r.stdout + r.stderr:
            say((r.stdout + r.stderr)[-1500:])
            sys.exit("‼ збірка %s впала" % name)
        work = os.path.join(folder(name), "чернетка") if draft else folder(name)
        s = sheet(sorted(glob.glob(os.path.join(work, "аркуш", "*.png"))), os.path.join(work, "аркуш.png"))
        save_state(name, збірка="чернетка" if draft else "фінал")
        say("[збірка] %s — %.0f с, аркуш %s" % (name, time.time() - t, os.path.relpath(s, ROOT)))


def reskin(names):
    """Замість пози/сітки/збірки: сітка, скелет і рухи — з готового виду
    `template`, кольори — з референсу (маска birefnet). Збій одного виду
    не зупиняє решту."""
    import monster3d as M
    gpu()
    for name in names:
        t = time.time()
        tpl = P.config(name).get("template")
        if not tpl:
            say("‼ %s — у профілі нема `template`, пропускаю" % name)
            continue
        os.makedirs(folder(name), exist_ok=True)
        mask = os.path.join(folder(name), "маска-референсу.png")
        M.cutout(reference(name), mask)
        r = subprocess.run([BLENDER, "-b", "--python", os.path.join(ROOT, "tools", "blender", "scan_reskin.py"),
                            "--", name, tpl, reference(name), mask], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if line.startswith("[скан]") or "‼" in line:
                say(line)
        if r.returncode or "Traceback" in r.stdout + r.stderr:
            say((r.stdout + r.stderr)[-1500:])
            say("‼ шаблон %s впав — далі без нього" % name)
            continue
        save_state(name, збірка="шаблон", шаблон=tpl)
        say("[шаблон] %s ← %s — %.0f с" % (name, tpl, time.time() - t))


def finish(names):
    """Усе після збірки одним викликом (розділи А7-А9, 4а.5, 8). Пакетом:
    mobs.json, імпорт Godot, проба й вікі — раз на всю пачку; знімки хутра
    й вікі-рендер — на кожен вид."""
    mobs_p = os.path.join(ROOT, "game", "data", "mobs.json")
    best_p = os.path.join(ROOT, "spec", "бестіарій.json")
    mobs = json.load(open(mobs_p, encoding="utf-8"))
    best = json.load(open(best_p, encoding="utf-8"))
    dirty = False
    for name in names:
        cfg = P.config(name)
        res = "res://models/own/%s.glb" % stem(name)
        # mobs.json: модель (гуманоїди — з шляху Б на плаский .glb) і хутро
        k, _ = mob(name)
        look = mobs[k].setdefault("вигляд", {})
        changed = []
        if look.get("модель") != res:
            changed.append("модель %s → %s" % (look.get("модель"), res))
            look["модель"] = res
        if cfg.get("fur") and not look.get("хутро"):
            look["хутро"] = cfg["fur"]
            changed.append("хутро %s" % cfg["fur"])
        if changed:
            dirty = True
            for m in best:
                if m.get("назва") == name:
                    m["модель"] = res
            say("[фініш] %s — mobs.json: %s" % (name, "; ".join(changed)))
    if dirty:
        dump_mobs(mobs, mobs_p)
        open(best_p, "w", encoding="utf-8").write(json.dumps(best, ensure_ascii=False, indent=1) + "\n")
    subprocess.run([GODOT, "--headless", "--path", "game", "--import"], cwd=ROOT, capture_output=True)
    probe = subprocess.run([GODOT, "--headless", "--path", "game", "--script", "res://probes/own_models.gd"],
                           cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
    for name in names:
        head = re.compile(r"^\s+[✓✗] %s\.glb " % re.escape(stem(name)))
        for i, line in enumerate(probe):
            if head.match(line):
                say("[проба] " + line.strip())
                if i + 1 < len(probe):
                    say("[проба] " + probe[i + 1].strip())
    for name in names:
        st_name = stem(name)
        shots = os.path.join(folder(name), "хутро")
        subprocess.run([GODOT, "--path", "game", "res://scenes/fur_look.tscn", "--", "--знімок", shots,
                        "--вид", name, "--поворот", "180"], cwd=ROOT, capture_output=True, timeout=120)
        blend = os.path.join(ROOT, "art", "monsters", st_name + ".blend")
        wiki = os.path.join(ROOT, "wiki", "img", "monstry", name + "-модель.png")
        subprocess.run([BLENDER, "-b", "--python", os.path.join(ROOT, "tools", "blender", "scan_wiki_render.py"),
                        "--", blend, wiki, "--авто"], capture_output=True)
        s = sheet([shots + "-поруч.png", shots + "-зблизька.png", shots + "-вікі.png", wiki],
                  os.path.join(folder(name), "фініш-аркуш.png"), cols=4, w=384)
        save_state(name, фініш=True)
        say("[фініш] %s — аркуш %s" % (name, os.path.relpath(s, ROOT)))
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "wiki.py")], cwd=ROOT, capture_output=True)


def queue():
    rows = []
    for name in P.SPECIES:
        s = status(name)
        rows.append((s["етап"] != "готово", name, s["профіль"], s["етап"]))
    for _, name, prof, st in sorted(rows):
        say("%-26s %-18s %s" % (name, prof, st))


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    cmd, rest = a[0], a[1:]
    names = [x for x in rest if not x.startswith("--")]
    if cmd == "черга":
        queue()
    elif cmd == "стан":
        say(json.dumps(status(names[0]), ensure_ascii=False, indent=1))
    elif cmd == "gpu":
        gpu()
    elif cmd == "поза":
        seeds = [int(x) for x in rest[rest.index("--сіди") + 1:]] if "--сіди" in rest else [11, 22, 33, 44]
        if "--сіди" in rest:
            names = [x for x in rest[:rest.index("--сіди")] if not x.startswith("--")]
        pose(names, seeds)
    elif cmd == "вибрати":
        choose(names[0], names[1])
    elif cmd == "сітка":
        mesh(names)
    elif cmd == "огляд":
        inspect(names[0])
    elif cmd == "збірка":
        build(names, "--чернетка" in rest)
    elif cmd == "фініш":
        finish(names)
    elif cmd == "шаблон":
        reskin(names)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
