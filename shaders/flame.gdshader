shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Llama de hoguera: una lengua de fuego que mira a la cámara (girando solo en vertical),
// dibujada con ruido que sube y la deforma: núcleo casi blanco, cuerpo naranja y bordes rojos
// que se deshacen arriba.

uniform float intensity = 2.0;
uniform float seed = 0.0;
uniform float speed = 2.2;

#include "res://shaders/noise.gdshaderinc"

void vertex() {
	// Cartel vertical: mira a la cámara pero se mantiene de pie.
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = cross(right, up);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * sx, 0.0), vec4(up * sy, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	float y = 1.0 - UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME * speed;
	float n1 = vnoise(vec2(x * 2.2 + seed * 7.0, y * 3.0 - t));
	float n2 = vnoise(vec2(x * 5.0 - seed * 3.0, y * 6.0 - t * 1.7));
	// Lengua: ancha abajo, afilada arriba, retorcida por el ruido (más cuanto más alta).
	float xd = x + (n1 - 0.5) * 0.9 * y + (n2 - 0.5) * 0.25 * y;
	float width = mix(0.85, 0.05, pow(y, 0.8)) * (0.8 + n2 * 0.4);
	float body = 1.0 - smoothstep(width * 0.55, width, abs(xd));
	body *= smoothstep(0.0, 0.08, y);
	body *= 1.0 - smoothstep(0.55 + n1 * 0.35, 1.0, y);
	float core = (1.0 - smoothstep(width * 0.15, width * 0.5, abs(xd))) * (1.0 - smoothstep(0.15, 0.6, y));
	vec3 red = vec3(1.0, 0.22, 0.05);
	vec3 orange = vec3(1.0, 0.55, 0.12);
	vec3 yellow = vec3(1.0, 0.92, 0.55);
	vec3 col = mix(red, orange, smoothstep(0.0, 0.6, body)) ;
	col = mix(col, yellow, core);
	ALBEDO = col * body * intensity;
}
