import json, sys, time, urllib.request, uuid

SRV = "http://127.0.0.1:8188"
PROMPT = open(sys.argv[1]).read().strip()
SEEDS = [int(s) for s in sys.argv[2].split(",")]
W, H, STEPS, GUID = 1792, 1152, 28, 3.5

def wf(seed):
    return {
      "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
      "2": {"class_type": "DualCLIPLoader", "inputs": {"clip_name1": "t5xxl_fp8_e4m3fn.safetensors", "clip_name2": "clip_l.safetensors", "type": "flux"}},
      "3": {"class_type": "CLIPTextEncode", "inputs": {"text": PROMPT, "clip": ["2", 0]}},
      "7": {"class_type": "CLIPTextEncode", "inputs": {"text": "", "clip": ["2", 0]}},
      "4": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["3", 0], "guidance": GUID}},
      "5": {"class_type": "EmptySD3LatentImage", "inputs": {"width": W, "height": H, "batch_size": 1}},
      "6": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["7", 0],
            "latent_image": ["5", 0], "seed": seed, "steps": STEPS, "cfg": 1.0,
            "sampler_name": "euler", "scheduler": "beta", "denoise": 1.0}},
      "8": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
      "9": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["8", 0]}},
      "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": "game_map_s%d" % seed}},
    }

def post(path, obj):
    r = urllib.request.Request(SRV + path, data=json.dumps(obj).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r))

cid = str(uuid.uuid4())
ids = []
for s in SEEDS:
    ids.append((s, post("/prompt", {"prompt": wf(s), "client_id": cid})["prompt_id"]))
    print("queued seed", s, flush=True)

t0 = time.time()
for s, pid in ids:
    while True:
        h = json.load(urllib.request.urlopen(SRV + "/history/" + pid))
        if pid in h:
            st = h[pid]["status"]
            if st.get("status_str") == "error":
                print("ERROR seed", s, json.dumps(st)[:800], flush=True); break
            imgs = [i["filename"] for o in h[pid]["outputs"].values() for i in o.get("images", [])]
            print("done seed %d -> %s  (%.0f s total)" % (s, ",".join(imgs), time.time() - t0), flush=True)
            break
        time.sleep(5)
