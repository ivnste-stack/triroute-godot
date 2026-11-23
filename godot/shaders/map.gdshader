// Map surface: port of the HTML version's map fragment shader (legacy/src/04-map.js, FSsrc, board lattice).
// The whole board is one plane; land, sea, state colours, border shading, sun glints and the board frame
// all come from the textures built by TRWorldGen.build_textures(). The shader works in sRGB like the
// original (WebGL writes sRGB directly) and converts to linear only at the very end.
// Not ported because the board never uses them: the coastal wall slab (wallOff=1 on the board),
// the occupation hatching (hasOcc) and the fine logistics grid (lgrid).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D t0 : filter_linear_mipmap_anisotropic, repeat_disable;   // terrain: coast/height, diagonal, light, noise
uniform sampler2D tb : filter_linear_mipmap_anisotropic, repeat_disable;   // distance to a state border
uniform sampler2D t1 : filter_nearest, repeat_disable;                     // state id + 1 (R8)
uniform float triS = 10.0;
uniform vec2 MWH = vec2(1800.0, 1200.0);    // texture size
uniform vec2 WSZ = vec2(22.5, 15.0);        // world size
uniform vec3 col[120];
uniform int hov = -1;
uniform int sel = -1;
uniform float lgrid = 0.0;   // the logistics layer: a fine grid of 0.08 world units and a coarse one of 5 cells

float lgr(vec2 p, float s, float w) {
	vec2 q = p / s;
	vec2 fw = fwidth(q);
	float fade = 1. - smoothstep(.12, .33, max(fw.x, fw.y));
	vec2 g = abs(fract(q - .5) - .5) / max(fw, vec2(1e-5));
	return (1. - min(min(g.x, g.y) / w, 1.)) * fade;
}

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float gridl(vec2 p, float s, float w) {
	vec2 q = p / s;
	vec2 g = abs(fract(q - .5) - .5) / fwidth(q);
	return 1. - min(min(g.x, g.y) / w, 1.);
}
uint idAt(vec2 uv) {
	return uint(round(texture(t1, uv).r * 255.0)) & 127u;
}
float hsh(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
vec3 cc(uint id) {
	return id >= 122u ? vec3(.36, .385, .41) : id == 121u ? vec3(.50, .50, .47) : id > 0u ? col[int(id) - 1] : vec3(.42, .45, .48);
}
vec3 triInfo(vec2 uv) {
	vec2 q = uv * MWH / triS;
	vec2 fl = floor(q), fr = q - fl;
	float dg = textureLod(t0, (fl + .5) * triS / MWH, 0.).g;
	float up;
	vec2 c;
	if (dg > .5) {
		up = step(fr.y, fr.x);
		c = mix(vec2(1. / 3., 2. / 3.), vec2(2. / 3., 1. / 3.), up);
	} else {
		up = step(1., fr.x + fr.y);
		c = mix(vec2(1. / 3.), vec2(2. / 3.), up);
	}
	return vec3((fl + c) * triS / MWH, up);
}
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 half_w = WSZ * .5;
	vec2 uv = (wp.xz + half_w) / WSZ;
	vec3 bg = vec3(.022, .038, .055);
	vec3 c;
	vec2 gq = wp.xz + half_w;
	float g1 = gridl(gq, .5, 1.), g2 = gridl(gq, 2.5, 1.2);
	vec2 e2 = min(uv, 1. - uv) * WSZ;
	float sd = min(e2.x, e2.y);
	float fe = max(fwidth(sd), 1e-5);
	float mask = smoothstep(-fe * .6, fe * .6, sd);
	vec3 cf;
	{
		vec2 d = max(abs(wp.xz) - half_w, 0.);
		float dd = length(d);
		cf = bg + vec3(.25, .45, .6) * (g1 * .05 + g2 * .1);
		cf *= .35 + .65 * smoothstep(0., .9, dd);
		cf += vec3(.05, .12, .18) * exp(-dd * 1.2) * .6;
	}
	c = cf;
	if (sd > -fe * 2.) {
		uv = clamp(uv, 0., 1.);
		vec4 t = texture(t0, uv);
		float h = t.r, bd = texture(tb, uv).r;
		vec2 tcuv = uv;
		float tH = .5;
		{
			vec3 ti_ = triInfo(uv);
			vec2 fl = floor(uv * MWH / triS);
			float up = ti_.z;
			tcuv = ti_.xy;
			tH = hsh(fl * vec2(1.13, .91) + up * vec2(.37, .71));
			h = texture(t0, tcuv).r;
		}
		float land = step(0., h);
		// ---- sea
		float depth = clamp(-h, 0., 1.);
		vec3 deep = vec3(.03, .13, .24), mid = vec3(.06, .27, .42), shal = vec3(.16, .52, .66);
		vec3 w = mix(shal, mid, smoothstep(0., .18, depth));
		w = mix(w, deep, smoothstep(.18, .85, depth));
		w += vec3(.12, .22, .24) * exp(-depth * 45.);
		w = w * (.84 + .32 * tH) + vec3(0., .035, .045) * (tH - .5);
		// ---- land: state colour
		uint id = idAt(tcuv);
		vec3 L = cc(id);
		uint su = uint(sel + 1), hu = uint(hov + 1);
		float fs = sel < 0 ? 0. : float(id == su);
		if (id == 121u) {
			vec2 hp = wp.xz * 55.;
			float st = abs(fract((hp.x + hp.y) * .5) - .5);
			float sw = fwidth((hp.x + hp.y) * .5);
			L *= 1. - .14 * (1. - smoothstep(.12, .12 + sw * 1.5, st)) * (1. - smoothstep(.15, .4, sw));
		}
		float fh = hov < 0 ? 0. : float(id == hu);
		L *= mix(.88, 1., smoothstep(1.6, 12., bd));
		L *= .95 + .1 * tH;
		L += vec3(.06) * fh;
		L = mix(L, L * 1.08 + vec3(.03, .05, .07) + vec3(.35, .7, .9) * (1. - smoothstep(1.2, 14., bd)) * (.35 + .12 * sin(TIME * 3.)), fs);
		if (lgrid > 0.) {
			float a1 = lgr(wp.xz, lgrid, 1.), a2 = lgr(wp.xz, lgrid * 5., 1.4);
			L = mix(L, L * .66, clamp(a1 * .42 + a2 * .55, 0., .8));
		}
		c = mix(w, L, land);
		// ---- state border: soft shade along the line (the line itself is drawn by the overlay)
		float bl = max(bd - .78, 0.);
		float px = max(fwidth(bd), 1e-4);
		float lw = max(.75, px * .62);
		float halo = (1. - smoothstep(lw, lw + px * 2.5 + 1.2, bl)) * .25;
		c = mix(c, c * .72, halo * land);
		// ---- board grid shimmer on the water
		c += vec3(.6, .8, 1.) * g1 * .03 * (1. - land * .75) + vec3(.6, .8, 1.) * g2 * .05 * (1. - land * .6);
		c = mix(cf, c, mask);
	}
	float fd = length(wp - CAMERA_POSITION_WORLD);
	c = mix(c, bg, smoothstep(14., 34., fd));
	ALBEDO = srgb_to_linear(pow(c, vec3(.95)));
}
