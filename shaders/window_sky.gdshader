shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Cristal de las ventanas del interior: deja ver el cielo de esta hora (no el mundo de verdad,
// que queda lejos), con un brillo suave y algo de reflejo de la habitación de noche.

global uniform vec4 sky_top;
global uniform vec4 sky_horizon;
global uniform float night_amount;

void fragment() {
	vec3 sky = mix(sky_horizon.rgb, sky_top.rgb, smoothstep(0.0, 1.0, 1.0 - UV.y));
	// Un poco más claro hacia abajo (luz que entra) y vaho en los bordes.
	vec2 e = min(UV, 1.0 - UV);
	float edge = 1.0 - smoothstep(0.0, 0.12, min(e.x, e.y));
	vec3 c = sky * 1.15 + vec3(0.04, 0.05, 0.06) * edge;
	// De noche el cristal refleja algo del interior cálido.
	c = mix(c, c + vec3(0.12, 0.08, 0.04), night_amount * 0.6);
	ALBEDO = c;
}
