// Iluminación compartida: difusa suave (lambert envuelto con un toque del escalón de dibujo
// animado), sombras suaves, un brillo especular amplio y una luz de contorno discreta.
// La sombra la pone el ambiente (azulado) del entorno.

global uniform float cloud_shadow;
global uniform vec2 cloud_offset;

varying float v_cloud;

float _cl_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p))) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float _cl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(_cl_hash(i), _cl_hash(i + vec2(1.0, 0.0)), u.x), mix(_cl_hash(i + vec2(0.0, 1.0)), _cl_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Sombra de las nubes que pasan (0 = sol, 1 = sombra). Se calcula por vértice.
float cloud_mask(vec3 wp) {
	vec2 p = (wp.xz + cloud_offset) * 0.012;
	float n = _cl_noise(p) * 0.65 + _cl_noise(p * 2.3 + 7.1) * 0.35;
	return smoothstep(0.5, 0.72, n) * cloud_shadow;
}

uniform float band_soft : hint_range(0.001, 0.5) = 0.06;
// 0 = escalón de dibujo animado, 1 = lambert envuelto (más realista).
uniform float softness : hint_range(0.0, 1.0) = 0.8;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.22;
uniform float spec_amount : hint_range(0.0, 1.0) = 0.0;
uniform float sheen : hint_range(0.0, 1.0) = 0.06;
// Luz que atraviesa (hojas): brillo cuando se mira hacia el sol a través de ellas.
uniform float translucency : hint_range(0.0, 1.0) = 0.0;
// Aclara las sombras proyectadas (follaje: que las hojas no se oscurezcan entre sí del todo).
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.0;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.02, band_soft, ndl);
	float wrapped = clamp((ndl + 0.3) / 1.3, 0.0, 1.0);
	wrapped *= wrapped * (3.0 - 2.0 * wrapped) * 0.35 + wrapped * 0.65;
	float diff = mix(band, wrapped, softness);
	float shadow = mix(smoothstep(0.25, 0.6, ATTENUATION), ATTENUATION, softness);
	shadow = mix(shadow, 1.0, shadow_lift);
	if (LIGHT_IS_DIRECTIONAL) {
		shadow *= 1.0 - v_cloud * 0.5;
	}
	float lit = diff * shadow;
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * lit;
	if (LIGHT_IS_DIRECTIONAL && translucency > 0.0) {
		float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * (0.4 + 0.6 * clamp(-ndl, 0.0, 1.0));
		DIFFUSE_LIGHT += lc * through * translucency * mix(1.0, ATTENUATION, 0.6);
	}
	if (LIGHT_IS_DIRECTIONAL) {
		float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float rim_band = smoothstep(0.55, 0.85, rim * pow(clamp(ndl + 0.35, 0.0, 1.0), 0.5));
		SPECULAR_LIGHT += lc * rim_band * rim_amount * 0.6 * shadow;
		vec3 hv = normalize(LIGHT + VIEW);
		float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
		// Brillo amplio y suave en todo (da volumen) y otro en escalón si el material lo pide.
		SPECULAR_LIGHT += lc * pow(ndh, 18.0) * sheen * lit;
		if (spec_amount > 0.0) {
			SPECULAR_LIGHT += lc * smoothstep(0.92, 0.94, ndh) * spec_amount * lit;
		}
	}
}
