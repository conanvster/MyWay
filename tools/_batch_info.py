import re, json, sys, html as ihtml

start, end = int(sys.argv[1]), int(sys.argv[2])

html_s = open('wiki/monstry-vyglyad.html', encoding='utf-8').read()
articles = re.findall(r'<article class="card" id="m(\d+)">(.*?)</article>', html_s, re.S)
cards = {}
for i, block in articles:
    i = int(i)
    name = ihtml.unescape(re.search(r'<h3>(.*?)</h3>', block).group(1))
    meta = re.search(r'<div class="meta">(.*?)</div>', block, re.S).group(1)
    grade = re.search(r'g-([A-Z]+)', meta).group(1)
    lvl = re.search(r'рівень (\d+)', meta).group(1)
    cards[i] = (name, grade, lvl)

d = json.load(open('spec/бестіарій.json'))
byname = {m['назва']: m for m in d}

existing = set()
try:
    import os
    existing = set(os.listdir('wiki/img/monstry'))
except FileNotFoundError:
    pass

for i in range(start, end+1):
    name, grade, lvl = cards[i]
    already = any(name + ext in existing for ext in ('.png', '.jpg', '.webp'))
    m = byname[name]
    print('===', i, name, '| рівень', lvl, '| grade', grade, '| де', m['де'], '| конвеєр', m['конвеєр'], '| ВЖЕ Є' if already else '')
    if already:
        continue
    print('опис:', m['опис'])
    om = m['опис моделі']
    for k in ['голова','тулуб','кінцівки','хвіст','амуніція','зброя']:
        v = om.get(k)
        if v: print(' ', k+':', v)
