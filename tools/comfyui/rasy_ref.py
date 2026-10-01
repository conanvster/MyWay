#!/usr/bin/env python3
"""Референси рас для вікі: 3 раси × 2 статі × 3 варіанти (01.10.2026).

Слово замовника: «на сторінці rasy.html немає гарного вигляду для наших
рас — згенеруй по 3 зображення для кожного полу кожної раси та збережи в
очищену заздалегідь сторінку test.html, я виберу». Правила — ті самі, що
для монстрів (`spec/генерація-референсів-монстрів.md`): FLUX dev Q4 у
ComfyUI, 1024×1024, 28 кроків, guidance 3.5, euler/beta, промт
англійською, обов'язковий рядок ракурсу, «fully clothed» для жінок.

Вигляд рас — лише з `spec/DECIDED.md` (моделі ельфа й орка, 19.09.2026):
орк — зелена шкіра, масивніший, ікла, короткі загострені вуха, 1,90 м;
ельф — бліда шкіра, тонший, довгі загострені вуха, 1,85 м; людина —
середина, 1,75 м. Вдача — з `rasy.html`. Смак замовника — реалістично,
не мультяшно. Одяг — простий стартовий, щоб видно було саме расу.

    python3 -u tools/comfyui/rasy_ref.py            згенерувати й зібрати сторінку
    python3 -u tools/comfyui/rasy_ref.py --сторінка лише перебудувати test.html
    … --дзеркало ~/гра-lineage                  ще й копіювати туди кожен кадр

Перед запуском — ComfyUI на 127.0.0.1:8188 і вільна відеокарта (розділ 4
спеки). Вихід: `wiki/img/test/rasy/<раса>-<стать>-v<N>.png` (лише диск,
`wiki/img/` у .gitignore) і `wiki/test.html`.
"""
import html
import json
import shutil
import sys
import time
import urllib.request
import uuid
from pathlib import Path

KORIN = Path(__file__).resolve().parents[2]
VYKHID = KORIN / "wiki/img/test/rasy"
STORINKA = KORIN / "wiki/test.html"
COMFY_OUT = Path.home() / "ComfyUI/output"
SRV = "http://127.0.0.1:8188"
W = H = 1024
STEPS, GUID = 28, 3.5
MITKA = "rasy1"   # префікс сесії в ~/ComfyUI/output, розділ 4 спеки

KUT = ("viewed from a dynamic three-quarter angle, body turned slightly "
       "away from camera, not a head-on frontal pose, standing fully "
       "upright, the whole figure in frame from head to feet with margin "
       "around it")
ODIAG = ("simple starting adventurer clothing: plain linen shirt, brown "
         "leather vest, wool trousers, leather belt, worn leather boots")
TLO = ("misty coniferous forest clearing in soft daylight, fog between "
       "tall pine trees")
KHVIST = ("Atmosphere: realistic and atmospheric, cinematic lighting, "
          "photorealistic skin and fabric, high detail texture, 8k "
          "resolution, Unreal Engine 5 style rendering.")
NEG = ("cartoon, anime, chibi, stylized, toy, plastic, sitting, seated, "
       "cropped feet, cropped head, front view, symmetric pose, text, "
       "watermark, armor, weapon")
NEG_ZHIN = NEG + ", nude, naked, topless, cleavage, lingerie, nsfw"

RASY = [
    # (ключ, назва, вдача, англійський опис тіла)
    ("людина", "Людина", "середина по всіх статах · 1,75 м",
     "an ordinary human of balanced, average build, about 1.75 m tall, "
     "natural human skin tone, rounded human ears"),
    ("орк", "Орк", "сильний, витривалий, повільний · 1,9 м",
     "an orc: green skin, massive heavy muscular build, broader and "
     "bulkier than a human, about 1.9 m tall, protruding lower tusks, "
     "short pointed ears, strong and enduring but slow"),
    ("ельф", "Ельф", "швидкий, чуйний, крихкий · 1,85 м",
     "an elf: pale skin, slender and thinner than a human, about 1.85 m "
     "tall, long straight white or pale straw-white hair, small sharp "
     "pointed ears, an elongated narrow face, light agile and perceptive "
     "but fragile"),
]
# Слово замовника після першого огляду (01.10.2026): «орки жінки з
# більшими грудями та стегнами і грубим виразом обличчя, ельфи усі мають
# біле або солом'яно-біле довге волосся, з гострими невеликими вухами, і
# видовженим обличчям» — ельфам уписано в опис вище, орчицям — тут.
DODATOK = {
    ("орк", "female"): "a larger bust and wide heavy hips, a coarse, "
                       "rough, stern facial expression",
}
NEG_ELF = ", long ears, huge ears, dark hair, black hair, brown hair, " \
          "round face"
# Відкинуті замовником варіанти: ім'я -> новий seed (старі seed 7102,
# 7111–7113, 7202, 7203, 7211, 7213). Решта лишається як була.
NOVI = {
    "орк-чоловік-v2": 8102,
    "орк-жінка-v1": 8111, "орк-жінка-v2": 8112, "орк-жінка-v3": 8113,
    "ельф-чоловік-v2": 8202, "ельф-чоловік-v3": 8203,
    "ельф-жінка-v1": 8211, "ельф-жінка-v3": 8213,
}
STATI = [("чоловік", "male", "чоловік"), ("жінка", "female", "жінка")]
SIDY = [1, 2, 3]


def promt(rasa, stat):
    _, _, _, tilo = rasa
    eng = stat[1]
    odiag = ODIAG + (", fully clothed, modest attire" if eng == "female"
                     else "")
    return (
        "Dark fantasy RPG character concept art, full-body portrait of a "
        "%s %s hero, %s, %s. Body: %s, %s%s. Clothing: %s. Hands empty, "
        "relaxed natural stance. %s"
        % (eng, rasa[0] == "людина" and "human" or rasa[0] == "орк"
           and "orc" or "elf", KUT, TLO, eng, tilo,
           ", " + DODATOK[(rasa[0], eng)] if (rasa[0], eng) in DODATOK
           else "", odiag, KHVIST))


# Кадри, зроблені не FLUX з нуля, а редагуванням Kontext: ім'я -> підпис.
PIDPYS = {
    "орк-жінка-v%d" % v: "Kontext від v1 (8111), seed %d" % s
    for v, s in ((1, 61), (2, 62), (3, 63))
}


def seed_of(ri, si, v):
    imia = "%s-%s-v%d" % (RASY[ri][0], STATI[si][0], v)
    return NOVI.get(imia, 7000 + ri * 100 + si * 10 + v)


def vybir():
    """[(ім'я файла, промт, seed, негатив)] — 18 штук."""
    out = []
    for ri, rasa in enumerate(RASY):
        for si, stat in enumerate(STATI):
            for v in SIDY:
                neg = NEG_ZHIN if stat[1] == "female" else NEG
                if rasa[0] == "ельф":
                    neg += NEG_ELF
                out.append(("%s-%s-v%d" % (rasa[0], stat[0], v),
                            promt(rasa, stat), seed_of(ri, si, v), neg))
    return out


def wf(prompt, seed, prefix, negative):
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "t5xxl_fp8_e4m3fn.safetensors",
                         "clip_name2": "clip_l.safetensors",
                         "type": "flux"}},
        "3": {"class_type": "CLIPTextEncode",
              "inputs": {"text": prompt, "clip": ["2", 0]}},
        "7": {"class_type": "CLIPTextEncode",
              "inputs": {"text": negative, "clip": ["2", 0]}},
        "4": {"class_type": "FluxGuidance",
              "inputs": {"conditioning": ["3", 0], "guidance": GUID}},
        "5": {"class_type": "EmptySD3LatentImage",
              "inputs": {"width": W, "height": H, "batch_size": 1}},
        "6": {"class_type": "KSampler",
              "inputs": {"model": ["1", 0], "positive": ["4", 0],
                         "negative": ["7", 0], "latent_image": ["5", 0],
                         "seed": seed, "steps": STEPS, "cfg": 1.0,
                         "sampler_name": "euler", "scheduler": "beta",
                         "denoise": 1.0}},
        "8": {"class_type": "VAELoader",
              "inputs": {"vae_name": "ae.safetensors"}},
        "9": {"class_type": "VAEDecode",
              "inputs": {"samples": ["6", 0], "vae": ["8", 0]}},
        "10": {"class_type": "SaveImage",
               "inputs": {"images": ["9", 0], "filename_prefix": prefix}},
    }


def post(path, obj):
    r = urllib.request.Request(SRV + path, data=json.dumps(obj).encode(),
                               headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r))


def generuvaty():
    VYKHID.mkdir(parents=True, exist_ok=True)
    cid = str(uuid.uuid4())
    jobs = []
    for imia, prompt, seed, neg in vybir():
        if (VYKHID / (imia + ".png")).exists():
            print("є", imia, flush=True)
            continue
        prefix = "%s_%s" % (MITKA, imia)
        pid = post("/prompt", {"prompt": wf(prompt, seed, prefix, neg),
                               "client_id": cid})["prompt_id"]
        jobs.append((imia, prefix, pid))
    print("у черзі %d" % len(jobs), flush=True)
    for imia, prefix, pid in jobs:
        while True:
            h = json.load(urllib.request.urlopen(SRV + "/history/" + pid))
            if pid in h:
                st = h[pid].get("status", {})
                if st.get("status_str") == "error":
                    print("‼ збій", imia, st.get("messages"), flush=True)
                    break
                imgs = [i["filename"] for o in h[pid]["outputs"].values()
                        for i in o.get("images", [])]
                # Найбільший суфікс — свіжий (розділ 4 спеки).
                shutil.copy(COMFY_OUT / sorted(imgs)[-1],
                            VYKHID / (imia + ".png"))
                print("готово", imia, flush=True)
                zibraty()
                dzerkalo(imia)
                break
            time.sleep(5)


def dzerkalo(imia):
    """`--дзеркало <корінь>`: копія кадру й сторінки ще й туди — у
    робочу копію, яку замовник відкриває в браузері."""
    if "--дзеркало" not in sys.argv:
        return
    kudy = Path(sys.argv[sys.argv.index("--дзеркало") + 1])
    (kudy / "wiki/img/test/rasy").mkdir(parents=True, exist_ok=True)
    shutil.copy(VYKHID / (imia + ".png"), kudy / "wiki/img/test/rasy")
    shutil.copy(STORINKA, kudy / "wiki/test.html")


def zibraty():
    """Очищена test.html: лише раси, сітка по 3 на стать."""
    stari = STORINKA.read_text(encoding="utf-8")
    holova = stari[:stari.index("<main>")]
    khvist = stari[stari.index("</main>"):]
    tilo = ['<main>', '<h1>Тест генерації</h1>',
            '<p class="lead">Раси: по три варіанти на кожну стать кожної '
            'раси — вибери, які йдуть на сторінку '
            '<a href="rasy.html">Раси та професії</a>. Нічого звідси не '
            'лінкується з основних сторінок.</p>',
            '<p class="note">FLUX dev Q4 у ComfyUI, 1024×1024, 28 кроків, '
            'guidance 3.5 — правила з '
            '<code>spec/генерація-референсів-монстрів.md</code>. Вигляд '
            'рас — із <code>spec/DECIDED.md</code>; одяг простий '
            'стартовий, тло — туманний хвойний ліс.</p>']
    for rasa in RASY:
        tilo.append('<h2>%s</h2>' % rasa[1])
        tilo.append('<p class="note">%s</p>' % html.escape(rasa[2]))
        for si, stat in enumerate(STATI):
            tilo.append('<h3>%s, %s</h3>' % (rasa[1], stat[2]))
            tilo.append('<div class="compare">')
            for v in SIDY:
                imia = "%s-%s-v%d" % (rasa[0], stat[0], v)
                seed = seed_of(RASY.index(rasa), si, v)
                if (VYKHID / (imia + ".png")).exists():
                    kadr = '<img src="img/test/rasy/%s.png" alt="%s, %s, ' \
                           'варіант %d">' % (imia, rasa[1], stat[2], v)
                else:
                    kadr = '<div style="aspect-ratio:1/1;background:#000;' \
                           'border-radius:3px;display:grid;place-items:' \
                           'center;color:#888">ще генерується</div>'
                pidpys = PIDPYS.get(imia, "seed %d" % seed)
                tilo.append('<figure>%s<figcaption><b>v%d</b>%s'
                            '</figcaption></figure>' % (kadr, v, pidpys))
            tilo.append('</div>')
    tilo.append('<p class="note">Тестова сторінка, не для гравців.</p>')
    STORINKA.write_text(holova + "\n".join(tilo) + "\n" + khvist,
                        encoding="utf-8")


if __name__ == "__main__":
    if "--сторінка" in sys.argv:
        zibraty()
    else:
        zibraty()
        generuvaty()
        print("сторінка: %s" % STORINKA, flush=True)
