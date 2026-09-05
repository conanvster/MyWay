shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley;

// Вітер у рослинах.
//
// Слово замовника 06.09.2026: «я б віддав пріоритет саме моделям, щоб
// можна було додати невелике колихання». Колихання дає САМЕ ШЕЙДЕР, а
// не форма: він зсуває вершини за часом, і йому байдуже, меш це чи
// картка з фотографією. На картці навіть дешевше — вершин чотири.
//
// Зсув росте з висотою вершини (низ стоїть, верх гойдається), а фаза
// береться з положення вузла у світі — інакше цілий ліс хитався б в
// один такт, як хор.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float sway = 0.05;         // розмах у частках висоти
uniform float speed = 1.10;
uniform float scissor : hint_range(0.0, 1.0) = 0.45;
uniform vec3 through : source_color = vec3(0.16, 0.22, 0.12);

void vertex() {
	// VERTEX у просторі моделі: наш хрест має висоту рівно 1, тож
	// висота вершини — це вже й частка. Масштаб вузла помножить зсув
	// сам, і велике дерево гойдатиметься ширше за мале, як і має бути.
	float high = clamp(VERTEX.y, 0.0, 1.0);
	float lean = high * high * sway;
	float phase = NODE_POSITION_WORLD.x * 0.31 + NODE_POSITION_WORLD.z * 0.23;
	float t = TIME * speed + phase;
	// Дві частоти: одна повільна хвиля й одна дрібніша тремтливість —
	// рівний синус читається як механізм, а не як вітер.
	VERTEX.x += (sin(t) * 0.75 + sin(t * 2.7) * 0.25) * lean;
	VERTEX.z += (cos(t * 0.83) * 0.75 + cos(t * 2.3) * 0.25) * lean * 0.7;
}

void fragment() {
	vec4 got = texture(albedo_tex, UV);
	ALBEDO = got.rgb;
	ALPHA = got.a;
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
	// Світло крізь хвою: без цього тіньовий бік крони — чорна дошка.
	BACKLIGHT = through;
}
