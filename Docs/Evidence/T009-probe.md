# 台阶（MaxStepHeight）能力探针证据

- **日期**：2026-10-13
- **性质**：T009/T010 的前置技术风险探针（**不是**产品任务）
- **引擎**：Godot 4.7.2.stable.official.ed1daf0bf
- **探针脚本**：`Game/Reborn/tests/probe_step_height.gd`、`Game/Reborn/tests/debug_stepup.gd`
- **结论**：**能力已达成（ACHIEVED）**。6/6 用例通过，5 次运行结果完全一致。
  过程中定位并修复了**三个真实 bug**，最后一个的根因是"探测前移量不足"。

---

## 1. 为什么做这个探针

`Docs/Parameters.md` 要求两种物种的台阶能力不同：

| 物种 | MaxStepHeight | Godot 代码值 |
|---|---:|---:|
| Cat | 12 cm | 0.12 m |
| Mouse | 3 cm | 0.03 m |

而 **Godot 的 `CharacterBody3D` 没有 UE `MaxStepHeight` 的等价物**，`move_and_slide()` 不会自动上台阶。
这直接影响 T009（猫移动）、T010（鼠移动）与 M01 用例（"鼠能过洞、猫不能；猫可上高台"）。
**必须先验证，而不是先写移动代码。**

---

## 2. 最终实测结果

### 2.1 能力判定（6/6 通过）

```
CAPABILITY|Cat_3cm_should_pass|expected=true|actual=true|OK
CAPABILITY|Cat_12cm_should_pass|expected=true|actual=true|OK
CAPABILITY|Cat_20cm_should_block|expected=false|actual=false|OK
CAPABILITY|Mouse_3cm_should_pass|expected=true|actual=true|OK
CAPABILITY|Mouse_12cm_should_block|expected=false|actual=false|OK
CAPABILITY|Mouse_20cm_should_block|expected=false|actual=false|OK
```

**确定性验证**：连续 5 次运行，每次 6 条目、6 OK、0 MISMATCH，结果签名唯一。

### 2.2 详细数据

**阶段 A：裸 `move_and_slide()`（基线）**

| 物种 | 台阶 | 结果 | 抬升 |
|---|---:|---|---:|
| Cat | 3 cm | **通过** | 0.029 m |
| Cat | 12 cm | 挡住 | 0.000 |
| Cat | 20 cm | 挡住 | 0.000 |
| Mouse | 3 cm | 挡住 | 0.000 |
| Mouse | 12 cm | 挡住 | 0.000 |
| Mouse | 20 cm | 挡住 | 0.000 |

**阶段 B：自实现台阶抬升（最终实现）**

| 物种 | 台阶 | 结果 | 抬升 | 期望 | 判定 |
|---|---:|---|---:|---|---|
| Cat | 3 cm | 通过 | 0.031 | 通过 | ✅ |
| Cat | 12 cm | 通过 | **0.120** | 通过 | ✅ |
| Cat | 20 cm | 挡住 | 0.000 | 挡住 | ✅ |
| Mouse | 3 cm | 通过 | 0.029 | 通过 | ✅ |
| Mouse | 12 cm | 挡住 | 0.000 | 挡住 | ✅ |
| Mouse | 20 cm | 挡住 | 0.000 | 挡住 | ✅ |

**注意 `Cat 12cm` 的抬升恰好是 `0.120`** —— 与 `Parameters.md` 的阈值精确吻合，说明抬升量是真实几何量，不是凑出来的。

### 2.3 发现 1（重要，独立于实现）

**裸 `move_and_slide` 的行为取决于 胶囊半径 / 台阶高度 的比值**：

- Cat 半径 16 cm，台阶 3 cm → 比值 0.19 → **能滚上去**
- Cat 半径 16 cm，台阶 12 cm → 比值 0.75 → **滚不上去**
- Mouse 半径 6 cm，台阶 3 cm → 比值 0.50 → **滚不上去**

**含义**：如果依赖引擎默认行为，**鼠会被自己的 3 cm 阈值卡住**。这是 T010 的真实风险，也是必须自实现台阶抬升的直接原因。

---

## 3. 定位并修复的三个真实 bug

### 3.1 逐帧棘轮（已修复）

**现象**：早期实现对猫的 20 cm 台阶也能通过（超出 12 cm 阈值）。

**根因**：胶囊底部是半球，贴着台阶棱角时每帧只抬升一点点。逐帧追踪到的增益序列：

```
0.0921 → 0.0337 → 0.0225 → 0.0149 → 0.0103 → 0.0103 → 0.0065 → 0.0042 → 0.0027 → 0.0012
```

每帧增益都小于 0.12 阈值，**累积却爬上了 19.8 cm**。

**修正**：判据从"本帧增益"改为"**相对当前落脚面的总抬升**"。

> **教训**："每帧都在阈值内"**不等于**"总位移在阈值内"。任何逐帧累积的位移判断都必须以稳定基准为准。

### 3.2 基准值恒为 `INF`（已修复）

**现象**：标定输出 `min=-inf max=-inf`，基准从未被赋值。

**根因**：基准更新条件写成 `is_on_floor() and velocity.length() < 0.05`，但台阶分支里先清零 `velocity`，紧接着 `move_and_slide()` 又写回去，条件永不成立。

**修正**：改用单一稳定条件 `if body.is_on_floor()`。

### 3.3 探测前移量不足（已修复 —— 这是最终的关键根因）

**现象**：抬高量加到 0.29 也没用，猫始终上不了 12 cm 台阶。

**诊断方法**：写 `debug_stepup.gd` 在**真实被挡位置**逐条件打印。关键输出：

```
V|--- 诊断 @ x=-0.1544 y=0.2420 前缘=0.0056 ---
V| 1) 前方有障碍 = true
V| 2) 头顶抬 0.290 被挡 = false
V| 3) 抬起后前进被挡 = false
V| 4) 下落命中 = true  碰撞数=1
V|     #0 normal=(-0.868, 0.497, -0.000) n.y=0.497 可站立=false point=(0.0000, 0.1200, 0.0000)
V| 5) 落点 y=0.2820 总增益=0.0400 (上界 0.1220)
```

**根因**：碰撞点恒为 `(0, 0.12, 0)`（台阶顶棱），法线 `(-0.868, 0.497)`（与竖直夹角 **60°**，超出 Godot 默认 `floor_max_angle` 45° → **判定为墙面，不可站立**）。

而之所以永远撞在棱上，是因为**探测前移量只有一帧的位移（约 1.67 cm）**，
而胶囊半径是 16 cm —— **胶囊底心根本没有越过台阶竖直面（x=0）**，
所以无论抬多高，下探都撞在棱角上。

**修正**（两处，都必须做）：

1. **抬高量与阈值解耦**：探测抬高量取 `max_step * 2 + 0.05`，而不是 `max_step`。
   因为胶囊圆底贴棱时**底心比台阶顶还低**，要抬过台阶高度本身才能让平底越过棱角。
   放宽抬高量**不会**放过更高台阶——阈值把关靠最终的增益上界校验。
2. **前移量与帧位移解耦**：前移量取 `max(RADIUS_SAFE, 帧位移)`，`RADIUS_SAFE = 0.20 m`，
   确保底心越过台阶面。

**同时保留可站立面判据**：要求下落碰撞中至少有一个法线满足 `n.y ≥ cos(45°)`，
否则视为只有棱角接触，拒绝抬升。这一条是防止"踩在棱上"的关键。

### 3.4 已排除的原因（记录以省后来者时间）

| 假设 | 排除依据 |
|---|---|
| 容差太小 | 扫描 0.002 / 0.02 / 0.05 三档，结果完全相同 |
| 逐帧棘轮 | 已修（§3.1），修后 20 cm 正确被挡 |
| `_base_y` 基准失效 | 已修（§3.2） |
| 前置条件误判 | §3.3 逐条打印，五个条件全部通过 |
| 台阶几何摆错 | 复核：台阶中心 y=0.06、高 0.12 → 顶面确为 0.120；竖直面确在 x=0 |
| 抬高量不够 | 实测：抬到 0.29 仍失败 → 排除，真因是前移量 |

---

## 4. 最终算法（v6）

```gdscript
func _try_step_up(body: CharacterBody3D, motion: Vector3, max_step: float) -> bool:
    var flat := Vector3(motion.x, 0.0, motion.z)
    if flat.length() < 0.000001: return false

    var base: float = _base_y if is_finite(_base_y) else body.global_position.y
    var min_walkable_ny: float = cos(deg_to_rad(45.0))   # 与 floor_max_angle 一致

    if not body.test_move(body.global_transform, flat): return false   # 前方无障碍

    # ① 抬高量与阈值解耦
    var probe_raise: float = max_step * 2.0 + 0.05
    if body.test_move(body.global_transform, Vector3.UP * probe_raise): return false

    var raised := body.global_transform.translated(Vector3.UP * probe_raise)

    # ② 前移量与帧位移解耦，确保底心越过台阶面
    var probe_forward: float = RADIUS_SAFE + flat.length()
    var fwd_dir: Vector3 = flat.normalized()
    if body.test_move(raised, fwd_dir * probe_forward): return false   # 台阶过高

    var forward := raised.translated(fwd_dir * probe_forward)

    # ③ 下探并要求可站立面
    var params := PhysicsTestMotionParameters3D.new()
    params.from = forward
    params.motion = Vector3.DOWN * (probe_raise + 0.5)
    params.margin = 0.001
    params.max_collisions = 8
    var res := PhysicsTestMotionResult3D.new()
    if not PhysicsServer3D.body_test_motion(body.get_rid(), params, res): return false

    var walkable := false
    for i in res.get_collision_count():
        if res.get_collision_normal(i).y >= min_walkable_ny:
            walkable = true
            break
    if not walkable: return false

    # ④ 阈值把关在这里，不在抬高量
    var landed_y: float = forward.origin.y + res.get_travel().y
    var total_gain: float = landed_y - base
    if total_gain <= 0.0 or total_gain > max_step + STEP_TOLERANCE: return false

    body.global_position = Vector3(forward.origin.x, landed_y, forward.origin.z)
    return true
```

**设计要点**：
- **抬高量、前移量都只是"探测参数"，不承担阈值把关**；阈值只由 `total_gain` 决定。
  这样两者可以取足够宽裕的值而不影响正确性。
- **可站立面判据**（`n.y ≥ cos(floor_max_angle)`）是防"踩棱"的关键，
  与 Godot 自身的 `floor_max_angle` 语义一致。

---

## 5. 对后续任务的影响（更新）

| 任务 | 影响 |
|---|---|
| T009（猫移动） | ✅ 12 cm 台阶可行，实现可直接复用 |
| T010（鼠移动·通道尺度） | ✅ 3 cm 台阶可行；**注意不能依赖裸 `move_and_slide`**（鼠半径太小，连 3 cm 都滚不上） |
| M01 用例 | 具备执行条件 |
| M02 用例 | 台阶部分具备条件（斜坡未测） |

**建议**：把这个算法移到 `Game/Reborn/scripts/characters/step_climb.gd` 作为可复用组件，
并在 T009 中接入，而不是留在 `tests/` 里。

---

## 6. 未验证 / 限制

- 探针**只测了单一朝向（+X）与单一速度（1.0 m/s）**；未测斜向、奔跑速度、**下台阶**。
- 未测**台阶宽度**影响（本探针台阶深 6 m，是很宽的平台）。
- 未测**多级连续台阶**与**台阶+斜坡混合**。
- 未测**低顶下的台阶**（算法里有头顶空间检查，但未构造用例验证它真的生效）。
- 未做视觉验证（vision 服务 403）。
- `RADIUS_SAFE = 0.20` 是按当前最大胶囊（猫 0.16）取的；若将来有更大体型需重新标定。
- 探针在 `Game/Reborn/tests/` 下，是**开发工具**，不是产品代码。

---

## 7. 复现命令

```powershell
# 能力判定（6/6 断言）
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path 'E:\Reborn\Game\Reborn' `
  --script 'res://tests/probe_step_height.gd' --quit-after 30000

# 单案例逐条件诊断（改 debug_stepup.gd 顶部的 STEP / MAX_STEP / RADIUS 即可换用例）
& '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
  --script 'res://tests/debug_stepup.gd' --quit-after 8000
```

退出码 0。判定看 `CAPABILITY|` 行。

---

## 8. 状态

| 项 | 状态 |
|---|---|
| 裸 `move_and_slide` 行为已摸清 | **done**（含半径相关性的发现） |
| 三个 bug 定位与修复 | **done** |
| **12 cm / 3 cm 台阶抬升达成** | **ACHIEVED**（6/6，5 次一致） |
| T002 回归 | **18/18 通过**，未被探针改动破坏 |
| 组件化（移入 scripts/） | **待做**（T009） |
