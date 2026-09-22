shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Хутро шарами (shell fur) для власних моделей звірів.
//
// Слово замовника 23.09.2026 про зайця: «навіть хутро не промальовується,
// не бачу волосинок». Справжнє волосся Blender у glTF не доходить, тож
// ворс робить рушій: ту саму сітку малюємо ще N разів (ланцюжок
// `next_pass`, по матеріалу на шар), кожен шар трохи далі вздовж нормалі,
// і в кожному лишаємо тільки точки, де «росте» волосина. Волосина тоншає
// до кінчика, корінь темніший — так видно окремі волоски, а не шар фарби.
// Скінінг Godot робить ДО вершинного шейдера, тож шари їдуть разом із
// кістками, і рухи моделі не ламаються.
//
// Де хутра нема (очі, ніс, кігті, нутро вух) — каже друга UV-розгортка:
// UV2.x = «голизна» (0 — повний ворс, 1 — голо). Її пише Blender-скрипт
// моделі (`tools/blender/make_hare_scan.py`); нема другої UV — Godot дає
// нуль, тобто ворс усюди. Кольори вершин для цього не годяться: імпорт
// glTF множить на них колір самої моделі.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float layer = 0.5;            // 0 — корінь, 1 — кінчики
uniform float fur_length = 0.02;      // у метрах моделі
uniform float density = 600.0;        // волосин на одиницю UV
uniform float thickness = 0.4;       // товщина біля кореня, частка клітинки
// Куди лягають кінчики, у власних осях моделі й частках довжини: вниз
// (вага) і назад (шерсть звіра прилизана від морди до хвоста). Перед
// власних моделей у файлі — +Z (Blender −Y), тож «назад» — це −Z.
uniform vec3 gravity = vec3(0.0, -0.35, -0.6);
uniform float root_shade = 0.55;      // наскільки темний корінь

varying float fur_amount;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	fur_amount = 1.0 - UV2.x;
	float reach = fur_length * layer * fur_amount;
	VERTEX += NORMAL * reach + gravity * fur_length * layer * layer * fur_amount;
}

void fragment() {
	if (fur_amount < 0.05) {
		discard;
	}
	vec2 grid = UV * density;
	vec2 cell = floor(grid);
	float seed = hash(cell);
	// Волосина не в центрі клітинки, а де випало, — інакше ворс лягає
	// рівними рядками й проступає сітка.
	vec2 spot = vec2(hash(cell + 17.0), hash(cell + 43.0)) * 2.0 - 1.0;
	vec2 local = fract(grid) * 2.0 - 1.0 - spot * (1.0 - thickness);
	// Волосини різної довжини: коротка обривається на нижчих шарах.
	float own_length = mix(0.55, 1.0, seed);
	if (layer > own_length) {
		discard;
	}
	float radius = thickness * (1.0 - layer / own_length);
	if (length(local) > radius) {
		discard;
	}
	vec3 base = texture(albedo_tex, UV).rgb;
	ALBEDO = base * mix(root_shade, 1.0, layer) * mix(0.9, 1.1, seed);
	ROUGHNESS = 1.0;
}
