shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;

// ART14 角色皮毛面 shader。
//
// 只做"呈现层"近似：不改顶点、不改骨骼、不改玩法。
// 逐项累加（负责人要求一项一项验）：
//   S1 PBR 校正（roughness / specular 由 uniform 控制）
//   S2 高频绒毛法线：程序化多倍频噪声扰动切线空间法线，制造"毛面小起伏"，
//      而不是抛光塑料那种绝对光滑面。
//
// 注意：噪声在 UV 空间算，因此依赖模型自带 UV；没有 UV 的物种会退化为平滑面。
//
// 注释必须用 //：GDShader 不支持 # / ##，写错会直接编译失败。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool has_albedo_tex = true;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal_tex = false;

uniform float fur_roughness = 0.94;
uniform float fur_specular = 0.16;

// S2：绒毛微观法线
uniform float fur_uv_scale = 90.0;
uniform float fur_normal_strength = 0.08;
uniform float fur_albedo_variation = 0.0;

// S3：轮廓绒光（掠射角的微弱边缘光，模拟绒毛发梢把光"烧"进轮廓）
// 注意：这是视角相关近似，不是真实次表面；强度必须克制，否则会读成"描边贴纸"。
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.82, 1.0);
uniform float rim_strength = 0.28;
uniform float rim_power = 3.5;

// S4：次表面近似。Godot 空间着色器没有真 SSS，用内置 BACKLIGHT（薄处透光）
// 近似"光穿过耳朵/鼻口"的观感；强度必须小于轮廓光，否则会读成自发光。
uniform vec3 backlight_color : source_color = vec3(0.80, 0.42, 0.28);
uniform float backlight_strength = 0.0;

float hashv(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hashv(i);
	float b = hashv(i + vec2(1.0, 0.0));
	float c = hashv(i + vec2(0.0, 1.0));
	float d = hashv(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 三个倍频叠加：低频"毛簇" + 高频"毛尖"（各向同性，强度刻意压到"只加微表面"）
// 实测记录：各向异性拉伸（0.32/x 压扁）在现有 UV 与面密度下读作"毛毡/拉丝金属"，
// 更差；因此这里保持各向同性并把强度压到接近判读阈。
float fur_noise(vec2 uv) {
	return vnoise(uv) * 0.55 + vnoise(uv * 2.6) * 0.32 + vnoise(uv * 6.4) * 0.13;
}

void fragment() {
	vec4 base = albedo_tint;
	if (has_albedo_tex) {
		base *= texture(albedo_tex, UV);
	}
	// 微小亮度起伏：真实毛发不是一整片均匀色块
	float v = fur_noise(UV * fur_uv_scale * 0.35);
	ALBEDO = base.rgb * (1.0 + (v - 0.5) * 2.0 * fur_albedo_variation);
	ROUGHNESS = fur_roughness;
	SPECULAR = fur_specular;

	vec3 n = vec3(0.0, 0.0, 1.0);
	if (has_normal_tex) {
		n = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	}
	// 有限差分求程序化高度场梯度 → 切线空间法线扰动
	float e = 0.0015;
	float h0 = fur_noise(UV * fur_uv_scale);
	float hx = fur_noise((UV + vec2(e, 0.0)) * fur_uv_scale);
	float hy = fur_noise((UV + vec2(0.0, e)) * fur_uv_scale);
	vec2 grad = vec2(hx - h0, hy - h0) / e;
	n.xy += -grad * fur_normal_strength * 0.06;
	NORMAL = normalize(n);

	// S3：掠射角绒光。用噪声轻微调制，避免一圈"描边"感
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float fuzz = 0.55 + 0.45 * fur_noise(UV * fur_uv_scale * 0.5);
	EMISSION += rim_color.rgb * fres * rim_strength * fuzz;

	// S4：薄处透光（耳朵/鼻口/尾尖）——引擎按光照方向自动调制，不需要自己写 light()
	BACKLIGHT = backlight_color * backlight_strength;
}
