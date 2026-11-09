"""MV-Adapter (зображення + геометрія → 6 видів) на нашій сітці (09.11.2026).

Пілот 2 орка, варіант Б: вигляди малюються одразу під нашу геометрію (карти
позицій і нормалей сітки), тож проєкція в розгортку лягає без розбіжностей.
nvdiffrast (потрібен CUDA-компілятор, якого нема) замінено своїм
растеризатором на numpy — ті самі камери й нормування, що в
`scripts/inference_ig2mv_sdxl.py`: сітка по центру, |коорд.| ≤ 0,5, вісь Z
вгору, перед — −Y, орто ±0,55, види: перед, лівий бік (+X), зад, правий бік,
верх, низ.

    ~/Програми/mvadapter-venv/bin/python tools/mvadapter/ig2mv.py <сітка.npz> <референс.png> <тека> \
        [--опис "..."] [--сід 7] [--кроків 40]
→ <тека>/mv-<i>.png, mv-pos-<i>.png, mv-nrm-<i>.png, kamery.json
"""
import json
import math
import os
import sys

import numpy as np
import torch
from PIL import Image

M = "/home/alex/Програми/mvadapter-models"
A = sys.argv[1:]
NPZ, REF, OUT = A[0], A[1], A[2]


def arg(k, typ, d):
    return typ(A[A.index(k) + 1]) if k in A else d


OPYS = arg("--опис", str, "high quality, photorealistic orc, olive green skin with pores, veins and scars")
SID = arg("--сід", int, 7)
KROKIV = arg("--кроків", int, 40)
RES = 768
os.makedirs(OUT, exist_ok=True)

d = np.load(NPZ)
V, VN, F = d["V"].astype(np.float64), d["VN"].astype(np.float64), d["F"]
tsentr = (V.max(0) + V.min(0)) / 2
V0 = V - tsentr
masht = 0.5 / np.abs(V0).max()
Vn = V0 * masht


def kamera(az, el):
    a, e = math.radians(az), math.radians(el)
    pos = np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)]) * 1.8
    look = -pos / np.linalg.norm(pos)
    up = np.array([0, 0, 1.0])
    right = np.cross(look, up)
    right /= np.linalg.norm(right)
    up = np.cross(right, look)
    return pos, look, right, up


KAMERY = [kamera(az - 90, el) for az, el in zip([0, 90, 180, 270, 180, 180], [0, 0, 0, 0, 89.99, -89.99])]


def rasteryzuvaty(look, right, up):
    """z-буфер: позиції (норм.) і нормалі світу в кожному пікселі."""
    x = Vn @ right
    y = Vn @ up
    z = Vn @ look                         # глибина вздовж погляду (менше — ближче)
    px = (x / 0.55 * 0.5 + 0.5) * RES
    py = (0.5 - y / 0.55 * 0.5) * RES
    zb = np.full((RES, RES), np.inf)
    pos = np.zeros((RES, RES, 3))
    nrm = np.zeros((RES, RES, 3))
    for f in F:
        xs, ys = px[f], py[f]
        x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, RES - 1)
        y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, RES - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, bx, cx), (ay, by, cy) = xs, ys
        det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(det) < 1e-9:
            continue
        l0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / det
        l1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / det
        l2 = 1 - l0 - l1
        ok = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not ok.any():
            continue
        zz = l0 * z[f[0]] + l1 * z[f[1]] + l2 * z[f[2]]
        iy, ix = (gy[ok] - 0.5).astype(int), (gx[ok] - 0.5).astype(int)
        zz = zz[ok]
        blyzhche = zz < zb[iy, ix]
        iy, ix = iy[blyzhche], ix[blyzhche]
        b = np.stack([l0[ok][blyzhche], l1[ok][blyzhche], l2[ok][blyzhche]], -1)
        zb[iy, ix] = zz[blyzhche]
        pos[iy, ix] = b @ Vn[f]
        n = b @ VN[f]
        nrm[iy, ix] = n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-9)
    maska = np.isfinite(zb)
    return pos, nrm, maska


kontrol = []
for i, (p, look, right, up) in enumerate(KAMERY):
    pos, nrm, maska = rasteryzuvaty(look, right, up)
    pos_i = np.where(maska[..., None], np.clip(pos + 0.5, 0, 1), 0.0)
    nrm_i = np.where(maska[..., None], np.clip(nrm / 2 + 0.5, 0, 1), 0.0)
    Image.fromarray((pos_i * 255).astype(np.uint8)).save("%s/mv-pos-%d.png" % (OUT, i))
    Image.fromarray((nrm_i * 255).astype(np.uint8)).save("%s/mv-nrm-%d.png" % (OUT, i))
    kontrol.append(np.concatenate([pos_i, nrm_i], -1))
    print("растр", i, int(maska.sum()), flush=True)
json.dump({"tsentr": tsentr.tolist(), "masht": masht, "res": RES, "pivshyryna": 0.55,
           "kamery": [{"look": k[1].tolist(), "right": k[2].tolist(), "up": k[3].tolist()}
                      for k in KAMERY]}, open(OUT + "/kamery.json", "w"), indent=1)

import types  # noqa: E402
# nvdiffrast (CUDA-компілятор) не потрібен: растр свій — заглушка модуля
for _m in ("nvdiffrast", "nvdiffrast.torch"):
    sys.modules.setdefault(_m, types.ModuleType(_m))
sys.modules["nvdiffrast"].torch = sys.modules["nvdiffrast.torch"]
sys.path.insert(0, "/home/alex/Програми/mvadapter-src/MV-Adapter/scripts")
from inference_ig2mv_sdxl import prepare_pipeline, remove_bg  # noqa: E402
from diffusers import AutoencoderKL  # noqa: E402,F401
from mvadapter.pipelines.pipeline_mvadapter_i2mv_sdxl import MVAdapterI2MVSDXLPipeline  # noqa: E402
# новий diffusers прибрав pipe.enable_vae_slicing() — те саме через сам VAE
if not hasattr(MVAdapterI2MVSDXLPipeline, "enable_vae_slicing"):
    MVAdapterI2MVSDXLPipeline.enable_vae_slicing = lambda self: self.vae.enable_slicing()

pipe = prepare_pipeline(base_model=M + "/sdxl-base", vae_model=M + "/sdxl-vae-fp16-fix",
                        unet_model=None, lora_model=None, adapter_path=M + "/mv-adapter",
                        scheduler=None, num_views=6, device="cuda", dtype=torch.float16)
# 16 ГБ мало для UNet + текстових енкодерів разом (OOM 09.11). enable_model_cpu_offload
# не годиться: хуки accelerate копіюють cross_attention_kwargs, і кеш референсу
# (cache_hidden_states) лишається порожнім → KeyError. Тож енкодери — на GPU лише
# на час encode_prompt.
pipe.text_encoder.to("cpu")
pipe.text_encoder_2.to("cpu")
torch.cuda.empty_cache()
_encode = pipe.encode_prompt


def _encode_na_gpu(*a, **k):
    pipe.text_encoder.to("cuda")
    pipe.text_encoder_2.to("cuda")
    try:
        return _encode(*a, **k)
    finally:
        pipe.text_encoder.to("cpu")
        pipe.text_encoder_2.to("cpu")
        torch.cuda.empty_cache()


pipe.encode_prompt = _encode_na_gpu
# пристрій пайплайна — за першим компонентом (енкодер, тепер на CPU) → примусово cuda
type(pipe)._execution_device = property(lambda self: torch.device("cuda"))
ctrl = torch.tensor(np.stack(kontrol), dtype=torch.float16).permute(0, 3, 1, 2).cuda()
ref = Image.open(REF).convert("RGB")
# референс — фігура по центру на сірому, як `preprocess_image`
w, h = ref.size
s = RES * 0.9 / max(w, h)
ref = ref.resize((int(w * s), int(h * s)))
tlo = Image.new("RGB", (RES, RES), (128, 128, 128))
tlo.paste(ref, ((RES - ref.width) // 2, (RES - ref.height) // 2))
images = pipe(OPYS, height=RES, width=RES, num_inference_steps=KROKIV, guidance_scale=3.0,
              num_images_per_prompt=6, control_image=ctrl, control_conditioning_scale=1.0,
              reference_image=tlo, reference_conditioning_scale=1.0,
              negative_prompt="watermark, ugly, deformed, noisy, blurry, low contrast, clothes, belt",
              generator=torch.Generator("cuda").manual_seed(SID)).images
for i, im in enumerate(images):
    im.save("%s/mv-%d.png" % (OUT, i))
print("MV ГОТОВО", OUT)
