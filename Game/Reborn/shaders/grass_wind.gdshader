shader_type spatial;
// 草丛/芦苇的**风摆动**（只改顶点，不改颜色逻辑）。
//
// 为什么需要：ART01 的草丛是平面细长叶片（双面、2040 tris），静止时近距离就是"绿纸条"。
// 运动是低成本把"假草"救回来的关键手段——风一吹，纸片感立刻弱很多。
//
// 做法：位移量 ∝ (顶点高度 / 资产高度)^1.7，所以根部几乎不动、叶尖摆得最多；
//       相位含**世界位置**，因此每丛草不同步（否则整片草像一个人做操）。
//
// 约束：
//   - 位移在**模型局部 XZ** 上做（不反解 MODEL_MATRIX 的逆，避免不同 Blender/Godot 版本的
//     `inverse()` 支持差异）；实例有 yaw 时风向会各自不同，视觉上更像"乱风"，可接受。
//   - `cull_disabled`：草叶是单面网格，必须双面可见（与 ART01 的资产契约一致）。
//   - 不用 discard、不写 NORMAL_MAP：没有贴图。

render_mode cull_disabled, diffuse_burley;

uniform vec3 albedo_color : source_color = vec3(0.24, 0.42, 0.26);
uniform float roughness_value = 0.85;
uniform float wind_strength = 0.05;   // 叶尖最大水平位移（米）
uniform float wind_speed = 1.7;       // 摆动频率
uniform vec2 wind_dir = vec2(0.85, 0.53);
uniform float height_ref = 0.88;      // 资产高度（用来把 VERTEX.y 归一）
uniform float bend_power = 1.7;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(height_ref, 0.001), 0.0, 1.5);
	float k = pow(h, bend_power);

	float phase = TIME * wind_speed + origin.x * 0.8 + origin.z * 1.1;
	// 两个不同频率叠加：主体摆动 + 细碎抖动，避免机械的正弦
	float sway = sin(phase) * 0.68 + sin(phase * 2.7 + 1.3) * 0.32;

	vec2 dir = normalize(wind_dir);
	VERTEX.xz += dir * (sway * wind_strength * k);
}

void fragment() {
	ALBEDO = albedo_color;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
}
