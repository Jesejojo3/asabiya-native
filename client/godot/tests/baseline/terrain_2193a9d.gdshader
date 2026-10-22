shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://tests/baseline/map_common_2193a9d.gdshaderinc"

// Climate fine layers (half float, hardware filtered) and engine biome palette.
uniform sampler2D temp_tex : filter_linear, repeat_enable;
uniform sampler2D prec_tex : filter_linear, repeat_enable;
uniform sampler2D river_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 biome_colors[10];

// Per-cell presentation data (logical grid, nearest).
uniform sampler2D cell_remap_tex : filter_nearest, repeat_enable;
uniform sampler2D cell_color_tex : filter_nearest, repeat_enable;
uniform sampler2D cell_key_tex : filter_nearest, repeat_enable;

uniform float skirt_depth = 3.0;
uniform float river_carve = 0.09;
uniform float river_min_px = 1.1;
uniform float minor_rivers = 1.0;     // fades streams in with zoom
uniform float overlay_opacity = 0.0;
uniform float province_border = 0.0;   // 0..1, faded by zoom from the script
uniform float key_border = 0.0;        // borders between overlay groups (states…)
uniform float key_border_width = 0.30;
uniform float edge_glow = 0.6;
uniform int selected_cell = -1;
uniform int hovered_cell = -1;
uniform float selected_key = -2.0;
uniform float terrain_desaturate = 0.0;
uniform float time_scale = 1.0;

varying vec3 v_world;
varying float v_elev;

float river_mask(vec2 p) {
	vec2 uv = vec2(p.x / map_size.x, clamp(p.y / map_size.y, 0.0, 1.0));
	vec2 m = textureLod(river_tex, uv, 0.0).rg;
	return max(m.r, m.g * minor_rivers);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = vec2(wp.x, clamp(wp.z, 0.0, map_size.y));
	float e = elev_smooth(p);
	float h = height_from_elev(p, e);
	if (e > 0.0) {
		h -= smoothstep(0.35, 0.8, river_mask(p)) * river_carve;
	}
	if (COLOR.r > 0.5) {
		h -= skirt_depth;
	}
	VERTEX.y = h;
	v_world = vec3(wp.x, h, wp.z);
	v_elev = e;
}

int biome_of(float t, float pp) {
	if (t < -9.0) return 1;
	if (t < -1.0) return 2;
	if (t < 5.0) return pp < 250.0 ? 2 : 3;
	float tt = max(t, 0.0);
	if (pp < 150.0 + 8.0 * tt) return 7;
	if (pp < 330.0 + 13.0 * tt) return 6;
	if (t >= 20.0) return pp < 1300.0 ? 8 : 9;
	return pp < 700.0 ? 5 : 4;
}

float cell_key(ivec2 c) {
	return texelFetch(cell_key_tex, c, 0).r;
}

int land_cell(ivec2 c, bool fine_land) {
	float r = texelFetch(cell_remap_tex, c, 0).r;
	int raw = c.y * int(grid_size.x) + c.x;
	// remap: >= 0 for land cells (itself) and coastal sea cells (a land neighbour)
	float own = texelFetch(cell_remap_tex, c, 0).g;
	if (own > 0.5) return raw;
	if (fine_land && r >= 0.0) return int(r + 0.5);
	return -1 - raw;
}

ivec2 cell_coord(int id) {
	int gw = int(grid_size.x);
	return ivec2(id % gw, id / gw);
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 pw = vec2(mod(p.x, map_size.x), clamp(p.y, 0.0, map_size.y - 0.001));
	vec2 uv = pw / map_size;

	// --- shading normal from the same height function (bilinear + relief)
	float e = elev_bilinear(p);
	vec2 rp = relief_params(p, e);
	float eps = 0.25;
	float hc = height_with(p, e, rp);
	float hl = height_with(p - vec2(eps, 0.0), elev_bilinear(p - vec2(eps, 0.0)), rp);
	float hr = height_with(p + vec2(eps, 0.0), elev_bilinear(p + vec2(eps, 0.0)), rp);
	float hu = height_with(p - vec2(0.0, eps), elev_bilinear(p - vec2(0.0, eps)), rp);
	float hd = height_with(p + vec2(0.0, eps), elev_bilinear(p + vec2(0.0, eps)), rp);
	vec3 n = normalize(vec3(hl - hr, 2.0 * eps, hu - hd));
	// cavity term: valleys darker, crests lighter (cheap ambient occlusion)
	float cavity = clamp(((hl + hr + hu + hd) * 0.25 - hc) * 6.0, -1.0, 1.0);
	bool fine_land = e > 0.0;

	// --- biome albedo with organically dithered boundaries
	vec2 jitter = vec2(vnoise(p, int(map_size.x * 0.9), 7000), vnoise(p, int(map_size.x * 0.9), 8000)) * 0.9;
	vec2 juv = (p + jitter) / map_size;
	juv.y = clamp(juv.y, 0.0, 1.0);
	float t = textureLod(temp_tex, juv, 0.0).r;
	float pr = textureLod(prec_tex, juv, 0.0).r;
	int b = biome_of(t, pr);
	vec3 col = biome_colors[b];
	float mottling = relief_noise(p * 3.1) * 0.5 + vnoise(p, int(map_size.x * 6.0), 9000) * 0.5;
	col *= 1.0 + mottling * 0.07;
	col = max(mix(vec3(dot(col, vec3(0.3, 0.59, 0.11))), col, 1.25), vec3(0.0));
	// highlands toward rock, then perennial snow (legacy paintBase thresholds)
	if (b != 1) {
		col = mix(col, vec3(0.50, 0.47, 0.43), clamp((e - 2200.0) / 2600.0, 0.0, 1.0));
	}
	float slope = 1.0 - n.y;
	col = mix(col, vec3(0.45, 0.42, 0.38), smoothstep(0.35, 0.65, slope) * (0.4 + 0.5 * rp.y));
	float snow = smoothstep(4350.0, 4600.0, e + relief_noise(p * 2.0) * 140.0 - cavity * 900.0) * step(t, 2.0);
	snow = max(snow, step(float(b), 1.5) * step(0.5, float(b)));
	col = mix(col, vec3(0.86, 0.88, 0.92), snow * (1.0 - smoothstep(0.45, 0.8, slope) * 0.7));
	// beaches
	col = mix(col, vec3(0.80, 0.75, 0.60), (1.0 - smoothstep(10.0, 70.0, e)) * 0.55 * step(0.0, e));
	col *= 1.0 - cavity * 0.28;
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))), terrain_desaturate);

	float rough = 0.92;
	float spec = 0.35;

	// --- rivers (engine drainage, rasterised by the client)
	if (fine_land) {
		vec2 ruv = vec2(pw.x / map_size.x, pw.y / map_size.y);
		vec2 rmm = texture(river_tex, ruv).rg;
		float rm = max(rmm.r, rmm.g * minor_rivers);
		// thin lines lose contrast in coarser mips: lower the threshold there
		vec2 tdx = dFdx(ruv * vec2(textureSize(river_tex, 0)));
		vec2 tdy = dFdy(ruv * vec2(textureSize(river_tex, 0)));
		float mip = max(0.0, 0.5 * log2(max(dot(tdx, tdx), dot(tdy, tdy))));
		float thr = max(0.5 * exp2(-mip * 0.8), 0.07);
		float aa = max(fwidth(rm) * river_min_px, 0.02);
		float water = smoothstep(thr - aa, thr + aa, rm);
		vec3 river_col = vec3(0.09, 0.24, 0.33);
		col = mix(col, col * 0.82, smoothstep(0.15, 0.5, rm) * 0.6);
		col = mix(col, river_col, water);
		rough = mix(rough, 0.25, water);
		spec = mix(spec, 0.6, water);
		n = normalize(mix(n, vec3(0.0, 1.0, 0.0), water * 0.8));
	}

	// --- overlays: thematic colour, province and group borders, selection
	if (fine_land) {
		vec2 q = pw + border_warp(pw);
		vec2 qc = q / cell_size;
		ivec2 gi = ivec2(int(floor(qc.x)), int(floor(qc.y)));
		int gw = int(grid_size.x);
		int gh = int(grid_size.y);
		gi.x = posmod_i(gi.x, gw);
		gi.y = clamp(gi.y, 0, gh - 1);
		int id = land_cell(gi, true);
		if (id >= 0) {
			ivec2 ci = cell_coord(id);
			vec4 oc = texelFetch(cell_color_tex, ci, 0);
			float my_key = cell_key(ci);
			vec2 f = qc - floor(qc);
			float dist[4] = float[4](f.x * cell_size, (1.0 - f.x) * cell_size, f.y * cell_size, (1.0 - f.y) * cell_size);
			ivec2 off[4] = ivec2[4](ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1));
			float d_prov = 99.0;
			float d_key = 99.0;
			float d_sel = 99.0;
			float d_selkey = 99.0;
			for (int k = 0; k < 4; k++) {
				ivec2 nc = gi + off[k];
				if (nc.y < 0 || nc.y >= gh) continue;
				nc.x = posmod_i(nc.x, gw);
				int nid = land_cell(nc, true);
				if (nid == id) continue;
				d_prov = min(d_prov, dist[k]);
				float nk = nid >= 0 ? cell_key(cell_coord(nid)) : -1.0;
				if (abs(nk - my_key) > 0.5) d_key = min(d_key, dist[k]);
				if (id == selected_cell || nid == selected_cell) d_sel = min(d_sel, dist[k]);
				if ((abs(my_key - selected_key) < 0.5) != (abs(nk - selected_key) < 0.5)) d_selkey = min(d_selkey, dist[k]);
			}
			float px = length(fwidth(q));
			float a = oc.a * overlay_opacity;
			// stronger fill near group borders, CK-style
			float glow = 1.0 - smoothstep(0.0, 1.6, d_key);
			a = clamp(a * (1.0 + edge_glow * glow * step(0.01, oc.a)), 0.0, 1.0);
			col = mix(col, oc.rgb, a);
			// province borders (thin, zoom-faded)
			float wp = max(0.045, px * 0.8);
			float lp = 1.0 - smoothstep(wp * 0.5, wp * 0.5 + px, d_prov);
			col = mix(col, col * 0.62, lp * province_border * 0.6);
			// group borders (states, peoples…)
			float wk = max(key_border_width, px * 1.4);
			float lk = 1.0 - smoothstep(wk * 0.5, wk * 0.5 + px, d_key);
			col = mix(col, vec3(0.08, 0.07, 0.06), lk * key_border * step(0.01, overlay_opacity));
			// selection
			if (selected_key > -1.5 && abs(my_key - selected_key) < 0.5) {
				col = mix(col, vec3(1.0, 0.95, 0.8), 0.12);
			}
			float ls = 1.0 - smoothstep(wk * 0.5, wk * 0.5 + px, d_selkey);
			col = mix(col, vec3(1.0, 0.94, 0.78), ls * step(-1.5, selected_key));
			if (id == hovered_cell) {
				col = mix(col, vec3(1.0), 0.16);
			}
			if (id == selected_cell) {
				col = mix(col, vec3(1.0, 0.92, 0.6), 0.22);
				float w2 = max(0.22, px * 2.0);
				float l2 = 1.0 - smoothstep(w2 * 0.5, w2 * 0.5 + px, d_sel);
				col = mix(col, vec3(1.0, 0.97, 0.86), l2);
			}
		}
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
