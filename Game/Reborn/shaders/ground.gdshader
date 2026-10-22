shader_type spatial;
// 地面：程序化草土混合（无贴图依赖）。80×80 m 的纯色平面是场景里最大的一块"假"，
// 用低频噪声做草/土斑块 + 高频细粒，成本几乎为零。
//
// 约束：地面节点仍是 `BoxMesh`（T011 断言 `ground_top_is_0.10` / 80×80 / 覆盖可玩区），
// 这里只换材质，不动几何与碰撞。

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 color_grass : source_color = vec3(0.255, 0.290, 0.215);
uniform vec3 color_dirt : source_color = vec3(0.285, 0.255, 0.215);
uniform vec3 color_dry : source_color = vec3(0.320, 0.310, 0.235);
uniform float patch_scale = 0.09;    // 低频斑块频率（1/m）
uniform float grain_strength = 0.10; // 高频细粒强度
uniform float contrast = 0.55;
uniform float roughness_value = 0.93;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	v += value_noise(p * 1.0) * 0.55;
	v += value_noise(p * 2.7) * 0.28;
	v += value_noise(p * 6.1) * 0.17;
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * patch_scale;
	float n = fbm(p);
	float n2 = fbm(p * 3.3 + vec2(11.7, 5.3));

	// 三色混合：草 → 土 → 干草
	vec3 col = mix(color_grass, color_dirt, smoothstep(0.35, 0.62, n));
	col = mix(col, color_dry, smoothstep(0.58, 0.86, n2) * contrast);

	// 高频细粒：让大面积不像纯色油漆
	float grain = (value_noise(world_pos.xz * 7.0) - 0.5) * grain_strength
		+ (value_noise(world_pos.xz * 21.0) - 0.5) * grain_strength * 0.5;
	col *= (1.0 + grain);

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
