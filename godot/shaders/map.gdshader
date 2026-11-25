// Map surface: port of the HTML version's map fragment shader (legacy/src/04-map.js, FSsrc, board lattice).
// The whole board is one plane; land, sea, state colours, border shading, sun glints and the board frame
// all come from the textures built by TRWorldGen.build_textures(). The shader works in sRGB like the
// original (WebGL writes sRGB directly) and converts to linear only at the very end.
// Not ported because the board never uses them: the coastal wall slab (wallOff=1 on the board),
// the occupation hatching (hasOcc), the fine logistics grid (lgrid: only off the board).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform float haze = 1.0;   // the distance haze (0 in the map editor: the whole board stays clear)

uniform sampler2D t0 : filter_linear_mipmap_anisotropic, repeat_disable;   // terrain: coast/height, diagonal, light, noise
uniform sampler2D tb : filter_linear_mipmap_anisotropic, repeat_disable;   // distance to a state border
uniform sampler2D t1 : filter_nearest, repeat_disable;                     // state id + 1 (R8)
uniform float triS = 10.0;
uniform vec2 MWH = vec2(1800.0, 1200.0);    // texture size
uniform vec2 WSZ = vec2(22.5, 15.0);        // world size
uniform vec3 col[120];
uniform int hov = -1;
uniform int sel = -1;
uniform float glint = 1.0;
// the coastal walls (WallMesh) hang from the coast this far down (0: no walls); the water's depth is written
// well below them, so land in front of a wall hides it and water lets it show
uniform float wall_h = 0.0;   // slow glints on the water triangles (settings)

uniform float night = 0.0;   // the test day and night: 0 day … 1 night
// the map editor: its lattice is drawn at once, before the textures are built again (MapEditor):
// one texel a square, r / g the owner of the half h0 / h1 (0 sea, state id + 1, 121 neutral), b the diagonal
uniform bool edit_on = false;
uniform sampler2D tE : filter_nearest, repeat_disable;
uniform vec2 SQWH = vec2(180.0, 120.0);

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
	return uint(round(textureLod(t1, uv, 0.).r * 255.0)) & 127u;
}
float hsh(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
vec3 cc(uint id) {
	return id >= 122u ? vec3(.36, .385, .41) : id == 121u ? vec3(.50, .50, .47) : id > 0u ? col[int(id) - 1] : vec3(.42, .45, .48);
}
vec4 edAt(vec2 fl) {
	return texelFetch(tE, ivec2(clamp(fl, vec2(0.), SQWH - 1.)), 0);
}
float diagAt(vec2 fl) {
	return edit_on ? edAt(fl).b : textureLod(t0, (fl + .5) * triS / MWH, 0.).g;
}
// the colour of the lattice triangle that holds q (in lattice squares): sea by depth, land by state, glints;
// bd (distance to a state border) and hatch are the pixel's own. land: 1 on land
vec3 triCol(vec2 q, float bd, float hatch, out float land) {
	vec2 fl = floor(q), fr = q - fl;
	float dg = diagAt(fl);
	float tup;
	vec2 cc_;
	if (dg > .5) {
		tup = step(fr.y, fr.x);
		cc_ = mix(vec2(1. / 3., 2. / 3.), vec2(2. / 3., 1. / 3.), tup);
	} else {
		tup = step(1., fr.x + fr.y);
		cc_ = mix(vec2(1. / 3.), vec2(2. / 3.), tup);
	}
	vec2 tcuv = clamp((fl + cc_) * triS / MWH, 0., 1.);
	float tH = hsh(fl * vec2(1.13, .91) + tup * vec2(.37, .71));
	float h = textureLod(t0, tcuv, 0.).r;
	uint eid = 0u;
	if (edit_on) {   // the half: across the diagonal "\\" tup 1 is h0, across "/" it is h1
		vec4 e = edAt(fl);
		eid = uint(round((dg > .5 ? (tup > .5 ? e.r : e.g) : (tup > .5 ? e.g : e.r)) * 255.));
		h = eid > 0u ? max(h, .01) : min(h, -.035);
	}
	land = step(0., h);
	// ---- sea
	float depth = clamp(-h, 0., 1.);
	vec3 deep = vec3(.03, .13, .24), mid = vec3(.06, .27, .42), shal = vec3(.16, .52, .66);
	vec3 w = mix(shal, mid, smoothstep(0., .18, depth));
	w = mix(w, deep, smoothstep(.18, .85, depth));
	w += vec3(.12, .22, .24) * exp(-depth * 45.);
	w = w * (.84 + .32 * tH) + vec3(0., .035, .045) * (tH - .5);
	// ---- glints: now and then a water triangle slowly lights up (or darkens a little) and slowly returns.
	// Every triangle has its own slow cycle (26…46 s) and is lit only in a short part of it (4…8 s);
	// only one in five takes part, so at any moment just a few are changing
	if (glint > 0.) {
		vec2 k = fl + tup * vec2(.5, .25);
		float g1 = hsh(k * vec2(3.17, 1.93) + 11.3), g2 = hsh(k * vec2(7.31, 4.77) + 2.9), g3 = hsh(k * vec2(2.71, 8.13) + 5.7);
		float per = 26. + 20. * g1;
		float ph = fract(TIME / per + g2);
		float win = .12 + .06 * g3;
		float e = ph < win ? sin(3.14159265 * ph / win) : 0.;
		e = e * e * step(.8, hsh(k * vec2(5.53, 3.11) + 7.7));
		e *= glint * smoothstep(.0, .04, depth);
		if (g3 > .72) {
			w *= 1. - .16 * e;   // a darker patch
		} else {
			w += vec3(.07, .13, .16) * e;
		}
	}
	// ---- land: state colour
	uint id = edit_on ? eid : idAt(tcuv);
	vec3 L = cc(id);
	uint su = uint(sel + 1), hu = uint(hov + 1);
	float fs = sel < 0 ? 0. : float(id == su);
	if (id == 121u) {
		L *= hatch;
	}
	float fh = hov < 0 ? 0. : float(id == hu);
	L *= mix(.88, 1., smoothstep(1.6, 12., bd));
	L *= .95 + .1 * tH;
	L += vec3(.06) * fh;
	L = mix(L, L * 1.08 + vec3(.03, .05, .07) + vec3(.35, .7, .9) * (1. - smoothstep(1.2, 14., bd)) * (.35 + .12 * sin(TIME * 3.)), fs);
	return mix(w, L, land);
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
		// a soft shadow under the board and a faint blue halo, both fading out exponentially: no edge where
		// a falloff ends (smoothstep over 0.9 left a visible band around the board)
		cf *= 1. - .6 * exp(-dd * 2.4);
		cf += vec3(.03, .085, .14) * exp(-dd * 3.2) * .55;
	}
	c = cf;
	float is_land = 0.;
	if (sd > -fe * 2.) {
		uv = clamp(uv, 0., 1.);
		float bd = texture(tb, uv).r;
		// the hatching of id 121 (per pixel: its stripes do not follow the triangles)
		vec2 hp = wp.xz * 55.;
		float hst = abs(fract((hp.x + hp.y) * .5) - .5);
		float hsw = fwidth((hp.x + hp.y) * .5);
		float hatch = 1. - .14 * (1. - smoothstep(.12, .12 + hsw * 1.5, hst)) * (1. - smoothstep(.15, .4, hsw));
		// the lattice triangle of this pixel and its colour
		vec2 q = uv * MWH / triS;
		float land;
		vec3 tri = triCol(q, bd, hatch, land);
		// the edges of the triangles smoothed in the shader itself: the nearest edge (a side of the square or its
		// drawn diagonal) in screen pixels, and within half a pixel of it the triangle across it mixed in — smooth
		// at any zoom without rendering the map larger
		vec2 fl = floor(q), fr = q - fl;
		float dg = diagAt(fl);
		float sdg = dg > .5 ? fr.x - fr.y : fr.x + fr.y - 1.;
		float pdg = abs(sdg) / max(fwidth(sdg), 1e-6);
		float sx = fr.x - .5, sy = fr.y - .5;
		float px_ = (.5 - abs(sx)) / max(fwidth(q.x), 1e-6);
		float py_ = (.5 - abs(sy)) / max(fwidth(q.y), 1e-6);
		float pm = min(pdg, min(px_, py_));
		c = tri;
		if (pm < .5) {
			vec2 qn;
			if (pm == pdg) {
				vec2 dir = dg > .5 ? vec2(1., -1.) : vec2(1., 1.);
				qn = q - sign(sdg) * dir * (abs(sdg) + .01) * .5;
			} else if (pm == px_) {
				qn = vec2(sx > 0. ? fl.x + 1.01 : fl.x - .01, q.y);
			} else {
				qn = vec2(q.x, sy > 0. ? fl.y + 1.01 : fl.y - .01);
			}
			float ln;
			vec3 nb = triCol(qn, bd, hatch, ln);
			float k = .5 - pm;
			c = mix(tri, nb, k);
			land = mix(land, ln, k);
		}
		land = step(.5, land);
		is_land = land * step(0., sd);
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
	// the distance haze: the farther from the camera, the more the background (zoomed out the board darkens)
	float fd = length(wp - CAMERA_POSITION_WORLD);
	c = mix(c, bg, smoothstep(14., 34., fd) * haze);
	c = mix(c, c * vec3(.26, .33, .52) + vec3(.004, .01, .03), night);
	ALBEDO = srgb_to_linear(pow(c, vec3(.95)));
	// the depth: land where it is, water far below (3 world units, the tallest wall is ~.4): a wall shows
	// wherever the ray to it meets water first, as drawWalls did, and land in front hides it
	float yy = is_land > .5 || wall_h <= 0. ? wp.y : wp.y - 3.0;
	vec4 cp = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp.x, yy, wp.z, 1.0));
	DEPTH = cp.z / cp.w;
}
