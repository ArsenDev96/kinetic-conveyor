shader_type canvas_item;

// Level 1 V3 Junction plate.
//
// The plate is a round belt. Its own frame is rotated by `plate_angle`, so the
// slats tilt to face the exit the cargo is routed to and the surface travels
// that way; level_1_v3.gd swings that angle between the two output-arm
// directions on every route change.
//
// Like the conveyor treads, every masked pixel is replaced by the same artwork
// sampled a short distance upstream, so the plate's own slats travel while the
// rim, bolts and chamber hardware outside the mask are never touched.
//
// The two candidate samples sit exactly one slat period apart, so they always
// show the SAME phase of the pattern - only the plate's own baked shading
// differs between them. That is what lets us simply pick whichever one is still
// inside the disc and cross-fade, rather than hard-wrapping at the rim: a hard
// wrap made the sampled content jump along an arc, and that arc swept visibly
// across the plate as it scrolled.
//
// All geometry is in texture pixels of level1_machine_base.png.

uniform sampler2D tread_mask : filter_linear, repeat_disable;
uniform vec2 region_origin = vec2(416.0, 713.0);
uniform vec2 region_size = vec2(190.0, 190.0);
uniform vec2 tex_size = vec2(1024.0, 1536.0);

// Plate travel in texture px/s; apparent world speed = speed_tex * sprite scale.
uniform float speed_tex = 156.25;
// Slat pitch: the plate pattern repeats every this many texture px.
uniform float wrap_tex = 29.25;
uniform float blend_frac = 0.30;
// Normally 0. A test harness can zero speed_tex and step this instead.
uniform float phase_offset = 0.0;

uniform vec2 plate_centre = vec2(511.0, 808.0);
uniform float plate_radius = 91.0;
// 0 = travel straight down; positive swings the plate toward the left exit.
uniform float plate_angle = 0.0;
// Cross-fade width, texture px, used where a sample runs off the disc.
uniform float plate_blend = 12.0;

varying vec2 v_px;
varying vec4 v_mod;

void vertex() {
	// Sprite is `centered`, so local (0,0) is the region centre.
	v_px = region_origin + region_size * 0.5 + VERTEX;
	v_mod = COLOR;
}

void fragment() {
	vec2 p = v_px;
	float m = texture(tread_mask, (p - region_origin) / region_size).r;
	vec4 col = texture(TEXTURE, p / tex_size);
	if (m > 0.002) {
		float f = fract(TIME * speed_tex / wrap_tex + phase_offset);
		// Into the plate's own frame, so +y is the way the cargo leaves.
		vec2 dv = p - plate_centre;
		float ca = cos(plate_angle);
		float sa = sin(plate_angle);
		vec2 loc = vec2(ca * dv.x + sa * dv.y, -sa * dv.x + ca * dv.y);
		// Half-height of the plate in this column: a sample must stay inside it.
		float h = sqrt(max(plate_radius * plate_radius - loc.x * loc.x, 0.0));
		float y1 = loc.y - f * wrap_tex;
		float y2 = loc.y - (f - 1.0) * wrap_tex;
		float b = max(plate_blend, 0.001);
		// Prefer y1; fade to y2 as y1 runs off the upstream edge, and never use
		// y2 once it has run off the downstream edge. The time term keeps the
		// cycle itself seamless, exactly as it does for the belts.
		float w_time = smoothstep(1.0 - blend_frac, 1.0, f);
		float w_up = clamp((b - (h + y1)) / b, 0.0, 1.0);
		float w_dn = clamp((h - y2) / b, 0.0, 1.0);
		float w = min(max(w_time, w_up), w_dn);
		vec4 c1 = texture(TEXTURE, (plate_centre + vec2(loc.x, clamp(y1, -h, h))) / tex_size);
		vec4 c2 = texture(TEXTURE, (plate_centre + vec2(loc.x, clamp(y2, -h, h))) / tex_size);
		col = mix(c1, c2, w);
	}
	COLOR = vec4(col.rgb * v_mod.rgb, m * col.a * v_mod.a);
}
