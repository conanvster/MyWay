// Очі MPFB (П-281, 08.11.2026; переписано П-285, 11.11.2026).
// Сітка ока — дві оболонки: внутрішня куля з білком і райдужкою та зовнішня
// прозора «рогівка» (у текстурі MakeHuman — альфа 0). Тут — внутрішня куля:
// райдужка з темним краєм і глибиною, білок із тінню від верхньої повіки.
// Рогівку малює другий прохід `avatar_cornea.gdshader` (лише відблиск).
// Колір райдужки — маскою R (`<модель>_маски-очі.png`) зі збереженням малюнка.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D masks_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec3 eye_color = vec3(0.35, 0.22, 0.12);
uniform float eye_mix = 0.0;
uniform float roughness_v = 0.3;
// центри райдужок у розгортці ока MakeHuman і їхній радіус
uniform vec2 iris_a = vec2(0.29, 0.71);
uniform vec2 iris_b = vec2(0.705, 0.297);
uniform float iris_r = 0.113;
uniform float limbus = 0.6;            // темний край райдужки
uniform float lid_shadow = 0.5;        // тінь верхньої повіки на яблуці
uniform float iris_depth = 0.035;      // «заглиблення» райдужки під рогівкою

vec3 lin(vec3 v) {
	return pow(max(v, vec3(0.0)), vec3(2.2));
}

void fragment() {
	vec2 uv = UV;
	vec2 cen = distance(uv, iris_a) < distance(uv, iris_b) ? iris_a : iris_b;
	float d = distance(uv, cen) / iris_r;
	// райдужка лежить глибше за рогівку: малюнок зсувається проти погляду
	if (d < 1.0) {
		vec3 vt = vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL));
		uv -= vt.xy / max(vt.z, 0.35) * iris_depth * iris_r * (1.0 - d * d);
		d = distance(uv, cen) / iris_r;
	}
	vec4 t = texture(albedo_tex, uv);
	vec3 c = t.rgb;
	float m = texture(masks_tex, uv).r;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, lin(eye_color) * clamp(0.35 + 1.4 * lum, 0.2, 1.6), m * eye_mix);
	// темний край райдужки й м'який перехід у білок
	c *= 1.0 - limbus * smoothstep(0.72, 1.0, d) * (1.0 - smoothstep(1.0, 1.12, d));
	// білок: до кутів ока тепліший і темніший
	float bilok = smoothstep(1.1, 2.4, d);
	c = mix(c, c * vec3(0.86, 0.78, 0.76), bilok * 0.6);
	// тінь повіки: верх видимої частини яблука дивиться вгору
	float vhoru = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	c *= 1.0 - lid_shadow * smoothstep(0.02, 0.45, vhoru);
	ALBEDO = c;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.3;
	SSS_STRENGTH = 0.15 * step(1.05, d);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
