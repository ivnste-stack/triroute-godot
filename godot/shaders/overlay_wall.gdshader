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

varying float v_part;    // faces: 0 soil, 1 water; lines: 0 dark, 1 light
varying float v_shade;
varying float v_d;       // lines: the distance across the line in px

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
	if (facing && wall_h > 0.0) {
		if (!lines) {
			vec2 g = mix(p1, p2, VERTEX.x);
			vec4 c = view_proj * vec4(g.x, -VERTEX.y * wall_h, g.y, 1.0);
			if (c.w > 0.02) outp = to_px(c);
			v_part = UV.x;
		} else {
			float id = UV.y;
			vec3 a, b;
			if (id < 0.5) { a = vec3(p1.x, 0.0, p1.y); b = vec3(p1.x, -wall_h, p1.y); }
			else if (id < 1.5) { a = vec3(p2.x, 0.0, p2.y); b = vec3(p2.x, -wall_h, p2.y); }
			else { a = vec3(p1.x, -wall_h * 0.5, p1.y); b = vec3(p2.x, -wall_h * 0.5, p2.y); }
			vec4 ca = view_proj * vec4(a, 1.0), cb = view_proj * vec4(b, 1.0);
			if (ca.w > 0.02 && cb.w > 0.02) {
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
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0 && texture(land, uv).r > 0.5) discard;
	if (lines) {
		float al = clamp(1.0 - abs(v_d), 0.0, 1.0);
		COLOR = v_part > 0.5 ? vec4(170.0, 225.0, 250.0, 255.0 * 0.45 * al) / 255.0 : vec4(10.0, 16.0, 22.0, 255.0 * 0.45 * al) / 255.0;
	} else {
		float sh = 0.62 + 0.38 * v_shade / 6.0;
		COLOR = v_part < 0.5 ? vec4(round(vec3(112.0, 80.0, 54.0) * sh) / 255.0, 1.0)
			: vec4(round(vec3(18.0 + 22.0 * sh, 62.0 + 40.0 * sh, 92.0 + 40.0 * sh)) / 255.0, 0.72);
	}
}
