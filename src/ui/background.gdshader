shader_type canvas_item;
// The window's backdrop: the logo's void with a faint gold glow up top and fine grain.

uniform vec2 rect_size = vec2(1280.0, 800.0);

void fragment() {
	float a = rect_size.x / max(rect_size.y, 1.0);
	vec2 p = (UV - vec2(0.72, -0.15)) * vec2(a, 1.0);
	vec2 q = (UV - vec2(0.05, 1.15)) * vec2(a, 1.0);
	vec3 col = vec3(0.043, 0.039, 0.071);
	col += vec3(0.83, 0.70, 0.45) * 0.075 * exp(-dot(p, p) * 1.4);
	col += vec3(0.42, 0.36, 0.72) * 0.045 * exp(-dot(q, q) * 1.8);
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * 0.014;
	COLOR = vec4(col, 1.0);
}
