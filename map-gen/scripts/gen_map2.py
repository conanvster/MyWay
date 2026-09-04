import json, sys, time, urllib.request, uuid
SRV = "http://127.0.0.1:8188"
PROMPT = open(sys.argv[1]).read().strip()
JOBS = [tuple(j.split(":")) for j in sys.argv[2].split(",")]   # base_image:seed
DENOISE = float(sys.argv[3]) if len(sys.argv) > 3 else 0.75
import os
STEPS, GUID = 30, float(os.environ.get("GUID", 3.5))
REFINE = float(os.environ.get("REFINE", 0.5))
CFG = float(os.environ.get("CFG", 1.0))
NEG = os.environ.get("NEG", "")

def wf(base, seed):
    return {
      "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
      "2": {"class_type": "DualCLIPLoader", "inputs": {"clip_name1": "t5xxl_fp8_e4m3fn.safetensors", "clip_name2": "clip_l.safetensors", "type": "flux"}},
      "3": {"class_type": "CLIPTextEncode", "inputs": {"text": PROMPT, "clip": ["2", 0]}},
      "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["2", 0]}},
      "4": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["3", 0], "guidance": GUID}},
      "8": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
      "11": {"class_type": "LoadImage", "inputs": {"image": base}},
      "12": {"class_type": "VAEEncode", "inputs": {"pixels": ["11", 0], "vae": ["8", 0]}},
      "6": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["7", 0],
            "latent_image": ["12", 0], "seed": seed, "steps": STEPS, "cfg": CFG,
            "sampler_name": "euler", "scheduler": "beta", "denoise": DENOISE}},
      "13": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["7", 0],
            "latent_image": ["6", 0], "seed": seed + 1, "steps": STEPS, "cfg": CFG,
            "sampler_name": "euler", "scheduler": "beta", "denoise": REFINE}},
      "9": {"class_type": "VAEDecode", "inputs": {"samples": ["13", 0], "vae": ["8", 0]}},
      "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": "worldmap_s%d" % seed}},
    }

def post(p, o):
    r = urllib.request.Request(SRV + p, data=json.dumps(o).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r))

cid = str(uuid.uuid4()); ids = []
for base, s in JOBS:
    s = int(s)
    ids.append((s, post("/prompt", {"prompt": wf(base, s), "client_id": cid})["prompt_id"]))
    print("queued", base, s, flush=True)
t0 = time.time()
for s, pid in ids:
    while True:
        h = json.load(urllib.request.urlopen(SRV + "/history/" + pid))
        if pid in h:
            st = h[pid]["status"]
            if st.get("status_str") == "error":
                print("ERROR seed", s, json.dumps(st)[:900], flush=True)
            else:
                imgs = [i["filename"] for o in h[pid]["outputs"].values() for i in o.get("images", [])]
                print("done seed %d -> %s  (%.0f s)" % (s, ",".join(imgs), time.time() - t0), flush=True)
            break
        time.sleep(5)
