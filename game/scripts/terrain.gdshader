shader_type spatial;
render_mode diffuse_burley;

// Земля світу версії 2 — фотографічні шари, змішані за вагами.
//
// Слово замовника 11.09.2026: «пошукай рішення схожі на Lineage 2 для
// красивого дизайну поверхонь… на більш реалістичному ґрунті». Lineage 2
// (Unreal Engine 2) малював землю саме так: кілька шарів текстур, і в
// кожній точці рельєфу своя вага кожного шару. Тут те саме: вісім-
// дев'ять фото ambientCG (CC0) у масиві, ваги лежать у вершинах землі
// (COLOR, CUSTOM0, CUSTOM1 — по чотири шари), а шейдер змішує.
//
// Три речі понад просте змішування, і всі три — проти «пласкої
// заливки», яку було видно раніше:
// - змішування ЗА ВИСОТОЮ текстури: трава заходить у щілини між
//   камінням, а не просвічує крізь нього напівпрозорою плямою;
// - друга вибірка кожного шару, повернута й утричі більша, — ламає
//   повтор, який згори видно як шахівницю;
// - скеля й щебінь кладуться з трьох боків (трипланарно): на крутому
//   схилі текстура інакше витягується смугами.

uniform sampler2DArray layer_color : source_color,
		filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_normal : filter_linear_mipmap_anisotropic,
		repeat_enable;
uniform sampler2DArray layer_height : filter_linear_mipmap, repeat_enable;
uniform float layer_size[12];
uniform float layer_rough[12];
// Множник кольору кожного шару. Фото знято при своєму світлі: підстилка
// Ground048 під нашим сонцем рожевіла, щебінь Ground022 здалеку білів
// (знімки 11.09.2026). Правимо тут, а не перефарбуванням файлу, —
// число видно й міняється одним рядком у `ground_paint.gd`.
uniform vec3 layer_tint[12];
uniform int layer_count = 9;
// Які шари кладуться з трьох боків (щебінь і скеля).
uniform int side_from = 4;
uniform int side_to = 5;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float macro_size = 70.0;
uniform float macro_power = 0.16;
// Наскільки глибоко один шар заходить в інший за висотою текстури.
uniform float blend_depth = 0.18;
uniform float normal_power = 1.0;
// Стежки (слово замовника 11.09.2026: «серед лісу із стежкою»). На
// сітці вершин 8 м трьохметрову стежку не намалювати — вона розпливлась
// би на шістнадцять. Тому окреме поле ВІДСТАНІ до найближчої стежки з
// кроком 4 м: відстань між пікселями змішується майже без похибки, і
// край стежки ріжеться тут, у шейдері, до сантиметрів.
uniform sampler2D path_field : filter_linear, repeat_disable;
uniform vec2 path_origin = vec2(0.0);
uniform float path_extent = 1.0;    // метрів, які покриває поле
uniform float path_range = 16.0;    // метрів, що відповідають 1,0 у полі
uniform float path_half = 1.4;      // пів ширини стежки
uniform int path_layer = 9;

varying vec3 world_pos;
varying vec3 world_up;
varying vec4 mix_a;
varying vec4 mix_b;
varying vec4 mix_c;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mix_a = COLOR;
	mix_b = CUSTOM0;
	mix_c = CUSTOM1;
}

vec2 turned(vec2 p) {
	return vec2(0.676 * p.x - 0.737 * p.y, 0.737 * p.x + 0.676 * p.y);
}

void fragment() {
	float w[12];
	w[0] = mix_a.r; w[1] = mix_a.g; w[2] = mix_a.b; w[3] = mix_a.a;
	w[4] = mix_b.r; w[5] = mix_b.g; w[6] = mix_b.b; w[7] = mix_b.a;
	w[8] = mix_c.r; w[9] = mix_c.g; w[10] = mix_c.b; w[11] = mix_c.a;

	// Стежка: витісняє решту шарів. Край рваний — шум на пів метра, як
	// у справжньої стежки, яку протоптали, а не проклали під шнур.
	if (path_layer < layer_count) {
		vec2 at = (world_pos.xz - path_origin) / path_extent;
		float gap = texture(path_field, at).r * path_range;
		float rag = texture(macro_noise, world_pos.xz / 7.0).r - 0.5;
		float trod = 1.0 - smoothstep(path_half - 0.5, path_half + 0.6,
				gap + rag * 1.1);
		for (int i = 0; i < 12; i++) {
			w[i] *= 1.0 - trod;
		}
		w[path_layer] += trod * 1.2;
		// Узбіччя: смуга витоптаної трави з ґрунтом обабіч.
		float verge = (1.0 - smoothstep(path_half + 0.4, path_half + 2.4,
				gap + rag)) * (1.0 - trod);
		w[1] += verge * 0.5;
	}

	float far = smoothstep(20.0, 90.0,
			length(world_pos - CAMERA_POSITION_WORLD));
	vec3 up = normalize(world_up);
	vec3 side = pow(abs(up), vec3(4.0));
	side /= side.x + side.y + side.z;

	vec3 col[12];
	vec3 bump[12];
	float high[12];
	float top = 0.0;
	for (int i = 0; i < layer_count; i++) {
		col[i] = vec3(0.0);
		bump[i] = vec3(0.0);
		high[i] = 0.0;
		if (w[i] < 0.004) {
			continue;
		}
		float size = layer_size[i];
		float layer = float(i);
		vec2 flat_uv = world_pos.xz / size;
		vec3 c = texture(layer_color, vec3(flat_uv, layer)).rgb;
		float h = texture(layer_height, vec3(flat_uv, layer)).r;
		vec3 n = texture(layer_normal, vec3(flat_uv, layer)).rgb * 2.0 - 1.0;
		// Площина XZ: +X — дотична, +V картинки дивиться в −Z світу.
		vec3 d = vec3(n.x, 0.0, -n.y);
		if (i >= side_from && i <= side_to && side.y < 0.97) {
			vec2 uv_x = world_pos.zy / size;
			vec2 uv_z = world_pos.xy / size;
			vec3 cx = texture(layer_color, vec3(uv_x, layer)).rgb;
			vec3 cz = texture(layer_color, vec3(uv_z, layer)).rgb;
			float hx = texture(layer_height, vec3(uv_x, layer)).r;
			float hz = texture(layer_height, vec3(uv_z, layer)).r;
			vec3 nx = texture(layer_normal, vec3(uv_x, layer)).rgb * 2.0 - 1.0;
			vec3 nz = texture(layer_normal, vec3(uv_z, layer)).rgb * 2.0 - 1.0;
			c = cx * side.x + c * side.y + cz * side.z;
			h = hx * side.x + h * side.y + hz * side.z;
			d = vec3(0.0, nx.y, nx.x) * side.x + d * side.y
					+ vec3(nz.x, nz.y, 0.0) * side.z;
		}
		// Друга вибірка: повернута й більша. Здалеку її частка росте —
		// саме там повтор і видно.
		vec2 wide_uv = turned(world_pos.xz) / (size * 3.3) + vec2(0.37, 0.71);
		vec3 c2 = texture(layer_color, vec3(wide_uv, layer)).rgb;
		c = mix(c, c2, mix(0.28, 0.55, far));
		col[i] = c * layer_tint[i];
		bump[i] = d - up * dot(up, d);
		high[i] = h;
		top = max(top, w[i] + h * 0.6);
	}

	vec3 albedo = vec3(0.0);
	vec3 bent = vec3(0.0);
	float rough = 0.0;
	float cavity = 0.0;
	float total = 0.0;
	for (int i = 0; i < layer_count; i++) {
		if (w[i] < 0.004) {
			continue;
		}
		float b = max(w[i] + high[i] * 0.6 - top + blend_depth, 0.0);
		albedo += col[i] * b;
		bent += bump[i] * b;
		rough += layer_rough[i] * b;
		cavity += high[i] * b;
		total += b;
	}
	total = max(total, 0.0001);
	albedo /= total;
	bent /= total;
	rough /= total;
	cavity /= total;

	// Великі плями світлішого й темнішого на десятки метрів: жива земля
	// ніколи не буває одного тону, і без цього поле здалеку — плитка.
	float macro = texture(macro_noise, world_pos.xz / macro_size).r;
	albedo *= 1.0 + (macro - 0.5) * 2.0 * macro_power;
	// Западини текстури трохи темніші — щілина між камінням у тіні.
	albedo *= mix(0.80, 1.0, cavity);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	vec3 n = normalize(up + bent * normal_power * (1.0 - far * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
