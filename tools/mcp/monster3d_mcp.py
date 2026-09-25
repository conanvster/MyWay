#!/usr/bin/env python3
"""MCP-сервер конвеєра 3D-моделей монстрів (шлях А) — без залежностей:
JSON-RPC 2.0 рядками через stdio (протокол MCP, tools).

Навіщо: до 24.09.2026 кожен звір — десятки shell-команд, власні цикли
очікування GPU (і «загадкові» смерті фонових процесів через `timeout`),
окремі Read на кожну картинку. Тут — кілька інструментів над
`tools/monster_pipeline.py`:

  queue      — уся черга: вид, профіль, етап;
  status     — стан одного виду;
  reference  — референс-арт (картинкою) + опис моделі з бестіарію
               (чекліст одним викликом);
  start      — довгі кроки (поза, сітка, збірка, фініш, огляд, gpu) у
               фоні: повертає номер завдання, не тримає виклик;
  job        — стан завдання (з очікуванням до 50 с) і хвіст журналу;
  choose     — обрати варіант пози або референс для сітки;
  sheet      — аркуш-зведення картинкою (пози 2×2, огляд сирої сітки,
               збірка/чернетка, фініш).

Реєстрація (user-рівень, працює з будь-якої теки):
    claude mcp add --scope user monster3d -- python3 /home/alex/гра-lineage/tools/mcp/monster3d_mcp.py
Інструменти з'являються лише в НОВІЙ сесії Claude Code.
"""
import base64
import io
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PIPE = os.path.join(ROOT, "tools", "monster_pipeline.py")
JOBS = os.path.join(ROOT, "art", "monsters", "_завдання")
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))

STEPS = ["поза", "сітка", "збірка", "фініш", "огляд", "gpu"]
SHEETS = {"пози": "поза-варіанти.png", "огляд": "огляд-аркуш.png",
          "збірка": "аркуш.png", "чернетка": "чернетка/аркуш.png",
          "фініш": "фініш-аркуш.png"}

TOOLS = [
    {"name": "queue", "description": "Черга моделей шляху А: вид, профіль типу тіла, етап (що робити далі).",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "status", "description": "Стан одного виду: пози, обраний варіант, сітка, чернетка, модель, вікі.",
     "inputSchema": {"type": "object", "properties": {"species": {"type": "string", "description": "назва виду, як у бестіарії (напр. «вовк-сіромаха»)"}}, "required": ["species"]}},
    {"name": "reference", "description": "Референс-арт виду (зображення) і «опис моделі» з бестіарію — для чекліста й рішення, чи потрібна поза Kontext.",
     "inputSchema": {"type": "object", "properties": {"species": {"type": "string", "description": "назва виду, як у бестіарії (напр. «вовк-сіромаха»)"}}, "required": ["species"]}},
    {"name": "start", "description": "Запустити довгий крок у фоні й повернути номер завдання. Кроки: поза (Kontext, пакетом для кількох видів — модель вантажиться раз), сітка (Pixal3D з обраної пози або референсу, пакетом), збірка (Blender: автокістки, рухи, корекція землі; чернетка — в теку чернетка/), фініш (mobs.json, Godot-проба, хутро, вікі), огляд (сира сітка з 4 боків), gpu (звільнити LM Studio, підняти ComfyUI).",
     "inputSchema": {"type": "object", "properties": {
         "step": {"type": "string", "enum": STEPS},
         "species": {"type": "array", "items": {"type": "string"}, "description": "один вид або пачка"},
         "seeds": {"type": "array", "items": {"type": "integer"}},
         "draft": {"type": "boolean", "description": "збірка в теку чернетка/"}}, "required": ["step"]}},
    {"name": "job", "description": "Стан фонового завдання: чи завершено, код, хвіст журналу. `wait` — до 50 с чекати завершення.",
     "inputSchema": {"type": "object", "properties": {"id": {"type": "string"}, "wait": {"type": "integer", "description": "секунд чекати завершення, до 50"}},
                     "required": ["id"]}},
    {"name": "choose", "description": "Обрати джерело для сітки: номер сіду пози (11, 22…) або «реф» — сам референс.",
     "inputSchema": {"type": "object", "properties": {"species": {"type": "string"}, "variant": {"type": "string", "description": "сід пози (11, 22…) або «реф»"}},
                     "required": ["species", "variant"]}},
    {"name": "sheet", "description": "Аркуш-зведення виду картинкою: пози | огляд | збірка | чернетка | фініш.",
     "inputSchema": {"type": "object", "properties": {"species": {"type": "string"},
                                                     "which": {"type": "string", "enum": list(SHEETS)}},
                     "required": ["species", "which"]}},
]


def image(path, max_w=1400):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    if im.width > max_w:
        im = im.resize((max_w, int(im.height * max_w / im.width)))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=82)
    return {"type": "image", "data": base64.b64encode(buf.getvalue()).decode(), "mimeType": "image/jpeg"}


def text(t):
    return {"type": "text", "text": t}


def run_sync(*args):
    r = subprocess.run([sys.executable, PIPE, *args], cwd=ROOT, capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def job_file(jid):
    return os.path.join(JOBS, jid + ".json")


def start(step, names, seeds, draft):
    os.makedirs(JOBS, exist_ok=True)
    jid = time.strftime("%H%M%S") + "-" + step
    log = os.path.join(JOBS, jid + ".log")
    args = [sys.executable, "-u", PIPE, step, *names]
    if step == "поза" and seeds:
        args += ["--сіди", *map(str, seeds)]
    if step == "збірка" and draft:
        args.append("--чернетка")
    p = subprocess.Popen(args, cwd=ROOT, stdout=open(log, "w"), stderr=subprocess.STDOUT,
                         start_new_session=True)
    json.dump({"pid": p.pid, "крок": step, "види": names, "журнал": log, "початок": time.time()},
              open(job_file(jid), "w", encoding="utf-8"), ensure_ascii=False)
    return jid


def job(jid, wait):
    meta = json.load(open(job_file(jid), encoding="utf-8"))
    t0 = time.time()
    while True:
        alive = os.path.exists("/proc/%d" % meta["pid"]) and \
            "Z" not in open("/proc/%d/stat" % meta["pid"]).read().split()[2]
        if not alive or time.time() - t0 >= min(wait, 50):
            break
        time.sleep(2)
    try:
        os.waitpid(meta["pid"], os.WNOHANG)
    except ChildProcessError:
        pass
    tail = open(meta["журнал"], encoding="utf-8", errors="replace").read().splitlines()[-25:]
    mins = (time.time() - meta["початок"]) / 60
    head = "завдання %s (%s %s): %s, %.1f хв" % (jid, meta["крок"], " ".join(meta["види"]),
                                                "ЗАВЕРШЕНО" if not alive else "виконується", mins)
    return head + "\n" + "\n".join(tail)


def reference(name):
    best = json.load(open(os.path.join(ROOT, "spec", "бестіарій.json"), encoding="utf-8"))
    m = next((x for x in best if x.get("назва") == name), None)
    if not m:
        return [text("немає виду «%s» у бестіарії" % name)]
    import monster_pipeline as MP
    import scan_profiles as P
    _, mb = MP.mob(name)
    cfg = P.config(name) if name in P.SPECIES else {}
    desc = "\n".join("- %s: %s" % (k, v) for k, v in m.get("опис моделі", {}).items()
                     if k not in ("скіли",))
    info = "%s — рівень %s, зріст %s м, профіль «%s» (%s)\n%s" % (
        name, m.get("рівень"), (mb or {}).get("вигляд", {}).get("зріст"),
        cfg.get("profile", "—"), cfg.get("body", "—"), desc)
    out = [text(info)]
    ref = os.path.join(ROOT, "wiki", "img", "monstry", name + ".png")
    if os.path.exists(ref):
        out.append(image(ref, 900))
    return out


def call(name, a):
    import monster_pipeline as MP
    if name == "queue":
        return [text(run_sync("черга"))]
    if name == "status":
        return [text(json.dumps(MP.status(a["species"]), ensure_ascii=False, indent=1))]
    if name == "reference":
        return reference(a["species"])
    if name == "start":
        jid = start(a["step"], a.get("species", []), a.get("seeds"), a.get("draft", False))
        return [text("запущено: %s\n%s" % (jid, job(jid, 3)))]
    if name == "job":
        return [text(job(a["id"], int(a.get("wait", 0))))]
    if name == "choose":
        return [text(run_sync("вибрати", a["species"], str(a["variant"])))]
    if name == "sheet":
        p = os.path.join(MP.folder(a["species"]), SHEETS[a["which"]])
        if not os.path.exists(p):
            return [text("аркуша ще немає: %s" % os.path.relpath(p, ROOT))]
        return [text(os.path.relpath(p, ROOT)), image(p)]
    raise ValueError("невідомий інструмент %s" % name)


def reply(mid, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": mid}
    if error:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        method, mid, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
        if mid is None:
            continue                                   # сповіщення
        if method == "initialize":
            reply(mid, {"protocolVersion": params.get("protocolVersion", "2024-11-05"),
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "monster3d", "version": "1.0"}})
        elif method == "ping":
            reply(mid, {})
        elif method == "tools/list":
            reply(mid, {"tools": TOOLS})
        elif method == "tools/call":
            try:
                reply(mid, {"content": call(params["name"], params.get("arguments") or {})})
            except Exception as e:                     # помилку — моделі, не падати
                reply(mid, {"content": [text("‼ %s: %s" % (type(e).__name__, e))], "isError": True})
        else:
            reply(mid, error={"code": -32601, "message": "метод не підтримується: %s" % method})


if __name__ == "__main__":
    main()
