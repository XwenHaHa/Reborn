# ART08 证据：角色资产授权门与统一接入

状态：awaiting-review / blocked（现有接入通过；展板级角色资产未授权）
日期：2026-10-28

## 现有资产事实

- 猫：`res://assets/characters/cat/sm_cat_002.glb`，33 骨，Idle/Walk/Run，无 AttackCue；模型 8,376 tris，2 材质槽。
- 鼠：`res://assets/characters/mouse/sm_mouse_002.glb`，23 骨，Eat/Idle/Run/Walk；3,602 tris。
- 视觉网格不含 `CollisionShape3D`，玩法尺寸和碰撞由 `AnimalBody` 胶囊负责。
- 兔、狐狸、鸟没有可玩配置或获批资产，维持未来开放占位。

## 验证结果

| 命令 | 结果 |
|---|---|
| `run_art08_character_contract.gd --check-only` | exit 0 |
| `run_art08_character_contract.gd` | 15/15，0 failures，exit 0 |
| `run_art02_cat.gd` | 72/72，0 failures，exit 0；出现一条既有 `apply_config` 入树前 warning |
| `run_art03_mouse.gd` | 45/45，0 failures，exit 0 |
| `run_t008_species.gd` | 118/118，0 failures，exit 0 |

核心输出：

```text
ASSET|species=Cat|visual=res://assets/characters/cat/sm_cat_002.glb|animations=["Idle", "Run", "Walk"]|status=existing_fallback
ASSET|species=Mouse|visual=res://assets/characters/mouse/sm_mouse_002.glb|animations=["Eat", "Idle", "Run", "Walk"]|status=existing_fallback
ASSET|rabbit=blocked|fox=blocked|bird=blocked|reason=authorization_required
SUMMARY|checks=15|failures=0
RESULT|PASS
```

## 未通过/未验证

- 新的展板级猫鼠模型、猫扑击动作、鼠逃跑动作没有导入或视觉验证。
- 没有负责人明确授权，未下载、购买、登录或改写正式 `.tres`。
- 外部 vision 判读未运行，角色视觉仍为 `NOT-VERIFIED`；ART08 菜单截图已显示当前猫鼠与目标展板差异明显。

## 恢复入口

新增资产登记、ART08 角色契约测试、任务和本证据文档；没有改 `SpeciesConfig`、`AnimalBody`、`cat.tres`、`mouse.tres` 或正式模型。
