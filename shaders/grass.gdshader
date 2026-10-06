shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;
// Hierba: matas con el color de su terreno (color por instancia), que ondean con el viento y se
// apartan al paso de Lía. La luz mezcla la normal del suelo (para que la pradera se funda con el
// terreno) con la de cada brizna (curvada y doblada en V), así cada hoja tiene su lado claro y
// su lado en sombra; a contraluz las briznas se transparentan. Cada brizna lleva su tono y su
// fase de viento (UV2.x), y la raíz queda en penumbra entre las demás.

global uniform vec3 player_pos;
global uniform vec2 wind_dir;

uniform float tip_bright = 1.2;
uniform float base_dark = 0.86;
uniform float wind_strength = 0.35;
// Cuánto pesa la normal de la brizna frente a la del suelo.
uniform float blade_normal = 0.24;

#include "res://shaders/toon_light.gdshaderinc"
#include "res://shaders/noise.gdshaderinc"

varying float tip;
varying vec3 inst_col;
varying vec3 root_w;
varying float blade_rnd;

void vertex() {
	tip = clamp(UV.y, 0.0, 1.0);
	blade_rnd = UV2.x;
	inst_col = INSTANCE_CUSTOM.rgb;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	root_w = root;
	v_cloud = cloud_mask(root);
	float k = tip * tip;
	// Ráfagas que recorren la pradera, más un temblor propio de cada brizna.
	float gust = sin(TIME * 1.3 + dot(root.xz, wind_dir) * 0.12) * 0.5 + 0.5;
	gust *= 0.75 + 0.25 * sin(TIME * 0.37 + dot(root.xz, vec2(0.031, 0.047)));
	float flutter = sin(TIME * (3.2 + blade_rnd * 1.6) + root.x * 0.9 + root.z * 0.7 + blade_rnd * 6.28) * 0.22;
	vec2 wd = normalize(wind_dir);
	vec3 offs = vec3(wd.x, 0.0, wd.y) * (gust * 0.8 + flutter) * wind_strength * k;
	vec3 away = root - player_pos;
	float dy = abs(away.y);
	away.y = 0.0;
	float dist = length(away);
	float push = (1.0 - smoothstep(0.4, 1.5, dist)) * (1.0 - smoothstep(1.0, 2.5, dy));
	offs += normalize(away + vec3(0.0001, 0.0, 0.0)) * push * 0.7 * k;
	// Al doblarse la brizna baja un poco (no se estira).
	offs.y -= (length(offs.xz) * 0.35 + push * 0.3) * k;
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * offs;
	// Pegada a la cámara (cuando roza el suelo), la mata se agacha para no tapar la vista.
	float camd = distance(root, INV_VIEW_MATRIX[3].xyz);
	VERTEX.y *= mix(0.08, 1.0, smoothstep(0.5, 1.7, camd));
}

void fragment() {
	// Las mismas manchas que el terreno, para que la raíz no se note.
	float n = vnoise(root_w.xz * 0.18) * 0.6 + vnoise(root_w.xz * 0.9) * 0.4;
	vec3 c = inst_col * mix(0.94, 1.06, smoothstep(0.45, 0.55, n));
	// Cada brizna, un poco más clara, más oscura o más amarilla que sus vecinas.
	c *= mix(0.9, 1.08, blade_rnd);
	c = mix(c, c * vec3(1.08, 1.04, 0.82), smoothstep(0.78, 1.0, blade_rnd) * tip);
	// Puntas más claras y cálidas; la raíz en penumbra (oclusión entre briznas).
	vec3 tip_col = c * tip_bright + vec3(0.04, 0.04, 0.0);
	float ao = mix(base_dark, 1.0, smoothstep(0.0, 0.6, tip));
	ALBEDO = mix(c, tip_col, smoothstep(0.2, 1.0, tip)) * ao;
	// Normal: mezcla de la del suelo y la de la brizna (de cara a la cámara en las dos caras).
	vec3 ground_n = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 bn = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = normalize(mix(ground_n, bn, blade_normal * (0.4 + 0.6 * tip)));
	// Oclusión ambiental entre briznas: la luz del cielo llega poco a la raíz (y así la luz
	// pálida del horizonte no lava el verde).
	AO = mix(0.55, 0.95, smoothstep(0.0, 0.9, tip));
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
