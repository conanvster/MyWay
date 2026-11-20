#!/usr/bin/env python3
"""Орк з нуля, крок 1: аркуш референсів із кадру вікі (spec/орк-з-нуля.md, 11.11.2026).

Qwen-Image-Edit 2511 (Lightning 8 кроків): той самий орк лисий, без бороди, у плавках —
тіло спереду в Т-позі й окремо голова великим планом.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_znulia_ref.py <тіло|голова|своє> <вхід.png> \
        <вихід-префікс> [сід ...] [--інстр "…"] [--мп 1.0]
→ <префікс>-s<сід>.png
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import bronia_2var as b2  # noqa: E402

INSTR = {
    "тіло": (
        "Turn this orc into a clean base body reference for 3D modeling. Strict symmetric "
        "T-pose, front view, arms straight out to the sides at shoulder height, palms down, "
        "fingers spread apart, legs straight and slightly apart. Remove all armor, fur, cloak, "
        "pauldron, bracers, belt, pouches, necklace, trousers and boots: bare muscular body, "
        "barefoot, wearing only plain tight black boxer briefs. Shave his head completely bald, "
        "remove the beard and all braids, clean-shaven jaw. Keep his face, lower tusks, pointed "
        "ears, olive green skin, belly and massive heavy build exactly the same. Plain light "
        "grey studio background, soft even shadowless light, whole body from head to feet in "
        "frame, photorealistic."),
    "голова": (
        "Close-up head and neck reference of this same orc for 3D modeling, strict front view, "
        "head upright and level, looking straight at the camera, mouth closed with the two "
        "lower tusks over the upper lip. Shave his head completely bald, remove the beard, "
        "moustache and all braids: clean-shaven jaw and chin, bare neck and bare shoulders, no "
        "armor, no fur, no necklace. Keep his face, heavy wrinkled brow, eyes, nose, tusks, "
        "pointed ears and olive green skin exactly the same, with sharp skin pores and "
        "wrinkles. Plain light grey studio background, soft even shadowless frontal light, "
        "the whole head with both ears and the neck in frame, photorealistic, sharp focus."),
    # орчиха (12.11.2026, слово замовника: «зроби так само орчиху»); волосся — окремими сітками,
    # тож скульпт лисий; білизна — як у чоловіка, плюс проста смуга на грудях
    "тіло-ж": (
        "Turn this orc woman into a clean base body reference for 3D modeling. Keep the strict "
        "symmetric T-pose, front view, arms straight out to the sides at shoulder height, palms "
        "down, fingers spread apart, legs straight and slightly apart. Remove the bracers, belts, "
        "pouches, loincloth and boots: bare athletic muscular body, barefoot, wearing only plain "
        "tight black briefs and a plain tight black bandeau top. Shave her head completely bald, "
        "remove all hair. Keep her face, pointed ears, olive green skin, muscular arms, abs and "
        "strong build exactly the same. Plain light grey studio background without any grid, "
        "soft even shadowless light, whole body from head to feet in frame, photorealistic."),
    "голова-ж": (
        "Close-up head and neck reference of this same orc woman for 3D modeling, strict front "
        "view, head upright and level, looking straight at the camera, mouth closed. Shave her "
        "head completely bald, remove all hair: bare scalp, bare neck and bare shoulders, no "
        "clothes, no jewelry. Keep her face, stern brow, eyes, nose, lips, pointed ears and olive "
        "green skin exactly the same, with sharp skin pores and fine wrinkles. Plain light grey "
        "studio background, soft even shadowless frontal light, the whole head with both ears "
        "and the neck in frame, photorealistic, sharp focus."),
    # ще два обличчя орчихи для вибору аватара (12.11.2026, «більш суворіші», кадри вікі v3 і v1)
    "голова-ж-сувора": (
        "Close-up head and neck reference of this same orc woman for 3D modeling, strict front "
        "view, head upright and level, looking straight at the camera, mouth closed, harsh stern "
        "menacing expression of a seasoned warrior. Shave her head completely bald, remove all "
        "hair and braids: bare scalp, bare neck and bare shoulders, no armor, no clothes, no "
        "jewelry. Keep her face exactly the same: heavy furrowed brow, deep-set eyes, broad nose, "
        "strong jaw, frowning lips, long pointed ears. Even olive green skin of the same tone on "
        "the face, scalp, neck and shoulders, with sharp skin pores. Plain light grey studio "
        "background, soft even shadowless frontal light, the whole head with both ears and the "
        "neck in frame, photorealistic, sharp focus."),
    # сет одягу (12.11.2026, слово замовника: «зроби сет одягу — почни з сету важкої броні для
    # орка», кадр вікі орк-чоловік-v3): перша картинка — наш лисий орк у білизні, друга (--друга) —
    # кадр вікі як зразок обладунку. Поза й тіло ті самі → скульпт вдягненого лягає на скульпт
    # голого, одяг — різниця.
    "сет-важкий-орк": (
        "Dress the bald orc from the first image in the heavy armor of the orc from the second "
        "image: two large layered dark steel pauldrons with thick fur trim, crossed brown leather "
        "chest straps with a buckle, studded leather and iron bracers with fur trim on both "
        "forearms, wide layered brown leather belts with iron buckles, a dark leather loincloth "
        "with studded hanging plates in front and at the sides, tall dark leather boots with fur "
        "tops. Bare chest and belly stay visible. No cloak, no cape, no helmet, no weapon. Keep "
        "the pose, arms, hands, legs, body proportions, bald head, face, skin and camera of the "
        "first image exactly the same. Plain light grey studio background, soft even shadowless "
        "light, whole body from head to feet in frame, photorealistic."),
    # сет по зонах (12.11.2026, `spec/сети-броні-дослідження.md`): великий план однієї частини
    # нашого тіла в одній речі з кадру вікі (--друга); решта тіла гола — за шкірою річ суміщається
    "зона-чоботи-орк": (
        "Put the boots of the orc from the second image on the legs from the first image: tall "
        "heavy dark leather boots reaching just below the knees, with a thick shaggy fur trim "
        "around the top, leather straps, iron buckles and studs, thick soles, closed toes. Keep "
        "the bare green thighs and knees, the black briefs, the pose of the legs and the camera "
        "of the first image exactly the same. No loincloth, no belt, no trousers, no cloak. Plain "
        "light grey studio background, soft even shadowless light, both legs and boots fully in "
        "frame, photorealistic, sharp detailed leather, fur and metal."),
    # людина-чоловік (19.11.2026, слово замовника «так - роби» на димовий прогін одягу): чоботи
    # з кадру вікі людина-чоловік-v1 на ноги нашої людини з нуля
    "зона-чоботи-людина": (
        "Put the boots of the man from the second image on the legs from the first image: tall "
        "dark brown leather boots reaching just below the knees, with a folded cuff at the top, "
        "leather straps with iron buckles, visible stitching, thick heels and soles, closed toes. "
        "Keep the bare thighs and knees, the skin tone, the black briefs, the hands, the pose of "
        "the legs and the camera of the first image exactly the same. No trousers, no belt, no "
        "cloak. Plain light grey studio background, soft even shadowless light, both legs and "
        "boots fully in frame, photorealistic, sharp detailed leather, stitching and metal."),
    "зона-наручі-людина": (
        "Put the bracer of the man from the second image on the forearm of the arm from the first "
        "image: a thick brown leather bracer with tooled patterns, three leather straps with small "
        "iron buckles, lacing on the side and stitched edges, covering the forearm from the wrist "
        "to just below the elbow. The elbow, upper arm, hand and fingers keep exactly the same "
        "bare light skin as in the first image. Keep the pose and the camera of the first image "
        "exactly the same. No glove, no sleeve, no other armor, no body behind the arm. Plain "
        "light grey studio background, soft even shadowless light, photorealistic, sharp "
        "detailed leather, metal and stitching."),
    "зона-наплічники-людина": (
        "Put leather shoulder armor in the style of the man from the second image on the bald man "
        "from the first image: two layered dark brown leather pauldrons with stitched edges and "
        "small iron rivets covering the shoulders, and one brown leather strap running diagonally "
        "across the chest from the right shoulder to the left hip, with an iron buckle. Bare "
        "chest, belly, neck and arms stay visible. No shirt, no vest, no cloak, no cape, no "
        "helmet, no hair, no beard. Keep the pose, body, bald head, face and camera of the first "
        "image exactly the same. Plain light grey studio background, soft even shadowless light, "
        "photorealistic, sharp detailed leather, metal and stitching."),
    # пояс людини, друга спроба (20.11.2026): у першій генератор лишив чорні труси відкритими й
    # повісив пластини на ремінцях стегон — у річ пішли труси й клапті шкіри
    "зона-пояс-людина": (
        "Replace the black briefs from the first image with a heavy leather battle skirt in the "
        "style of the man from the second image: a wide dark brown leather belt with a large iron "
        "buckle at the waist, and below it a skirt of overlapping vertical riveted dark brown "
        "leather strips hanging all around the hips, front, sides and back, down to the middle of "
        "the thighs. The skirt fully covers the hips and the groin, no black fabric is visible "
        "anywhere. No straps around the thighs, no pouches. Keep the bare belly, the bare thighs "
        "below the skirt, the hands, the skin tone, the pose and the camera of the first image "
        "exactly the same. Plain light grey studio background, soft even shadowless light, "
        "photorealistic, sharp detailed leather, rivets and stitching."),
    "зона-наручі-орк": (
        "Put the bracer of the orc from the second image on the forearm of the arm from the first "
        "image: a heavy bracer of dark leather and iron plates with rows of rivets, engraved iron "
        "bands, leather straps with buckles and lacing, and a short fur trim at the elbow end, "
        "covering the forearm from the wrist to just below the elbow. This is the arm of a green "
        "orc: the elbow, upper arm, hand, fingers and body keep exactly the same olive green skin "
        "as in the first image, no pink or human skin anywhere. Keep the pose and the camera of "
        "the first image exactly the same. No glove, no other armor. Plain light grey studio background, soft even shadowless "
        "light, photorealistic, sharp detailed leather, metal and stitching."),
    "зона-наплічники-орк": (
        "Put the shoulder armor of the orc from the second image on the bald orc from the first "
        "image: two large layered dark steel pauldrons with riveted edges and engraved trim, a "
        "short fur lining under them, and two crossed brown leather chest straps with stitching, "
        "rivets and an iron ring buckle in the middle of the chest. Bare chest, belly, neck and "
        "arms stay visible. No cloak, no cape, no helmet, no hair, no beard, no necklace. Keep the "
        "pose, body, bald head, face and camera of the first image exactly the same. Plain light "
        "grey studio background, soft even shadowless light, photorealistic, sharp detailed "
        "metal, leather and stitching."),
    "зона-пояс-орк": (
        "Put the belt and loincloth of the orc from the second image on the hips from the first "
        "image: wide layered brown leather belts with stitching, rivets and a large iron buckle, "
        "small leather pouches, and a dark leather loincloth of hanging studded leather plates "
        "with iron trim in front, at the sides and at the back, reaching the middle of the thighs "
        "and fully covering the black briefs. Keep the bare green belly, thighs, hands, the pose "
        "and the camera of the first image exactly the same. No cloak, no trousers, no boots. "
        "Plain light grey studio background, soft even shadowless light, photorealistic, sharp "
        "detailed leather, metal and stitching."),
    # важкий сет ельфа-чоловіка v1 (20.11.2026, слово замовника: «вдягай в броню ельф чоловік»):
    # ті самі речі, що й у людини, на блідому стрункому ельфі; кадр вікі ельф-чоловік-v1
    "зона-чоботи-ельф": (
        "Put the boots of the elf from the second image on the legs from the first image: tall "
        "dark brown leather boots reaching just below the knees, with a folded cuff at the top, "
        "leather straps with iron buckles, visible stitching, thick heels and soles, closed toes. "
        "The boots are slim and fit the long thin legs closely. Keep the bare thighs and knees, "
        "the pale skin tone, the hands, the pose of the legs and the camera of the first image "
        "exactly the same. No trousers, no belt, no cloak. Plain light grey studio background, "
        "soft even shadowless light, both legs and boots fully in frame, photorealistic, sharp "
        "detailed leather, stitching and metal."),
    "зона-наручі-ельф": (
        "Put the bracer of the elf from the second image on the forearm of the arm from the first "
        "image: a thick brown leather bracer with tooled leaf patterns, three leather straps with "
        "small iron buckles, lacing on the side and stitched edges, covering the forearm from the "
        "wrist to just below the elbow, fitting the slim forearm closely. The elbow, upper arm, "
        "hand and fingers keep exactly the same bare pale skin as in the first image. Keep the "
        "pose and the camera of the first image exactly the same. No glove, no sleeve, no other "
        "armor, no body behind the arm. Plain light grey studio background, soft even shadowless "
        "light, photorealistic, sharp detailed leather, metal and stitching."),
    "зона-наплічники-ельф": (
        "Put leather shoulder armor in the style of the elf from the second image on the bald elf "
        "man from the first image: two layered dark brown leather pauldrons with stitched edges "
        "and small iron rivets covering the shoulders, and one brown leather strap running "
        "diagonally across the chest from the right shoulder to the left hip, with an iron "
        "buckle. Bare chest, belly, neck and arms stay visible. No shirt, no vest, no cloak, no "
        "cape, no helmet, no hair, no belt. Keep the slender body, pale skin, bald head, pointed "
        "ears, face, pose and camera of the first image exactly the same. Plain light grey studio "
        "background, soft even shadowless light, photorealistic, sharp detailed leather, metal "
        "and stitching."),
    "зона-пояс-ельф": (
        "Replace the black briefs from the first image with a heavy leather battle skirt in the "
        "style of the elf from the second image: a wide dark brown leather belt with a large iron "
        "buckle at the waist, and below it a skirt of overlapping vertical riveted dark brown "
        "leather strips hanging all around the hips, front, sides and back, down to the middle of "
        "the thighs. The skirt fully covers the hips and the groin, no black fabric is visible "
        "anywhere. No straps around the thighs, no pouches. Keep the bare belly, the bare thighs "
        "below the skirt, the hands, the pale skin tone, the pose and the camera of the first "
        "image exactly the same. Plain light grey studio background, soft even shadowless light, "
        "photorealistic, sharp detailed leather, rivets and stitching."),
    # важкий сет людини-жінки, картка 1 — пілот Б (20.11.2026, слово замовника: «вдягай в броню
    # людину жінку»): вхід — рендер моделі (tools/blender/kadr_tila.py), кадр вікі людина-жінка-v1
    "зона-чоботи-людина-жінка": (
        "Put the boots of the woman from the second image on the legs from the first image: tall "
        "dark brown leather boots reaching just below the knees, with a folded cuff at the top, "
        "leather straps with iron buckles, visible stitching, low heels and sturdy soles, closed "
        "toes, fitting the slim legs closely. Keep the bare thighs and knees, the skin tone, the "
        "hands, the pose of the legs and the camera of the first image exactly the same. No "
        "trousers, no belt, no cloak. Plain light grey studio background, soft even shadowless "
        "light, both legs and boots fully in frame, photorealistic, sharp detailed leather, "
        "stitching and metal."),
    "зона-наручі-людина-жінка": (
        "Put the bracer of the woman from the second image on the forearm of the arm from the "
        "first image: a thick brown leather bracer with tooled patterns, three leather straps with "
        "small iron buckles, lacing on the side and stitched edges, covering the forearm from the "
        "wrist to just below the elbow, fitting the slim forearm closely. The elbow, upper arm, "
        "hand and fingers keep exactly the same bare skin as in the first image. Keep the pose and "
        "the camera of the first image exactly the same. No glove, no sleeve, no other armor, no "
        "body behind the arm. Plain light grey studio background, soft even shadowless light, "
        "photorealistic, sharp detailed leather, metal and stitching."),
    "зона-наплічники-людина-жінка": (
        "Put leather shoulder armor in the style of the woman from the second image on the bald "
        "woman from the first image: two layered dark brown leather pauldrons with stitched edges "
        "and small iron rivets covering the shoulders, and one brown leather strap running "
        "diagonally across the chest from the right shoulder to the left hip over the dark top, "
        "with an iron buckle. The dark grey bandeau top, bare belly, neck and arms stay visible. "
        "No shirt, no vest, no cloak, no cape, no helmet, no hair, no belt. Keep the pose, body, "
        "bald head, face and camera of the first image exactly the same. Plain light grey studio "
        "background, soft even shadowless light, photorealistic, sharp detailed leather, metal "
        "and stitching."),
    # панцир жінки = наплічники + захист грудей (20.11.2026, слово замовника: «якщо для чоловіків
    # панцир достатньо тільки наплічників то для жінки доцільно зробити … наплічники + захист грудей»)
    "зона-панцир-людина-жінка": (
        "Replace the dark grey bandeau top of the bald woman from the first image with leather "
        "chest armor in the style of the woman from the second image: a fitted cuirass of hardened "
        "dark brown leather that fully covers the chest and the upper belly down to just below the "
        "ribs, front, sides and back, shaped to a female figure, with stitched edges, small iron "
        "rivets and side straps with iron buckles, and two layered dark brown leather pauldrons "
        "with stitched edges and rivets covering the shoulders. No grey fabric is visible anywhere. "
        "The lower belly, the navel, the neck and the arms stay bare. No shirt, no sleeves, no "
        "cloak, no cape, no helmet, no hair, no belt, no skirt. Keep the pose, body, bald head, "
        "face and camera of the first image exactly the same. Plain light grey studio background, "
        "soft even shadowless light, photorealistic, sharp detailed leather, metal and stitching."),
    "зона-пояс-людина-жінка": (
        "Replace the dark grey briefs from the first image with a heavy leather battle skirt in "
        "the style of the woman from the second image: a wide dark brown leather belt with a large "
        "iron buckle at the waist, and below it a skirt of overlapping vertical riveted dark brown "
        "leather strips hanging all around the hips, front, sides and back, down to the middle of "
        "the thighs. The skirt fully covers the hips and the groin, no grey fabric is visible "
        "anywhere. No straps around the thighs, no pouches. Keep the bare belly, the bare thighs "
        "below the skirt, the hands, the skin tone, the pose and the camera of the first image "
        "exactly the same. Plain light grey studio background, soft even shadowless light, "
        "photorealistic, sharp detailed leather, rivets and stitching."),
    # ельфійки (12.11.2026, слово замовника: «зроби ельфійок», кадри вікі ельф-жінка-v1..v3):
    # одне тіло (з v1) і три обличчя; висока тендітна (пам'ятка про пропорції ельфійки)
    "тіло-ельф-ж": (
        "Turn this elf woman into a clean base body reference for 3D modeling. Strict symmetric "
        "T-pose, front view, arms straight out to the sides at shoulder height, palms down, "
        "fingers spread apart, legs straight and slightly apart. Remove the shirt, vest, belts, "
        "bracers, trousers and boots: bare body, barefoot, wearing only plain tight black briefs "
        "and a plain tight black bandeau top. Shave her head completely bald, remove all hair. "
        "She is very tall and slender with long thin legs, narrow hips, narrow shoulders, thin "
        "arms and a long neck; crotch at half of her height. Keep her face, small pointed ears and "
        "pale fair skin exactly the same. Plain light grey studio background, soft even "
        "shadowless light, whole body from head to feet in frame, photorealistic."),
    "голова-ельф-ж": (
        "Close-up head and neck portrait of this same elf woman for 3D modeling, strict front "
        "view, head upright and level, looking straight at the camera, mouth closed, calm serious "
        "expression. She is a young woman: delicate feminine face, smooth pale fair skin, thin "
        "light eyebrows, slender long neck and narrow bare shoulders. Shave her head completely "
        "bald, remove all hair, remove clothes and jewelry. Keep her own facial features, eyes, "
        "nose, lips, cheekbones and small pointed ears exactly the same as in the image. Even "
        "skin tone on face, scalp, neck and shoulders. Plain light grey studio background, soft "
        "even shadowless frontal light, the whole head with both ears and the neck in frame, "
        "photorealistic, sharp focus."),
}


def arg(k, typ, d):
    return typ(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d


def main():
    vyd, vhid, pref = sys.argv[1], sys.argv[2], sys.argv[3]
    instr = arg("--інстр", str, INSTR.get(vyd))
    sidy = [int(a) for a in sys.argv[4:] if a.isdigit()] or [5101]
    kadr = m.stage(vhid)
    druha = m.stage(arg("--друга", str, "")) if "--друга" in sys.argv else None
    for sd in sidy:
        kudy = "%s-s%d.png" % (pref, sd)
        if os.path.exists(kudy):
            continue
        g = b2.graf_qwen(kadr, kadr, instr, sd, "ork_znulia")
        g["1"]["inputs"]["unet_name"] = "qwen-image-edit-2511-Q4_K_M.gguf"
        g["2"]["inputs"]["lora_name"] = "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
        if druha:                           # друга картинка — зразок (одяг із кадру вікі)
            g["8"]["inputs"]["image"] = druha
        else:
            for n in ("9", "10"):
                g[n]["inputs"].pop("image2", None)
        g["7"]["inputs"]["resolution_steps"] = 1
        g["7"]["inputs"]["megapixels"] = arg("--мп", float, 1.0)
        done = m.run(g)
        out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
        print("готово", kudy, flush=True)
    m.free()


if __name__ == "__main__":
    main()
