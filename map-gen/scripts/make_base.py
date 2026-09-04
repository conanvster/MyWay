from PIL import Image, ImageDraw, ImageFilter
import math, random, sys

SZ = 1408
seed = int(sys.argv[1]); out = sys.argv[2]
random.seed(seed)

SEA    = (156, 176, 178)   # бліда акварельна вода
NORTH  = (233, 233, 228)   # зимові каньйони, білий
NSHAD  = (206, 212, 216)   # крижані тіні
WSNOW  = (226, 224, 214)
WROCK  = (178, 162, 132)   # вохра-скеля
WFOR   = (94, 112, 76)     # темна зелень
CFOR   = (128, 152, 92)    # зелень центру
CMEAD  = (158, 174, 112)   # яскрава зелень лук
CFIELD = (198, 188, 134)   # поля
SAND   = (214, 198, 156)   # плями піску
RIVER  = (124, 154, 168)
VOLC   = (102, 84, 74)
LAVA   = (170, 92, 54)
SWAMP  = (124, 130, 96)
DEAD   = (184, 176, 160)   # мертвий камінь
NECRO  = (158, 152, 142)
SCLIF  = (172, 158, 134)

def wob(t, amp, freq, ph):
    return amp * math.sin(t*freq + ph) + 0.45*amp*math.sin(t*freq*2.7 + ph*1.9)

ph = [random.uniform(0, 6.28) for _ in range(14)]

cx, cy = SZ*0.5, SZ*0.5
N = 110
rr = [random.uniform(0.72, 1.0) for _ in range(N)]
for _ in range(2):
    rr = [(rr[i-1]+rr[i]+rr[(i+1) % N])/3 for i in range(N)]
pts = []
for i in range(N):
    a = 2*math.pi*i/N
    r = SZ*0.475*rr[i]
    pts.append((cx + r*math.cos(a), cy + r*math.sin(a)*0.98))
mask = Image.new("L", (SZ, SZ), 0)
ImageDraw.Draw(mask).polygon(pts, fill=255)
for _ in range(random.randint(4, 8)):
    ix, iy = random.uniform(0.04, 0.96)*SZ, random.uniform(0.04, 0.96)*SZ
    ir = random.uniform(14, 46)
    ImageDraw.Draw(mask).ellipse([ix-ir, iy-ir*0.8, ix+ir, iy+ir*0.8], fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(8)).point(lambda v: 255 if v > 130 else 0)

land = Image.new("RGB", (SZ, SZ)); lp = land.load()
b1, b2, b3 = 0.30, 0.60, 0.81
for x in range(SZ):
    fx = x/SZ
    e1 = b1 + wob(x, 0.040, 0.0055, ph[0])
    e2 = b2 + wob(x, 0.035, 0.0048, ph[1])
    e3 = b3 + wob(x, 0.028, 0.0062, ph[2])
    nb = 0.150 + wob(x, 0.035, 0.0040, ph[3])
    sb = 0.850 + wob(x, 0.035, 0.0044, ph[4])
    for y in range(SZ):
        fy = y/SZ
        if fy < nb:
            c = NSHAD if wob(y, 1.0, 0.030, ph[10]) > 0.7 else NORTH
        elif fy > sb:
            c = SCLIF
        elif fx < e1:
            t = wob(y, 1.0, 0.009, ph[5]) + (e1-fx)*9
            c = WSNOW if t > 1.25 else (WROCK if t > 0.35 else WFOR)
        elif fx < e2:
            t = wob(y, 1.0, 0.011, ph[6]); u = wob(x, 1.0, 0.017, ph[11])
            c = CFIELD if t > 0.75 else (SAND if (t > 0.45 and u > 0.6) else (CMEAD if t > -0.15 else CFOR))
        elif fx < e3:
            t = wob(y, 1.0, 0.015, ph[7])
            c = LAVA if t > 0.95 else (SWAMP if t < -0.75 else VOLC)
        else:
            c = NECRO if wob(y, 1.0, 0.020, ph[8]) > 0.9 else DEAD
        n = random.randint(-6, 6)
        lp[x, y] = tuple(max(0, min(255, v+n)) for v in c)

land = land.filter(ImageFilter.GaussianBlur(6))
d = ImageDraw.Draw(land)
for i in range(4):
    xs = SZ*(b1 + 0.03 + i*0.075)
    d.line([(xs + wob(y, 42, 0.0075, ph[9+i]), y) for y in range(0, SZ, 18)],
           fill=RIVER, width=9, joint="curve")
land = land.filter(ImageFilter.GaussianBlur(3))

img = Image.new("RGB", (SZ, SZ), SEA)
img.paste(land, (0, 0), mask)
img = img.filter(ImageFilter.GaussianBlur(1))
gp = img.load()
for x in range(SZ):
    for y in range(SZ):
        n = random.randint(-14, 14)
        r, g, b = gp[x, y]
        gp[x, y] = (max(0, min(255, r+n)), max(0, min(255, g+n)), max(0, min(255, b+n)))
img.save(out)
print("saved", out)
