// Рогівка ока MPFB (П-285, 11.11.2026) — другий прохід поверх `avatar_eye`.
// Малює лише зовнішню прозору оболонку (альфа 0 у текстурі ока) і лише
// відблиск світла: додається до кадру, самого ока не закриває. Без нього
// око матове й «мертве».
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, ambient_light_disabled, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float gloss_roughness = 0.045;
uniform float gloss = 1.0;

void fragment() {
	if (texture(albedo_tex, UV).a > 0.5) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ROUGHNESS = gloss_roughness;
	SPECULAR = gloss;
	METALLIC = 0.0;
}
