// Волосся аватара картками (П-285, 11.11.2026).
// Світло рахується ВЗДОВЖ волосини (модель Каджії–Кея), а не за нормаллю
// картки: сусідні картки з різним нахилом більше не дають «латок», а відблиск
// іде смугою впоперек пасом, як у справжнього волосся. Дві смуги відблиску:
// біла ближче до кінчика й кольорова ближче до кореня; зсув — свій у кожної
// волосини. Волосина йде вздовж V розгортки (корінь — V=0).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 hair_color : source_color = vec3(0.36, 0.21, 0.12);
uniform float scissor = 0.4;
uniform float root_dark = 0.55;       // корені темніші (тінь від сусідніх пасом)
uniform float strand_var = 0.22;      // різниця тону між волосинами
uniform float gloss1 = 0.10;          // біла смуга
uniform float gloss2 = 0.55;          // кольорова смуга
uniform float shift1 = 0.06;
uniform float shift2 = -0.14;
uniform float wrap = 0.5;             // наскільки світло огинає зачіску
uniform float strands_u = 96.0;
uniform float card_var = 1.0;          // різниця тону між картками (нові картки, UV2)       // волосин упоперек текстури (для зсуву й тону)

varying vec3 strand_t;                // напрям волосини, простір виду
varying float strand_id;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// здалеку тонкі волосини розмиваються в міпах і зачіска рідшає — підсилити
	float lod = textureQueryLod(albedo_tex, UV).x;
	t.a = clamp(t.a * (1.0 + 0.8 * lod), 0.0, 1.0);
	// номер картки — у другій розгортці (нові картки); у старих її немає
	float id = fract(hash(floor(UV.x * strands_u)) * 0.5 + UV2.x * card_var);
	float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	vec3 c = hair_color * (0.34 + 0.42 * lum);
	c *= 1.0 + strand_var * (id - 0.5) * 2.0;
	c *= mix(root_dark, 1.0, smoothstep(0.0, 0.3, UV.y));
	ALBEDO = c;
	ROUGHNESS = 0.6;
	strand_t = normalize(BINORMAL);
	strand_id = id;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
}

float smuha(vec3 t, vec3 h, float hostrota) {
	float th = dot(t, h);
	float s = sqrt(max(0.0, 1.0 - th * th));
	return smoothstep(-1.0, 0.0, th) * pow(s, hostrota);
}

void light() {
	vec3 t = normalize(strand_t);
	float tl = dot(t, LIGHT);
	float vzdovzh = sqrt(max(0.0, 1.0 - tl * tl));
	// м'яке огинання: щоб тильний бік зачіски не світився, як лицьовий
	float nl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float ogyn = mix(1.0 - wrap, 1.0, nl);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (0.2 + 0.5 * vzdovzh) * ogyn / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float zs = (strand_id - 0.5) * 0.12;
	vec3 t1 = normalize(t + NORMAL * (shift1 + zs));
	vec3 t2 = normalize(t + NORMAL * (shift2 + zs));
	vec3 vidbl = vec3(gloss1) * smuha(t1, h, 110.0) + ALBEDO * (gloss2 * 1.6) * smuha(t2, h, 38.0);
	SPECULAR_LIGHT += ATTENUATION * LIGHT_COLOR * vidbl * ogyn;
}
