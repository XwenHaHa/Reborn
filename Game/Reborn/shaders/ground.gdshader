shader_type spatial;
// 地面：程序化草土混合（无贴图依赖）。80×80 m 的纯色平面是场景里最大的一块"假"，
// 用低频噪声做草/土斑块 + 高频细粒，成本几乎为零。
//
// 约束：地面节点仍是 `BoxMesh`（T011 断言 `ground_top_is_0.10` / 80×80 / 覆盖可玩区），
// 这里只换材质，不动几何与碰撞。
//
// ART13（2026-11-02）：可选贴图路径（`tex_amount` 默认 0 → 既有使用者零变化）。
// 远景平铺感修复：世界坐标**双尺度采样 + 低频噪声互混**（打破 UV 平铺周期），
// 程序化斑块 (n/n2) 保留为贴图明度调制，维持草/土区域感。

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 color_grass : source_color = vec3(0.255, 0.290, 0.215);
uniform vec3 color_dirt : source_color = vec3(0.285, 0.255, 0.215);
uniform vec3 color_dry : source_color = vec3(0.320, 0.310, 0.235);
uniform float patch_scale = 0.09;    // 低频斑块频率（1/m）
uniform float grain_strength = 0.10; // 高频细粒强度
uniform float contrast = 0.55;
uniform float roughness_value = 0.93;

// ART13：可选双尺度贴图（世界坐标采样，不依赖网格 UV）
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_arm : filter_linear_mipmap, repeat_enable;
uniform float tex_amount = 0.0;      // 0 = 纯程序化（旧行为）；1 = 全贴图
uniform vec3 tex_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec2 tex_scale_a = vec2(0.52, 0.52);   // 小尺度（~1.9 m/tile）
uniform vec2 tex_scale_b = vec2(0.185, 0.185); // 大尺度（~5.4 m/tile）
uniform float tex_noise_scale = 0.06;          // 互混权重噪声频率（~17 m 周期）

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

	// ART13：可选双尺度贴图路径（世界坐标采样 + 低频噪声互混，打破平铺周期）
	vec3 out_col = col;
	vec3 out_nrm = vec3(0.5, 0.5, 1.0);
	float out_rough = roughness_value;
	float out_ao = 1.0;
	if (tex_amount > 0.001) {
		vec2 uv_a = world_pos.xz * tex_scale_a;
		vec2 uv_b = world_pos.xz * tex_scale_b + vec2(0.37, 0.61);
		float w = smoothstep(0.32, 0.68, fbm(world_pos.xz * tex_noise_scale));
		vec3 ta = texture(tex_albedo, uv_a).rgb;
		vec3 tb = texture(tex_albedo, uv_b).rgb;
		// 程序化低频斑块转为贴图明度调制：保住草/土区域感，避免整张均一
		float pm = 0.82 + 0.55 * (n - 0.5) + 0.30 * (n2 - 0.5);
		out_col = mix(ta, tb, w) * tex_tint * pm;
		out_nrm = mix(texture(tex_normal, uv_a).rgb, texture(tex_normal, uv_b).rgb, w);
		vec2 arm_a = texture(tex_arm, uv_a).rg;
		vec2 arm_b = texture(tex_arm, uv_b).rg;
		out_rough = clamp(mix(arm_a.g, arm_b.g, w) * 1.15, 0.5, 1.0);
		out_ao = mix(arm_a.r, arm_b.r, w);
	}

	ALBEDO = out_col * (1.0 + grain);
	ROUGHNESS = out_rough;
	SPECULAR = 0.2;
	NORMAL_MAP = out_nrm;
	AO = mix(1.0, out_ao, 0.6 * tex_amount);
}
