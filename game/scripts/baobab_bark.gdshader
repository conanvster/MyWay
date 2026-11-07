shader_type spatial;
// Кора дерева-велета (07.11.2026): фото кори баобаба замовника. На стовбурі
// в сотню метрів одна текстура повторювалась би сіткою — тож та сама
// текстура у двох масштабах і повільні плями кольору поверх, а донизу
// кора темніша (земля, вогкість), як на фото.

uniform sampler2D bark : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float ground_y = 0.0;

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
	vec3 near = texture(bark, UV).rgb;
	vec3 far = texture(bark, UV * 0.31 + vec2(0.37, 0.11)).rgb;
	vec3 c = mix(near, far, 0.45);
	vec2 flat_at = vec2(world_at.x + world_at.z, world_at.y);
	float blotch = noise(flat_at * 0.025) * 0.6 + noise(flat_at * 0.09) * 0.4;
	float streak = noise(vec2(UV.x * 3.0, world_at.y * 0.01)) * 0.25;
	c *= tint * (0.72 + 0.5 * blotch - streak);
	float low = 1.0 - smoothstep(0.0, 8.0, world_at.y - ground_y);
	c *= 1.0 - 0.35 * low;
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
