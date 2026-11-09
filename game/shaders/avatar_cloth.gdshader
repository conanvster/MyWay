// Одяг аватара (П-281, крок 4, 08.11.2026): колір і матеріал дає річ
// (`вигляд` у items.json — «колір», «текстура», «масштаб», «шорсткість»),
// а крій — частина моделі: її власна картинка дає лише світлотінь (шви,
// складки, строчки — яскравість відносно середньої, без барви), її карта
// нормалей — рельєф. Без власної картинки — як `_cloth` раніше: колір ×
// плитка матеріалу.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 item_color : source_color = vec4(0.54, 0.48, 0.38, 1.0);
uniform sampler2D item_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_item_tex = false;
uniform float item_scale = 4.0;
uniform sampler2D own_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_own_tex = false;
uniform float own_mean = 0.5;          // звична (медіанна) яскравість власної картинки
uniform float own_strength = 0.7;
uniform sampler2D own_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_own_normal = false;
uniform float roughness_v = 0.9;
uniform float metallic_v = 0.0;        // «метал» у вигляді речі (сталь, латунь)

void fragment() {
	vec3 c = item_color.rgb;
	if (has_item_tex) {
		c *= texture(item_tex, UV * item_scale).rgb;
	}
	if (has_own_tex) {
		vec3 o = texture(own_tex, UV).rgb;
		float l = dot(o, vec3(0.299, 0.587, 0.114)) / max(own_mean, 0.02);
		c *= mix(1.0, clamp(l, 0.0, 2.2), own_strength);
	}
	ALBEDO = c;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	if (has_own_normal) {
		NORMAL_MAP = texture(own_normal, UV).rgb;
	}
}
