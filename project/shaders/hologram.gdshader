// Голографическое тело вируса/фантома: френель + сканлайны, аддитивное свечение.
shader_type spatial;
render_mode blend_add, unshaded, cull_back;

uniform vec3 col : source_color = vec3(0.2, 0.85, 1.0);
uniform float fresnel_power = 2.4;
uniform float scan_speed = 3.0;
uniform float brightness = 1.4;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float scan = 0.75 + 0.25 * sin((VERTEX.y + TIME * scan_speed) * 22.0);
	ALBEDO = col * (0.10 + f * 1.7) * scan * brightness;
}
