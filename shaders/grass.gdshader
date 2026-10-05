shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;
// Hierba: matas con el color de su terreno (color por instancia), que ondean con el
// viento y se apartan al paso de Lía. Se ilumina con la normal del suelo (las dos caras
// igual) para que la pradera se funda con el terreno, como en los dibujos animados.

global uniform vec3 player_pos;
global uniform vec2 wind_dir;

uniform float tip_bright = 1.2;
uniform float base_dark = 0.93;
uniform float wind_strength = 0.35;

#include "res://shaders/toon_light.gdshaderinc"
#include "res://shaders/noise.gdshaderinc"

varying float tip;
varying vec3 inst_col;
varying vec3 root_w;

void vertex() {
	tip = clamp(UV.y, 0.0, 1.0);
	inst_col = INSTANCE_CUSTOM.rgb;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	root_w = root;
	v_cloud = cloud_mask(root);
	float k = tip * tip;
	float gust = sin(TIME * 1.3 + dot(root.xz, wind_dir) * 0.12) * 0.5 + 0.5;
	float flutter = sin(TIME * 3.7 + root.x * 0.9 + root.z * 0.7) * 0.25;
	vec2 wd = normalize(wind_dir);
	vec3 offs = vec3(wd.x, 0.0, wd.y) * (gust * 0.8 + flutter) * wind_strength * k;
	vec3 away = root - player_pos;
	float dy = abs(away.y);
	away.y = 0.0;
	float dist = length(away);
	float push = (1.0 - smoothstep(0.4, 1.5, dist)) * (1.0 - smoothstep(1.0, 2.5, dy));
	offs += normalize(away + vec3(0.0001, 0.0, 0.0)) * push * 0.7 * k;
	offs.y -= push * 0.35 * k;
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * offs;
}

void fragment() {
	// Las mismas manchas que el terreno, para que la raíz no se note.
	float n = vnoise(root_w.xz * 0.18) * 0.6 + vnoise(root_w.xz * 0.9) * 0.4;
	vec3 c = inst_col * mix(0.94, 1.06, smoothstep(0.45, 0.55, n));
	// Puntas más claras y algo más cálidas; la raíz apenas más oscura que el suelo.
	vec3 tip_col = c * tip_bright + vec3(0.05, 0.05, 0.0);
	ALBEDO = mix(c * base_dark, tip_col, smoothstep(0.15, 1.0, tip));
	// Normal del suelo en las dos caras (sin esto la cara trasera sale negra).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
