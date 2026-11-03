shader_type canvas_item;
// A game's cover cropped to fill its box (like CSS object-fit: cover). Without art it
// draws a placeholder: a dark field lit by two soft glows in the game's tint.

uniform sampler2D cover : repeat_disable;
uniform bool has_cover = false;
uniform float cover_aspect = 1.7778;
uniform vec2 rect_size = vec2(320.0, 180.0);
uniform vec4 tint : source_color = vec4(0.83, 0.70, 0.45, 1.0);
uniform float zoom = 1.0;   // the card pushes in a little on hover
uniform float shade = 1.0;  // dims games that aren't installed
uniform float fade = 0.0;   // how much the bottom melts into fade_color
uniform vec4 fade_color : source_color = vec4(0.07, 0.067, 0.1, 1.0);

void fragment() {
	float rect_aspect = rect_size.x / max(rect_size.y, 1.0);
	vec3 col;
	if (has_cover) {
		vec2 c = UV - 0.5;
		if (rect_aspect > cover_aspect) {
			c.y *= cover_aspect / rect_aspect;
		} else {
			c.x *= rect_aspect / cover_aspect;
		}
		col = texture(cover, c / zoom + 0.5).rgb;
	} else {
		vec2 p = (UV - vec2(0.78, 0.15)) * vec2(rect_aspect, 1.0) / zoom;
		vec2 q = (UV - vec2(0.12, 1.05)) * vec2(rect_aspect, 1.0) / zoom;
		col = vec3(0.05, 0.047, 0.075);
		col += tint.rgb * 0.5 * exp(-dot(p, p) * 2.6);
		col += tint.bgr * 0.16 * exp(-dot(q, q) * 4.0);
		float lines = smoothstep(0.9, 1.0, sin((UV.x * rect_aspect + UV.y) * 120.0) * 0.5 + 0.5);
		col += lines * 0.02;
	}
	col *= shade;
	col = mix(col, fade_color.rgb, fade * smoothstep(0.35, 1.0, UV.y));
	COLOR = vec4(col, 1.0);
}
