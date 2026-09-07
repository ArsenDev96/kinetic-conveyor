shader_type canvas_item;

// Level 1 V3 conveyor tread motion.
//
// One overlay Sprite2D per belt (input, left output, right output) sits on top
// of the static full-machine sprite. Each overlay shows a region of the SAME
// approved machine texture and draws ONLY the pixels its tread mask marks:
// every masked pixel is replaced by the same artwork sampled a short distance
// upstream along the belt centreline, so the rubber ribs travel while rails,
// bolts, housings and stations (outside the mask) are never touched.
//
// Because the rib pattern repeats every `wrap_tex` texture pixels, the upstream
// distance is taken modulo that repeat: the sample never leaves the belt and
// the motion is a pure phase loop, so nothing can drift over time.
//
// mode 0  straight vertical belt   (input conveyor)
// mode 1  diagonal + arc + vertical (output conveyors, mirrored for the right)
// mode 1: diagonal starts at diag_p0 heading (-sin alpha, cos alpha) for
// len_diag px, bends through an arc of radius arc_r until vertical, then runs
// straight down.
uniform vec2 diag_p0 = vec2(422.146, 893.59);
uniform float alpha = 0.703368;
uniform float arc_r = 65.0;
uniform float len_diag = 239.212;

varying vec2 v_px;
varying vec4 v_mod;

void vertex() {
	// Sprite is `centered`, so local (0,0) is the region centre.
	v_px = region_origin + region_size * 0.5 + VERTEX;
	v_mod = COLOR;
}

vec2 bend_to_st(vec2 p) {
	vec2 u = vec2(-sin(alpha), cos(alpha));
	vec2 n = vec2(cos(alpha), sin(alpha));
	vec2 c = diag_p0 + u * len_diag + n * arc_r;
	float len_arc = arc_r * alpha;
	if (p.y >= c.y) {
		return vec2(len_diag + len_arc + (p.y - c.y), p.x - (c.x - arc_r));
	}
	vec2 d = p - diag_p0;
	float proj = dot(d, u);
	if (proj <= len_diag) {
		return vec2(proj, dot(d, n));
	}
	vec2 v = p - c;
	float phi = alpha - atan(-v.y, -v.x);
	return vec2(len_diag + arc_r * phi, arc_r - length(v));
}

vec2 bend_from_st(float s, float t) {
	vec2 u = vec2(-sin(alpha), cos(alpha));
	vec2 n = vec2(cos(alpha), sin(alpha));
	vec2 c = diag_p0 + u * len_diag + n * arc_r;
	float len_arc = arc_r * alpha;
	if (s <= len_diag) {
		return diag_p0 + u * s + n * t;
	}
	if (s <= len_diag + len_arc) {
		float phi = (s - len_diag) / arc_r;
		return c + (arc_r - t) * vec2(-cos(alpha - phi), -sin(alpha - phi));
	}
	return vec2(c.x - arc_r + t, c.y + (s - len_diag - len_arc));
}

float wrap_s(float s) {
	s += wrap_tex * step(s, s_min);
	s -= wrap_tex * step(s_max, s);
	return s;
}

// Texture-pixel position `d` upstream of `p` along the belt.
vec2 upstream(vec2 p, float d) {
	if (mirror_x >= 0.0) {
		p.x = 2.0 * mirror_x - p.x;
	}
	vec2 q;
	if (mode == 1) {
		vec2 st = bend_to_st(p);
		q = bend_from_st(wrap_s(st.x - d), st.y);
	} else {
		q = vec2(p.x, lin_y0 + wrap_s((p.y - lin_y0) - d));
	}
	if (mirror_x >= 0.0) {
		q.x = 2.0 * mirror_x - q.x;
	}
	return q;
}

void fragment() {
	vec2 p = v_px;
	float m = texture(tread_mask, (p - region_origin) / region_size).r;
	vec4 col = texture(TEXTURE, p / tex_size);
	if (m > 0.002) {
		float f = fract(TIME * speed_tex / wrap_tex + phase_offset);
		vec4 s1 = texture(TEXTURE, upstream(p, f * wrap_tex) / tex_size);
		vec4 s2 = texture(TEXTURE, upstream(p, (f - 1.0) * wrap_tex) / tex_size);
		col = mix(s1, s2, smoothstep(1.0 - blend_frac, 1.0, f));
	}
	COLOR = vec4(col.rgb * v_mod.rgb, m * col.a * v_mod.a);
}
