class_name BoardTokens
extends RefCounted
## ART09 展板视觉令牌。
##
## 依据：`Docs/Tasks/ART09_BOARD_PARITY.md` 阶段 A、基准图 `《轮生：森林生存游戏概念展板》.png`。
##
## 纪律：
##   1. **只放表现层常量**：颜色、字号、间距、尺寸、字体候选、关键图路径。
##      不读写游戏状态、不建节点、不碰物种数据。
##   2. 取值为展板采样（1536×1024）换算到设计分辨率 1280×720 的结果；
##      改这里等于改全站视觉，改完必须重跑 `res://tests/run_art09_tokens.gd`。
##   3. 尺寸契约是**布局断言的真源**：`run_art09_menu_contract.gd` 直接比对这些常量。

# ---------------------------------------------------------------------------
# 设计分辨率与三段栅格
# ---------------------------------------------------------------------------

const DESIGN := Vector2i(1280, 720)

## 左栏（品牌 + 按钮）宽度：0 … LEFT_WIDTH
const LEFT_WIDTH := 430.0
## 右栏（物种卡列）宽度 + 右侧留白：RAIL_LEFT = DESIGN.x - RAIL_WIDTH
const RAIL_WIDTH := 380.0
const RAIL_INNER_PAD := 22.0
## 中央主视觉可用区：LEFT_WIDTH … DESIGN.x - RAIL_WIDTH
const CENTER_PAD := 24.0

const CONTENT_MARGIN_LEFT := 72.0
const CONTENT_MARGIN_TOP := 64.0

# ---------------------------------------------------------------------------
# 颜色（展板采样）
# ---------------------------------------------------------------------------

const GOLD := Color("d89b3cff")
const GOLD_BRIGHT := Color("f2bd66ff")
const GOLD_DEEP := Color("8d5a1aff")
const TEXT := Color("f4f1e8ff")
const TEXT_WARM := Color("eddfb9ff")
const TEXT_DIM := Color("b7c0bcff")
const TEXT_FAINT := Color("8a938cff")
## 面板底色：展板右栏是压暗的深青灰玻璃
const PANEL := Color("07141ddd")
const PANEL_SELECTED := Color("16211ff2")
const PANEL_BORDER := Color("7b8b8f66")
const RAIL_BG := Color("08141af0")
const RAIL_BORDER := Color("d89b3c59")
const SCRIM := Color("03121340")
const BUTTON_DARK := Color("0c1415e0")

# ---------------------------------------------------------------------------
# 字号阶（展板：书法主标题 > 英文标题 > 副标题 > 正文 > 注释）
# ---------------------------------------------------------------------------

const FONT_TITLE := 104
const FONT_TITLE_LATIN := 20
const FONT_TAGLINE := 20
const FONT_TAGLINE_SMALL := 14
const FONT_BUTTON := 19
const FONT_CARD_NAME := 18
const FONT_CARD_TAG := 12
const FONT_CARD_NOTE := 11
const FONT_RAIL_HEAD := 16
const FONT_FOOTNOTE := 11

# ---------------------------------------------------------------------------
# 控件尺寸
# ---------------------------------------------------------------------------

const BUTTON_W := 300.0
const BUTTON_H := 52.0
const BUTTON_GAP := 8.0
const CARD_H := 84.0
const CARD_GAP := 10.0
## 卡片缩略图边长（展板是 64 px 方图）
const THUMB := 64.0
## 缩略图的超采样倍数：SubViewport 按 THUMB × 该值渲染，显示时再缩小
const THUMB_SUPERSAMPLE := 2
const TITLE_RULE_W := 240.0

## 物种选择页的大卡（展板第二块）与底部缩略图行
const SPECIES_CARD_X := 40.0
const SPECIES_CARD_Y := 96.0
const SPECIES_CARD_W := 430.0
const SPECIES_CARD_H := 468.0
const STRIP_SLOT := 64.0

## 四条状态：键/显示名/颜色。与 `hud.gd` 的四条 bar 同色同序（HUD 真源见 `hud.gd` VITALS 常量）。
## 这里只用于**菜单卡片**的初始值展示（出生即满），不参与任何生存计算。
const VITAL_ROWS := [
	{"key": &"health", "name": "生命", "color": Color(0.851, 0.325, 0.310)},
	{"key": &"hunger", "name": "饥饿", "color": Color(0.878, 0.651, 0.227)},
	{"key": &"thirst", "name": "水分", "color": Color(0.239, 0.608, 0.878)},
	{"key": &"stamina", "name": "体力", "color": Color(0.553, 0.761, 0.290)},
]

# ---------------------------------------------------------------------------
# 字体
# ---------------------------------------------------------------------------

## 书法主标题候选：中文名优先，找不到就退回系统默认（仍可读，只是没有笔锋）。
## 用 `SystemFont` 现取系统字体，**不把字体文件打进仓库**（商业字体不可再分发）。
const TITLE_FONT_CANDIDATES := [
	"华文行楷", "STXingkai", "华文新魏", "STXinwei",
	"楷体", "KaiTi", "FZKai-Z03", "SimSun",
]

static var _title_font: Font = null

## 书法标题字体（带进程内缓存；同一进程里只建一次）
static func title_font() -> Font:
	if _title_font != null:
		return _title_font
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(TITLE_FONT_CANDIDATES)
	sf.allow_system_fallback = true
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_title_font = sf
	return _title_font

# ---------------------------------------------------------------------------
# 关键图（来源规则见 `Docs/BoardArtPipeline.md`）
# ---------------------------------------------------------------------------

## 天空球：Poly Haven `mossy_forest` 2k HDR，CC0（苔石溪床 + 蕨类 + 斑驳阳光）
const ASSET_SKY_HDRI := "res://assets/environment/hdri/mossy_forest_2k.hdr"

# ---------------------------------------------------------------------------
# 度量（测试与布局共用，避免两处各写一套）
# ---------------------------------------------------------------------------

## 右栏左边界（像素）
static func rail_left(viewport_width: float) -> float:
	return viewport_width - RAIL_WIDTH

## 中央主视觉可用宽度
static func center_width(viewport_width: float) -> float:
	return rail_left(viewport_width) - LEFT_WIDTH - CENTER_PAD * 2.0

## 供断言读取的布局快照
static func layout_metrics(viewport: Vector2) -> Dictionary:
	return {
		"viewport": viewport,
		"left_width": LEFT_WIDTH,
		"rail_left": rail_left(viewport.x),
		"rail_width": RAIL_WIDTH,
		"center_width": center_width(viewport.x),
		"button": Vector2(BUTTON_W, BUTTON_H),
		"card": Vector2(RAIL_WIDTH - RAIL_INNER_PAD * 2.0, CARD_H),
		"thumb": THUMB,
	}
