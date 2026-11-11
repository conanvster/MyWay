// Шкіра аватара з масками рис (12.10.2026, слово замовника: «Очі різного
// кольору та контурів … Колір зачіски … Колір скіна»).
//
// Маски — `<модель>_маски.png` (tools/maski_oblychchia.py → avatar_build.py):
// R райдужка, G підводка, B губи, A волосся на голові (скальп). Кольори —
// множником зі збереженням світлотіні оригінальної текстури.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D masks_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec3 skin_ref = vec3(0.80, 0.68, 0.62);   // середній тон шкіри текстури
uniform vec3 skin_tint = vec3(0.80, 0.68, 0.62);  // = skin_ref — без змін
uniform vec3 hair_color = vec3(0.90, 0.90, 0.88);
uniform float hair_mix = 0.0;
uniform vec3 eye_color = vec3(0.35, 0.22, 0.12);
uniform float eye_mix = 0.0;
uniform float liner = 0.0;                          // 0 — як є, 1 — темна підводка
uniform vec3 lips_color = vec3(0.70, 0.35, 0.35);
uniform float lips_mix = 0.0;
uniform float roughness_v = 0.6;
uniform float lips_skin = 0.0;
// людина MPFB (09.11.2026): текстури MakeHuman світлі (≈208,162,135 sRGB) —
// під сонцем гри шкіра виходила білою; приглушення й м'яке підповерхневе
// розсіювання (шкіра не пластик).
uniform float skin_gain = 1.0;
uniform float sss = 0.0;
// дрібний рельєф шкіри (вени, шрами, м'язи) — карта нормалей у розгортці
// (`tools/blender/projektsiia.py`, пілот орка 09.11.2026)
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform bool has_normal = false;
uniform float normal_depth = 1.0;
// тіло під вдягненою річчю (кольори вершин `під_одяг`, людина MPFB)
uniform vec4 hide_under = vec4(0.0);                      // 1 — губи беруть тон шкіри (людина MPFB)
// Карти шкіри (П-285, 11.11.2026; `tools/blender/shkira_karty.py`): R — затінення
// в заглибинах, G — «тонке» (вуха, крила носа, пальці — світло йде наскрізь),
// B — опуклість (0,5 — рівно; чоло, ніс, вилиці блищать, заглибини матові).
uniform sampler2D maps_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform bool has_maps = false;
// пори — плиткова карта нормалей, одна на гру; здалеку згасає (не мерехтить)
uniform sampler2D pores_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_pores = false;
uniform float pores_scale = 190.0;
uniform float pores_depth = 0.2;
uniform float specular_v = 0.42;
uniform float lips_wet = 0.55;                     // губи гладші за шкіру
uniform vec3 scatter_color : source_color = vec3(0.86, 0.20, 0.12);
uniform float backlight = 1.0;                     // просвічування тонкого проти світла

// Кольори з палітри й середній тон текстури — у sRGB (як у меню), а
// текстура тут уже лінійна. Без переведення вибраний колір виходив
// блідим: оливкова шкіра орка ставала майже білою (07.11.2026).
vec3 lin(vec3 v) {
	return pow(max(v, vec3(0.0)), vec3(2.2));
}

void fragment() {
	if (dot(COLOR, hide_under) > 0.5) {
		discard;
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 ref_l = lin(skin_ref);
	vec4 m = texture(masks_tex, UV);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float ref_lum = dot(ref_l, vec3(0.299, 0.587, 0.114));
	float inshe = max(max(m.r, m.b * (1.0 - lips_skin)), m.a);
	// шкіра: відношення нового тону до середнього тону текстури
	vec3 shkira = c * (lin(skin_tint) / max(ref_l, vec3(0.002)));
	c = mix(c, shkira, 1.0 - inshe);
	// скальп під зачіскою — колір волосся з тінню текстури
	c = mix(c, lin(hair_color) * clamp(0.45 + 0.7 * lum / max(ref_lum, 0.05), 0.2, 1.3), smoothstep(0.3, 0.85, m.a) * hair_mix);
	// райдужка
	c = mix(c, lin(eye_color) * clamp(0.35 + 1.4 * lum, 0.2, 1.6), m.r * eye_mix);
	// губи
	c = mix(c, lin(lips_color) * clamp(0.55 + 0.6 * lum / max(ref_lum, 0.05), 0.3, 1.3), m.b * lips_mix);
	// підводка
	c = mix(c, c * 0.18, m.g * liner);
	vec3 k = has_maps ? texture(maps_tex, UV).rgb : vec3(1.0, 0.0, 0.5);
	float conv = (k.b - 0.5) * 2.0;
	// у заглибинах і тонких місцях шкіра червоніша (кров ближче)
	c = mix(c, c * vec3(1.06, 0.90, 0.86), clamp((1.0 - k.r) * 0.6 + k.g * 0.25, 0.0, 0.6));
	ALBEDO = c * mix(1.0, skin_gain, 1.0 - m.r);
	float rough = roughness_v - 0.17 * clamp(conv, 0.0, 1.0) + 0.10 * clamp(-conv, 0.0, 1.0);
	rough = mix(rough, 0.34, m.b * lips_wet);
	ROUGHNESS = clamp(rough, 0.28, 0.95);
	// скальп під зачіскою — матовий: блиск шкіри крізь рідкі картки читався сивою плямою
	float skalp = smoothstep(0.3, 0.85, m.a) * hair_mix;
	ROUGHNESS = mix(ROUGHNESS, 0.95, skalp);
	SPECULAR = specular_v * mix(0.55, 1.0, k.r) * (1.0 - 0.85 * skalp);
	if (has_maps) {
		AO = k.r;
		AO_LIGHT_AFFECT = 0.3;
	}
	vec3 n = vec3(0.0, 0.0, 1.0);
	if (has_normal) {
		n = texture(normal_tex, UV).rgb * 2.0 - 1.0;
		n.xy *= normal_depth;
	}
	if (has_pores) {
		float blyzko = 1.0 - smoothstep(1.0, 3.5, -VERTEX.z);
		vec3 pr = texture(pores_tex, UV * pores_scale).rgb * 2.0 - 1.0;
		n.xy += pr.xy * pores_depth * blyzko * (1.0 - m.b);
	}
	if (has_normal || has_pores) {
		NORMAL_MAP = normalize(n) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 1.0;
	}
	if (sss > 0.0) {
		SSS_STRENGTH = sss * mix(1.0, 1.5, k.g);
		if (has_maps && backlight > 0.0) {
			// стримано: на повну силу вухо проти контрового світла ставало білим
			SSS_TRANSMITTANCE_COLOR = vec4(scatter_color, clamp(k.g * backlight * 0.45, 0.0, 1.0));
			SSS_TRANSMITTANCE_DEPTH = 0.06;
			SSS_TRANSMITTANCE_BOOST = 0.08 * k.g;
		}
	}
}
