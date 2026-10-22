shader_type canvas_item;
render_mode unshaded;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform sampler2D temperatures : filter_linear, repeat_disable;
uniform sampler2D rainfall : filter_linear, repeat_disable;
uniform sampler2D overlay : filter_nearest, repeat_disable;
uniform sampler2D grouping : filter_nearest, repeat_disable;
uniform sampler2D remap : filter_nearest, repeat_disable;
uniform vec2 grid_size;
uniform vec2 fine_size;
uniform float selected = -2.0;
uniform float cell_pixels = 1.0;
uniform float border_strength = 1.0;
float province(vec2 uv) {
	vec2 cell = clamp(floor(uv * grid_size), vec2(0.0), grid_size-1.0);
	float original = cell.y * grid_size.x + cell.x;
	float land_id = texture(remap, (cell + 0.5) / grid_size).r;
	return texture(heights, uv).r > 0.0 && land_id >= 0.0 ? land_id : original;
}
vec2 cell_uv(float id) {
	return (vec2(mod(id, grid_size.x), floor(id/grid_size.x))+0.5)/grid_size;
}
void fragment() {
	vec2 uv = UV;
	float h = texture(heights, uv).r;
	float t = texture(temperatures, uv).r;
	float p = texture(rainfall, uv).r;
	vec3 base = vec3(110.0,150.0,83.0)/255.0;
	if (p > 1600.0) base=vec3(48.0,109.0,72.0)/255.0;
	if (p < 350.0) base=vec3(192.0,171.0,109.0)/255.0;
	if (t < 0.0) base=vec3(182.0,198.0,185.0)/255.0;
	if (h > 1800.0) base=vec3(137.0,123.0,95.0)/255.0;
	if (h > 3500.0) base=vec3(220.0,218.0,205.0)/255.0;
	vec2 d=1.0/fine_size;
	float dx=texture(heights,uv+vec2(d.x,0)).r-texture(heights,uv-vec2(d.x,0)).r;
	float dy=texture(heights,uv+vec2(0,d.y)).r-texture(heights,uv-vec2(0,d.y)).r;
	float shade=clamp(0.88+dot(normalize(vec3(-dx/900.0,-dy/900.0,1.0)), normalize(vec3(-0.6,-0.8,1.4)))*0.27,0.55,1.18);
	if (h <= 0.0) {
		float depth=clamp(-h/6000.0,0.0,1.0);
		base=vec3(12.0,85.0-45.0*depth,140.0-65.0*depth)/255.0;
	} else {
		float id=province(uv);
		vec2 cuv=cell_uv(id);
		vec4 thematic=texture(overlay,cuv);
		base=mix(base,thematic.rgb,thematic.a*0.82)*shade;
		float key=texture(grouping,cuv).r;
		vec2 step_uv=max(fwidth(uv),vec2(0.000001));
		float other=province(uv+step_uv);
		float other_key=texture(grouping,cell_uv(other)).r;
		float other2=province(uv-step_uv*vec2(1.0,-1.0));
		float key2=texture(grouping,cell_uv(other2)).r;
		if (cell_pixels>2.0 && key>=0.0 && (other_key!=key || key2!=key)) base=mix(base,vec3(0.08,0.09,0.10),0.65*border_strength);
		if (id==selected) base=mix(base,vec3(1.0,0.85,0.35),0.35);
		if (cell_pixels>20.0) {
			vec2 edges=min(fract(uv*grid_size),1.0-fract(uv*grid_size))*cell_pixels;
			if (min(edges.x,edges.y)<0.7) base*=0.77;
		}
	}
	COLOR=vec4(base,1.0);
}
