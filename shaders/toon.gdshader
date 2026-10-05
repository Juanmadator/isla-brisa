shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;
// Material de los modelos (personajes, casas, rocas, árboles...): sombreado suave, una
// variación sutil de superficie (ruido en espacio del objeto, no "nada" al moverse) y
// oclusión de cielo (lo que mira hacia abajo recibe menos luz ambiental).
// `surface` añade el dibujo y el relieve de un material, sin texturas: veta de la madera,
// grietas de la piedra, estuco del enlucido, filas de tejas o surcos de la corteza. El relieve
// se aplica a la normal con derivadas de pantalla (bump mapping de Mikkelsen) y se apaga a lo
// lejos. `edge_highlight` aclara los cantos redondeados según su curvatura, como en el arte
// pintado a mano.

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
// 0 nada, 1 madera, 2 piedra, 3 enlucido, 4 tejas, 5 corteza, 6 paja, 7 tela, 8 pelo.
uniform int surface = 0;
// Escala del dibujo del material (1 = tamaño real).
uniform float surface_scale = 1.0;
uniform float bump_strength = 1.0;
uniform float edge_highlight = 0.0;

global uniform vec2 wind_dir;
global uniform float night_amount;

#include "res://shaders/toon_light.gdshaderinc"
#include "res://shaders/noise.gdshaderinc"

varying vec3 inst_tint;
varying vec3 local_pos;
varying vec3 obj_n;
varying vec3 obj_v;

void vertex() {
	inst_tint = use_instance_tint ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	// Las instancias de vegetación y rocas desplazan su ruido para no repetir el mismo dibujo
	// (los objetos que se mueven no: su ruido iría "nadando").
	vec3 root_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 offs = use_instance_tint ? vec3(root_w.x * 0.37, 0.0, root_w.z * 0.29) : vec3(0.0);
	local_pos = VERTEX * length(MODEL_MATRIX[0].xyz) + offs;
	obj_n = NORMAL;
	obj_v = VERTEX * length(MODEL_MATRIX[0].xyz);
	v_cloud = cloud_mask((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	if (sway > 0.0) {
		vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float s = sin(TIME * 1.1 + root.x * 0.13 + root.z * 0.11) * 0.6 + sin(TIME * 2.3 + root.x * 0.4) * 0.25;
		VERTEX.xz += normalize(wind_dir) * s * sway * max(VERTEX.y, 0.0) * max(VERTEX.y, 0.0) * 0.01;
	}
}

// Celdas de Voronoi: x = distancia al centro más cercano, y = distancia al borde de la celda
// (F2 - F1), z = número aleatorio de la celda.
vec3 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + vec2(17.0, 31.0)));
			vec2 r = g + o * 0.85 + 0.075 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash(i + g + vec2(5.0, 11.0));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), id);
}

// Dibujo y relieve del material: devuelve la altura (en metros) y multiplica el color.
float surface_pattern(vec3 p, vec3 n, inout vec3 c) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-4);
	if (surface == 1) {
		// Madera: veta a lo largo de la pieza (en las caras horizontales, a lo largo de x).
		vec2 uv = abs(n.y) > 0.6 ? p.xz : vec2(p.y, abs(n.x) > abs(n.z) ? p.z : p.x);
		float g = sin(uv.y * 46.0 + vnoise(vec2(uv.x * 1.3, uv.y * 7.0)) * 6.5) * 0.5 + 0.5;
		float fine = vnoise(vec2(uv.x * 2.2, uv.y * 70.0));
		float knot = smoothstep(0.82, 0.95, vnoise(uv * vec2(1.6, 9.0) + 3.1));
		float h = g * 0.55 + fine * 0.45 - knot * 0.6;
		c *= mix(0.82, 1.07, h);
		return h * 0.0035;
	}
	if (surface == 2) {
		// Piedra: bloques irregulares (celdas deformadas con ruido) con grietas y moteado.
		float s = 1.9;
		vec3 warp = vec3(vnoise(p.yz * 1.7), vnoise(p.xz * 1.7 + 3.0), vnoise(p.xy * 1.7 + 6.0)) - 0.5;
		vec3 pw = p + warp * 0.35;
		vec3 a = voronoi(pw.zy * s);
		vec3 b = voronoi(pw.xz * s + 7.0);
		vec3 d = voronoi(pw.xy * s + 13.0);
		float edge = a.y * w.x + b.y * w.y + d.y * w.z;
		float tone = a.z * w.x + b.z * w.y + d.z * w.z;
		// Grietas de grosor variable: unas marcadas y otras casi borradas.
		float crack = (1.0 - smoothstep(0.0, 0.07, edge)) * mix(0.35, 1.0, vnoise(pw.xy * 3.0 + pw.z));
		float speck = vnoise(p.xy * 23.0 + p.z * 11.0) * w.z + vnoise(p.zy * 23.0) * w.x + vnoise(p.xz * 23.0) * w.y;
		c *= mix(0.84, 1.07, tone) * (1.0 - crack * 0.3) * mix(0.9, 1.06, speck);
		return (1.0 - crack) * 0.012 + speck * 0.002;
	}
	if (surface == 3) {
		// Enlucido: manchas suaves y estuco fino.
		float m = (vnoise(p.xy * 1.1 + p.z) * w.z + vnoise(p.zy * 1.1) * w.x + vnoise(p.xz * 1.1) * w.y);
		float st = (vnoise(p.xy * 31.0 + p.z * 7.0) * w.z + vnoise(p.zy * 31.0) * w.x + vnoise(p.xz * 31.0) * w.y);
		// Desconchones: alguna mancha más clara o más oscura donde el enlucido se ha gastado.
		float patch = smoothstep(0.68, 0.74, vnoise(p.xy * 0.9 + p.z * 0.7 + 11.0) * w.z + vnoise(p.zy * 0.9 + 11.0) * w.x + vnoise(p.xz * 0.9 + 11.0) * w.y);
		c *= mix(0.9, 1.04, m) * mix(0.96, 1.03, st) * (1.0 - patch * 0.07);
		return st * 0.0018 + m * 0.003 - patch * 0.002;
	}
	if (surface == 4) {
		// Tejas: filas a lo largo de x (la pendiente) con juntas desplazadas en z.
		if (n.y < 0.4) {
			return 0.0;
		}
		float rows = p.x * 3.3;
		float row = floor(rows);
		float f = fract(rows);
		float cols = p.z * 3.6 + row * 0.5;
		float col = fract(cols);
		float seam = smoothstep(0.0, 0.07, min(col, 1.0 - col));
		float t = hash(vec2(row, floor(cols)));
		c *= mix(0.78, 1.05, smoothstep(0.0, 0.9, f)) * mix(0.82, 1.0, seam) * mix(0.92, 1.06, t);
		return (f * 0.018) * mix(0.6, 1.0, seam);
	}
	if (surface == 5) {
		// Corteza: surcos verticales que se abren y cierran.
		float ang = atan(obj_v.z, obj_v.x);
		float g = sin(ang * 9.0 + vnoise(vec2(obj_v.y * 1.8, ang * 2.5)) * 3.5) * 0.5 + 0.5;
		float cracks = smoothstep(0.65, 0.8, vnoise(vec2(ang * 6.0, obj_v.y * 5.0)));
		c *= mix(0.78, 1.06, g) * (1.0 - cracks * 0.15);
		return g * 0.01;
	}
	if (surface == 7) {
		// Tela: pliegues suaves que caen en vertical y una trama fina.
		float ang = atan(obj_v.z, obj_v.x);
		float folds = sin(ang * 7.0 + vnoise(vec2(ang * 2.0, obj_v.y * 6.0)) * 3.0) * 0.5 + 0.5;
		float weave = (sin(p.x * 420.0) * sin(p.y * 420.0) + sin(p.z * 420.0) * sin(p.y * 420.0)) * 0.25 + 0.5;
		c *= mix(0.9, 1.04, folds) * mix(0.97, 1.02, weave);
		return folds * 0.006 + weave * 0.0006;
	}
	if (surface == 8) {
		// Pelo: mechones que bajan desde la coronilla y un brillo en anillo.
		vec3 d = normalize(obj_v + vec3(0.0, -0.02, 0.0));
		float ang = atan(d.z, d.x);
		float strands = vnoise(vec2(ang * 22.0, d.y * 3.0)) * 0.6 + vnoise(vec2(ang * 60.0, d.y * 6.0)) * 0.4;
		float ring = smoothstep(0.2, 0.45, d.y) * (1.0 - smoothstep(0.55, 0.8, d.y));
		c *= mix(0.8, 1.06, strands);
		c *= 1.0 + ring * 0.22 * smoothstep(0.45, 0.75, strands);
		return strands * 0.004;
	}
	if (surface == 6) {
		// Paja: haces que bajan por la pendiente, en capas que se solapan.
		float ang = atan(obj_v.z, obj_v.x);
		float strands = vnoise(vec2(ang * 38.0, obj_v.y * 1.5)) * 0.6 + vnoise(vec2(ang * 120.0, obj_v.y * 4.0)) * 0.4;
		float layer = fract(obj_v.y * 2.6 + vnoise(vec2(ang * 6.0, 1.0)) * 0.5);
		c *= mix(0.78, 1.08, strands) * mix(0.8, 1.02, smoothstep(0.0, 0.35, layer));
		return strands * 0.01 + layer * 0.012;
	}
	return 0.0;
}

void fragment() {
	vec3 c = albedo.rgb * inst_tint;
	if (use_vertex_color) {
		// Los colores de vértice vienen en sRGB (como los de los materiales): pasarlos a lineal.
		vec3 vc = COLOR.rgb;
		c *= mix(pow((vc + 0.055) / 1.055, vec3(2.4)), vc / 12.92, lessThan(vc, vec3(0.04045)));
	}
	if (detail > 0.0) {
		vec3 q = local_pos * detail_scale;
		float n = (vnoise(q.xy) + vnoise(q.yz + 5.3) + vnoise(q.xz + 9.1)) / 3.0;
		float n2 = (vnoise(q.xy * 3.7) + vnoise(q.zy * 3.7 + 2.0)) * 0.5;
		c *= 1.0 + ((n - 0.5) * 1.6 + (n2 - 0.5) * 0.6) * detail;
	}
	if (edge_highlight > 0.0) {
		// Curvatura = cuánto gira la normal por metro (antes del relieve): los biseles se aclaran.
		float curv = length(fwidth(NORMAL)) / max(length(fwidth(VERTEX)), 1e-4);
		c *= 1.0 + smoothstep(2.5, 12.0, curv) * edge_highlight;
	}
	if (surface > 0) {
		float h = surface_pattern(local_pos * surface_scale, normalize(obj_n), c) * bump_strength;
		// Relieve: se apaga con la distancia para que no parpadee.
		h *= 1.0 - smoothstep(14.0, 40.0, -VERTEX.z);
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
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
