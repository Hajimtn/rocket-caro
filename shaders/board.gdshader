shader_type spatial;
render_mode unshaded, cull_disabled;

// N x N board drawn entirely in the fragment shader from a tiny data texture.
// Texel value: bits 0-1 = owner (0 empty, 1 X, 2 O), bit 2 = part of the winning line.
// The look comes from the board skin (colours + pattern) and each team's mark skin (shape).

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
uniform int pattern = 0;       // 0 plain, 1 wood grain, 2 chalk dust, 3 neon glow
uniform int mark_style_x = 0;  // 0 classic X/O, 1 star, 2 heart, 3 diamond
uniform int mark_style_o = 0;
uniform float frost = 0.0;     // 0..1: the board is frozen by a freeze rocket

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Signed distances (negative inside), by Inigo Quilez.
float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return length(p - vec2(0.25, 0.75)) - sqrt(2.0) / 4.0;
	}
	vec2 a = p - vec2(0.0, 1.0);
	vec2 b = p - 0.5 * max(p.x + p.y, 0.0);
	return sqrt(min(dot(a, a), dot(b, b))) * sign(p.x - p.y);
}

// Coverage (0..1) of one mark inside its cell; p runs -1..1 with y pointing down the board.
float mark_mask(int style, int kind, vec2 p) {
	vec2 q = vec2(p.x, -p.y);
	if (style == 1) {
		return 1.0 - smoothstep(-0.03, 0.03, sd_star5(q * 1.05 + vec2(0.0, 0.04), 0.7, 0.45));
	}
	if (style == 2) {
		return 1.0 - smoothstep(-0.03, 0.03, sd_heart(q / 1.1 + vec2(0.0, 0.55)) * 1.1);
	}
	if (style == 3) {
		float d = (abs(q.x) + abs(q.y) - 0.62) * 0.7071;
		float ring = 1.0 - smoothstep(0.06, 0.12, abs(d));
		float gem = 1.0 - smoothstep(-0.03, 0.03, (abs(q.x) + abs(q.y) - 0.26) * 0.7071);
		return max(ring, gem);
	}
	if (kind == 1) {
		float d = min(abs(p.x - p.y), abs(p.x + p.y)) * 0.7071;
		float box = step(max(abs(p.x), abs(p.y)), 0.62);
		return (1.0 - smoothstep(0.07, 0.13, d)) * box;
	}
	return 1.0 - smoothstep(0.06, 0.12, abs(length(p) - 0.58));
}

void fragment() {
	vec2 g = UV * grid_size;
	vec2 id = floor(g);
	vec2 f = fract(g);
	int val = int(texture(cells, (id + 0.5) / grid_size).r * 255.0 + 0.5);
	int kind = val & 3;
	bool win = (val & 4) != 0;

	vec4 col = paper;
	if (pattern == 1) {
		// wood: long wavy grain plus a few darker rings
		float w = UV.y * 46.0 + sin(UV.x * 7.0 + UV.y * 3.0) * 2.2 + sin(UV.x * 23.0) * 0.4;
		float grain = 0.5 + 0.5 * sin(w);
		col.rgb *= 0.86 + 0.14 * grain + 0.05 * (hash(floor(UV * vec2(300.0, 40.0))) - 0.5);
	} else if (pattern == 2) {
		// chalk: fine dust and a couple of broad smudges where it was wiped
		float smudge = 0.5 + 0.5 * sin(UV.x * 5.0 + 1.3) * sin(UV.y * 4.0 + 0.4);
		col.rgb += (hash(floor(UV * 520.0)) - 0.5) * 0.05 + smudge * 0.05;
	}
	if (frost > 0.0) {
		// ice creeps in from the frame; a faint crystal pattern all over
		vec2 e = abs(UV - 0.5);
		float rim = smoothstep(0.32, 0.5, max(e.x, e.y));
		float crystal = smoothstep(0.86, 1.0, abs(sin(UV.x * 61.0 + UV.y * 37.0)) * abs(sin(UV.x * 29.0 - UV.y * 53.0)));
		float ice = frost * (0.16 + 0.5 * rim + 0.3 * crystal);
		col.rgb = mix(col.rgb, vec3(0.82, 0.94, 1.0), clamp(ice, 0.0, 0.7));
		col.a = max(col.a, frost * 0.9);
	}
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
	if (pattern == 3) {
		// neon: the heavy lines bleed light into the cells around them
		float halo = exp(-min(d5.x, d5.y) * 3.0) * 0.35 + exp(-min(d1.x, d1.y) * 14.0) * 0.12;
		col.rgb += line_major.rgb * halo;
	}
	col = mix(col, line_minor, minor);
	col = mix(col, line_major, major);
	col.a = max(col.a, max(minor, major));

	if (kind == 1 || kind == 2) {
		vec2 p = f * 2.0 - 1.0;
		float m = mark_mask(kind == 1 ? mark_style_x : mark_style_o, kind, p);
		vec3 mc = kind == 1 ? color_x.rgb : color_o.rgb;
		col.rgb = mix(col.rgb, mc, m);
		col.a = mix(col.a, 1.0, m);
	}

	ALBEDO = col.rgb;
	ALPHA = col.a;
}
