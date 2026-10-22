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

// Mathematical modulo for m > 0. A float quotient (exact for |a| < 2^24) plus
// one correction step replaces the integer division GPUs emulate; the result
// is the same integer as ((a % m) + m) % m.
int posmod_i(int a, int m) {
	int r = a - m * int(floor(float(a) / float(m)));
	if (r < 0) r += m;
	else if (r >= m) r -= m;
	return r;
}

float vbilerp(float a, float b, float c, float d, vec2 u) {
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
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
	return vbilerp(a, b, c, d, u);
}

// vnoise at p and at the four points p -/+ (d,0), p -/+ (0,d) (returned as
// xm, xp, zm, zp), sharing lattice hashes: 8 instead of 20 per call. Each value
// uses the same lattice coordinates, hashes and interpolation as vnoise().
// Requires d * periods / map_size.x < 0.5, so at most one x and one z
// neighbour leaves the centre cell (terrain: at most 0.45).
vec4 vnoise_cross(vec2 p, float d, int periods, int salt, out float centre) {
	vec2 s = p * float(periods) / map_size.x;
	vec2 sxm = (p - vec2(d, 0.0)) * float(periods) / map_size.x;
	vec2 sxp = (p + vec2(d, 0.0)) * float(periods) / map_size.x;
	vec2 szm = (p - vec2(0.0, d)) * float(periods) / map_size.x;
	vec2 szp = (p + vec2(0.0, d)) * float(periods) / map_size.x;
	vec2 i = floor(s);
	vec2 f = s - i;
	int ix = int(i.x);
	int iz = int(i.y);
	int x0 = posmod_i(ix, periods);
	int x1 = posmod_i(ix + 1, periods);
	int z0 = max(iz + salt, 0);
	int z1 = max(iz + 1 + salt, 0);
	float h00 = rnd(x0, z0);
	float h10 = rnd(x1, z0);
	float h01 = rnd(x0, z1);
	float h11 = rnd(x1, z1);
	centre = vbilerp(h00, h10, h01, h11, f * f * (3.0 - 2.0 * f));
	// x neighbours keep the centre row; one extra lattice column.
	vec2 im = floor(sxm);
	vec2 ip = floor(sxp);
	vec2 fm = sxm - im;
	vec2 fp = sxp - ip;
	bool cross_m = int(im.x) < ix;
	bool cross_p = int(ip.x) > ix;
	int xe = posmod_i(cross_m ? ix - 1 : ix + 2, periods);
	float e0 = rnd(xe, z0);
	float e1 = rnd(xe, z1);
	vec4 v;
	v.x = cross_m ? vbilerp(e0, h00, e1, h01, fm * fm * (3.0 - 2.0 * fm)) : vbilerp(h00, h10, h01, h11, fm * fm * (3.0 - 2.0 * fm));
	v.y = cross_p ? vbilerp(h10, e0, h11, e1, fp * fp * (3.0 - 2.0 * fp)) : vbilerp(h00, h10, h01, h11, fp * fp * (3.0 - 2.0 * fp));
	// z neighbours keep the centre column; one extra lattice row.
	im = floor(szm);
	ip = floor(szp);
	fm = szm - im;
	fp = szp - ip;
	cross_m = int(im.y) < iz;
	cross_p = int(ip.y) > iz;
	int ze = max((cross_m ? iz - 1 : iz + 2) + salt, 0);
	e0 = rnd(x0, ze);
	e1 = rnd(x1, ze);
	v.z = cross_m ? vbilerp(e0, e1, h00, h10, fm * fm * (3.0 - 2.0 * fm)) : vbilerp(h00, h10, h01, h11, fm * fm * (3.0 - 2.0 * fm));
	v.w = cross_p ? vbilerp(h01, h11, e0, e1, fp * fp * (3.0 - 2.0 * fp)) : vbilerp(h00, h10, h01, h11, fp * fp * (3.0 - 2.0 * fp));
	return v;
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

// relief_noise/ridge_noise at the centre and the four cross neighbours at
// distance d (see vnoise_cross), with the same octave weights per point.
vec4 relief_noise_cross(vec2 p, float d, out float centre) {
	int periods = int(map_size.x * 0.45);
	float c1;
	float c2;
	float c3;
	vec4 v1 = vnoise_cross(p, d, periods, 0, c1);
	vec4 v2 = vnoise_cross(p, d, periods * 2, 1000, c2);
	vec4 v3 = vnoise_cross(p, d, periods * 4, 2000, c3);
	centre = c1 * 0.6 + c2 * 0.28 + c3 * 0.12;
	return v1 * 0.6 + v2 * 0.28 + v3 * 0.12;
}

vec4 ridge_noise_cross(vec2 p, float d, out float centre) {
	int periods = int(map_size.x * 0.2);
	float c1;
	float c2;
	float c3;
	vec4 r1 = vec4(1.0) - abs(vnoise_cross(p, d, periods, 21000, c1));
	vec4 r2 = vec4(1.0) - abs(vnoise_cross(p, d, periods * 2, 22000, c2));
	vec4 r3 = vec4(1.0) - abs(vnoise_cross(p, d, periods * 4, 23000, c3));
	c1 = 1.0 - abs(c1);
	c2 = 1.0 - abs(c2);
	c3 = 1.0 - abs(c3);
	centre = (c1 * c1 * 0.55 + c2 * c2 * 0.3 * c1 + c3 * c3 * 0.15 * c2) * 2.0 - 0.9;
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

float height_from_noise(float e, vec2 rp, float relief, float ridge) {
	float y = metres_to_units(e);
	if (e > 0.0) {
		float n = mix(relief, ridge, rp.y);
		y += n * rp.x * smoothstep(0.0, 60.0, e);
	}
	return y;
}

float height_with(vec2 p, float e, vec2 rp) {
	if (e <= 0.0) {
		return metres_to_units(e);
	}
	// mix(a, b, 0.0) is exactly a: gentle terrain (steep == 0) skips the ridges.
	return height_from_noise(e, rp, relief_noise(p), rp.y > 0.0 ? ridge_noise(p) : 0.0);
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
