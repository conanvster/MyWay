"""Вікі гри — статичні сторінки з тих самих даних, що їх читає сервер.

Слово замовника 21.09.2026: «невеличка wiki з хедером, де будуть
розділи: карта світу, раси та професії, монстри, зброя та захист, ігрові
ітеми та матеріали». Монстри — таблицею за грейдами (рівень, скіли,
дроп, параметри, де спавняться), а вигляд — окремою сторінкою в два
стовпці: фото й опис. Фото немає — клітинка лишається порожньою.

    python3 tools/wiki.py            зібрати wiki/ заново

Руками wiki/ не правити: усе береться з `game/data/*.json` і
`spec/бестіарій.json`, тож після зміни даних досить перезібрати.
Картинку монстра покласти в `wiki/img/monstry/<назва>.jpg` (або .png,
.webp) — наступна збірка її підхопить; сама тека при збірці не
стирається.
"""
import html
import json
import math
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "game", "data")
OUT = os.path.join(ROOT, "wiki")
IMG = os.path.join(OUT, "img")
ФОТО_МОНСТРІВ = os.path.join(IMG, "monstry")

sys.path.insert(0, os.path.join(ROOT, "tools"))
import bestiary      # noqa: E402 — де стоїть вид, з map2.json
import rozselennia   # noqa: E402 — зони й опорні міста

ГРЕЙДИ = ["E", "D", "C", "B", "A", "S", "SS"]
СТАТИ_EN = {"strength": "сила", "agility": "спритність",
            "stamina": "витривалість", "intellect": "інтелект",
            "sense": "чуття"}
ЦІЛЬ = {"жива": "одна ціль", "усі-поруч": "усі поруч",
        "свої-поруч": "свої поруч", "себе": "на себе"}


def читати(ім_я):
    with open(os.path.join(DATA, ім_я), encoding="utf-8") as f:
        return json.load(f)


def e(x):
    return html.escape(str(x), quote=True)


def число(x):
    """1234567 → «1 234 567», дроби з комою — як у решті документів."""
    if isinstance(x, float) and not x.is_integer():
        return ("%.2f" % x).rstrip("0").rstrip(".").replace(".", ",")
    return "{:,}".format(int(x)).replace(",", " ")


def відсоток(шанс):
    p = шанс * 100
    return ("%d%%" % round(p)) if p >= 1 else ("%s%%" % число(round(p, 1)))


# ─────────────────────────── дані разом ───────────────────────────

class Світ:
    def __init__(self):
        self.mobs = {k: v for k, v in читати("mobs.json").items()
                     if isinstance(v, dict)}
        items = читати("items.json")
        self.до_рівня = items["грейди"]["до рівня"]
        self.бази = items["бази"]
        self.афікси = items["афікси"]
        self.торгівля = items["торгівля"]
        self.скіли = {k: v for k, v in читати("skills.json").items()
                      if isinstance(v, dict)}
        prof = читати("professions.json")
        self.етапи = prof["етапи"]
        self.професії = prof["професії"]
        self.мапа = читати("map2.json")
        self.рівні = читати("levels.json")
        self.телепорт = читати("teleports.json")
        self.коваль = читати("smith.json")
        self.каталог = bestiary.читати()
        self.за_назвою = {x["назва"]: x for x in self.каталог}
        self.місця, self.сторожі = bestiary.де_спавниться()
        self.агресія = {}
        for зона in self.мапа.get("зони появи", []):
            назва = self.mobs.get(str(зона["вид"]), {}).get("назва")
            if назва:
                self.агресія.setdefault(назва, set()).add(
                    bool(зона.get("агресивний")))
        # Звідки падає кожна річ: назва → [(монстр, рівень, шанс)].
        self.джерела = {}
        for вид, m in self.mobs.items():
            for d in m.get("дроп", []):
                self.джерела.setdefault(d["що"], []).append(
                    (m["назва"], m.get("рівень", 1), d["шанс"]))
        # Руна → скіл, якого вона вчить.
        self.руна_скіла = {}
        for ключ, s in self.скіли.items():
            руна = s.get("вивчення", {}).get("руна")
            if руна:
                self.руна_скіла[руна] = s

    def грейд(self, рівень):
        for г in ГРЕЙДИ:
            if рівень <= self.до_рівня[г]:
                return г
        return "SS"

    def скіл(self, ключ):
        if ключ in self.скіли:
            return self.скіли[ключ]
        for s in self.скіли.values():
            if s.get("назва") == ключ or s.get("назва") == ключ.replace("-", " "):
                return s
        return None


# ─────────────────────────── оформлення ───────────────────────────

РОЗДІЛИ = [
    ("index.html", "Карта світу"),
    ("rasy.html", "Раси та професії"),
    ("monstry.html", "Монстри"),
    ("zbroia.html", "Зброя та захист"),
    ("rechi.html", "Ітеми та матеріали"),
    ("test.html", "Тест генерації"),
]

CSS = r"""
:root{
  --ground:#e9ece6; --paper:#f6f7f3; --ink:#1b211e; --muted:#5a6660;
  --rule:#c9d0c8; --accent:#2c6a58; --accent-ink:#f3f7f4; --chip:#dfe5de;
  --g-E:#7b817d; --g-D:#4f7d3c; --g-C:#2f6f96; --g-B:#6b4f9a; --g-A:#a3651c;
  --g-S:#a33a2c; --g-SS:#8a6a12;
  --display:"Alegreya SC", "Alegreya", Georgia, serif;
  --body:"IBM Plex Sans", "Segoe UI", system-ui, sans-serif;
  --mono:"IBM Plex Mono", ui-monospace, Menlo, monospace;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --ground:#111513; --paper:#181d1a; --ink:#e1e6e1; --muted:#95a19a;
    --rule:#2c3530; --accent:#7cbca4; --accent-ink:#0f1512; --chip:#222a26;
    --g-E:#9aa19c; --g-D:#86b872; --g-C:#6fb0d8; --g-B:#a88bd6; --g-A:#d9a25a;
    --g-S:#e07a69; --g-SS:#d8b851;
  }
}
:root[data-theme="dark"]{
  --ground:#111513; --paper:#181d1a; --ink:#e1e6e1; --muted:#95a19a;
  --rule:#2c3530; --accent:#7cbca4; --accent-ink:#0f1512; --chip:#222a26;
  --g-E:#9aa19c; --g-D:#86b872; --g-C:#6fb0d8; --g-B:#a88bd6; --g-A:#d9a25a;
  --g-S:#e07a69; --g-SS:#d8b851;
}
*{box-sizing:border-box}
html{scroll-padding-top:7.5rem}
body{margin:0;background:var(--ground);color:var(--ink);
  font:15px/1.55 var(--body)}
a{color:var(--accent)}
a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.top{position:sticky;top:env(safe-area-inset-top,0px);z-index:5;
  background:var(--paper);border-bottom:1px solid var(--rule)}
.top .in{max-width:1280px;margin:0 auto;padding:.6rem 16px;display:flex;
  flex-wrap:wrap;align-items:baseline;gap:.4rem 1.6rem}
.brand{font:600 1.45rem/1 var(--display);letter-spacing:.04em;
  color:var(--ink);text-decoration:none}
.brand small{font:500 .7rem var(--body);letter-spacing:.12em;
  text-transform:uppercase;color:var(--muted);margin-left:.5rem}
nav.main{display:flex;flex-wrap:wrap;gap:.2rem .3rem}
nav.main a{padding:.3rem .65rem;border-radius:4px;text-decoration:none;
  color:var(--muted);font-weight:500}
nav.main a:hover{color:var(--ink);background:var(--chip)}
nav.main a[aria-current]{color:var(--accent-ink);background:var(--accent)}
main{max-width:1280px;margin:0 auto;padding-inline:16px;padding-block:1.6rem 4rem}
h1{font:600 2.1rem/1.1 var(--display);margin:.2rem 0 .4rem;text-wrap:balance}
h2{font:600 1.5rem/1.2 var(--display);margin:2.4rem 0 .6rem;text-wrap:balance;
  display:flex;align-items:baseline;gap:.6rem;flex-wrap:wrap}
h3{font:600 1.1rem/1.3 var(--body);margin:1.6rem 0 .4rem}
.lead{color:var(--muted);max-width:68ch;margin:0 0 1rem}
p{max-width:72ch}
.note{color:var(--muted);font-size:.85rem;max-width:72ch}
.sub{display:flex;flex-wrap:wrap;gap:.35rem;margin:1rem 0 .4rem;
  position:sticky;top:calc(env(safe-area-inset-top,0px) + 3.2rem);z-index:4;
  background:var(--ground);padding-block:.45rem}
.sub a,.chip{display:inline-block;padding:.15rem .55rem;border-radius:3px;
  background:var(--chip);color:var(--ink);text-decoration:none;
  font:500 .85rem var(--body)}
.sub a:hover{background:var(--rule)}
.g{display:inline-block;min-width:2.1em;text-align:center;padding:.05rem .4rem;
  border-radius:3px;font:700 .78rem/1.5 var(--mono);color:var(--paper);
  background:var(--g-E)}
.g-E{background:var(--g-E)}.g-D{background:var(--g-D)}.g-C{background:var(--g-C)}
.g-B{background:var(--g-B)}.g-A{background:var(--g-A)}.g-S{background:var(--g-S)}
.g-SS{background:var(--g-SS)}
.count{font:400 .9rem var(--body);color:var(--muted)}
.wrap{overflow-x:auto;border:1px solid var(--rule);border-radius:4px;
  background:var(--paper)}
table{border-collapse:collapse;width:100%;font-size:.86rem}
th,td{text-align:left;vertical-align:top;padding:.5rem .6rem;
  border-bottom:1px solid var(--rule)}
th{font:600 .72rem var(--body);letter-spacing:.07em;text-transform:uppercase;
  color:var(--muted);background:var(--paper);position:sticky;top:0}
tr:last-child td{border-bottom:0}
td.num{font-variant-numeric:tabular-nums;white-space:nowrap}
.nm{font-weight:600;white-space:nowrap}
.nm a{color:var(--ink);text-decoration-color:var(--rule)}
.nm a:hover{color:var(--accent)}
.kv{display:grid;grid-template-columns:auto auto;gap:0 .7rem;
  font-variant-numeric:tabular-nums;white-space:nowrap}
.kv span:nth-child(odd){color:var(--muted)}
ul.d{margin:0;padding:0;list-style:none}
ul.d li{white-space:nowrap}
ul.d li .p{font:500 .8rem var(--mono);color:var(--muted)}
.muted{color:var(--muted)}
.skill b{font-weight:600}
.skill .how{display:block;color:var(--muted);font-size:.8rem}
.cards{display:grid;gap:1px;background:var(--rule);border:1px solid var(--rule);
  border-radius:4px;overflow:hidden}
.card{display:grid;grid-template-columns:minmax(0,260px) minmax(0,1fr);
  gap:1.2rem;background:var(--paper);padding:1rem}
.photo{aspect-ratio:1/1;max-width:100%;border:1px dashed var(--rule);
  border-radius:3px;background:var(--ground);display:grid;place-items:center;
  overflow:hidden}
.photo img{width:100%;height:100%;object-fit:cover}
.photos{display:grid;gap:.5rem;align-content:start}
.photo-3d{margin:0;padding:0;background:transparent;border:0}
.photo-3d img{height:100%}
.photo-3d figcaption{font-size:.75rem;color:var(--muted);margin-top:.25rem;
  text-align:center}
.card h3{margin:0 0 .15rem;font:600 1.25rem/1.2 var(--display)}
.card .meta{color:var(--muted);font-size:.85rem;margin-bottom:.6rem}
.card dl{margin:0;display:grid;gap:.45rem}
.card dt{font:600 .72rem var(--body);letter-spacing:.07em;
  text-transform:uppercase;color:var(--muted)}
.card dd{margin:0;max-width:75ch}
details summary{cursor:pointer;color:var(--accent);font-size:.85rem}
.figs{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr));
  gap:1rem}
figure{margin:0;background:var(--paper);border:1px solid var(--rule);
  border-radius:4px;padding:.6rem}
figure img{display:block;width:100%;height:auto}
figcaption{font-size:.8rem;color:var(--muted);margin-top:.4rem}
.stats{display:flex;flex-wrap:wrap;gap:.4rem 1.6rem;margin:.4rem 0 1rem}
.stats div{display:flex;flex-direction:column}
.stats b{font:600 1.5rem/1.1 var(--display)}
.stats span{font-size:.78rem;color:var(--muted)}
.icon{width:28px;height:28px;vertical-align:middle;margin-right:.4rem;
  border-radius:3px;background:var(--chip)}
.ref3d{display:inline-block;margin-left:.4rem;padding:.05rem .4rem;
  border:1px solid var(--accent);border-radius:3px;background:transparent;
  color:var(--accent);font:700 .68rem var(--mono);letter-spacing:.04em;
  cursor:pointer;vertical-align:middle}
.ref3d:hover{background:var(--accent);color:var(--accent-ink)}
dialog.ref3d-modal{max-width:min(90vw,900px);max-height:85vh;overflow:auto;
  border:1px solid var(--rule);border-radius:6px;background:var(--paper);
  color:var(--ink);padding:1rem}
dialog.ref3d-modal::backdrop{background:rgba(0,0,0,.6)}
dialog.ref3d-modal h3{margin:0 0 .8rem;font:600 1.1rem var(--display)}
dialog.ref3d-modal .close{float:right;border:0;background:transparent;
  color:var(--muted);font-size:1.3rem;line-height:1;cursor:pointer}
dialog.ref3d-modal .close:hover{color:var(--ink)}
.ref3d-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));
  gap:.8rem;clear:both}
.ref3d-grid figure{margin:0;padding:0;background:transparent;border:0}
.ref3d-grid img{width:100%;height:auto;border-radius:4px;background:#000}
.ref3d-grid figcaption{font-size:.75rem;color:var(--muted);margin-top:.3rem;
  text-align:center}
footer{max-width:1280px;margin:0 auto;padding:0 16px 2rem;color:var(--muted);
  font-size:.8rem}
.download{background:var(--paper);border:1px solid var(--rule);
  border-left:4px solid var(--accent);border-radius:8px;padding:.4rem 1.2rem 1rem;
  margin:1.2rem 0 1.6rem}
.download h2{margin-top:.6rem}
.dls{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));
  gap:.7rem;margin:.8rem 0}
.dl{display:flex;flex-direction:column;gap:.15rem;padding:.75rem 1rem;
  border:1px solid var(--rule);border-radius:6px;text-decoration:none;
  color:var(--ink);background:var(--ground)}
.dl b{font:600 1.15rem var(--display);letter-spacing:.03em}
.dl span{font-size:.82rem;color:var(--muted)}
.dl .sz{font-family:var(--mono)}
.dl:hover{border-color:var(--accent)}
.dl.mine{background:var(--accent);border-color:var(--accent)}
.dl.mine b,.dl.mine span{color:var(--accent-ink)}
.dl-meta{font-size:.85rem;color:var(--muted)}
.steps{padding-left:1.3rem}
.steps li{margin:.2rem 0}
@media (max-width:640px){
  .card{grid-template-columns:1fr}
  .photo,.photos{max-width:260px}
  h1{font-size:1.7rem}
  html{scroll-padding-top:10rem}
  .sub{top:calc(env(safe-area-inset-top,0px) + 5.4rem)}
}
@media (prefers-reduced-motion:reduce){*{scroll-behavior:auto!important}}
"""


def сторінка(файл, назва, тіло, опис=""):
    меню = "".join(
        '<a href="%s"%s>%s</a>' % (f, ' aria-current="page"'
                                   if f == файл or (файл == "monstry-vyglyad.html"
                                                    and f == "monstry.html")
                                   else "", e(n))
        for f, n in РОЗДІЛИ)
    текст = """<!doctype html>
<html lang="uk"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>%s · MyWay</title>
<meta name="description" content="%s">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Alegreya+SC:wght@500;700&family=IBM+Plex+Mono:wght@500;700&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<link rel="stylesheet" href="style.css">
</head><body>
<header class="top"><div class="in">
<a class="brand" href="index.html">MyWay<small>вікі</small></a>
<nav class="main" aria-label="Розділи">%s</nav>
</div></header>
<main>
%s
</main>
<footer>Зібрано з даних гри командою <code>python3 tools/wiki.py</code>.
Руками не правити — перезібрати.</footer>
</body></html>
""" % (e(назва), e(опис), меню, тіло)
    with open(os.path.join(OUT, файл), "w", encoding="utf-8") as f:
        f.write(текст)
    print("  %-22s %6.0f КБ" % (файл, len(текст.encode()) / 1024))


def бейдж(г):
    return '<span class="g g-%s">%s</span>' % (г, г)


def підменю(грейди, лічба):
    return '<nav class="sub" aria-label="Грейди">%s</nav>' % "".join(
        '<a href="#%s">%s <span class="muted">%d</span></a>'
        % (г, бейдж(г), лічба.get(г, 0)) for г in грейди)


def таблиця(голови, рядки):
    return ('<div class="wrap"><table><thead><tr>%s</tr></thead>'
            '<tbody>%s</tbody></table></div>'
            % ("".join("<th>%s</th>" % h for h in голови),
               "".join("<tr>%s</tr>" % "".join(r) for r in рядки)))


def джерела_html(світ, річ, скільки=4):
    дж = sorted(світ.джерела.get(річ, []), key=lambda x: (-x[2], x[1]))
    if not дж and річ.startswith("рунна есенція"):
        return "боси підземель, понад свій дроп"
    if not дж:
        return '<span class="muted">не падає</span>'
    перші = ", ".join("%s <span class=\"muted\">(%d рів., %s)</span>"
                      % (e(n), р, відсоток(ш)) for n, р, ш in дж[:скільки])
    if len(дж) > скільки:
        перші += ' <span class="muted">і ще %d</span>' % (len(дж) - скільки)
    return перші


ВІДСОТКОВІ = {"швидкість касту", "швидкість відкату", "швидкість атаки"}


def стати_html(стати):
    if not стати:
        return '<span class="muted">—</span>'
    return ", ".join("%s %s%s%s" % (e(k), "+" if v >= 0 else "−",
                                    число(abs(v)),
                                    "%" if k in ВІДСОТКОВІ else "")
                     for k, v in стати.items())


def файл_значка(річ):
    шлях = os.path.join(ROOT, "game", "assets", "icons", "items", річ + ".png")
    if not os.path.exists(шлях):
        return ""
    os.makedirs(os.path.join(IMG, "rechi"), exist_ok=True)
    shutil.copyfile(шлях, os.path.join(IMG, "rechi", річ + ".png"))
    return '<img class="icon" src="img/rechi/%s.png" alt="">' % e(річ)


ТРИД_РЕФ = os.path.join(ROOT, "spec", "refs", "zbroia")


def значок_3д(річ):
    """Якщо в spec/refs/zbroia/<річ>/ є render.png і/або source-*, повертає
    (кнопка, діалог) для показу референсу 3D-моделі. Інакше ("", "")."""
    тека = os.path.join(ТРИД_РЕФ, річ)
    if not os.path.isdir(тека):
        return "", ""
    файли = []
    if os.path.exists(os.path.join(тека, "render.png")):
        файли.append(("render.png", "згенерований референс"))
    for f in sorted(os.listdir(тека)):
        if f.startswith("source-"):
            файли.append((f, "джерело натхнення"))
    if not файли:
        return "", ""
    вих = os.path.join(IMG, "ref3d", річ)
    os.makedirs(вих, exist_ok=True)
    for f, _ in файли:
        shutil.copyfile(os.path.join(тека, f), os.path.join(вих, f))
    ід = "r3d-%d" % (abs(hash(річ)) % 100000)
    кнопка = ('<button type="button" class="ref3d" '
              'onclick="document.getElementById(\'%s\').showModal()">3D</button>'
              % ід)
    зображення = "".join(
        '<figure><img src="img/ref3d/%s/%s" alt="%s"><figcaption>%s</figcaption></figure>'
        % (e(річ), e(f), e(річ), e(підпис))
        for f, підпис in файли)
    діалог = ('<dialog id="%s" class="ref3d-modal">'
              '<button type="button" class="close" '
              'onclick="this.closest(\'dialog\').close()">×</button>'
              '<h3>%s — референс для 3D</h3>'
              '<div class="ref3d-grid">%s</div></dialog>'
              % (ід, e(річ), зображення))
    return кнопка, діалог


# ─────────────────────────── карта світу ───────────────────────────

ПЛАТФОРМИ = [("windows", "Windows", "Windows 10/11, x86_64"),
             ("macos", "macOS", "Apple Silicon та Intel"),
             ("linux", "Linux", "x86_64")]


def завантаження_html():
    """Блок «Завантажити гру» на головній (П-291, слово замовника 27.11.2026:
    «на головній буде додано розділ скачати апдейтер/лоадер»).

    Архіви апдейтера й `zavantazhennia/info.json` кладе
    `tools/vyklasty_wiki.sh` поруч із вікі на сервері; сторінка лише
    посилається на сталі імена й підтягує версію, розміри та IP сервера
    гри з info.json. Відкрита з диска (без info.json) — блок чесно каже,
    що архівів поруч немає."""
    кнопки = "".join(
        '<a class="dl" data-os="%s" href="zavantazhennia/MyWay-Updater-%s.zip" '
        'download><b>%s</b><span>%s</span><span class="sz" data-size="%s">'
        '</span></a>' % (k, k, e(n), e(опис), k)
        for k, n, опис in ПЛАТФОРМИ)
    return """<section class="download" id="zavantazhyty" aria-labelledby="dl-h">
<h2 id="dl-h">Завантажити гру</h2>
<p>Завантаж <b>апдейтер</b> для своєї системи. Він сам завантажить гру, оновлюватиме її й запустить.</p>
<div class="dls">%s</div>
<p class="dl-meta" id="dl-meta">Версія апдейтера та адреса сервера з'являться тут, коли сторінку відкрито із сервера.</p>
<ol class="steps">
<li>Розпакуй архів і запусти <code>MyWay-Updater</code>.</li>
<li>Введи <b>IP сервера</b>: <code id="dl-ip">той, що дав власник</code>.</li>
<li>За бажанням обери теку, куди встановити гру, натисни <b>«Оновити»</b>, потім <b>«Грати»</b>.</li>
<li>У грі створи персонажа або зайди наявним.</li>
</ol>
<p class="note"><b>macOS:</b> апдейтер не підписаний Apple. Першого разу відкрий його через правий клік → «Відкрити» (або «Усе одно відкрити» в «Приватності та безпеці»). <b>Windows:</b> якщо SmartScreen попередить — «Докладніше» → «Усе одно запустити».</p>
<script>
(function(){
  var ua=navigator.userAgent, os=/Mac/.test(ua)?"macos":/Win/.test(ua)?"windows":/Linux|X11/.test(ua)?"linux":"";
  if(os){var a=document.querySelector('.dl[data-os="'+os+'"]'); if(a) a.classList.add("mine");}
  function mb(b){return (b/1048576).toFixed(0)+" МБ";}
  fetch("zavantazhennia/info.json",{cache:"no-store"}).then(function(r){
    if(!r.ok) throw 0; return r.json();
  }).then(function(i){
    (i.files||[]).forEach(function(f){
      var s=document.querySelector('.sz[data-size="'+f.os+'"]'); if(s) s.textContent=mb(f.size);
    });
    var m="Апдейтер "+i.version+" · викладено "+i.date;
    if(i.server) m+=" · сервер гри "+i.server;
    document.getElementById("dl-meta").textContent=m;
    if(i.server) document.getElementById("dl-ip").textContent=i.server;
  }).catch(function(){
    document.getElementById("dl-meta").textContent="Архівів поруч немає — сторінку відкрито не із сервера вікі.";
  });
})();
</script>
</section>""" % кнопки


def карта(світ):
    м = світ.мапа
    os.makedirs(IMG, exist_ok=True)
    shutil.copyfile(os.path.join(DATA, "svit2", "karta", "svit.jpg"),
                    os.path.join(IMG, "svit.jpg"))
    розселення = os.path.join(ROOT, "spec", "карта-розселення.png")
    є_розселення = False
    if os.path.exists(розселення):
        try:
            from PIL import Image
            Image.MAX_IMAGE_PIXELS = None
            with Image.open(розселення) as im:
                im = im.convert("RGB")
                im.thumbnail((2000, 2000))
                im.save(os.path.join(IMG, "rozselennia.jpg"), quality=85)
            є_розселення = True
        except ImportError:
            pass
    суша = м["земля"]["сторона"]
    святині = {}
    for s in м.get("святині", []):
        святині.setdefault(s["грейд"], []).append(s)
    гнізд = sum(int(z["скільки"]) for z in м["зони появи"])
    тіло = ['<h1>Карта світу</h1>',
            '<p class="lead">Світ версії 2: один материк, море довкола, '
            'п\'ять зон, що сильнішають від столиці. Назви міст і сіл '
            'тимчасові (П-173).</p>',
            '<div class="stats">%s</div>' % "".join(
                "<div><b>%s</b><span>%s</span></div>" % (v, e(k)) for k, v in [
                    ("сторона світу, м", число(суша)),
                    ("міст", len(м["міста"])), ("сіл", len(м["села"])),
                    ("зон появи", число(len(м["зони появи"]))),
                    ("монстрів на мапі", число(гнізд)),
                    ("святинь", len(м.get("святині", []))),
                    ("орієнтирів", len(м.get("орієнтири", [])))])]
    тіло.append(завантаження_html())
    тіло.append('<div class="figs"><figure><img src="img/svit.jpg" '
                'alt="Намальована карта світу" loading="lazy">'
                '<figcaption>Аркуш карти — те саме, що вікно «Карта» в грі. '
                'Аркуш покриває весь світ, %s × %s м.</figcaption></figure>'
                % (число(суша), число(суша)))
    if є_розселення:
        тіло.append('<figure><img src="img/rozselennia.jpg" alt="Карта '
                    'розселення монстрів" loading="lazy"><figcaption>Карта '
                    'розселення: де стоять скупчення й святині '
                    '(<code>tools/rozselennia.py</code>).</figcaption></figure>')
    тіло.append('</div>')

    # Зони
    рядки = []
    опори = {}
    for зона, місто, від, до in rozselennia.ОПОРИ:
        опори.setdefault(зона, []).append("%s %s–%s" % (місто, від, до))
    for код, назва, _, заселена, хто in rozselennia.ЗОНИ:
        рядки.append(["<td class=\"nm\">%s</td>" % e(назва),
                      "<td class=\"num\">%s</td>" % e(код),
                      "<td>%s</td>" % e(хто),
                      "<td>%s</td>" % (e(" · ".join(опори.get(код, [])))
                                       if заселена == "так" else
                                       '<span class="muted">не заселена</span>')])
    тіло.append('<h2>Зони</h2>')
    тіло.append(таблиця(["Зона", "№", "Хто живе", "Рівні за опорними містами"],
                        рядки))

    # Міста і села
    рядки = []
    for місто in м["міста"] + м["села"]:
        x, _, z = місто["центр"]
        люди = ", ".join("%s — %s" % (e(p["хто"]), e(p["ремесло"]))
                         for p in місто.get("мешканці", []))
        рядки.append(["<td class=\"nm\">%s%s</td>" % (
                          e(місто["назва"]),
                          ' <span class="chip">столиця</span>'
                          if місто.get("столиця") else ""),
                      "<td>%s</td>" % ("місто" if місто in м["міста"] else "село"),
                      "<td class=\"num\">%s</td>" % число(round(math.hypot(x, z))),
                      "<td>%s</td>" % (люди or '<span class="muted">без '
                                       'мешканців</span>')])
    тіло.append('<h2>Міста й села</h2>')
    тіло.append('<p class="note">Майстер магії переносить між містами: '
                '%s монет за кілометр по прямій, не менше %s.</p>'
                % (число(світ.телепорт["ціна за км"]),
                   число(світ.телепорт["найменша ціна"])))
    тіло.append(таблиця(["Назва", "Що", "Від столиці, м", "Мешканці"], рядки))

    # Святині
    рядки = []
    for г in ГРЕЙДИ:
        свої = святині.get(г, [])
        if not свої:
            continue
        далеко = [s["далеко від міста"] for s in свої]
        рівні = [s.get("рівень поруч", 0) for s in свої]
        форми = sorted(set(s.get("форма", "") for s in свої))
        рядки.append(["<td>%s</td>" % бейдж(г),
                      "<td class=\"num\">%d</td>" % len(свої),
                      "<td class=\"num\">%s–%s</td>" % (число(round(min(далеко))),
                                                        число(round(max(далеко)))),
                      "<td class=\"num\">%d–%d</td>" % (min(рівні), max(рівні)),
                      "<td>%s</td>" % e(", ".join(форми))])
    тіло.append('<h2>Святині й підземелля</h2>')
    тіло.append('<p class="note">Святиня — вхід у підземелля свого грейду. '
                'Відчиняє її ключ святині того ж грейду, що падає з монстрів '
                'поруч. Довкола кожної стоїть охорона купками з главарями.</p>')
    тіло.append(таблиця(["Грейд", "Святинь", "Від столиці, м",
                         "Рівень монстрів поруч", "Вигляд"], рядки))

    # Орієнтири
    рядки = []
    for о in м.get("орієнтири", []):
        x, _, z = о["де"]
        рядки.append(["<td class=\"nm\">%s</td>" % e(о["вид"]),
                      "<td class=\"num\">%s</td>" % число(round(math.hypot(x, z))),
                      "<td class=\"num\">%s</td>" % число(round(о["радіус"]))])
    тіло.append('<h2>Орієнтири</h2>')
    тіло.append('<p class="note">Поки що прикраса, не механіка: ні входу, ні '
                'здобичі. Що з них зробити — відкрите питання П-220.</p>')
    тіло.append(таблиця(["Орієнтир", "Від столиці, м", "Радіус, м"], рядки))

    море = м.get("море", {})
    тіло.append('<h2>Море</h2><p>Плавати можна. Повітря вистачає на %s с, '
                'далі вода забирає здоров\'я.</p>' % число(море.get("дихання", 0)))
    сторінка("index.html", "Карта світу", "\n".join(тіло),
             "Карта світу MyWay: зони, міста, святині, орієнтири")


# ─────────────────────────── раси й професії ───────────────────────────

РАСИ = [("людина", "Людина", "середина по всіх статах"),
        ("орк", "Орк", "сильний, витривалий, повільний"),
        ("ельф", "Ельф", "швидкий, чуйний, крихкий")]
ЗРІСТ = {"людина": 1.75, "ельф": 1.85, "орк": 1.9}


def скіл_рядок(s):
    рівень0 = (s.get("рівні") or [{}])[0]
    що = []
    if "шкода" in рівень0:
        що.append("шкода ×%s" % число(рівень0["шкода"]))
    if "лік" in рівень0:
        що.append("лік ×%s" % число(рівень0["лік"]))
    стан = рівень0.get("стан")
    if стан:
        що.append("%s: %s ×%s%s" % (стан.get("назва", ""),
                                    СТАТИ_EN.get(стан.get("стат"), стан.get("стат")),
                                    число(стан.get("множник", 1)),
                                    (", %s с" % число(стан["строк"]))
                                    if стан.get("строк") else ""))
    if "мана" in рівень0:
        що.append("мана %s" % число(рівень0["мана"]))
    return "; ".join(що)


def промти_рас(ключ, стать):
    """Згорнуті промти, якими зроблено аватари цієї раси й статі (слово
    замовника 01.10.2026: «необхідно десь зберегти промти… додай їх
    згорнутими на rasy.html»). Джерело — `tools/comfyui/rasy_ref.py`, той
    самий перелік, яким кадри генерувались, тож не розходиться з ними."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "comfyui"))
    import rasy_ref
    рядки = []
    for ім_я, промт, сід, негатив in rasy_ref.vybir():
        if not ім_я.startswith("%s-%s-v" % (ключ, стать)):
            continue
        рядки.append('<p><b>варіант %s · seed %d</b> · FLUX dev Q4, '
                     '1024×1024, 28 кроків, guidance 3.5, euler/beta</p>'
                     '<pre style="white-space:pre-wrap">%s</pre>'
                     '<p class="muted">негатив:</p>'
                     '<pre style="white-space:pre-wrap">%s</pre>'
                     % (ім_я[-1], сід, e(промт), e(негатив)))
    if not рядки:
        return ""
    return ('<details><summary>Промти (%d)</summary>%s</details>'
            % (len(рядки), "".join(рядки)))


def раси(світ):
    теки = os.path.join(ROOT, "art", "скіли")
    os.makedirs(os.path.join(IMG, "skily"), exist_ok=True)
    тіло = ['<h1>Раси та професії</h1>',
            '<p class="lead">Три раси по дві статі — шість типів героя. Раса '
            'зсуває стати вдвічі сильніше за стать. Професія береться '
            'квестом на 20, 40 і 60 рівнях; від раси вона не залежить.</p>']
    рядки = []
    for ключ, назва, характер in РАСИ:
        свої = [s for s in світ.скіли.values() if ключ in (s.get("раси") or [])]
        зсув = світ.рівні["раса"].get(ключ, 0.0)
        рядки.append(["<td class=\"nm\">%s</td>" % назва,
                      "<td>%s</td>" % e(характер),
                      "<td class=\"num\">%s м</td>" % число(ЗРІСТ[ключ]),
                      "<td class=\"num\">%s%s%%</td>" % ("+" if зсув > 0 else "",
                                                         число(round(зсув * 100))),
                      "<td>%s</td>" % "<br>".join(
                          '<span class="skill"><b>%s</b>%s</span>'
                          % (e(s["назва"]),
                             (" <span class=\"muted\">(%s)</span>"
                              % e(", ".join(s["статі"])) if s.get("статі") else ""))
                          for s in sorted(свої, key=lambda s: s.get("з рівня", 1)))])
    тіло.append('<h2>Раси</h2>')
    тіло.append(таблиця(["Раса", "Вдача", "Зріст", "Повага на рівень",
                         "Спадкова гілка"], рядки))
    тіло.append('<p class="note">«Повага на рівень» — наскільки більше чи '
                'менше поваги треба набрати на кожен рівень, ніж людині. '
                'Жінкам треба на %s%% менше.</p>'
                % число(abs(round(світ.рівні["стать"].get("жінка", 0) * 100))))
    # Вигляд (слово замовника 01.10.2026: «перенеси референси рас до
    # rasy.html»). Файли — `wiki/img/rasy/<раса>-<стать>-v<N>.png`, лише
    # диск, як фото монстрів; зроблені `tools/comfyui/rasy_ref.py`. Три на
    # стать — гравець вибиратиме один при створенні персонажа.
    вигляд = []
    for ключ, назва, _ in РАСИ:
        for стать in ("чоловік", "жінка"):
            кадри = []
            for v in (1, 2, 3):
                ім_я = "%s-%s-v%d.png" % (ключ, стать, v)
                if os.path.exists(os.path.join(IMG, "rasy", ім_я)):
                    кадри.append('<figure><img src="img/rasy/%s" alt="%s, '
                                 '%s, варіант %d" loading="lazy">'
                                 '<figcaption>%s, %s — варіант %d'
                                 '</figcaption></figure>'
                                 % (e(ім_я), назва, стать, v, назва, стать, v))
            if кадри:
                вигляд.append('<h3>%s, %s</h3><div class="figs">%s</div>'
                              % (назва, стать, "".join(кадри)))
                вигляд.append(промти_рас(ключ, стать))
    if вигляд:
        тіло.append('<h2>Вигляд</h2>')
        тіло.append('<p class="note">По три варіанти аватара на кожну стать '
                    'кожної раси — при створенні персонажа гравець вибере '
                    'один. Вигляд стати не міняє.</p>')
        тіло.extend(вигляд)
    фігури = []
    for ключ, назва, _ in РАСИ:
        for стать in ("чоловік", "жінка"):
            ім_я = "дерево-%s-%s.png" % (ключ, стать)
            шлях = os.path.join(теки, ім_я)
            if os.path.exists(шлях):
                shutil.copyfile(шлях, os.path.join(IMG, "skily", ім_я))
                фігури.append('<figure><img src="img/skily/%s" alt="Дерево '
                              'вмінь: %s, %s" loading="lazy"><figcaption>%s, '
                              '%s — етап 1</figcaption></figure>'
                              % (e(ім_я), назва, стать, назва, стать))
    if фігури:
        тіло.append('<details><summary>Дерева вмінь етапу 1 для кожного типу '
                    '(%d аркушів)</summary><div class="figs" style="margin-top:'
                    '.8rem">%s</div></details>' % (len(фігури), "".join(фігури)))

    тіло.append('<h2>Етапи</h2>')
    тіло.append(таблиця(["Етап", "Назва", "Рівні", "Професій"], [
        ["<td class=\"num\">%s</td>" % k, "<td>%s</td>" % e(v["назва"]),
         "<td class=\"num\">%d–%d</td>" % (v["від"], v["до"]),
         "<td class=\"num\">%d</td>" % (len([p for p in світ.професії.values()
                                             if str(p["етап"]) == k])
                                        if k != "1" else 0)]
        for k, v in світ.етапи.items()]))

    тіло.append('<h2>Професії</h2>')
    тіло.append('<nav class="sub" aria-label="Професії">%s</nav>' % "".join(
        '<a href="#p-%s">%s</a>' % (e(k), e(p["назва"]))
        for k, p in світ.професії.items()))
    for етап in ("2", "3", "4"):
        тіло.append('<h3>Етап %s — %s</h3>' % (етап, e(світ.етапи[етап]["назва"])))
        рядки = []
        for k, p in світ.професії.items():
            if str(p["етап"]) != етап:
                continue
            батько = світ.професії.get(p.get("батько"), {}).get("назва", "")
            к = p.get("квест", {})
            умови = "; ".join(
                ("вбити %s ×%d" % (у["вбити"], у["скільки"])) if "вбити" in у else
                ("принести %s ×%d" % (у["принести"], у["скільки"])) if "принести" in у
                else json.dumps(у, ensure_ascii=False) for у in к.get("умови", []))
            г = p.get("гілка", {})
            від = г.get("відкриття", {})
            як = {"амулет": "амулет «%s»" % від.get("річ", ""),
                  "полювання": "убити %s ×%s" % (від.get("вид", ""),
                                                 від.get("скільки", "")),
                  }.get(від.get("як"), від.get("як", ""))
            свої = [s for s in світ.скіли.values() if s.get("професія") == k]
            ланцюг = [s for s in свої if s.get("обовязковий")]
            приховані = [s for s in свої if not s.get("обовязковий")]
            def список(ss):
                return "<br>".join(
                    '<span class="skill">%s <b>%s</b><span class="how">%s</span></span>'
                    % (бейдж(s["грейд"]), e(s["назва"]), e(скіл_рядок(s)))
                    for s in sorted(ss, key=lambda s: s.get("з рівня", 0)))
            рядки.append([
                '<td class="nm" id="p-%s">%s<div class="muted" style="font-weight:'
                '400">з %d рів.%s</div></td>' % (e(k), e(p["назва"]), p["з рівня"],
                                                ", від: %s" % e(батько) if батько else ""),
                "<td>%s</td>" % e(p.get("опис", "")),
                "<td><b>%s</b><div class=\"muted\">%s</div>%s</td>"
                % (e(к.get("назва", "")), e(к.get("де", "")), e(умови)),
                "<td>%s</td>" % список(ланцюг),
                "<td><b>%s</b><div class=\"muted\">%s · відкриває: %s</div>%s</td>"
                % (e(г.get("назва", "")), e(г.get("нащо", "")), e(як),
                   список(приховані))])
        тіло.append(таблиця(["Професія", "Хто це", "Квест переходу",
                             "Основний ланцюг", "Прихована гілка"], рядки))

    синтез = [s for s in світ.скіли.values() if s.get("синтез")]
    if синтез:
        рядки = []
        for s in синтез:
            з = " + ".join(e((світ.скіл(x) or {}).get("назва", x)) for x in s["синтез"])
            рядки.append(["<td class=\"nm\">%s %s</td>" % (бейдж(s["грейд"]), e(s["назва"])),
                          "<td>%s</td>" % з,
                          "<td>%s</td>" % e(світ.професії.get(s.get("професія"), {})
                                           .get("назва", "")),
                          "<td>%s</td>" % e(s.get("опис", ""))])
        тіло.append('<h2>Синтез</h2><p class="note">Два вивчені вміння '
                    'зливаються в нове. Руною синтезоване вміння не вивчити.</p>')
        тіло.append(таблиця(["Вміння", "З чого", "Професія", "Що робить"], рядки))
    сторінка("rasy.html", "Раси та професії", "\n".join(тіло),
             "Раси, етапи, двадцять професій MyWay з квестами й гілками")


# ─────────────────────────── монстри ───────────────────────────

НАЗВИ_ЗОН = {"зона 1": "Початкова рівнина", "зона 2": "Гори заходу",
             "зона 3": "Попіл", "зона 4": "Пустка",
             "крижана північ": "Крижана північ", "у грі": "перша хвиля"}


def де_html(світ, назва, запис):
    місце = світ.місця.get(назва)
    куди = (запис or {}).get("де", "")
    частини = []
    if місце:
        далеко = місце["далеко"]
        агр = світ.агресія.get(назва, set())
        частини.append("<b>%s</b>" % e(НАЗВИ_ЗОН.get(куди, куди) or "світ"))
        частини.append("%d скупч., %s голів" % (len(місце["скупчень"]),
                                                  число(місце["гнізд"])))
        частини.append("%s–%s м від столиці" % (число(round(min(далеко))),
                                                 число(round(max(далеко)))))
        частини.append("агресивний" if True in агр else "мирний")
    if куди.startswith("підземелля"):
        частини.append("<b>%s</b>" % e(куди))
    сторож = світ.сторожі.get(назва)
    if сторож:
        частини.append("охороняє святині: %d" % сторож)
    if not частини:
        return '<span class="muted">ніде не стоїть (П-222)</span>'
    return "<br>".join(частини)


def дроп_html(світ, m):
    рядки = []
    спорядження = {}
    for d in m.get("дроп", []):
        б = світ.бази.get(d["що"], {})
        if б.get("вид") in ("зброя", "обладунок", "амулет") and б.get("грейд"):
            спорядження.setdefault((б["грейд"], d["шанс"]), []).append(d["що"])
            continue
        к = ("%s–%s" % (число(d["від"]), число(d["до"]))
             if d["від"] != d["до"] else ("" if d["від"] == 1 else число(d["від"])))
        рядки.append('<li>%s%s <span class="p">%s</span></li>'
                     % (e(d["що"]), (" ×" + к) if к else "", відсоток(d["шанс"])))
    for (г, шанс), речі in sorted(спорядження.items()):
        if len(речі) >= 3:
            рядки.append('<li><a href="zbroia.html#%s">спорядження %s</a> ×%d '
                         '<span class="p">по %s</span></li>'
                         % (г, г, len(речі), відсоток(шанс)))
        else:
            for р in речі:
                рядки.append('<li>%s <span class="p">%s</span></li>'
                             % (e(р), відсоток(шанс)))
    return '<ul class="d">%s</ul>' % "".join(рядки) if рядки else "—"


def скіли_моба_html(світ, m):
    out = []
    for коли, підпис in (("у відповідь", "у відповідь"),
                         ("по кривднику", "по кривднику")):
        ключ = (m.get("скіли") or {}).get(коли)
        if not ключ:
            continue
        s = світ.скіл(ключ)
        назва = s["назва"] if s else ключ
        out.append('<span class="skill"><b>%s</b><span class="how">%s · %s%s</span></span>'
                   % (e(назва), підпис,
                      e(ЦІЛЬ.get(s.get("ціль"), s.get("ціль", ""))) if s else "",
                      (" · " + e(скіл_рядок(s))) if s else ""))
    б = m.get("баф при появі")
    if б:
        out.append('<span class="skill"><b>%s</b><span class="how">завжди: %s ×%s'
                   '</span></span>' % (e(б["назва"]),
                                       e(СТАТИ_EN.get(б["стат"], б["стат"])),
                                       число(б["множник"])))
    return "<br>".join(out) or '<span class="muted">—</span>'


def параметри_html(m):
    с = m["стати"]
    сила, вит, спр = с.get("сила", 10), с.get("витривалість", 10), с.get("спритність", 10)
    пари = [("здоров'я", число(40 + вит * 6)),
            ("фіз. атака", число(round(3 + сила * 0.4, 1))),
            ("фіз. захист", число(round(вит * 1.5, 1))),
            ("біг, м/с", число(round(5 + 0.6 * math.log(max(1, спр) / 10), 2))),
            ("С / В / Сп", "%d / %d / %d" % (сила, вит, спр)),
            ("помічає, м", число(m.get("помічає", 0))),
            ("досвід", "%s–%s" % tuple(число(x) for x in m["досвід"])),
            ("повага", "%s–%s" % tuple(число(x) for x in m["повага"]))]
    return '<div class="kv">%s</div>' % "".join(
        "<span>%s</span><span>%s</span>" % (e(k), v) for k, v in пари)


def ід(m_вид):
    return "m%s" % m_вид


def монстри(світ):
    за_грейдом = {}
    for вид, m in світ.mobs.items():
        за_грейдом.setdefault(світ.грейд(m.get("рівень", 1)), []).append((вид, m))
    for г in за_грейдом:
        за_грейдом[г].sort(key=lambda x: (x[1].get("рівень", 1), x[1]["назва"]))
    лічба = {г: len(v) for г, v in за_грейдом.items()}

    тіло = ['<h1>Монстри</h1>',
            '<p class="lead">%d видів, розкладені за грейдом їхнього рівня '
            '(%s). Зовнішність і повний опис кожного — на сторінці '
            '<a href="monstry-vyglyad.html">Вигляд монстрів</a>; клік по '
            'назві веде туди ж.</p>' % (len(світ.mobs), ", ".join(
                "%s до %s" % (г, світ.до_рівня[г]) for г in ГРЕЙДИ[:-1])
                + ", SS вище"),
            '<p class="note">Здоров\'я, атака, захист і біг пораховані з '
            'сили (С), витривалості (В) і спритності (Сп) тими самими '
            'формулами, що в <code>stats.gd</code>, без бафів. Скіли — '
            'що монстр робить у відповідь на удар (бафить своїх) і по '
            'кривднику (дебаф).</p>',
            підменю(ГРЕЙДИ, лічба)]
    for г in ГРЕЙДИ:
        свої = за_грейдом.get(г, [])
        if not свої:
            continue
        тіло.append('<h2 id="%s">%s Грейд %s <span class="count">%d видів · '
                    'рівні %d–%d</span></h2>'
                    % (г, бейдж(г), г, len(свої), свої[0][1].get("рівень", 1),
                       свої[-1][1].get("рівень", 1)))
        рядки = []
        for вид, m in свої:
            запис = світ.за_назвою.get(m["назва"])
            рядки.append([
                '<td class="nm"><a href="monstry-vyglyad.html#%s">%s</a></td>'
                % (ід(вид), e(m["назва"])),
                '<td class="num">%d</td>' % m.get("рівень", 1),
                "<td>%s</td>" % параметри_html(m),
                "<td>%s</td>" % скіли_моба_html(світ, m),
                "<td>%s</td>" % дроп_html(світ, m),
                "<td>%s</td>" % де_html(світ, m["назва"], запис)])
        тіло.append(таблиця(["Монстр", "Рів.", "Параметри", "Скіли", "Дроп",
                             "Де спавниться"], рядки))
    сторінка("monstry.html", "Монстри", "\n".join(тіло),
             "Усі монстри MyWay за грейдами: рівень, скіли, дроп, параметри, місця")

    # Вигляд: фото + опис у два стовпці.
    os.makedirs(ФОТО_МОНСТРІВ, exist_ok=True)
    з_фото = 0
    з_моделлю = 0
    тіло = ['<h1>Вигляд монстрів</h1>',
            '<p class="lead">Ліворуч фото, праворуч опис моделі. Порожня рамка '
            'означає, що зображення ще немає: досить покласти файл '
            '<code>wiki/img/monstry/&lt;назва&gt;.jpg</code> і перезібрати. '
            'Числа й дроп — у <a href="monstry.html">таблиці монстрів</a>.</p>',
            None,
            підменю(ГРЕЙДИ, лічба)]
    for г in ГРЕЙДИ:
        свої = за_грейдом.get(г, [])
        if not свої:
            continue
        тіло.append('<h2 id="%s">%s Грейд %s <span class="count">%d видів</span></h2>'
                    % (г, бейдж(г), г, len(свої)))
        картки = []
        for вид, m in свої:
            запис = світ.за_назвою.get(m["назва"]) or {}
            фото = ""
            for розш in ("jpg", "png", "webp"):
                if os.path.exists(os.path.join(ФОТО_МОНСТРІВ, "%s.%s" % (m["назва"], розш))):
                    фото = '<img src="img/monstry/%s.%s" alt="%s" loading="lazy">' % (
                        e(m["назва"]), розш, e(m["назва"]))
                    з_фото += 1
                    break
            # 3D-модель (якщо вже своя, з Blender) — окремим квадратом ПІД
            # референс-артом, не замінюючи його й не ділячи рамку навпіл
            # (слово замовника 23.09.2026: «це зображення повинно бути під
            # основним зображенням референсу»). Файл кладеться поруч:
            # wiki/img/monstry/<назва>-модель.png.
            фото = '<div class="photo">%s</div>' % фото
            for розш in ("jpg", "png", "webp"):
                шлях = os.path.join(ФОТО_МОНСТРІВ, "%s-модель.%s" % (m["назва"], розш))
                if os.path.exists(шлях):
                    фото = ('<div class="photos">%s<figure class="photo-3d">'
                            '<div class="photo"><img src="img/monstry/%s-модель.%s" '
                            'alt="%s (3D-модель)" loading="lazy"></div>'
                            '<figcaption>3D-модель у грі</figcaption></figure></div>') % (
                        фото, e(m["назва"]), розш, e(m["назва"]))
                    з_моделлю += 1
                    break
            d = запис.get("опис моделі") or {}
            пункти = []
            for ключ, підпис in bestiary.ЧАСТИНИ + [("тактика", "Як б'ється")]:
                if d.get(ключ):
                    пункти.append("<dt>%s</dt><dd>%s</dd>" % (e(підпис), e(d[ключ])))
            if d.get("скіли"):
                пункти.append("<dt>Скіли в описі</dt><dd>%s</dd>" % "<br>".join(
                    "<b>%s</b> — %s" % (e(n), e(як)) for n, як in d["скіли"]))
            рухи = d.get("анімації") or {}
            if рухи:
                пункти.append("<dt>Анімації</dt><dd><details><summary>%d рухів"
                              "</summary>%s</details></dd>" % (len(рухи), "<br>".join(
                                  "<i>%s</i> — %s" % (e(п), e(рухи[к]))
                                  for к, п in bestiary.РУХИ if рухи.get(к))))
            if not пункти:
                пункти.append('<dd class="muted">Опису моделі ще немає.</dd>')
            місце = НАЗВИ_ЗОН.get(запис.get("де", ""), запис.get("де", ""))
            картки.append(
                '<article class="card" id="%s">%s'
                '<div><h3>%s</h3><div class="meta">%s рівень %d · %s%s</div>'
                '<dl>%s</dl></div></article>'
                % (ід(вид), фото, e(m["назва"]), бейдж(г), m.get("рівень", 1),
                   e(місце or "—"),
                   (" · " + e(запис["опис"])) if запис.get("опис") else "",
                   "".join(пункти)))
        тіло.append('<div class="cards">%s</div>' % "".join(картки))
    тіло[2] = ('<p class="note">Зображень зараз: %d із %d; 3D-моделей: %d.</p>'
               % (з_фото, len(світ.mobs), з_моделлю))
    сторінка("monstry-vyglyad.html", "Вигляд монстрів", "\n".join(тіло),
             "Фото й опис моделі кожного монстра MyWay за грейдами")


# ─────────────────────────── зброя й захист ───────────────────────────

СЛОТИ = ["зброя", "щит", "голова", "тіло", "рукавиці", "ремінь", "взуття",
         "підвіска", "перстень"]
# Порядок у таблиці грейду: спершу зброя, тоді броня тип за типом.
ТИПИ = ["меч", "сокира", "кинджал", "спис", "лук", "посох",
        "важка", "легка", "магічна", "щит", "ремінь", "прикраса"]
ПІДПИС_ТИПУ = {"важка": "важка броня", "легка": "легка броня",
               "магічна": "магічний одяг", "прикраса": "прикраса"}


def зброя(світ):
    речі = [(n, b) for n, b in світ.бази.items()
            if b.get("вид") in ("зброя", "обладунок", "амулет") and b.get("слот")]
    за_грейдом = {}
    for n, b in речі:
        за_грейдом.setdefault(b["грейд"], []).append((n, b))
    лічба = {г: len(v) for г, v in за_грейдом.items()}
    асортимент = set(світ.торгівля.get("асортимент крамаря", []))
    тіло = ['<h1>Зброя та захист</h1>',
            '<p class="lead">%d речей, які можна вдягнути. Зброя шести видів: '
            'меч, сокира й кинджал одноручні, спис, лук і посох — на дві '
            'руки. Броня трьох типів на голову, тіло, рукавиці й взуття: '
            'важка дає захист і здоров\'я, легка — біг і швидкість атаки, '
            'магічний одяг — каст і магічну атаку. Штрафу за «чужу» броню '
            'немає. Щит додає захисту й забирає спритність. Ременів чотири, '
            'E…B, і кожен відкриває стільки смуг панелі, який його грейд. '
            'Крамар продає лише E і D, купує за %d%% ціни.</p>'
            % (len(речі), round(світ.торгівля["крамар купує за"] * 100)),
            підменю(ГРЕЙДИ, лічба)
            .replace("</nav>", '<a href="#koval">коваль</a></nav>')]
    усі_3д_діалоги = []
    for г in ГРЕЙДИ:
        свої = sorted(за_грейдом.get(г, []),
                      key=lambda x: (ТИПИ.index(x[1].get("тип"))
                                     if x[1].get("тип") in ТИПИ else 99,
                                     СЛОТИ.index(x[1]["слот"])
                                     if x[1]["слот"] in СЛОТИ else 99, x[0]))
        if not свої:
            continue
        тіло.append('<h2 id="%s">%s Грейд %s <span class="count">%d речей · '
                    'носити до %s рівня</span></h2>'
                    % (г, бейдж(г), г, len(свої),
                       світ.до_рівня[г] if г != "SS" else "80"))
        рядки = []
        for n, b in свої:
            слот = b["слот"]
            if слот == "ремінь":
                слот = "ремінь · смуг панелі %d" % (ГРЕЙДИ.index(г) + 1)
            elif b.get("вид") == "зброя":
                слот = "%s · міцність %s" % (
                    "на дві руки" if b.get("дві руки") else "одноручна",
                    число(світ.коваль["міцність"]["зброя"]))
            тип = b.get("тип") or ("прикраса" if b.get("вид") == "амулет"
                                   else b["слот"])
            кнопка_3д, діалог_3д = значок_3д(n)
            if діалог_3д:
                усі_3д_діалоги.append(діалог_3д)
            рядки.append([
                '<td class="nm">%s%s%s</td>' % (файл_значка(n), e(n), кнопка_3д),
                "<td>%s</td>" % e(ПІДПИС_ТИПУ.get(тип, тип)),
                "<td>%s</td>" % e(слот),
                "<td>%s</td>" % стати_html(b.get("стати")),
                '<td class="num">%s</td>' % число(b.get("ціна", 0)),
                "<td>%s%s</td>" % ('<span class="chip">крамар</span> '
                                   if n in асортимент else "",
                                   джерела_html(світ, n))])
        тіло.append(таблиця(["Річ", "Тип", "Місце", "Стати", "Ціна", "Звідки"],
                            рядки))

    рядки = []
    for бік in ("спереду", "ззаду"):
        for а in світ.афікси.get(бік, []):
            назва = а["назва"]["ч"] if isinstance(а["назва"], dict) else а["назва"]
            рядки.append(["<td class=\"nm\">%s</td>" % e(назва),
                          "<td>%s</td>" % ("перед назвою" if бік == "спереду"
                                          else "після назви"),
                          "<td>%s</td>" % e(а.get("стат", "")),
                          '<td class="num">+%s…%s</td>' % (число(а.get("від", 0)),
                                                           число(а.get("до", 0))),
                          '<td class="num">%s</td>' % відсоток(а.get("шанс", 0))])
    if рядки:
        тіло.append('<h2>Афікси</h2><p class="note">Річ, що впала, може '
                    'дістати прикметник і додатковий стат. Числа ростуть із '
                    'грейдом: на E стат до 4, на SS — до 18.</p>')
        тіло.append(таблиця(["Афікс", "Де стоїть", "Стат", "Базово", "Шанс"],
                            рядки))
    тіло.append(коваль_html(світ))
    if усі_3д_діалоги:
        тіло.append("".join(усі_3д_діалоги))
    сторінка("zbroia.html", "Зброя та захист", "\n".join(тіло),
             "Уся зброя, обладунки й прикраси MyWay за грейдами")


def шанси(коваль, магічна, грейд):
    """Те саме, що `Smith.chances` у грі: бік, потім параметр за вагою."""
    з = коваль["зачарування"]
    свій = float(з["свій бік"])
    масштаб = 1.0 + float(з["крок за грейд"]) * ГРЕЙДИ.index(грейд)
    out = []
    for бік in ("магічні", "фізичні"):
        шанс_боку = свій if (бік == "магічні") == магічна else 1.0 - свій
        пул = з[бік]
        всього = sum(float(р.get("вага", 1)) for р in пул)
        for р in пул:
            out.append(dict(стат=р["стат"], бік=бік,
                            шанс=шанс_боку * float(р.get("вага", 1)) / всього,
                            від=max(1, round(р["від"] * масштаб)),
                            до=max(1, round(р["до"] * масштаб)),
                            відсотки=bool(р.get("відсотки"))))
    return out


def коваль_html(світ):
    к = світ.коваль
    з = к["зачарування"]
    р = к["ремонт"]
    тіло = ['<h2 id="koval">Коваль: ремонт і зачарування</h2>',
            '<p>Коваль стоїть у Стільній, Крайній Брамі, Гірському Порозі й '
            'Тихій Пустці. <b>Ремонт</b>: зброя тупиться на %s за кожен удар, '
            'що влучив, а на нулі ламається: річ зникає, у торбу лягає %d%% '
            'матеріалів її крафту, а з зачарованої ще %d%% ресурсів '
            'зачарування, до цілого вгору. Ремонт коштує %d%% ціни '
            'речі, помножені на те, скільки міцності бракує, і не менше %d '
            'монет.</p>' % (число(к["міцність"]["за удар"]),
                            round(к["поломка"]["частка крафту"] * 100),
                            round(к["поломка"]["частка зачарування"] * 100),
                            round(р["частка ціни"] * 100), р["найменше"]),
            '<p><b>Зачарування</b> кладе на річ одне рунне посилення. Нове '
            'замінює старе, а зброю ще й лагодить до повної. Ціна: %d%% '
            'ціни речі, рунна есенція її грейду ×%d (падає з босів) і метал '
            'її грейду ×%d. Магічна річ (та, що сама дає більше інтелекту й '
            'чуття, ніж решти) з імовірністю %d%% дістає магічний параметр; '
            'фізична так само — фізичний.</p>'
            % (round(з["ціна частка"] * 100), з["есенції"], з["матеріалу"],
               round(з["свій бік"] * 100)),
            '<p class="note">Числа — пропозиція, не рішення: лежать у '
            '<code>game/data/smith.json</code>, таблиці нижче збираються з '
            'нього.</p>']
    тіло.append(таблиця(["Грейд", "Метал", "Есенція"], [
        ["<td>%s</td>" % бейдж(г), "<td>%s ×%d</td>" % (e(з["матеріал"][г]),
                                                      з["матеріалу"]),
         "<td>рунна есенція %s ×%d</td>" % (г, з["есенції"])]
        for г in ГРЕЙДИ]))
    for г in ГРЕЙДИ:
        маг = шанси(к, True, г)
        фіз = {(x["стат"]): x for x in шанси(к, False, г)}
        рядки = []
        for x in маг:
            одиниця = "%" if x["відсотки"] else ""
            рядки.append([
                '<td class="nm">%s</td>' % e(x["стат"]),
                "<td>%s</td>" % ("магічний" if x["бік"] == "магічні"
                                 else "фізичний"),
                '<td class="num">%s</td>' % відсоток(x["шанс"]),
                '<td class="num">%s</td>' % відсоток(фіз[x["стат"]]["шанс"]),
                '<td class="num">+%d…%d%s</td>' % (x["від"], x["до"], одиниця)])
        тіло.append('<h3>%s Зачарування речі грейду %s</h3>' % (бейдж(г), г))
        тіло.append(таблиця(["Параметр", "Бік", "Шанс на магічній речі",
                             "Шанс на фізичній речі", "Скільки"], рядки))
    return "\n".join(тіло)


# ─────────────────────────── ітеми й матеріали ───────────────────────────

def ітеми(світ):
    групи = [
        ("materialy", "Матеріали", lambda b: b.get("вид") == "ресурс",
         "Падають із монстрів, продаються крамареві."),
        ("vytratne", "Зілля й кристали", lambda b: b.get("вид") == "витратне",
         "Витрачаються з торби чи з панелі."),
        ("kliuchi", "Ключі святинь", lambda b: b.get("вид") == "ключ",
         "Відчиняють святиню свого грейду і вхід у підземелля."),
        ("amulety", "Амулети гілок",
         lambda b: b.get("вид") == "амулет" and not b.get("слот"),
         "Не вдягаються: відчиняють приховану гілку професії назавжди."),
        ("artefakty", "Артефакти", lambda b: b.get("вид") == "артефакт", ""),
        ("runy", "Руни", lambda b: b.get("вид") == "руна",
         "Руна вчить уміння або піднімає його рівень."),
    ]
    тіло = ['<h1>Ітеми та матеріали</h1>',
            '<p class="lead">Усе, що лежить у торбі й не вдягається. '
            'Зброя, обладунки й прикраси — у розділі '
            '<a href="zbroia.html">Зброя та захист</a>.</p>']
    лічби = {k: len([1 for b in світ.бази.values() if f(b)]) for k, _, f, _ in групи}
    тіло.append('<nav class="sub" aria-label="Групи">%s</nav>' % "".join(
        '<a href="#%s">%s <span class="muted">%d</span></a>' % (k, e(н), лічби[k])
        for k, н, _, _ in групи))
    for k, назва, f, нотатка in групи:
        свої = sorted([(n, b) for n, b in світ.бази.items() if f(b)],
                      key=lambda x: (ГРЕЙДИ.index(x[1]["грейд"])
                                     if x[1].get("грейд") in ГРЕЙДИ else -1,
                                     x[1].get("ціна", 0), x[0]))
        тіло.append('<h2 id="%s">%s <span class="count">%d</span></h2>'
                    % (k, e(назва), len(свої)))
        if нотатка:
            тіло.append('<p class="note">%s</p>' % e(нотатка))
        if k == "runy":
            тіло.append(руни_html(світ, свої))
            continue
        рядки = []
        for n, b in свої:
            що = b.get("_про", "")
            if b.get("дія"):
                що = ", ".join("%s +%s" % (e(a), число(v)) for a, v in b["дія"].items())
            if k == "amulety":
                що = ", ".join(p["назва"] for p in світ.професії.values()
                               if p.get("гілка", {}).get("відкриття", {}).get("річ") == n)
                що = ("гілка професії: " + що) if що else ""
            рядки.append(['<td class="nm">%s%s%s</td>' % (
                              файл_значка(n),
                              (бейдж(b["грейд"]) + " ") if b.get("грейд") else "",
                              e(n)),
                          "<td>%s</td>" % e(що),
                          '<td class="num">%s</td>' % число(b.get("ціна", 0)),
                          "<td>%s</td>" % джерела_html(світ, n)])
        тіло.append(таблиця(["Річ", "Що дає", "Ціна", "Звідки падає"], рядки))
    сторінка("rechi.html", "Ітеми та матеріали", "\n".join(тіло),
             "Матеріали, зілля, ключі, амулети й руни MyWay")


def руни_html(світ, свої):
    рядки = []
    for n, b in свої:
        s = світ.руна_скіла.get(n)
        if s:
            кому = (світ.професії.get(s.get("професія"), {}).get("назва")
                    or ", ".join(s.get("раси") or []) or "усім")
            що = '%s <b>%s</b> <span class="muted">· %s · з %d рів.</span>' % (
                бейдж(s["грейд"]), e(s["назва"]), e(кому), s.get("з рівня", 1))
        else:
            що = '<span class="muted">%s</span>' % (
                "піднімає вміння до наступного грейду" if "підняття" in n else "—")
        рядки.append(['<td class="nm">%s%s</td>' % (файл_значка(n), e(n)),
                      "<td>%s</td>" % що,
                      '<td class="num">%s</td>' % число(b.get("ціна", 0)),
                      "<td>%s</td>" % джерела_html(світ, n, 3)])
    return таблиця(["Руна", "Чого вчить", "Ціна", "Звідки падає"], рядки)


def головне():
    os.makedirs(OUT, exist_ok=True)
    світ = Світ()
    with open(os.path.join(OUT, "style.css"), "w", encoding="utf-8") as f:
        f.write(CSS.strip() + "\n")
    print("[вікі] %s" % OUT)
    карта(світ)
    раси(світ)
    монстри(світ)
    зброя(світ)
    ітеми(світ)
    print("[вікі] відкрити: file://%s/index.html" % OUT)


if __name__ == "__main__":
    головне()
