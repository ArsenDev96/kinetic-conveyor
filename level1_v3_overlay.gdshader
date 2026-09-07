shader_type canvas_item;

// Level 1 V3 machine-part overlay.
//
// Draws one masked region of the approved machine texture on top of the static
// full-machine sprite. At rest it is pixel-identical to what lies beneath it, so
// it is invisible; animating its modulate / position / scale then moves or
// brightens ONLY the masked part (beacon, source housing, a destination
// station) while the rest of the machine stays untouched.

uniform sampler2D part_mask : filter_linear, repeat_disable;
uniform vec2 region_origin = vec2(0.0, 0.0);
uniform vec2 region_size = vec2(1.0, 1.0);
uniform vec2 tex_size = vec2(1024.0, 1536.0);

varying vec2 v_px;
varying vec4 v_mod;

void vertex() {
	v_px = region_origin + region_size * 0.5 + VERTEX;
	v_mod = COLOR;
}

void fragment() {
	float m = texture(part_mask, (v_px - region_origin) / region_size).r;
	vec4 col = texture(TEXTURE, v_px / tex_size);
	COLOR = vec4(col.rgb * v_mod.rgb, m * col.a * v_mod.a);
}
