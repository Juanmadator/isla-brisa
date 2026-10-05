shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Rayos de luz giratorios detrás de un objeto recién descubierto (siempre de cara a la cámara).

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float rays = 12.0;
uniform float speed = 0.35;
uniform float intensity = 0.8;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float beams = smoothstep(0.35, 0.75, sin(a * rays + TIME * speed * 6.2831) * 0.5 + 0.5);
	float beams2 = smoothstep(0.55, 0.9, sin(a * rays * 0.5 - TIME * speed * 3.0 + 1.3) * 0.5 + 0.5);
	float fall = (1.0 - smoothstep(0.15, 1.0, r));
	float core = 1.0 - smoothstep(0.0, 0.35, r);
	float v = (max(beams, beams2 * 0.7) * fall + core * 0.9) * intensity;
	ALBEDO = color.rgb * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
