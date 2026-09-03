shader_type canvas_item;

// Conveyor tread motion for the Level 1 V2 belt family.
//
// The production sprite is drawn untouched; only pixels the tread mask marks are
// replaced by the same artwork sampled a short distance upstream along the belt.
// Because the rib pattern repeats every `wrap_tex` texture pixels, the upstream
// offset is taken modulo that repeat, so the sample never leaves the belt and the
// motion never accumulates drift. Rails, tabs, rollers, bolts and housings sit
// outside the mask and stay perfectly still.
//
// mode 0  linear   - straights (including the rotated diagonal runs) and sources
// mode 1  bend     - arc-length mapping: diagonal arm + arc + vertical arm
// mode 2  splitter - vertical stem fanning smoothly into two branches

uniform sampler2D tread_mask : filter_linear, repeat_disable;
uniform vec2 tex_size = vec2(724.0, 2172.0);
uniform int mode : hint_range(0, 2) = 0;

// Travel along the belt. speed_tex is texture px/s; multiply the sprite scale by
// it to get the apparent world speed. dir_sign flips travel for mirrored sprites.
uniform float speed_tex = 640.71;
uniform float wrap_tex = 123.0;
uniform float dir_sign = 1.0;
uniform float blend_frac = 0.30;
// Normally 0. Lets a test harness drive the belt phase deterministically by
// zeroing speed_tex and stepping this instead.
uniform float phase_offset = 0.0;

// mode 0 guards: keep the upstream sample on the belt rather than in the housing.
uniform float valid_min = -100000.0;
uniform float valid_max = 100000.0;

// mode 1 - measured off conveyor_bend_45_v2.png
uniform vec2 arc_o = vec2(989.5, 806.5);
uniform float arc_r = 455.0;
uniform vec2 tan_v = vec2(534.5, 806.5);
uniform vec2 tan_d = vec2(666.5, 486.0);
uniform float arm_alpha = 0.789203;
uniform float len_diag = 468.4;
uniform float len_arc = 355.63;
uniform float len_vert = 429.5;

// mode 2 - measured off conveyor_split_42_v2.png
uniform vec2 pivot = vec2(627.36, 619.98);
uniform float branch_th = 0.746540;
uniform float fan_x = 70.0;
uniform float fan_y = 110.0;

vec2 bend_pos(float s, float t) {
	float arc_end = len_diag + len_arc;
	if (s >= arc_end) {
		return vec2(tan_v.x + t, tan_v.y + (s - arc_end));
	}
	if (s <= len_diag) {
		vec2 u_up = vec2(cos(arm_alpha), -sin(arm_alpha));
		vec2 n_d = vec2(sin(arm_alpha), cos(arm_alpha));
		return tan_d + u_up * (len_diag - s) + n_d * t;
	}
	float ang_td = atan(tan_d.y - arc_o.y, tan_d.x - arc_o.x);
	float a = ang_td - (s - len_diag) / arc_r;
	return arc_o + (arc_r - t) * vec2(cos(a), sin(a));
}

// Returns the texture-pixel position `d` upstream of `p` along the belt.
vec2 upstream(vec2 p, float d) {
	if (mode == 1) {
		vec2 u_up = vec2(cos(arm_alpha), -sin(arm_alpha));
		vec2 n_d = vec2(sin(arm_alpha), cos(arm_alpha));
		float proj = dot(p - tan_d, u_up);
		float s;
		float t;
		if (p.y >= tan_v.y) {
			s = len_diag + len_arc + (p.y - tan_v.y);
			t = p.x - tan_v.x;
		} else if (proj > 0.0) {
			s = len_diag - proj;
			t = dot(p - tan_d, n_d);
		} else {
			vec2 v = p - arc_o;
			float ang_td = atan(tan_d.y - arc_o.y, tan_d.x - arc_o.x);
			s = len_diag + arc_r * (ang_td - atan(v.y, v.x));
			t = arc_r - length(v);
		}
		float s_max = len_diag + len_arc + len_vert;
		float sp = s - dir_sign * d;
		sp += wrap_tex * step(sp, 0.0);
		sp -= wrap_tex * step(s_max, sp);
		return bend_pos(sp, t);
	}

	vec2 dir = vec2(0.0, 1.0);
	if (mode == 2) {
		float u = clamp((p.y - pivot.y + fan_y * 0.5) / fan_y, 0.0, 1.0);
		float w = clamp((p.x - pivot.x) / fan_x * 0.5 + 0.5, 0.0, 1.0);
		vec2 bdir = vec2((2.0 * w - 1.0) * sin(branch_th), cos(branch_th));
		dir = normalize(mix(vec2(0.0, 1.0), bdir, u));
	}
	vec2 q = p - dir * (dir_sign * d);
	q.y += wrap_tex * step(q.y, valid_min);
	q.y -= wrap_tex * step(valid_max, q.y);
	return q;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float m = texture(tread_mask, UV).r;
	if (m > 0.004) {
		float f = fract(TIME * speed_tex / wrap_tex + phase_offset);
		vec2 p = UV * tex_size;
		vec4 s1 = texture(TEXTURE, upstream(p, f * wrap_tex) / tex_size);
		vec4 s2 = texture(TEXTURE, upstream(p, (f - 1.0) * wrap_tex) / tex_size);
		vec4 moved = mix(s1, s2, smoothstep(1.0 - blend_frac, 1.0, f));
		base = mix(base, moved, m);
	}
	COLOR = base * COLOR;
}
