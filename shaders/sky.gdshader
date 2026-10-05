shader_type sky;
// Cielo pintado: degradado, sol y luna en disco, nubes de algodón con dos tonos
// y estrellas de noche. Los colores los pone el ciclo de día.

uniform vec3 top_color : source_color = vec3(0.24, 0.55, 0.92);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.88, 0.98);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.82);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.68, 0.76, 0.9);
uniform vec3 moon_dir = vec3(-0.3, 0.6, -0.4);
uniform vec3 sun_vec = vec3(0.3, 0.8, 0.3);
uniform float night = 0.0;
uniform float cloud_time = 0.0;
uniform float cloud_cover = 0.5;

#include "res://shaders/noise.gdshaderinc"

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.55, y));
	// Bajo el horizonte: un poco más oscuro (el mar lejano se funde con la niebla).
	col = mix(col, horizon_color * 0.92, smoothstep(0.0, -0.08, y));

	vec3 sd = normalize(sun_vec);
	float sun_dot = dot(dir, sd);
	float sun_up = smoothstep(-0.12, 0.05, sd.y);
	// El halo del sol tiñe el horizonte al amanecer y al atardecer.
	col += sun_color * pow(max(sun_dot, 0.0), 6.0) * 0.25 * sun_up;

	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(0.9988, 0.9992, sun_dot) * sun_up;
		col = mix(col, sun_color * 1.6, disk);
		col += sun_color * pow(max(sun_dot, 0.0), 300.0) * 0.6 * sun_up;

		vec3 md = normalize(moon_dir);
		float moon_dot = dot(dir, md);
		float moon = smoothstep(0.9993, 0.9995, moon_dot);
		float moon_shadow = smoothstep(0.9993, 0.9995, dot(dir, normalize(md + vec3(0.012, 0.006, 0.0))));
		col = mix(col, vec3(0.95, 0.96, 1.0), moon * (1.0 - moon_shadow * 0.85) * night);
		col += vec3(0.5, 0.6, 0.9) * pow(max(moon_dot, 0.0), 400.0) * 0.4 * night;

		// Estrellas
		if (night > 0.01 && y > 0.0) {
			vec2 sp = vec2(atan(dir.x, dir.z) * 90.0, asin(clamp(y, -1.0, 1.0)) * 90.0);
			vec2 cell = floor(sp);
			float h = hash(cell);
			vec2 off = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
			float d = length(fract(sp) - 0.5 - off * 0.6);
			float star = step(0.985, h) * smoothstep(0.12, 0.0, d);
			float twinkle = 0.6 + 0.4 * sin(TIME * (2.0 + h * 5.0) + h * 40.0);
			col += vec3(1.0, 0.97, 0.9) * star * twinkle * night * smoothstep(0.0, 0.25, y);
		}

		// Nubes
		if (y > 0.0) {
			vec2 uv = dir.xz / (y + 0.18) * 1.1 + vec2(cloud_time * 0.012, cloud_time * 0.005);
			float n = fbm(uv * 1.3);
			float thr = mix(0.62, 0.42, cloud_cover);
			float cloud = smoothstep(thr, thr + 0.035, n);
			float n2 = fbm(uv * 1.3 + sd.xz * 0.12);
			float shade = smoothstep(thr + 0.02, thr + 0.12, n2);
			float rim = smoothstep(thr + 0.035, thr + 0.0, n) * cloud;
			vec3 cc = mix(cloud_light, cloud_shade, shade * 0.85);
			cc += sun_color * rim * 0.25 * sun_up;
			float fade = smoothstep(0.0, 0.12, y);
			col = mix(col, cc, cloud * fade * 0.96);
		}
	}
	COLOR = col;
}
