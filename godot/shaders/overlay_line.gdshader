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
uniform float hatch = 0.0;          // > 0: stripes across the line, this many pixels apart (toll motorways)
uniform vec3 color2 = vec3(0.0);    // the stripes' colour

varying vec2 v_d;       // the offset from the line (segments: x only) in pixels
varying float v_w;
varying vec2 v_p;       // the screen position in pixels (the stripes run on from one segment to the next)
varying vec2 v_t;       // the segment's direction on the screen (zero for the discs)

vec4 clip_of(vec2 p) {
	return view_proj * vec4(p.x, 0.0, p.y, 1.0);
}

// the unit quad: segments VERTEX = (t: 0 at a, 1 at b; side ±1); discs VERTEX = corner (±1, ±1)
void vertex() {
	vec2 hs = screen * 0.5;
	float w = max(width_px, 0.0);
	float ext = max(w, 1.0) * 0.5 + 1.5;   // room for the antialiased edge
	v_w = w;
	const float EPS = 0.1;   // the camera's near plane: nothing behind it is projected
	vec2 s = vec2(-1e5);
	v_d = vec2(0.0);
	v_t = vec2(0.0);
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
			v_t = L > 1e-6 ? d / L : vec2(1.0, 0.0);
		}
	}
	v_p = s;
	VERTEX = vec2(s.x + hs.x, hs.y - s.y);   // NDC → pixels, y down
}

void fragment() {
	// a line thinner than a pixel is drawn one pixel wide with its width as the alpha (like the browser)
	float d = length(v_d);
	// the edge fades over ~1.4 px (analytic anti-aliasing: smooth diagonals without a supersampled buffer)
	float a = clamp((max(v_w, 1.0) * 0.5 + 0.7 - d) / 1.4, 0.0, 1.0) * min(v_w, 1.0);
	if (a <= 0.0) discard;
	vec3 c = color;
	if (hatch > 0.0 && dot(v_t, v_t) > 0.25) {
		// stripes slanted at 45° to the line, in screen pixels: as wide at every zoom, and continuous along a
		// straight run made of many segments; the edges antialiased over a pixel
		vec2 n = vec2(-v_t.y, v_t.x);
		float u = (dot(v_p, v_t) + dot(v_p, n)) * 0.70710678;   // pixels across the stripes
		float f = fract(u / hatch);
		float edge = min(abs(f - 0.5), min(f, 1.0 - f)) * hatch;   // pixels to the nearest stripe edge
		float on = f >= 0.5 ? 1.0 : 0.0;
		c = mix(color, color2, mix(0.5, on, clamp(edge, 0.0, 1.0)));
	}
	COLOR = vec4(c, a);
}
