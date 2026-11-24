// Coastal side walls (drawWalls in 08e-company.js) as real 3D faces: one static mesh, a vertical face on the
// water side of every coastline segment. The map shader writes the depth of the water a little lower than the
// walls' foot, so the depth buffer itself hides a wall wherever land lies in front of it and shows it over
// the water: no projection by hand, no clipping at the camera, no ray per pixel, right at any turn.
// The upper half is soil shaded by the light, the lower half water; thin dark lines at the ends and a light
// line at the water level, ~1.5 px whatever the zoom.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float wall_h = 0.0625;    // the height, following the view like the original (set by MapView)

varying float v_face;
varying vec3 v_wp;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// VERTEX.y: −(0 … 1) of the height; NORMAL: towards the water; COLOR = (light 0…1, part 0 soil / 1 water);
// UV = (metres along the segment, the share of the height); UV2.x = the segment's length
void vertex() {
	VERTEX.y *= wall_h;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_face = dot(NORMAL.xz, CAMERA_POSITION_WORLD.xz - v_wp.xz);
}

void fragment() {
	if (v_face <= 0.0) discard;     // a face turned away from the camera
	float sh = 0.62 + 0.38 * COLOR.r;
	vec3 c;
	float a;
	if (COLOR.g < 0.5) {
		c = round(vec3(112.0, 80.0, 54.0) * sh) / 255.0;
		a = 1.0;
	} else {
		c = round(vec3(18.0 + 22.0 * sh, 62.0 + 40.0 * sh, 92.0 + 40.0 * sh)) / 255.0;
		a = 0.86;   // the original's .72 blended in sRGB (a browser canvas); this blends in linear light
	}
	// the lines: the ends of the segment (dark) and the water level (light), in pixels
	float ends = min(UV.x, UV2.x - UV.x) / max(fwidth(UV.x), 1e-6);
	float lvl = abs(UV.y - 0.5) / max(fwidth(UV.y), 1e-6);
	float al_end = clamp(1.5 - ends, 0.0, 1.0) * 0.45;
	float al_lvl = clamp(1.5 - lvl, 0.0, 1.0) * 0.3;   // .45 in sRGB blending looked like this
	c = mix(c, vec3(10.0, 16.0, 22.0) / 255.0, al_end);
	c = mix(c, vec3(170.0, 225.0, 250.0) / 255.0, al_lvl);
	a = max(a, max(al_end, al_lvl));
	// the same distance fade as the map
	float fd = length(v_wp - CAMERA_POSITION_WORLD);
	float fog = smoothstep(14., 34., fd);
	c = mix(c, vec3(.022, .038, .055), fog);
	ALBEDO = srgb_to_linear(pow(c, vec3(.95)));
	ALPHA = a;
}
