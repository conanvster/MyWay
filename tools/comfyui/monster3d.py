"""Звір із референс-арту → поза → сітка з текстурою, через локальний ComfyUI.

Два кроки конвеєра `spec/генерація-3d-моделей-монстрів.md` (розділи 3–4):

    python3 tools/comfyui/monster3d.py поза <референс.png> <назва> <хто> [сіди...]
        FLUX Kontext переставляє ТОГО САМОГО звіра в спокійну стійку на
        сірому тлі. <хто> — англійською, як у промті (hare, wolf, brown
        bear). Типово 4 сіди (11 22 33 44). Кадри → ComfyUI/output/
        <назва>_pose_s<сід>_00001_.png і копії в art/monsters/<назва>-3d/.

    python3 tools/comfyui/monster3d.py сітка <поза.png> <назва> [граней]
        Pixal3D (шаблон `3d_pixal3d_trellis2_image_to_model`, граф —
        `pixal3d.api.json` поруч) → ComfyUI/output/3d/<назва>_textured_
        00001_.glb і копія в art/monsters/<назва>-3d/pixal3d.glb.
        Граней до розгортки UV — типово 150 000 (700 000 з шаблону
        розгортку в 16 ГБ не пускають).

    python3 tools/comfyui/monster3d.py звільнити
        Вивантажити моделі з відеопам'яті ComfyUI.

ComfyUI має вже працювати: `cd ~/ComfyUI && venv/bin/python main.py
--listen 127.0.0.1 --port 8188`. Відеопам'ять має бути вільна (LM Studio:
`~/.lmstudio/bin/lms unload --all`).
"""
import json
import os
import shutil
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
COMFY = os.path.expanduser("~/ComfyUI")
URL = "http://127.0.0.1:8188"

# Слова, перевірені на зайці 23.09.2026. «{хто}» — хто на референсі
# англійською (hare, wolf…); решта — щоб Kontext не малював НОВОГО звіра,
# а переставив того самого.
POSE_PROMPT = (
    "Change only the pose and background. The same {who} now stands calmly on "
    "all four paws on flat ground, full body fully visible, three-quarter view "
    "from the front-left, all four legs straight and touching the ground, "
    "relaxed neutral standing stance, head level. Replace the grass and "
    "blurred background with a plain uniform light grey studio background, "
    "soft even lighting. Keep exactly the same {who}: same fur colour and "
    "texture, same face, same eyes, same ears, same tail, same markings, "
    "same photorealistic style.")


def post(path, body):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req).read() or b"{}")


def run(graph):
    """Поставити граф у чергу й дочекатись. Помилку вузла — показати й
    вийти, а не мовчки лишити порожній вихід."""
    answer = post("/prompt", {"prompt": graph})
    if answer.get("node_errors"):
        sys.exit("‼ граф не прийнято: %s" % answer["node_errors"])
    pid = answer["prompt_id"]
    while True:
        h = json.loads(urllib.request.urlopen(URL + "/history/" + pid).read())
        if h and "status_str" in h[pid]["status"]:
            status = h[pid]["status"]
            for kind, msg in status["messages"]:
                if kind == "execution_error":
                    sys.exit("‼ %s: %s" % (msg.get("node_type"),
                                           msg.get("exception_message")))
            return h[pid]
        time.sleep(3)


def stage(picture):
    """Покласти вхідну картинку в ComfyUI/input, повернути її ім'я там."""
    name = "monster3d_" + os.path.basename(picture)
    shutil.copy(picture, os.path.join(COMFY, "input", name))
    return name


def free():
    post("/free", {"unload_models": True, "free_memory": True})


def pose(picture, name, seeds, who):
    image = stage(picture)
    folder = os.path.join(ROOT, "art", "monsters", name + "-3d")
    os.makedirs(folder, exist_ok=True)
    free()
    for seed in seeds:
        g = {
            "1": {"class_type": "UnetLoaderGGUF",
                  "inputs": {"unet_name": "flux1-kontext-dev-Q5_K_S.gguf"}},
            "2": {"class_type": "DualCLIPLoader",
                  "inputs": {"clip_name1": "clip_l.safetensors",
                             "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
                             "type": "flux"}},
            "3": {"class_type": "VAELoader",
                  "inputs": {"vae_name": "ae.safetensors"}},
            "4": {"class_type": "LoadImage", "inputs": {"image": image}},
            "5": {"class_type": "FluxKontextImageScale",
                  "inputs": {"image": ["4", 0]}},
            "6": {"class_type": "VAEEncode",
                  "inputs": {"pixels": ["5", 0], "vae": ["3", 0]}},
            "7": {"class_type": "CLIPTextEncode",
                  "inputs": {"text": POSE_PROMPT.format(who=who),
                             "clip": ["2", 0]}},
            "8": {"class_type": "ReferenceLatent",
                  "inputs": {"conditioning": ["7", 0], "latent": ["6", 0]}},
            "9": {"class_type": "FluxGuidance",
                  "inputs": {"conditioning": ["8", 0], "guidance": 2.5}},
            "10": {"class_type": "ConditioningZeroOut",
                   "inputs": {"conditioning": ["7", 0]}},
            "11": {"class_type": "KSampler",
                   "inputs": {"model": ["1", 0], "seed": seed, "steps": 24,
                              "cfg": 1.0, "sampler_name": "euler",
                              "scheduler": "simple", "positive": ["9", 0],
                              "negative": ["10", 0],
                              "latent_image": ["6", 0], "denoise": 1.0}},
            "12": {"class_type": "VAEDecode",
                   "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
            "13": {"class_type": "SaveImage",
                   "inputs": {"images": ["12", 0],
                              "filename_prefix": "%s_pose_s%d" % (name, seed)}},
        }
        done = run(g)
        for out in done["outputs"]["13"]["images"]:
            src = os.path.join(COMFY, "output", out["subfolder"],
                               out["filename"])
            dst = os.path.join(folder, "поза-s%d.png" % seed)
            shutil.copy(src, dst)
            print("[поза] сід %d → %s" % (seed, dst))


def mesh(picture, name, faces):
    graph = json.load(open(os.path.join(HERE, "pixal3d.api.json")))
    graph["122"]["inputs"]["image"] = stage(picture)
    graph["186"]["inputs"]["target_face_count"] = faces
    graph["900"]["inputs"]["filename_prefix"] = "3d/%s_textured" % name
    graph["901"]["inputs"]["filename_prefix"] = "3d/%s_vertexcolor" % name
    free()
    done = run(graph)
    folder = os.path.join(ROOT, "art", "monsters", name + "-3d")
    os.makedirs(folder, exist_ok=True)
    for node in ("900",):
        for out in done["outputs"][node].get("3d", []):
            src = os.path.join(COMFY, "output", out["subfolder"],
                               out["filename"])
            dst = os.path.join(folder, "pixal3d.glb")
            shutil.copy(src, dst)
            print("[сітка] %s → %s" % (src, dst))
    free()


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "поза" and len(args) >= 4:
        seeds = [int(s) for s in args[4:]] or [11, 22, 33, 44]
        pose(args[1], args[2], seeds, args[3])
    elif args[0] == "сітка" and len(args) >= 3:
        mesh(args[1], args[2], int(args[3]) if len(args) > 3 else 150000)
    elif args[0] == "звільнити":
        free()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
