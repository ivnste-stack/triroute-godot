// A background picture of the main menu (#bgSnap: filter: blur(6px) brightness(.9)). The picture covers the
// rect (object-fit: cover), slowly zoomed and panned by the parameters (set every frame, sub-pixel smooth), and
// blurred by a gaussian over a mip level of it: smooth at any screen size, no blocks of an enlarged
// small image.
shader_type canvas_item;

uniform sampler2D pic : filter_linear_mipmap, repeat_disable;
uniform vec2 pic_size = vec2(3840.0, 2160.0);
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform float zoom = 1.08;          // > 1: the picture is larger than the screen, so it can drift
uniform vec2 pan = vec2(0.0);       // the drift, a share of the picture
uniform float blur_px = 6.0;        // the CSS blur radius in screen pixels
uniform vec3 shade = vec3(0.9);     // brightness

void fragment() {
	// cover: the picture fills the rect, the overflow is cut equally on both sides
	float ra = rect_size.x / rect_size.y, pa = pic_size.x / pic_size.y;
	vec2 s = ra > pa ? vec2(1.0, pa / ra) : vec2(ra / pa, 1.0);
	vec2 uv = (UV - 0.5) * s / zoom + 0.5 + pan;
	// one screen pixel in the picture's texels: the mip level that already holds the blur's scale
	float tex_per_px = s.x / zoom * pic_size.x / rect_size.x;
	float sigma_tex = blur_px * 0.5 * tex_per_px;
	float lod = log2(max(sigma_tex, 1.0));
	vec2 step_uv = vec2(sigma_tex) / pic_size;
	vec3 acc = vec3(0.0);
	float ws = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float w = exp(-float(x * x + y * y) / 4.5);
			acc += textureLod(pic, uv + vec2(float(x), float(y)) * step_uv, lod).rgb * w;
			ws += w;
		}
	}
	COLOR = vec4(acc / ws * shade, COLOR.a);
}
