extends RefCounted
## 单一时钟接缝（T043a）。
##
## 生产实现只读真实单调时钟 `Time.get_ticks_msec()`；测试可切到假时间，
## 用 `advance_ms()` 精确跨过 Toast 到期、存档节流窗口等**单调计时**判定。
##
## 约定：
## - 游戏世界时间仍是 `WorldDirector.world_time`，本类**不参与**世界时间推进。
## - 只有确实需要"墙钟单调计时"的模块可以调用 `now_ms()`（当前消费者：
##   `scripts/ui/hud.gd` 的 Toast 到期、`autoload/save_manager.gd` 的普通写节流）。
## - 生产代码里不允许出现"是否是测试"的分支；假时间只由测试/取证脚本显式开启。

static var _fake := false
static var _fake_ms := 0
## 上一次 `take_delta_ms()` 的读数；-1 = 需要重置基线（首帧/切模式/暂停恢复）。
static var _last_ms := -1


## 当前单调毫秒。生产 = 真实墙钟；测试 = 注入的假时间。
static func now_ms() -> int:
	return _fake_ms if _fake else Time.get_ticks_msec()


## 自上次调用以来的单调毫秒差。时钟切模式、回绕或首帧时返回 0（并重建基线），
## 生产侧不需要知道"是否测试"，只消费差值。
static func take_delta_ms() -> int:
	var now := now_ms()
	if _last_ms < 0 or now < _last_ms:
		_last_ms = now
		return 0
	var d := now - _last_ms
	_last_ms = now
	return d


## 重置差值基线（暂停恢复/场景重启时调用，避免把停摆时长补进世界时间）。
static func reset_delta() -> void:
	_last_ms = -1


## 测试注入：切换到假时间，从 `start_ms` 开始。
static func use_fake(start_ms: int = 0) -> void:
	_fake = true
	_fake_ms = start_ms
	_last_ms = -1


## 测试注入：推进假时间（仅在假时间模式下生效）。
static func advance_ms(ms: int) -> void:
	if _fake:
		_fake_ms += ms


## 测试结束：恢复真实墙钟。
static func use_real() -> void:
	_fake = false
	_fake_ms = 0
	_last_ms = -1
