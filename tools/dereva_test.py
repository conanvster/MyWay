#!/usr/bin/env python3
"""Пакет дерев для тесту вигляду (П-253, крок 2) → розділ «Дерева» на test.html.

Слово замовника 01.10.2026: «далі теж через тестування вигляду зберемо
декілька типів з варіаціями дерев». Кожне дерево — свій seed, тип, кора й
листя; генератор — `tools/blender/derevo.py`, листя —
`tools/derevo_lystia.py`.

    python3 -u tools/dereva_test.py [скільки] [--дзеркало ~/гра-lineage]

Сирі кори й листя — у `~/асети/дерева/` (Poly Haven, ambientCG, CC0; поза
репозиторієм). Кадри — `wiki/img/test/dereva/<N>.png` (лише диск), сітки
— `~/асети/дерева/vyhid/<N>/derevo.glb`. Розділ сторінки стоїть між
мітками `<!-- дерева -->` і `<!-- /дерева -->`; `rasy_ref.py` його не
чіпає.
"""
import json
import random
import shutil
import subprocess
import sys
from pathlib import Path

KORIN = Path(__file__).resolve().parents[1]
ASETY = Path.home() / "асети/дерева"
KADRY = KORIN / "wiki/img/test/dereva"
STORINKA = KORIN / "wiki/test.html"
POCHATOK, KINETS = "<!-- дерева -->", "<!-- /дерева -->"

KORA_LYST = ["jolcham_oak_bark_01", "bark_brown_01", "bark_platanus",
             "bark_willow_02"]
KORA_KHVOI = ["pine_bark", "bark_brown_01"]
LYSTIA = ["LeafSet004", "LeafSet005", "LeafSet009", "LeafSet010",
          "LeafSet014", "LeafSet016", "LeafSet022", "LeafSet023",
          "LeafSet024"]
KHVOIA = ["LeafSet019"]


def nabir(skilky):
    rng = random.Random(253)
    out = []
    for i in range(skilky):
        khvoine = i % 4 == 3            # кожне четверте — хвойне
        out.append({
            "seed": 100 + i,
            "тип": "хвойне" if khvoine else "листяне",
            "кора": rng.choice(KORA_KHVOI if khvoine else KORA_LYST),
            "листя": rng.choice(KHVOIA if khvoine else LYSTIA),
        })
    return out


def vyrostyty(d):
    tut = ASETY / "vyhid" / str(d["seed"])
    kora = ASETY / "polyhaven" / d["кора"]
    cmd = ["blender", "-b", "--factory-startup", "-P",
           str(KORIN / "tools/blender/derevo.py"), "--",
           "--seed", str(d["seed"]), "--тип", d["тип"],
           "--кора", str(kora) + "_diff_1k.jpg",
           "--нормаль", str(kora) + "_nor_gl_1k.jpg",
           "--листя", str(ASETY / "klastery" / (d["листя"] + ".png")),
           "--вихід", str(tut), "--рендер"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not (tut / "kadr.png").exists():
        print("‼ дерево %d не вийшло:\n%s" % (d["seed"], r.stdout[-2000:]
                                               + r.stderr[-2000:]))
        return None
    KADRY.mkdir(parents=True, exist_ok=True)
    shutil.copy(tut / "kadr.png", KADRY / ("%d.png" % d["seed"]))
    return json.loads((tut / "derevo.json").read_text())


def rozdil(chysla):
    ryadky = [POCHATOK, '<h2>Дерева — генератор (П-253)</h2>',
              '<p class="note">Кожне дерево — випадковий тип і крона '
              'зі справжньої кори (Poly Haven) і справжніх листків '
              '(ambientCG), CC0; <code>tools/blender/derevo.py</code>. '
              'Вибери типи, які лишаємо, і що поправити.</p>',
              '<div class="compare">']
    for c in chysla:
        ryadky.append(
            '<figure><img src="img/test/dereva/%d.png" alt="дерево %d">'
            '<figcaption><b>№ %d · %s, крона «%s»</b>%.0f м · кора %s · '
            'листя %s · %d тис. трикутників</figcaption></figure>'
            % (c["seed"], c["seed"], c["seed"], c["тип"], c["форма крони"],
               c["висота"], c["кора"].replace("_diff_1k.jpg", ""),
               c["листя"].replace(".png", ""), c["трикутників"] // 1000))
    ryadky += ['</div>', KINETS]
    return "\n".join(ryadky)


def vpysaty(chysla):
    t = STORINKA.read_text(encoding="utf-8")
    blok = rozdil(chysla)
    if POCHATOK in t:
        a = t.index(POCHATOK)
        b = t.index(KINETS) + len(KINETS)
        t = t[:a] + blok + t[b:]
    else:
        a = t.index("</main>")
        t = t[:a] + blok + "\n" + t[a:]
    STORINKA.write_text(t, encoding="utf-8")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    skilky = int(args[0]) if args and args[0].isdigit() else 12
    dzerkalo = Path(sys.argv[sys.argv.index("--дзеркало") + 1]) \
        if "--дзеркало" in sys.argv else None
    chysla = []
    for d in nabir(skilky):
        c = vyrostyty(d)
        if c is None:
            continue
        chysla.append(c)
        vpysaty(chysla)
        if dzerkalo:
            (dzerkalo / "wiki/img/test/dereva").mkdir(parents=True,
                                                      exist_ok=True)
            shutil.copy(KADRY / ("%d.png" % c["seed"]),
                        dzerkalo / "wiki/img/test/dereva")
            shutil.copy(STORINKA, dzerkalo / "wiki/test.html")
        print("готово", c["seed"], c["тип"], c["форма крони"], flush=True)


if __name__ == "__main__":
    main()
