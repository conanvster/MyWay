// Очі MPFB (П-281, 08.11.2026): окрема сітка з прозорою рогівкою (альфа 0
// у текстурі MakeHuman) — відсікання за альфою, як `transparent True` у
// матеріалі MPFB. Колір райдужки — маскою R (`<модель>_маски-очі.png`)
// множником зі збереженням малюнка, як у `avatar_skin.gdshader`.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D masks_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec3 eye_color = vec3(0.35, 0.22, 0.12);
uniform float eye_mix = 0.0;
uniform float roughness_v = 0.12;

vec3 lin(vec3 v) {
	return pow(max(v, vec3(0.0)), vec3(2.2));
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 c = t.rgb;
	float m = texture(masks_tex, UV).r;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, lin(eye_color) * clamp(0.35 + 1.4 * lum, 0.2, 1.6), m * eye_mix);
	ALBEDO = c;
	ROUGHNESS = roughness_v;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
