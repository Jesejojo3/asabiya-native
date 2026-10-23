// Shared visual geometry. Mirrors scripts/map/map_math.gd line by line:
// any change here must be made there too (picking and object placement use it).

uniform vec2 map_size = vec2(1600.0, 800.0);
uniform vec2 grid_size = vec2(400.0, 200.0);
uniform float cell_size = 4.0;
uniform float land_scale = 0.0023809524;
uniform float ocean_scale = 1.8;
uniform float relief_detail = 0.55;
uniform float warp_amp = 0.85;
uniform sampler2D elev_tex : filter_linear, repeat_enable;

const float OCEAN_REF_DEPTH = 5600.0;

uint hash2u(uint x, uint y) {
	uint h = x * 374761393u + y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return h ^ (h >> 16u);
}

float rnd(int x, int y) {
	return float(hash2u(uint(x), uint(y)) & 16777215u) / 16777215.0;
}

int posmod_i(int a, int m) {
	int r = a % m;
	return r < 0 ? r + m : r;
}

float vnoise(vec2 p, int periods, int salt) {
	vec2 s = p * float(periods) / map_size.x;
	vec2 i = floor(s);
	vec2 f = s - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	int ix = int(i.x);
	int iz = int(i.y);
	int x0 = posmod_i(ix, periods);
	int x1 = posmod_i(ix + 1, periods);
	int z0 = max(iz + salt, 0);
	int z1 = max(iz + 1 + salt, 0);
	float a = rnd(x0, z0);
	float b = rnd(x1, z0);
	float c = rnd(x0, z1);
	float d = rnd(x1, z1);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

float relief_noise(vec2 p) {
	int periods = int(map_size.x * 0.45);
	return vnoise(p, periods, 0) * 0.6 + vnoise(p, periods * 2, 1000) * 0.28 + vnoise(p, periods * 4, 2000) * 0.12;
}

float ridge_noise(vec2 p) {
	int periods = int(map_size.x * 0.2);
	float r1 = 1.0 - abs(vnoise(p, periods, 21000));
	float r2 = 1.0 - abs(vnoise(p, periods * 2, 22000));
	float r3 = 1.0 - abs(vnoise(p, periods * 4, 23000));
	return (r1 * r1 * 0.55 + r2 * r2 * 0.3 * r1 + r3 * r3 * 0.15 * r2) * 2.0 - 0.9;
}

vec2 border_warp(vec2 p) {
	int periods = int(map_size.x * 0.3);
	float wx = vnoise(p, periods, 3000) + 0.45 * vnoise(p, periods * 3, 4000);
	float wz = vnoise(p, periods, 5000) + 0.45 * vnoise(p, periods * 3, 6000);
	return vec2(wx, wz) * warp_amp;
}

float texel_elev(int x, int y) {
	ivec2 sz = ivec2(map_size);
	return texelFetch(elev_tex, ivec2(posmod_i(x, sz.x), clamp(y, 0, sz.y - 1)), 0).r;
}

float elev_bilinear(vec2 p) {
	vec2 s = p - 0.5;
	vec2 i = floor(s);
	vec2 f = s - i;
	int ix = int(i.x);
	int iz = int(i.y);
	return mix(mix(texel_elev(ix, iz), texel_elev(ix + 1, iz), f.x), mix(texel_elev(ix, iz + 1), texel_elev(ix + 1, iz + 1), f.x), f.y);
}

float cr(float p0, float p1, float p2, float p3, float t) {
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)));
}

float elev_bicubic(vec2 p) {
	vec2 s = p - 0.5;
	vec2 i = floor(s);
	vec2 f = s - i;
	int ix = int(i.x);
	int iz = int(i.y);
	float r[4];
	for (int j = -1; j < 3; j++) {
		r[j + 1] = cr(texel_elev(ix - 1, iz + j), texel_elev(ix, iz + j), texel_elev(ix + 1, iz + j), texel_elev(ix + 2, iz + j), f.x);
	}
	return cr(r[0], r[1], r[2], r[3], f.y);
}

float elev_smooth(vec2 p) {
	float b = elev_bilinear(p);
	float c = elev_bicubic(p);
	float v = mix(b, c, smoothstep(60.0, 320.0, abs(b)));
	if (b > 0.0) {
		v = max(v, min(b, 1.0));
	} else {
		v = min(v, max(b, -1.0));
	}
	return v;
}

float metres_to_units(float e) {
	if (e >= 0.0) {
		return e * land_scale;
	}
	return -ocean_scale * pow(-e / OCEAN_REF_DEPTH, 0.55);
}

// Relief character from the engine data: steep fine elevation gradients get
// ridged mountains, flat lowlands and plateaus only gentle undulation.
vec2 relief_params(vec2 p, float e) {
	float gx = elev_bilinear(p + vec2(1.0, 0.0)) - elev_bilinear(p - vec2(1.0, 0.0));
	float gz = elev_bilinear(p + vec2(0.0, 1.0)) - elev_bilinear(p - vec2(0.0, 1.0));
	float g = length(vec2(gx, gz)) * 0.5;
	float steep = smoothstep(60.0, 700.0, g);
	float amp = relief_detail * (0.10 + 1.3 * steep + 0.35 * smoothstep(1500.0, 4500.0, e));
	return vec2(amp, steep);
}

float height_with(vec2 p, float e, vec2 rp) {
	float y = metres_to_units(e);
	if (e > 0.0) {
		float n = mix(relief_noise(p), ridge_noise(p), rp.y);
		y += n * rp.x * smoothstep(0.0, 60.0, e);
	}
	return y;
}

float height_from_elev(vec2 p, float e) {
	return height_with(p, e, relief_params(p, e));
}

float height_at(vec2 p) {
	return height_from_elev(p, elev_smooth(p));
}

// Fast fragment-side approximation (bilinear hardware filtering) used only for
// shading normals, never for geometry.
float elev_hw(vec2 p) {
	return textureLod(elev_tex, vec2(p.x / map_size.x, clamp(p.y / map_size.y, 0.0, 1.0)), 0.0).r;
}
