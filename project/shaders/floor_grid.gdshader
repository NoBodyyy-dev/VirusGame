// Эмиссивная неоновая сетка пола дата-узла: тёмная база + пульсирующие линии.
shader_type spatial;

uniform vec3 base_col : source_color = vec3(0.008, 0.016, 0.032);
uniform vec3 line_col : source_color = vec3(0.08, 0.75, 0.95);
uniform float cell = 2.0;
uniform float line_w = 0.035;
uniform float pulse_speed = 0.7;
uniform float energy = 1.1;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(wpos.xz / cell - 0.5) - 0.5) * cell;
	float d = min(g.x, g.y);
	float line = 1.0 - smoothstep(0.0, line_w * cell, d);
	// мягкая волна яркости, бегущая по залу — «живой» узел
	float pulse = 0.55 + 0.45 * sin(TIME * pulse_speed + wpos.x * 0.12 + wpos.z * 0.09);
	// редкие яркие «магистрали» каждые 5 ячеек
	vec2 big = abs(fract(wpos.xz / (cell * 5.0) - 0.5) - 0.5) * cell * 5.0;
	float trunk = 1.0 - smoothstep(0.0, line_w * cell * 1.8, min(big.x, big.y));
	ALBEDO = base_col;
	ROUGHNESS = 0.35;
	METALLIC = 0.3;
	EMISSION = line_col * (line * pulse * 0.8 + trunk * (0.6 + 0.4 * sin(TIME * 1.3))) * energy;
}
