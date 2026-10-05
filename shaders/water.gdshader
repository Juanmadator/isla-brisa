shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Agua: color según profundidad, relieve del oleaje iluminado por el sol, reflejo del cielo
// que crece hacia el horizonte (Fresnel), estela de luz del sol y espuma en la orilla.

global uniform vec3 sun_dir;
global uniform vec4 day_tint;
global uniform float night_amount;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.36, 0.86, 0.84, 1.0);
uniform vec4 deep_color : source_color = vec4(0.12, 0.45, 0.74, 1.0);
uniform vec4 foam_color : source_color = vec4(0.97, 1.0, 1.0, 1.0);
uniform float depth_range = 9.0;
uniform float wave_height = 0.22;
uniform float foam_width = 1.1;
uniform vec2 clip_center = vec2(0.0);
uniform float clip_radius = 0.0;
// Color del cielo que refleja el agua (se multiplica por la luz del día).
uniform vec4 sky_reflect : source_color = vec4(0.72, 0.84, 0.95, 1.0);

varying vec3 wpos;

#include "res://shaders/noise.gdshaderinc"

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
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	upos.xyz /= upos.w;
	float water_depth = max(VERTEX.z - upos.z, 0.0);
	float t = clamp(water_depth / depth_range, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, t));

	// Espuma: línea de orilla con borde irregular + olas que llegan a la playa.
	float n = vnoise(wpos.xz * 0.6 + vec2(TIME * 0.3, TIME * 0.2));
	float edge = 1.0 - smoothstep(foam_width * (0.55 + 0.45 * n), foam_width * (0.6 + 0.45 * n), water_depth);
	float stripe_phase = fract(water_depth * 0.55 - TIME * 0.35);
	float stripes = smoothstep(0.8, 0.9, stripe_phase) * (1.0 - smoothstep(0.92, 0.99, stripe_phase));
	stripes *= (1.0 - smoothstep(0.8, 3.6, water_depth)) * smoothstep(0.3, 0.5, vnoise(wpos.xz * 0.25 + TIME * 0.05)) * 0.7;
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
	grad += vec2(rx - r0, rz - r0) / 0.08 * 0.05 * ripple;
	vec3 nrm = normalize(vec3(-grad.x, 1.0, -grad.y));

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 sun = normalize(sun_dir);
	vec3 lit = day_tint.rgb;
	// Luz del sol sobre el relieve de las olas.
	col *= lit * (0.88 + 0.2 * clamp(dot(nrm, sun), 0.0, 1.0));
	// Reflejo del cielo: más fuerte cuanto más rasante se mira el agua.
	float fres = pow(1.0 - clamp(dot(nrm, view_dir), 0.0, 1.0), 4.0);
	col = mix(col, sky_reflect.rgb * lit, clamp(fres * 0.75 + 0.04, 0.0, 0.85));
	// Estela del sol y destellos.
	vec3 refl = reflect(-sun, nrm);
	float sun_spec = pow(max(dot(refl, view_dir), 0.0), 160.0) * 2.5;
	float sparkle_noise = vnoise(wpos.xz * 1.4 + vec2(TIME * 0.7, -TIME * 0.5)) * vnoise(wpos.xz * 0.7 - TIME * 0.3);
	float glint = smoothstep(0.3, 0.45, sparkle_noise) * pow(max(dot(refl, view_dir), 0.0), 24.0);
	vec3 sun_col = vec3(1.0, 0.96, 0.86) * (1.0 - night_amount);
	col += sun_col * (sun_spec + glint * 0.9);
	col = mix(col, foam_color.rgb * mix(lit, vec3(1.0), 0.25), foam * 0.88);
	ALBEDO = col;
	// El agua profunda es opaca: si no, se transparenta distinto sobre el fondo y sobre el vacío.
	ALPHA = clamp(mix(0.55, 1.0, smoothstep(0.0, 0.6, t)) + foam, 0.0, 1.0);
}
