shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled, skip_vertex_transform;
// Follaje de los árboles: tarjetas que miran a la cámara, cada una con un racimo de hojas
// recortado (alpha scissor). La normal sale del centro de la copa, así que la copa entera
// se ilumina como un volumen suave; a contraluz el sol se cuela entre las hojas.

uniform vec4 albedo : source_color = vec4(1.0);
// Color por instancia (MultiMesh); en mallas sueltas, desactivado y manda `albedo`.
uniform bool use_instance_tint = true;
uniform float sway = 1.0;
// Multiplica el tamaño de cada tarjeta (que va en COLOR.r, en metros).
uniform float card_size = 1.0;
uniform float leaf_count : hint_range(3.0, 14.0) = 11.0;
// Medio ancho y medio largo de cada hoja dentro de la tarjeta (agujas de pino: finas).
uniform vec2 leaf_shape = vec2(0.135, 0.3);

global uniform vec2 wind_dir;

#include "res://shaders/toon_light.gdshaderinc"
#include "res://shaders/noise.gdshaderinc"

varying vec3 inst_tint;
varying float seed;
varying float depth_in;

float h1(float x) {
	return hash(vec2(x * 13.7 + 1.3, x * 7.1 + 5.9));
}

void vertex() {
	inst_tint = use_instance_tint ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	seed = UV2.x;
	depth_in = UV2.y;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_cloud = cloud_mask(root + VERTEX);
	vec3 local = VERTEX;
	// Balanceo con el viento (más arriba, más se mueve) y un temblor propio de cada tarjeta.
	float s = sin(TIME * 1.1 + root.x * 0.13 + root.z * 0.11) * 0.6 + sin(TIME * 2.3 + root.x * 0.4) * 0.25;
	local.xz += normalize(wind_dir) * s * sway * max(local.y, 0.0) * max(local.y, 0.0) * 0.01;
	local += vec3(sin(TIME * 3.1 + seed * 40.0), 0.0, cos(TIME * 2.7 + seed * 31.0)) * 0.04 * sway;
	vec3 view_c = (MODELVIEW_MATRIX * vec4(local, 1.0)).xyz;
	// La tarjeta se abre en el plano de la pantalla, girada al azar.
	float ang = seed * 6.2831;
	vec2 corner = (UV - 0.5) * 2.0;
	corner = vec2(cos(ang) * corner.x - sin(ang) * corner.y, sin(ang) * corner.x + cos(ang) * corner.y);
	float scale = length(MODEL_MATRIX[0].xyz);
	VERTEX = view_c + vec3(corner * COLOR.r * card_size * scale * mix(0.8, 1.15, h1(seed + 3.0)), 0.0);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Racimo de hojas: posición y giro (coseno, seno) de cada hoja, fijos; cada tarjeta empieza en
// un sitio distinto de la tabla y además va girada, así que no se nota la repetición.
const vec4 LEAF_POS[16] = vec4[16](
	vec4(-0.069, -0.083, -0.157, 0.988),
	vec4(-0.047, -0.557, 0.779, -0.627),
	vec4(0.095, 0.474, 0.986, 0.166),
	vec4(-0.295, -0.406, 0.185, 0.983),
	vec4(-0.144, 0.226, 0.964, -0.266),
	vec4(0.177, 0.116, 0.575, -0.818),
	vec4(0.204, -0.544, -0.974, -0.226),
	vec4(-0.365, 0.349, 0.478, -0.878),
	vec4(0.543, -0.036, -0.937, -0.350),
	vec4(0.272, -0.267, -0.560, -0.829),
	vec4(-0.323, -0.131, -0.862, -0.507),
	vec4(0.416, 0.342, 0.261, -0.965),
	vec4(-0.636, 0.190, 0.711, -0.703),
	vec4(0.541, -0.331, -0.300, 0.954),
	vec4(-0.541, -0.198, 0.563, 0.826),
	vec4(-0.231, 0.602, 0.286, -0.958)
);
const float LEAF_SHADE[16] = float[16](0.223, 0.087, 0.199, 0.589, 0.337, 0.604, 0.973, 0.619, 0.685, 0.396, 0.898, 0.422, 0.263, 0.639, 0.297, 0.861);

float leaf(vec2 p, vec2 c, vec2 cs, vec2 sz) {
	vec2 d = p - c;
	d = vec2(cs.x * d.x - cs.y * d.y, cs.y * d.x + cs.x * d.y) / sz;
	// Hoja apuntada: elipse que se estrecha hacia la punta.
	float w = 1.0 - d.y * d.y;
	return (1.0 - smoothstep(0.85, 1.0, abs(d.x) / max(w, 0.001) * 0.9 + abs(d.y) * 0.1)) * step(abs(d.y), 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Centro relleno de la tarjeta (más pequeño en los mechones de agujas).
	float disc = mix(0.14, 0.26, smoothstep(0.06, 0.2, leaf_shape.x));
	float a = 1.0 - smoothstep(disc, disc + 0.16, length(p));
	float shade = 0.0;
	int first = int(seed * 16.0);
	for (int i = 0; i < 14; i++) {
		if (float(i) >= leaf_count || a > 0.98) {
			break;
		}
		int k = (first + i * 5) % 16;
		vec4 lv = LEAF_POS[k];
		float l = leaf(p, lv.xy, lv.zw, leaf_shape);
		if (l > a) {
			shade = LEAF_SHADE[k];
		}
		a = max(a, l);
	}
	// Las tarjetas del interior de la copa, más oscuras (oclusión); las de arriba, más claras.
	vec3 c = albedo.rgb * inst_tint;
	c *= mix(0.74, 1.08, depth_in) * mix(0.9, 1.08, shade);
	ALBEDO = c;
	// Las tarjetas se ven por detrás según su giro: no dejar que Godot invierta la normal.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
