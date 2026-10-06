shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Agua: color según profundidad, relieve del oleaje iluminado por el sol, reflejo del cielo
// real de cada hora (Fresnel) y de lo que hay en pantalla (árboles, casas, barcos), estela de
// luz del sol y espuma en la orilla.

global uniform vec3 sun_dir;
global uniform vec4 day_tint;
global uniform float night_amount;
global uniform vec4 sky_top;
global uniform vec4 sky_horizon;
global uniform vec4 sky_sun;
global uniform vec3 sky_sun_dir;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.36, 0.86, 0.84, 1.0);
uniform vec4 deep_color : source_color = vec4(0.12, 0.45, 0.74, 1.0);
uniform vec4 foam_color : source_color = vec4(0.97, 1.0, 1.0, 1.0);
uniform float depth_range = 9.0;
uniform float wave_height = 0.22;
uniform float foam_width = 1.1;
uniform vec2 clip_center = vec2(0.0);
uniform float clip_radius = 0.0;
// Reflejo mínimo mirando de frente (el resto crece con el Fresnel) y rizado de la superficie.
uniform float reflect_min = 0.04;
uniform float reflect_max = 0.85;
uniform float ripple_amount = 1.0;
// Reflejos en pantalla: pasos del trazado (0 = solo cielo) y fuerza.
uniform int ssr_steps = 40;
uniform float ssr_strength = 0.8;

varying vec3 wpos;

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/sky_common.gdshaderinc"

// La versión web usa el renderizador Compatibility (OpenGL): ahí la profundidad no está invertida
// (el cielo vale 1) y la z de NDC va de -1 a 1. En Forward+ (Vulkan) el cielo vale 0 y z = d.
float ndc_z(float d) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return d * 2.0 - 1.0;
#else
	return d;
#endif
}

bool is_sky_depth(float d) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return d >= 0.999999;
#else
	return d <= 0.000001;
#endif
}

// Traza el rayo reflejado por la pantalla con la profundidad; devuelve color y cobertura (a).
vec4 trace_reflection(vec3 vpos, vec3 rd, mat4 proj, mat4 inv_proj) {
	float stp = clamp(-vpos.z * 0.025, 0.2, 2.0);
	vec3 p = vpos;
	vec3 prev = p;
	for (int i = 0; i < ssr_steps; i++) {
		prev = p;
		p += rd * stp;
		stp *= 1.13;
		vec4 c = proj * vec4(p, 1.0);
		if (c.w <= 0.0) {
			break;
		}
		vec2 uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		float d = texture(depth_tex, uv).r;
		if (is_sky_depth(d)) {
			continue;   // cielo: no tapa nada
		}
		vec4 sp = inv_proj * vec4(uv * 2.0 - 1.0, ndc_z(d), 1.0);
		float sz = sp.z / sp.w;
		if (p.z < sz && sz - p.z < max(stp * 2.5, 0.6)) {
			// Afinar entre el paso anterior y este.
			vec3 a = prev;
			vec3 b = p;
			for (int j = 0; j < 5; j++) {
				vec3 m = (a + b) * 0.5;
				vec4 mc = proj * vec4(m, 1.0);
				vec2 muv = mc.xy / mc.w * 0.5 + 0.5;
				vec4 ms = inv_proj * vec4(muv * 2.0 - 1.0, ndc_z(texture(depth_tex, muv).r), 1.0);
				if (m.z < ms.z / ms.w) {
					b = m;
				} else {
					a = m;
				}
			}
			vec4 bc = proj * vec4(b, 1.0);
			vec2 huv = bc.xy / bc.w * 0.5 + 0.5;
			vec2 edge = smoothstep(vec2(0.0), vec2(0.07), huv) * smoothstep(vec2(0.0), vec2(0.07), 1.0 - huv);
			float fade = edge.x * edge.y * (1.0 - smoothstep(float(ssr_steps) * 0.6, float(ssr_steps), float(i)));
			return vec4(textureLod(screen_tex, huv, 0.0).rgb, fade);
		}
	}
	return vec4(0.0);
}

float waves(vec2 p, float t) {
	return sin(p.x * 0.09 + t * 0.9) * 0.55 + sin(p.y * 0.12 + t * 1.15) * 0.45 + sin((p.x + p.y) * 0.21 + t * 1.7) * 0.25;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(wpos.xz, TIME) * wave_height;
}

void fragment() {
	if (clip_radius > 0.0 && distance(wpos.xz, clip_center) > clip_radius) {
		discard;
	}
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_z(depth), 1.0);
	upos.xyz /= upos.w;
	float water_depth = max(VERTEX.z - upos.z, 0.0);
	float t = clamp(water_depth / depth_range, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, t));

	// Espuma: línea de orilla con borde irregular + olas que llegan a la playa. La espuma es
	// de burbujas (ruido a dos escalas que se mueve): se rompe en jirones en vez de ser una
	// franja blanca lisa; solo el filo que lame la arena es continuo.
	float n = vnoise(wpos.xz * 0.6 + vec2(TIME * 0.3, TIME * 0.2));
	float bubbles = vnoise(wpos.xz * 2.6 + vec2(TIME * 0.45, -TIME * 0.3)) * 0.6 + vnoise(wpos.xz * 6.5 - vec2(TIME * 0.2, TIME * 0.5)) * 0.4;
	float edge = 1.0 - smoothstep(foam_width * (0.55 + 0.45 * n), foam_width * (0.6 + 0.45 * n), water_depth);
	float lip = 1.0 - smoothstep(0.03, 0.1 + 0.08 * n, water_depth);
	edge = max(lip, edge * smoothstep(0.32 + water_depth / foam_width * 0.35, 0.5 + water_depth / foam_width * 0.35, bubbles));
	float stripe_phase = fract(water_depth * 0.55 - TIME * 0.35);
	float stripes = smoothstep(0.8, 0.9, stripe_phase) * (1.0 - smoothstep(0.92, 0.99, stripe_phase));
	stripes *= (1.0 - smoothstep(0.8, 3.6, water_depth)) * smoothstep(0.3, 0.5, vnoise(wpos.xz * 0.25 + TIME * 0.05)) * 0.7;
	stripes *= smoothstep(0.35, 0.6, bubbles);
	float foam = max(edge, stripes);

	// Normal del agua: pendiente de las olas grandes y rizos finos (que se apagan a lo lejos).
	float cam_d = distance(CAMERA_POSITION_WORLD.xz, wpos.xz);
	vec2 p = wpos.xz;
	float e = 0.5;
	float hc = waves(p, TIME) * wave_height;
	vec2 grad = vec2(waves(p + vec2(e, 0.0), TIME) * wave_height - hc, waves(p + vec2(0.0, e), TIME) * wave_height - hc) / e;
	vec2 q = p * 0.42 + vec2(TIME * 0.35, TIME * 0.22);
	float r0 = vnoise(q) + vnoise(q * 2.3 - TIME * 0.2) * 0.5;
	float rx = vnoise(q + vec2(0.08, 0.0)) + vnoise((q + vec2(0.08, 0.0)) * 2.3 - TIME * 0.2) * 0.5;
	float rz = vnoise(q + vec2(0.0, 0.08)) + vnoise((q + vec2(0.0, 0.08)) * 2.3 - TIME * 0.2) * 0.5;
	float ripple = (1.0 - smoothstep(30.0, 260.0, cam_d)) * 0.35 + 0.08;
	grad += vec2(rx - r0, rz - r0) / 0.08 * 0.05 * ripple * ripple_amount;
	vec3 nrm = normalize(vec3(-grad.x, 1.0, -grad.y));

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 sun = normalize(sun_dir);
	vec3 lit = day_tint.rgb;
	// Luz del sol sobre el relieve de las olas.
	col *= lit * (0.88 + 0.2 * clamp(dot(nrm, sun), 0.0, 1.0));
	// Reflejo: el cielo de esta hora en la dirección reflejada y, encima, lo que se ve en pantalla.
	vec3 rw = reflect(-view_dir, nrm);
	rw.y = abs(rw.y);
	vec3 sky_r = sky_gradient(rw, sky_top.rgb, sky_horizon.rgb, sky_sun.rgb, normalize(sky_sun_dir));
	vec3 reflection = sky_r;
	if (ssr_steps > 0 && ssr_strength > 0.0) {
		vec3 vn = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
		vec3 rd = reflect(normalize(VERTEX), vn);
		vec4 hit = trace_reflection(VERTEX, rd, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
		reflection = mix(reflection, hit.rgb, hit.a * ssr_strength);
	}
	float fres = pow(1.0 - clamp(dot(nrm, view_dir), 0.0, 1.0), 4.0);
	float refl_k = clamp(reflect_min + fres * 0.8, 0.0, reflect_max);
	col = mix(col, reflection, refl_k);
	// Estela del sol (o de la luna) y destellos, del color de la luz de esta hora.
	vec3 refl = reflect(-sun, nrm);
	float sun_spec = pow(max(dot(refl, view_dir), 0.0), 160.0) * 2.5;
	// Destellos: muchos y pequeños (crestas de los rizos que pillan el sol), más grandes a lo
	// lejos para que no parpadeen.
	float gsc = mix(5.5, 1.3, smoothstep(8.0, 140.0, cam_d));
	float sparkle_noise = vnoise(wpos.xz * gsc + vec2(TIME * 0.9, -TIME * 0.6)) * vnoise(wpos.xz * gsc * 0.63 - TIME * 0.45 + 3.7);
	float glint = smoothstep(0.42, 0.58, sparkle_noise) * pow(max(dot(refl, view_dir), 0.0), 18.0) * 1.3;
	float low = smoothstep(0.42, 0.06, sky_sun_dir.y);
	vec3 sun_col = mix(vec3(1.0, 0.96, 0.86), sky_sun.rgb * vec3(1.15, 0.85, 0.6), low) * (1.0 - night_amount);
	sun_col += vec3(0.6, 0.7, 1.0) * night_amount * 0.35;
	col += sun_col * (sun_spec + glint * mix(0.9, 1.4, low));
	col = mix(col, foam_color.rgb * mix(lit, vec3(1.0), 0.25), foam * 0.88);
	ALBEDO = col;
	// El agua profunda es opaca: si no, se transparenta distinto sobre el fondo y sobre el vacío.
	// Donde refleja mucho tampoco se ve el fondo.
	ALPHA = clamp(max(mix(0.55, 1.0, smoothstep(0.0, 0.6, t)), refl_k * 1.1) + foam, 0.0, 1.0);
}
