shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley;

// Вітер у рослинах: фотодерева, кущі, папороть.
//
// Слово замовника 06.09.2026: «я б віддав пріоритет саме моделям, щоб
// можна було додати невелике колихання». Колихання дає САМЕ ШЕЙДЕР, а
// не форма: він зсуває вершини за часом, і йому байдуже, меш це чи
// картка з фотографією. На картці навіть дешевше — вершин чотири.
//
// Зсув росте з висотою вершини (низ стоїть, верх гойдається). Куди й
// коли хилитись, каже спільний вітер (`wind.gdshaderinc`) — той самий,
// що й у трави: порив, який іде полем, доходить до лісу й хитає його
// в той самий бік (слово замовника 11.09.2026 про «вітерець, який
// колихає різнотрав'я та дерева»).

#include "res://scripts/wind.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool use_normal = false;
uniform float sway = 0.05;         // розмах у частках висоти
uniform float speed = 1.10;
uniform float scissor : hint_range(0.0, 1.0) = 0.45;
uniform vec3 through : source_color = vec3(0.16, 0.22, 0.12);
// Низ і висота моделі в її власних одиницях. Хрест фотодерева має
// висоту рівно 1 від нуля, а скан Poly Haven — справжні метри (папороть
// 0,4 м): без цього вона ледь ворушилась би.
uniform float model_floor = 0.0;
uniform float model_tall = 1.0;

void vertex() {
	// VERTEX у просторі моделі; висота вершини — частка від низу до
	// верху моделі. Масштаб вузла помножить зсув сам, і велике дерево
	// гойдатиметься ширше за мале, як і має бути.
	float high = clamp((VERTEX.y - model_floor) / model_tall, 0.0, 1.0);
	float lean = high * high * sway * model_tall;
	vec2 push = wind_push(NODE_POSITION_WORLD.xz, TIME, speed);
	// Вітер дме у світі, а вершина лежить у моделі, повернутій і
	// масштабованій: переводимо зсув назад у її простір.
	vec3 local = inverse(mat3(MODEL_MATRIX)) * vec3(push.x, 0.0, push.y);
	float size = length(MODEL_MATRIX[1].xyz);
	VERTEX.xz += local.xz * size * lean;
}

void fragment() {
	vec4 got = texture(albedo_tex, UV);
	ALBEDO = got.rgb;
	ALPHA = got.a;
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	// Світло крізь хвою: без цього тіньовий бік крони — чорна дошка.
	BACKLIGHT = through;
}
