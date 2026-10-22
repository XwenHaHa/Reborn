shader_type spatial;
// 浅溪水面：程序化流动 + 涟漪高光 + 岸边泡沫。
//
// 为什么用 shader 而不是贴图：
//   ① 项目里没有水体贴图（也不该为一条 22×9 m 的小溪去拉一张 2K 法线）；
//   ② 之前的材质是纯色 StandardMaterial3D，**完全静态**，被负责人直接指出"水都不带动的"；
//   ③ 涟漪必须随时间变，用 `TIME` 最省事，且不引入任何资源依赖。
//
// 约束（别乱改）：
//   - 水面节点 `CreekWater` 仍必须是 **BoxMesh**（T011 断言 `creek_water_mesh_is_box` /
//     `creek_water_top_0.13` / `creek_water_depth_0.03`），所以这里**不做顶点位移**——
//     Box 顶面没有细分，位移也看不出来。运动全在片元里做。
//   - 不用 `discard`，不写 `NORMAL_MAP`（无贴图），只扰动 `NORMAL` 与 `ALBEDO`。

render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.281, 0.514, 0.596);
uniform vec3 deep_color : source_color = vec3(0.121, 0.286, 0.376);
uniform vec3 foam_color : source_color = vec3(0.858, 0.898, 0.925);
uniform vec2 flow_dir = vec2(-0.92, 0.39);   // 世界 XZ 上的流动方向（斜穿溪面）
uniform float flow_speed = 0.42;             // 图案平移速度（m/s 量级）
uniform float ripple_scale = 14.0;           // 涟漪频率（cells ~7 cm；太低会出现可见方块网格）
uniform float ripple_strength = 0.35;        // 法线扰动强度
uniform float warp_amount = 1.7;             // 域扭曲强度（打散噪声网格的规则感）
uniform float foam_width = 0.05;             // 岸边泡沫带宽度（UV 归一，0..0.5）
uniform float foam_strength = 0.55;
uniform float base_alpha = 0.62;
uniform float roughness_base = 0.08;         // 水要亮：粗糙度低才有太阳反光
uniform float specular_amount = 0.55;

varying vec3 world_pos;
varying vec2 face_uv;

// 整数型 hash（不用 sin-hash）：世界坐标 × 频率后可达上百，sin 精度退化会冒出方块状色带（实机踩到过）
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

// 三层叠加的涟漪高度场
float ripple_height(vec2 p, float t) {
	float h = 0.0;
	h += value_noise(p * 1.0 + vec2(t * 0.7, t * 0.3)) * 0.55;
	h += value_noise(p * 2.3 - vec2(t * 1.1, t * 0.5)) * 0.30;
	h += value_noise(p * 5.1 + vec2(t * 0.2, t * 1.7)) * 0.15;
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face_uv = UV;
}

void fragment() {
	// ① 世界 XZ 上的滚动坐标
	vec2 flow = normalize(flow_dir);
	vec2 base = world_pos.xz * ripple_scale - flow * (TIME * flow_speed * ripple_scale);
	float t = TIME;

	// ② 域扭曲：让噪声的方格边界弯掉，否则会看出规则的矩形块
	vec2 warp = vec2(
		value_noise(base * 0.13 + vec2(t * 0.21, -t * 0.17)),
		value_noise(base * 0.11 + vec2(-t * 0.19, t * 0.23)));
	vec2 p = base + (warp - 0.5) * warp_amount;

	// ③ 高度场 → 有限差分求法线（水面在 XZ 平面，法线朝 +Y）
	float h = ripple_height(p, t);
	float e = 0.08;
	float hx = ripple_height(p + vec2(e, 0.0), t);
	float hz = ripple_height(p + vec2(0.0, e), t);
	vec3 ripple_n = normalize(vec3(-(hx - h) / e * ripple_strength, 1.0, -(hz - h) / e * ripple_strength));

	// ④ 视角菲涅尔：掠射角更亮更"镜面"，正视更透明更浅
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fres = pow(1.0 - clamp(dot(ripple_n, view_dir), 0.0, 1.0), 3.0);

	// ⑤ 颜色：深色 ↔ 浅色，涟漪高处偏亮（像被风推起的细浪）
	float band = smoothstep(0.35, 0.75, h);
	vec3 water = mix(deep_color, shallow_color, band);
	water = mix(water, shallow_color * 1.10, fres * 0.30);

	// ⑥ 岸边泡沫：用面 UV 到矩形边界的距离，形成一圈窄白边（水的边界不再是硬切口）
	float edge = min(min(face_uv.x, 1.0 - face_uv.x), min(face_uv.y, 1.0 - face_uv.y));
	float foam = 1.0 - smoothstep(0.0, max(foam_width, 0.001), edge);
	foam *= mix(0.55, 1.0, value_noise(p * 6.0 + vec2(t * 1.6, -t * 0.9)));
	foam *= foam_strength;

	NORMAL = normalize((VIEW_MATRIX * vec4(ripple_n, 0.0)).xyz);
	ALBEDO = mix(water, foam_color, clamp(foam, 0.0, 1.0));
	ROUGHNESS = mix(roughness_base, 0.55, clamp(foam, 0.0, 1.0));
	SPECULAR = specular_amount;
	ALPHA = clamp(base_alpha + fres * 0.28 + foam * 0.35, 0.0, 0.95);
}
