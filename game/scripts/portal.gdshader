shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never,
		shadows_disabled;

// Сяйво порталу (П-190): вир у колі й стовп світла над ним, кольором
// грейду. Слово замовника 13.09.2026: «зрозуміло по візуалізації, що
// портал активовано — підсвіти його красиво, в кольорі грейду».
//
// Одна тінь на обидві частини: `swirl` — вир на площині кола, інакше —
// стовп, що тане вгору й мерехтить.

uniform vec4 tone : source_color = vec4(1.0);
uniform float power = 2.0;
uniform bool swirl = false;
uniform float radius = 2.4;
uniform float height = 6.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float a;
	if (swirl) {
		float d = length(local.xz) / radius;
		float turn = atan(local.z, local.x);
		float wave = 0.5 + 0.5 * sin(turn * 5.0 + TIME * 2.2 - d * 9.0);
		a = (1.0 - smoothstep(0.6, 1.0, d)) * (0.3 + 0.7 * wave)
				* (0.35 + 0.65 * d);
	} else {
		float up = clamp(local.y / height + 0.5, 0.0, 1.0);
		float flicker = 0.75 + 0.25 * sin(TIME * 3.0 + UV.x * 40.0);
		a = pow(1.0 - up, 2.2) * flicker * 0.6;
	}
	ALBEDO = tone.rgb * power;
	ALPHA = clamp(a * tone.a, 0.0, 1.0);
}
