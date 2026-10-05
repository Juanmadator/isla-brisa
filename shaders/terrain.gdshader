shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;
// Terreno: color por vértice (biomas pintados al generar) con variación en manchas.
// En las paredes empinadas la roca se dibuja como estratos de bloques de piedra:
// cada bloque con su tono y su faceta, juntas oscuras y el canto superior iluminado.

global uniform float night_amount;

#include "res://shaders/toon_light.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;

#include "res://shaders/noise.gdshaderinc"

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cloud = cloud_mask(wpos);
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Celdas de Voronoi: x = distancia al centro, y = distancia al borde, z = número de la celda.
vec3 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 g = vec2(float(xx), float(yy));
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

float h1(float a, float b) {
	return hash(vec2(a * 17.0 + 3.0, b * 31.0 + 7.0));
}

// Roca de una pared vista a lo largo de `u`: estratos de ~4 m con el borde ondulado y bloques
// irregulares (Voronoi alargado y deformado). Devuelve el color y, en a, cuánto sobresale.
vec4 rock_layer(float u, float wy, vec3 c) {
	float y = wy + (vnoise(vec2(u * 0.06, wy * 0.03)) - 0.5) * 3.0;
	float layer = y / 4.0;
	float lid = floor(layer);
	float lf = fract(layer);
	vec2 bp = vec2(u * 0.11, y * 0.26);
	bp += (vec2(vnoise(bp * 1.7), vnoise(bp * 1.7 + 4.0)) - 0.5) * 0.7;
	vec3 vor = voronoi(bp);
	vec3 rc = c * mix(0.86, 1.07, vor.z) * mix(0.94, 1.05, vnoise(vec2(u * 0.05, wy * 0.09)));
	// Toque de color: unos estratos más cálidos y otros más fríos.
	rc *= mix(vec3(1.03, 0.99, 0.95), vec3(0.97, 0.99, 1.03), h1(lid, 5.0));
	// Juntas bajo cada estrato (grosor variable) y grietas entre bloques.
	float seam_h = (1.0 - smoothstep(0.0, 0.03 + fwidth(layer) * 1.2, lf)) * mix(0.5, 1.0, vnoise(vec2(u * 0.2, lid)));
	float crack = (1.0 - smoothstep(0.0, 0.035 + fwidth(bp.x) * 1.5, vor.y)) * mix(0.25, 0.9, vnoise(bp * 3.0));
	float seam = max(seam_h, crack * 0.75);
	// Canto superior de cada estrato, más claro (le da el sol).
	rc *= 1.0 + smoothstep(0.88, 0.95, lf) * 0.1;
	rc = mix(rc, rc * 0.7, seam);
	return vec4(rc, (vor.z - 0.5) * (1.0 - seam));
}

void fragment() {
	vec3 c = COLOR.rgb;
	float n = vnoise(wpos.xz * 0.18) * 0.6 + vnoise(wpos.xz * 0.9) * 0.4;
	float patches = smoothstep(0.45, 0.55, n);
	c *= mix(0.94, 1.06, patches);
	float steep = (1.0 - smoothstep(0.5, 0.78, wnrm.y)) * smoothstep(0.15, 0.5, COLOR.a);
	if (steep > 0.01) {
		// La roca se dibuja dos veces (proyectada a lo largo de x y de z) y se mezcla según
		// hacia dónde mira la pared: sin costuras donde cambia de orientación.
		vec2 wxz = pow(abs(wnrm.xz), vec2(4.0));
		wxz /= (wxz.x + wxz.y + 1e-4);
		vec4 ra = rock_layer(wpos.z, wpos.y, c);
		vec4 rb = rock_layer(wpos.x, wpos.y, c);
		vec4 rk = ra * wxz.x + rb * wxz.y;
		c = mix(c, rk.rgb, steep);
		// Repisas: la normal se inclina hacia arriba en el canto de cada estrato.
		float y = wpos.y + (vnoise(vec2((wpos.x + wpos.z) * 0.06, wpos.y * 0.03)) - 0.5) * 3.0;
		float lf = fract(y / 4.0);
		vec3 tilt = (VIEW_MATRIX * vec4(0.0, (lf - 0.5) * 0.3 + rk.a * 0.25, 0.0, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, normalize(NORMAL + tilt), steep));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
