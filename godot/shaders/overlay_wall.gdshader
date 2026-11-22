// Coastal side walls (drawWalls in 08e-company.js): a vertical face hangs from every coastline segment on its
// water side, so the land looks raised above the sea. The upper half is soil shaded by the light, the lower
// half is water; dark lines at the ends, a light line at the water level. The height follows the view like
// the original. Faces turned away from the camera collapse; a face never hangs over land in front of it: the
// pixel's ground point is looked up in the land mask (the original clips to the lattice's water triangles).
// Drawn on the 2D canvas (sRGB blending like the browser).
shader_type canvas_item;

uniform mat4 view_proj;
uniform mat4 inv_view_proj;
uniform vec2 screen;
uniform vec3 eye;
uniform float wall_h = 0.0625;
uniform bool lines = false;
uniform sampler2D land : filter_nearest;
uniform vec2 world;      // WX, WZ
uniform sampler2D t0 : filter_linear, repeat_disable;   // the map's terrain: height in r, the diagonal in g
uniform float triS = 10.0;
uniform vec2 MWH = vec2(1800.0, 1200.0);
const float NEAR = 0.1;  // the camera's near plane: what lies behind it is cut off, never projected

varying float v_part;    // faces: 0 soil, 1 water; lines: 0 dark, 1 light
varying float v_shade;
varying float v_d;       // lines: the distance across the line in px

// the centre of the lattice triangle under uv (triInfo of map.gdshader): land and sea follow these triangles
vec2 tri_centre(vec2 uv) {
	vec2 q = uv * MWH / triS;
	vec2 fl = floor(q), fr = q - fl;
	float dg = textureLod(t0, (fl + .5) * triS / MWH, 0.).g;
	vec2 c;
	if (dg > .5) c = mix(vec2(1. / 3., 2. / 3.), vec2(2. / 3., 1. / 3.), step(fr.y, fr.x));
	else c = mix(vec2(1. / 3.), vec2(2. / 3.), step(1., fr.x + fr.y));
	return (fl + c) * triS / MWH;
}

// a segment of clip-space points cut at the near plane: false when all of it is behind the camera
bool clip_seg(inout vec4 a, inout vec4 b) {
	if (a.w < NEAR && b.w < NEAR) return false;
	if (a.w < NEAR) a = mix(a, b, (NEAR - a.w) / (b.w - a.w));
	if (b.w < NEAR) b = mix(b, a, (NEAR - b.w) / (a.w - b.w));
	return true;
}

vec2 to_px(vec4 c) {
	vec2 hs = screen * 0.5;
	vec2 s = c.xy / c.w * hs;
	return vec2(s.x + hs.x, hs.y - s.y);
}

// INSTANCE_CUSTOM: the segment (x1, z1, x2, z2); COLOR: (nx, nz, light level 0…6, 0) of the instance.
// faces: VERTEX = (t along the segment, depth 0 / .5 / 1), UV.x = part.
// lines: VERTEX = (t along, depth), UV = (side ±1, line: 0 end 1, 1 end 2, 2 the water line)
void vertex() {
	vec2 p1 = INSTANCE_CUSTOM.xy, p2 = INSTANCE_CUSTOM.zw;
	vec2 n = COLOR.xy;
	v_shade = COLOR.z;
	vec2 m = (p1 + p2) * 0.5;
	bool facing = n.x * (eye.x - m.x) + n.y * (eye.z - m.y) > 0.0;
	vec2 outp = vec2(-1e5);
	// a wall with a corner behind the camera is left out, like drawWalls (project() of a corner fails)
	bool whole = true;
	for (int k = 0; k < 4; k++) {
		vec2 q = k % 2 == 0 ? p1 : p2;
		vec4 c = view_proj * vec4(q.x, k < 2 ? 0.0 : -wall_h, q.y, 1.0);
		if (c.w < NEAR) whole = false;
	}
	if (facing && whole && wall_h > 0.0) {
		if (!lines) {
			// the edge of the face at this depth, cut at the near plane, then the point along it
			vec4 ca = view_proj * vec4(p1.x, -VERTEX.y * wall_h, p1.y, 1.0);
			vec4 cb = view_proj * vec4(p2.x, -VERTEX.y * wall_h, p2.y, 1.0);
			if (clip_seg(ca, cb)) outp = to_px(mix(ca, cb, VERTEX.x));
			v_part = UV.x;
		} else {
			float id = UV.y;
			vec3 a, b;
			if (id < 0.5) { a = vec3(p1.x, 0.0, p1.y); b = vec3(p1.x, -wall_h, p1.y); }
			else if (id < 1.5) { a = vec3(p2.x, 0.0, p2.y); b = vec3(p2.x, -wall_h, p2.y); }
			else { a = vec3(p1.x, -wall_h * 0.5, p1.y); b = vec3(p2.x, -wall_h * 0.5, p2.y); }
			vec4 ca = view_proj * vec4(a, 1.0), cb = view_proj * vec4(b, 1.0);
			if (clip_seg(ca, cb)) {
				vec2 sa = to_px(ca), sb = to_px(cb);
				vec2 d = sb - sa;
				float L = length(d);
				vec2 nn = L > 1e-6 ? vec2(-d.y, d.x) / L : vec2(0.0, 1.0);
				outp = mix(sa, sb, VERTEX.x) + nn * UV.x * 1.5;
				v_d = UV.x * 1.5;
			}
			v_part = id > 1.5 ? 1.0 : 0.0;
		}
	}
	VERTEX = outp;
}

void fragment() {
	// the ground under this pixel: land in front of the wall hides it
	vec2 ndc = vec2(FRAGCOORD.x / screen.x * 2.0 - 1.0, 1.0 - FRAGCOORD.y / screen.y * 2.0);
	vec4 a = inv_view_proj * vec4(ndc, -1.0, 1.0), b = inv_view_proj * vec4(ndc, 1.0, 1.0);
	vec3 A = a.xyz / a.w, B = b.xyz / b.w;
	float t = A.y / (A.y - B.y);
	vec3 g = mix(A, B, t);
	vec2 uv = (g.xz + world * 0.5) / world;
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0 && textureLod(t0, tri_centre(uv), 0.).r >= 0.0) discard;
	if (lines) {
		float al = clamp(1.0 - abs(v_d), 0.0, 1.0);
		COLOR = v_part > 0.5 ? vec4(170.0, 225.0, 250.0, 255.0 * 0.45 * al) / 255.0 : vec4(10.0, 16.0, 22.0, 255.0 * 0.45 * al) / 255.0;
	} else {
		float sh = 0.62 + 0.38 * v_shade / 6.0;
		COLOR = v_part < 0.5 ? vec4(round(vec3(112.0, 80.0, 54.0) * sh) / 255.0, 1.0)
			: vec4(round(vec3(18.0 + 22.0 * sh, 62.0 + 40.0 * sh, 92.0 + 40.0 * sh)) / 255.0, 0.72);
	}
}
