shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Різнотрав'я: травинки, колоски, квіти й низьке листя біля землі.
//
// Слово замовника 11.09.2026: «невеличкий вітерець, який колихає
// різнотрав'я». Трава — справжні травинки з трикутників (їх будує
// `meadow.gd`), а не картки з картинкою: камера в грі дивиться згори
// навскоси, і картка під таким кутом стає смужкою.
//
// Кожна купка — екземпляр MultiMesh. INSTANCE_CUSTOM:
//   трава — r: світлість купки, g: сухість (0 соковита, 1 солома);
//   квітка — rgb: колір пелюсток;
//   a — випадкове число, за яким купка вирішує, де їй зникнути.
//
// COLOR вершини — колір травинки (уже лінійний), COLOR.a — висота на
// травинці: 0 біля землі, 1 на кінчику.
// UV.x = 1 — пелюстка (фарбується кольором екземпляра), UV.y = 1 —
// частина, якої екземпляр не чіпає (стебло квітки, серединка).

#include "res://scripts/wind.gdshaderinc"

uniform float fade_from = 26.0;
uniform float fade_to = 46.0;
// Наскільки хилиться кінчик на повному пориві, у частках висоти.
uniform float bend = 0.30;
uniform vec3 straw : source_color = vec3(0.66, 0.58, 0.36);
uniform vec3 through : source_color = vec3(0.30, 0.34, 0.12);

varying float up_share;
varying vec3 paint;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float h = COLOR.a;
	// Дальня трава рідшає поступово: кожна купка зникає на СВОЇЙ
	// відстані, тож межа трави не читається лінією.
	float d = distance(root.xz, CAMERA_POSITION_WORLD.xz);
	float edge = mix(fade_from, fade_to, INSTANCE_CUSTOM.a);
	float shrink = 1.0 - smoothstep(edge - 5.0, edge, d);
	vec3 rel = VERTEX - root;
	vec2 push = wind_push(root.xz, TIME, 2.6);
	rel.xz += push * bend * h * max(rel.y, 0.0);
	rel.y *= 1.0 - 0.28 * bend * length(push) * h;
	VERTEX = root + rel * shrink;
	up_share = h;
	if (UV.x > 0.5) {
		paint = INSTANCE_CUSTOM.rgb * COLOR.rgb;
	} else if (UV.y > 0.5) {
		paint = COLOR.rgb;
	} else {
		paint = mix(COLOR.rgb, straw * (0.7 + 0.5 * h), INSTANCE_CUSTOM.g)
				* INSTANCE_CUSTOM.r;
	}
	// Нормаль трави — майже вгору. Інакше тіньовий бік травинки
	// чорніє, і поле рябіє світлим і темним без жодної причини.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));
}

void fragment() {
	// Біля землі темніше: низ купки в тіні інших травинок.
	ALBEDO = paint * mix(0.55, 1.0, up_share);
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = through * up_share;
}
