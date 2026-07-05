// Тревожная виньетка: краснеет по мере роста Trace / при уроне.
shader_type canvas_item;

uniform float intensity = 0.0;
uniform vec3 tint : source_color = vec3(0.85, 0.07, 0.22);

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	float a = smoothstep(0.32, 0.72, d) * intensity;
	COLOR = vec4(tint, a);
}
