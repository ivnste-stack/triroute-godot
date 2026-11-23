// The "glass" of the HTML version's panels (.glass: backdrop-filter: blur(18px) saturate(150%), a translucent
// tint, a thin border): the map behind is blurred (a mip level of the screen, averaged over a few offsets, about
// the CSS blur) and saturated, then tinted.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.0431, 0.0667, 0.098, 0.66);
uniform float radius_px = 18.0;
uniform float saturate = 1.5;
// the dark veil a dialog lays over the screen (.55 under a modal): the copy of the screen is taken before it,
// so the glass of a dialog darkens what it blurs by itself, as backdrop-filter sees the veil in the HTML version
uniform float dim = 0.0;

void fragment() {
	vec3 acc = vec3(0.0);
	float ws = 0.0;
	float lod = log2(radius_px * 0.5);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = exp(-float(x * x + y * y) / 2.0);
			acc += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * radius_px * 0.5 * SCREEN_PIXEL_SIZE, lod).rgb * w;
			ws += w;
		}
	}
	vec3 c = acc / ws;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturate);
	c = mix(c, vec3(0.0078, 0.0196, 0.0353), dim);
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
