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
// ART07 收尾轮 #2：vision 两轮判"草丛像平贴在地上的 2D 面片 / 贴纸、底部没有 AO"。
// 原因是这层材质只给**单色**（albedo 来自资产的 leaf 材质），叶片从根到梢没有明暗差，
// 草团在画面里就是一块均匀色斑。这里加两件**只用顶点高度/实例世界位置**的确定性处理：
//   ① 垂直接触 AO：根部压暗到 45%，叶片中部恢复原色 → 草团有"从地面长出来"的体积；
//   ② 逐实例微幅明暗差（世界位置哈希，无时间、无随机数）→ 远处草团不再像复制粘贴。
// 不动顶点风摆、不动任何几何/碰撞/资产。
varying float v_h_norm;
varying float v_inst_var;

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

	// 归一化的叶片高度（0=根，1=梢），片元里用它做垂直接触 AO
	v_h_norm = clamp(VERTEX.y / max(height_ref, 0.001), 0.0, 1.0);
	// 逐实例确定性明暗差：只用世界位置的哈希（没有时间、没有随机数），范围 ±0.09
	float hsh = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	v_inst_var = 0.91 + hsh * 0.18;
}

void fragment() {
	// 双面法线修正：草叶是单面网格 + cull_disabled，背面若不翻 NORMAL，从草丛内部看会发黑
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	// 垂直接触 AO：根部压暗（0.45×）→ 梢部恢复原色；叶片因此有"从地里长出来"的明暗过渡
	float contact_ao = mix(0.45, 1.0, smoothstep(0.0, 0.70, v_h_norm));
	ALBEDO = albedo_color * contact_ao * v_inst_var;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
}
