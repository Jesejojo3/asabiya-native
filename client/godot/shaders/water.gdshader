shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/map_common.gdshaderinc"

uniform vec3 shallow_color = vec3(0.17, 0.42, 0.47);
uniform vec3 deep_color = vec3(0.025, 0.085, 0.17);
uniform vec3 foam_color = vec3(0.78, 0.86, 0.86);
uniform float wave_strength = 0.18;
uniform float overlay_dim = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float e = elev_bilinear(p);
	if (e > 0.0) {
		discard;
	}
	float depth = -e;
	float k = pow(clamp(depth / 4500.0, 0.0, 1.0), 0.45);
	vec3 col = mix(shallow_color, deep_color, k);
	// continental shelf banding gives depth cues from afar
	col *= 1.0 - 0.08 * smoothstep(150.0, 260.0, depth) + 0.05 * (1.0 - smoothstep(0.0, 120.0, depth));
	float t = TIME * 0.05;
	// three wave octaves, each faded out once it would alias on screen
	float px = length(fwidth(p));
	vec2 slope = vec2(0.0);
	int per[3] = int[3](int(map_size.x * 1.5), int(map_size.x * 5.0), int(map_size.x * 14.0));
	float amp[3] = float[3](0.5, 0.3, 0.2);
	vec2 drift[3] = vec2[3](vec2(9.0, 4.0), vec2(-6.0, 7.0), vec2(4.0, -11.0));
	for (int o = 0; o < 3; o++) {
		float f = float(per[o]) / map_size.x;
		float fade = 1.0 - smoothstep(0.15, 0.6, px * f);
		if (fade <= 0.0) continue;
		vec2 q = p + drift[o] * t / f * 0.2;
		float h0 = vnoise(q, per[o], 11000 + o * 1000);
		float hx = vnoise(q + vec2(0.25 / f, 0.0), per[o], 11000 + o * 1000);
		float hz = vnoise(q + vec2(0.0, 0.25 / f), per[o], 11000 + o * 1000);
		slope += vec2(h0 - hx, h0 - hz) * amp[o] * fade;
	}
	vec3 n = normalize(vec3(slope.x * wave_strength * 2.2, 1.0, slope.y * wave_strength * 2.2));
	// shoreline foam
	float shore = 1.0 - smoothstep(0.0, 70.0, depth);
	float foam = shore * smoothstep(0.1, 0.7, vnoise(p * 2.0 + vec2(TIME * 0.4, 0.0), per[1], 13000) * 0.5 + 0.5 + shore * 0.4);
	col = mix(col, foam_color, foam * 0.45);
	col *= 1.0 - overlay_dim;
	ALBEDO = col;
	ROUGHNESS = 0.18;
	SPECULAR = 0.55;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
