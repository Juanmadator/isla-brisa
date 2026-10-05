shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;
// Material de los modelos (personajes, casas, rocas, árboles...): sombreado suave, una
// variación sutil de superficie (ruido en espacio del objeto, no "nada" al moverse) y
// oclusión de cielo (lo que mira hacia abajo recibe menos luz ambiental).

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform bool use_instance_tint = false;
uniform float sway = 0.0;
// Brillo que se enciende solo de noche (ventanas iluminadas).
uniform vec4 night_color : source_color = vec4(1.0, 0.78, 0.42, 1.0);
uniform float night_emission = 0.0;
// Variación de tono de la superficie (0 = color plano).
uniform float detail = 0.07;
uniform float detail_scale = 2.5;

global uniform vec2 wind_dir;
global uniform float night_amount;

#include "res://shaders/toon_light.gdshaderinc"
#include "res://shaders/noise.gdshaderinc"

varying vec3 inst_tint;
varying vec3 local_pos;

void vertex() {
	inst_tint = use_instance_tint ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	// Las instancias de vegetación y rocas desplazan su ruido para no repetir el mismo dibujo
	// (los objetos que se mueven no: su ruido iría "nadando").
	vec3 root_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 offs = use_instance_tint ? vec3(root_w.x * 0.37, 0.0, root_w.z * 0.29) : vec3(0.0);
	local_pos = VERTEX * length(MODEL_MATRIX[0].xyz) + offs;
	v_cloud = cloud_mask((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	if (sway > 0.0) {
		vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float s = sin(TIME * 1.1 + root.x * 0.13 + root.z * 0.11) * 0.6 + sin(TIME * 2.3 + root.x * 0.4) * 0.25;
		VERTEX.xz += normalize(wind_dir) * s * sway * max(VERTEX.y, 0.0) * max(VERTEX.y, 0.0) * 0.01;
	}
}

void fragment() {
	vec3 c = albedo.rgb * inst_tint;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	if (detail > 0.0) {
		vec3 q = local_pos * detail_scale;
		float n = (vnoise(q.xy) + vnoise(q.yz + 5.3) + vnoise(q.xz + 9.1)) / 3.0;
		float n2 = (vnoise(q.xy * 3.7) + vnoise(q.zy * 3.7 + 2.0)) * 0.5;
		c *= 1.0 + ((n - 0.5) * 1.6 + (n2 - 0.5) * 0.6) * detail;
	}
	// Oclusión de cielo: las caras que miran al suelo, algo más oscuras.
	float wn_y = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	c *= mix(0.8, 1.0, smoothstep(-0.9, 0.4, wn_y));
	EMISSION = emission_color.rgb * emission_energy;
	if (night_emission > 0.0) {
		float on = smoothstep(0.3, 0.65, night_amount);
		c = mix(c, night_color.rgb, on * 0.85);
		EMISSION += night_color.rgb * night_emission * on;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
