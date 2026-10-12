shader_type spatial;
render_mode unshaded, cull_disabled;

// N x N board drawn entirely in the fragment shader from a tiny data texture.
// Texel value: bits 0-1 = owner (0 empty, 1 X, 2 O), bit 2 = part of the winning line.

uniform sampler2D cells : filter_nearest, repeat_disable;
uniform vec4 paper : source_color = vec4(0.847, 0.882, 0.733, 0.9);
uniform vec4 line_minor : source_color = vec4(0.663, 0.718, 0.604, 1.0);
uniform vec4 line_major : source_color = vec4(0.443, 0.545, 0.467, 1.0);
uniform vec4 color_x : source_color = vec4(0.769, 0.282, 0.212, 1.0);
uniform vec4 color_o : source_color = vec4(0.157, 0.424, 0.612, 1.0);
uniform vec4 win_tint : source_color = vec4(0.96, 0.94, 0.45, 1.0);
uniform vec4 last_color : source_color = vec4(0.914, 0.957, 0.545, 1.0);
uniform vec2 last_cell = vec2(-1.0, -1.0); // (col, row)
uniform float grid_size = 50.0;

void fragment() {
	vec2 g = UV * grid_size;
	vec2 id = floor(g);
	vec2 f = fract(g);
	int val = int(texture(cells, (id + 0.5) / grid_size).r * 255.0 + 0.5);
	int kind = val & 3;
	bool win = (val & 4) != 0;

	vec4 col = paper;
	if (win) {
		col = mix(col, win_tint, 0.85);
	}
	if (abs(id.x - last_cell.x) < 0.5 && abs(id.y - last_cell.y) < 0.5) {
		float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
		vec2 e = min(f, 1.0 - f);
		float edge = 1.0 - smoothstep(0.06, 0.12, min(e.x, e.y));
		col = mix(col, last_color, 0.25 + 0.2 * pulse);
		col = mix(col, last_color, edge * (0.6 + 0.4 * pulse));
		col.a = max(col.a, edge);
	}

	// Grid: thin lines per cell, heavier every 5 cells.
	vec2 aa = fwidth(g);
	vec2 d1 = min(f, 1.0 - f);
	float minor = max(1.0 - smoothstep(aa.x * 0.5, aa.x * 1.2, d1.x),
					  1.0 - smoothstep(aa.y * 0.5, aa.y * 1.2, d1.y));
	vec2 f5 = fract(g / 5.0);
	vec2 d5 = min(f5, 1.0 - f5) * 5.0;
	float major = max(1.0 - smoothstep(aa.x * 0.9, aa.x * 2.0, d5.x),
					  1.0 - smoothstep(aa.y * 0.9, aa.y * 2.0, d5.y));
	col = mix(col, line_minor, minor);
	col = mix(col, line_major, major);
	col.a = max(col.a, max(minor, major));

	vec2 p = f * 2.0 - 1.0;
	if (kind == 1) {
		float d = min(abs(p.x - p.y), abs(p.x + p.y)) * 0.7071;
		float box = step(max(abs(p.x), abs(p.y)), 0.62);
		float m = (1.0 - smoothstep(0.07, 0.13, d)) * box;
		col.rgb = mix(col.rgb, color_x.rgb, m);
		col.a = mix(col.a, 1.0, m);
	} else if (kind == 2) {
		float m = 1.0 - smoothstep(0.06, 0.12, abs(length(p) - 0.58));
		col.rgb = mix(col.rgb, color_o.rgb, m);
		col.a = mix(col.a, 1.0, m);
	}

	ALBEDO = col.rgb;
	ALPHA = col.a;
}
