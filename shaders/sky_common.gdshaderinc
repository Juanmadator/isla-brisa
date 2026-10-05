// Degradado del cielo compartido por el cielo y el agua (que lo refleja): horizonte → cénit,
// halo del sol y, con el sol bajo, una franja cálida hacia su lado y otra fresca enfrente.

vec3 sky_gradient(vec3 dir, vec3 top, vec3 horizon, vec3 sun_col, vec3 sd) {
	float y = dir.y;
	vec3 col = mix(horizon, top, smoothstep(-0.02, 0.55, y));
	col = mix(col, horizon * 0.92, smoothstep(0.0, -0.08, y));
	float sun_up = smoothstep(-0.12, 0.05, sd.y);
	// Sol bajo (amanecer y atardecer): cuánto pesa la luz rasante.
	float low = smoothstep(0.42, 0.06, sd.y) * smoothstep(-0.3, -0.04, sd.y);
	vec2 hd = normalize(dir.xz + vec2(1e-5));
	vec2 hs = normalize(sd.xz + vec2(1e-5));
	float az = dot(hd, hs) * 0.5 + 0.5;
	float near_h = 1.0 - smoothstep(0.0, 0.4, abs(y));
	// Lado del sol: dorado/naranja intenso pegado al horizonte.
	vec3 warm = mix(sun_col, vec3(1.0, 0.58, 0.26), 0.55);
	col = mix(col, warm, pow(az, 4.0) * near_h * low * 0.85);
	// Lado contrario: banda rosada sobre un horizonte más frío (cinturón de Venus).
	float anti = pow(1.0 - az, 2.0) * low;
	col = mix(col, mix(top, vec3(0.42, 0.36, 0.62), 0.5), anti * (1.0 - smoothstep(0.0, 0.1, y)) * 0.45);
	col = mix(col, vec3(0.92, 0.6, 0.66), anti * smoothstep(0.03, 0.12, y) * (1.0 - smoothstep(0.12, 0.3, y)) * 0.35);
	// Halo del sol: más ancho cuanto más bajo está (la luz cruza más aire).
	float sun_dot = max(dot(dir, sd), 0.0);
	col += sun_col * pow(sun_dot, mix(6.0, 3.0, low)) * mix(0.25, 0.45, low) * sun_up;
	return col;
}
