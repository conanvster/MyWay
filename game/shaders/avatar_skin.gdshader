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

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec4 m = texture(masks_tex, UV);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float ref_lum = dot(skin_ref, vec3(0.299, 0.587, 0.114));
	float inshe = max(max(m.r, m.b), m.a);
	// шкіра: відношення нового тону до середнього тону текстури
	vec3 shkira = c * (skin_tint / max(skin_ref, vec3(0.02)));
	c = mix(c, shkira, 1.0 - inshe);
	// скальп під зачіскою — колір волосся з тінню текстури
	c = mix(c, hair_color * clamp(0.45 + 0.7 * lum / max(ref_lum, 0.05), 0.2, 1.3), m.a * hair_mix);
	// райдужка
	c = mix(c, eye_color * clamp(0.35 + 1.4 * lum, 0.2, 1.6), m.r * eye_mix);
	// губи
	c = mix(c, lips_color * clamp(0.55 + 0.6 * lum / max(ref_lum, 0.05), 0.3, 1.3), m.b * lips_mix);
	// підводка
	c = mix(c, c * 0.18, m.g * liner);
	ALBEDO = c;
	ROUGHNESS = roughness_v;
}
