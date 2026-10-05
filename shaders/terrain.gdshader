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

float h1(float a, float b) {
	return hash(vec2(a * 17.0 + 3.0, b * 31.0 + 7.0));
}

void fragment() {
	vec3 c = COLOR.rgb;
	float n = vnoise(wpos.xz * 0.18) * 0.6 + vnoise(wpos.xz * 0.9) * 0.4;
	float patches = smoothstep(0.45, 0.55, n);
	c *= mix(0.94, 1.06, patches);
	float steep = (1.0 - smoothstep(0.5, 0.78, wnrm.y)) * smoothstep(0.15, 0.5, COLOR.a);
	if (steep > 0.01) {
		// Coordenada horizontal estable: la del eje del mundo más paralelo a la pared.
		float u = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
		// Estratos de unos 4 m con el borde ondulado.
		float y = wpos.y + (vnoise(vec2(u * 0.06, wpos.y * 0.03)) - 0.5) * 3.0;
		float layer = y / 4.0;
		float lid = floor(layer);
		float lf = fract(layer);
		// Bloques anchos (8-14 m) desplazados de un estrato a otro.
		float bw = mix(8.0, 14.0, h1(lid, 1.0));
		float bx = u / bw + h1(lid, 2.0) * 7.0;
		float bid = floor(bx);
		float bf = fract(bx);
		float tone = h1(lid, bid);
		vec3 rc = c * mix(0.88, 1.06, tone) * mix(0.95, 1.04, vnoise(vec2(u * 0.04, wpos.y * 0.08)));
		// Toque de color: unos estratos más cálidos y otros más fríos.
		rc *= mix(vec3(1.03, 0.99, 0.95), vec3(0.97, 0.99, 1.03), h1(lid, 5.0));
		// Juntas: bajo cada estrato (sombra del saliente) y, más finas, entre bloques.
		float seam_h = 1.0 - smoothstep(0.0, 0.035 + fwidth(layer) * 1.2, lf);
		float seam_v = (1.0 - smoothstep(0.0, 0.012 + fwidth(bx) * 1.2, min(bf, 1.0 - bf))) * step(0.35, lf);
		float seam = max(seam_h, seam_v * 0.6);
		// Canto superior de cada estrato, más claro (le da el sol).
		float lip = smoothstep(0.88, 0.95, lf);
		rc *= 1.0 + lip * 0.1;
		rc = mix(rc, rc * 0.7, seam);
		c = mix(c, rc, steep);
		// Faceta propia de cada bloque: la normal se inclina un poco hacia un lado.
		vec3 side = abs(wnrm.x) > abs(wnrm.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 tilt_w = side * (h1(lid, bid + 9.0) - 0.5) * 0.6 + vec3(0.0, 1.0, 0.0) * (lf - 0.5) * 0.35;
		vec3 tilt = (VIEW_MATRIX * vec4(tilt_w, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, normalize(NORMAL + tilt), steep));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
