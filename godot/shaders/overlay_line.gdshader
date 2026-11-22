// Lines on the map with a width in screen pixels, like the strokes of the HTML version's 2D canvas
// (drawBorders, drawLogistics). Drawn on the 2D canvas, which blends in sRGB like the browser. One instance
// per segment (INSTANCE_CUSTOM = its ends in world units) or per vertex (a disc: round joins and caps); the
// vertex shader projects the ends with the camera matrix and widens the quad in screen space. Edges are
// antialiased here. A translucent stroke is drawn opaque inside a CanvasGroup and composited once with its
// alpha (LineLayer.gd), so overlapping segments do not darken.
shader_type canvas_item;

uniform mat4 view_proj;
uniform vec2 screen;
uniform float width_px = 2.0;
uniform vec3 color = vec3(1.0);
uniform bool discs = false;

varying vec2 v_d;       // the offset from the line (segments: x only) in pixels
varying float v_w;

vec4 clip_of(vec2 p) {
	return view_proj * vec4(p.x, 0.0, p.y, 1.0);
}

// the unit quad: segments VERTEX = (t: 0 at a, 1 at b; side ±1); discs VERTEX = corner (±1, ±1)
void vertex() {
	vec2 hs = screen * 0.5;
	float w = max(width_px, 0.0);
	float ext = max(w, 1.0) * 0.5 + 1.0;   // one more pixel for the antialiased edge
	v_w = w;
	const float EPS = 0.02;
	vec2 s = vec2(-1e5);
	v_d = vec2(0.0);
	if (discs) {
		vec4 pa = clip_of(INSTANCE_CUSTOM.xy);
		if (pa.w >= EPS) {
			s = pa.xy / pa.w * hs + VERTEX * ext;
			v_d = VERTEX * ext;
		}
	} else {
		vec4 pa = clip_of(INSTANCE_CUSTOM.xy), pb = clip_of(INSTANCE_CUSTOM.zw);
		if (pa.w >= EPS || pb.w >= EPS) {
			// a segment crossing the camera plane is cut where it leaves the view (clipPath)
			if (pa.w < EPS) pa = mix(pa, pb, (EPS - pa.w) / (pb.w - pa.w));
			if (pb.w < EPS) pb = mix(pb, pa, (EPS - pb.w) / (pa.w - pb.w));
			vec2 sa = pa.xy / pa.w * hs, sb = pb.xy / pb.w * hs;
			vec2 d = sb - sa;
			float L = length(d);
			vec2 n = L > 1e-6 ? vec2(-d.y, d.x) / L : vec2(0.0, 1.0);
			s = mix(sa, sb, VERTEX.x) + n * VERTEX.y * ext;
			v_d = vec2(VERTEX.y * ext, 0.0);
		}
	}
	VERTEX = vec2(s.x + hs.x, hs.y - s.y);   // NDC → pixels, y down
}

void fragment() {
	// a line thinner than a pixel is drawn one pixel wide with its width as the alpha (like the browser)
	float d = length(v_d);
	float a = clamp(max(v_w, 1.0) * 0.5 + 0.5 - d, 0.0, 1.0) * min(v_w, 1.0);
	if (a <= 0.0) discard;
	COLOR = vec4(color, a);
}
