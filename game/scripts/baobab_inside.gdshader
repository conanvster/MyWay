shader_type spatial;
// Нутро дерева-велета (07.11.2026, фото замовника: дупла, мох, «джунглі»).
// Деревина дупла, а понизу — мох плямами: висота над підлогою поверху
// приходить у UV2.y (підлога — 0, стеля — далеко вгорі).

uniform sampler2D wood : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss : source_color, filter_linear_mipmap, repeat_enable;
uniform float moss_high = 2.6;
uniform vec3 tint = vec3(1.0);

varying vec3 world_at;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 w = texture(wood, UV).rgb * tint;
	vec3 m = texture(moss, UV * 1.6).rgb * 0.85;
	float n = noise(world_at.xz * 0.12 + world_at.y * 0.08) * 1.8
			+ noise(world_at.xz * 0.55 + world_at.y * 0.3) * 0.7;
	float above = UV2.y;
	float k = 1.0 - smoothstep(moss_high * 0.3, moss_high, above + 1.2 - n);
	ALBEDO = mix(w, m, clamp(k, 0.0, 1.0));
	ROUGHNESS = 0.95;
}
