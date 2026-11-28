// The start menu's name (TRYROUTE): its letters as they are, with a slanted band of light that runs across them
// now and then (StartMenu sets the band's place in the label's own pixels).
shader_type canvas_item;

uniform float band = -10000.0;   // the band's centre along x (label pixels; far left when there is none)
uniform float width = 26.0;      // its half-width
uniform float slant = .55;       // how much it leans

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec4 c = COLOR * texture(TEXTURE, UV);
	float d = (lp.x + lp.y * slant - band) / width;
	float g = exp(-d * d) * .85 + exp(-d * d * 9.0) * .35;   // a soft glow, a brighter core
	c.rgb = mix(c.rgb, vec3(1.0), clamp(g, 0.0, 1.0));
	COLOR = c;
}
