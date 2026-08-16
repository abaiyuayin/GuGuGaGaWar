extends CanvasLayer
## 肉鸽模式专用 HUD 层：手牌展示 + 拖放部署 + 层数/波次提示
##
## 只在肉鸽模式下由 battle_root 实例化，常规战役/双人流程完全不会加载此场景，
## 因此对既有 HUD 逻辑零侵入。
## 战场引用由 battle_root 通过 setup() 注入，本层不主动向上查找父节点。

## 卡牌成功部署时发出。[param unit_id] 兵种 ID，[param world_pos] 部署的世界坐标
signal card_deployed(unit_id: String, world_pos: Vector2)

## 单张卡牌的最小尺寸
const CARD_SIZE: Vector2 = Vector2(132, 140)
## 可部署区域（世界坐标）—— 肉鸽模式地图正中央环绕水晶的区域（#7：原左侧半场）
## #7：放置区由左侧半场移到地图中央（环绕中央水晶），玩家从两翼防守合围的敌军
const DEPLOY_X_MIN: float = -180.0
const DEPLOY_X_MAX: float = 180.0
const DEPLOY_Y_MIN: float = -70.0
const DEPLOY_Y_MAX: float = 130.0
## 拖拽预览：落点合法时的着色
const COLOR_VALID: Color = Color(0.45, 1.0, 0.55, 0.9)
## 拖拽预览：落点非法时的着色
const COLOR_INVALID: Color = Color(1.0, 0.4, 0.4, 0.7)
## 各阶层卡牌的边框颜色（索引 0 未使用，阶层从 1 起）
const TIER_COLORS: Array[Color] = [
	Color(0.6, 0.6, 0.6, 1.0),
	Color(0.72, 0.72, 0.72, 1.0),
	Color(0.45, 0.85, 0.45, 1.0),
	Color(0.42, 0.66, 1.0, 1.0),
	Color(0.92, 0.62, 1.0, 1.0),
]
## 卡牌等级徽章配色（索引 0 未用，等级从 1 起）：1 银 / 2 蓝 / 3 金（#211 圆框）
const CARD_LEVEL_BADGE_COLORS: Array[Color] = [
	Color(0.6, 0.6, 0.6, 1.0),
	Color(0.80, 0.80, 0.76, 1.0),
	Color(0.48, 0.70, 1.0, 1.0),
	Color(1.0, 0.82, 0.30, 1.0),
]
## 提示语恢复默认文本的延迟（秒）
const HINT_RESET_DELAY: float = 1.5
## 默认提示文本
const HINT_DEFAULT: String = "拖动卡牌到左半场部署兵种"
## 每张卡牌默认一次部署的兵种数量
const UNITS_PER_CARD: int = 3
## 同一张卡牌多次出兵的落点偏移（避免完全重叠）
const DEPLOY_OFFSETS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(18.0, 10.0),
	Vector2(-18.0, 10.0),
]
## 己方半场提示区域的填充色
const DEPLOY_ZONE_COLOR: Color = Color(0.2, 0.55, 0.9, 0.18)
## 己方半场提示区域的边框色
const DEPLOY_ZONE_BORDER_COLOR: Color = Color(0.35, 0.78, 1.0, 0.45)
## 顶部波次标签字体色（暖金，区别于默认纯白，避免像调试残留文本）
const WAVE_LABEL_COLOR: Color = Color(1.0, 0.92, 0.74, 1.0)
## 顶部提示标签默认字体色（柔灰白），非法拖放时由 COLOR_INVALID 覆盖
const HINT_DEFAULT_COLOR: Color = Color(0.82, 0.84, 0.86, 0.92)
## 军令生效等正向反馈的提示色（暖金）
const HINT_HIGHLIGHT_COLOR: Color = Color(1.0, 0.86, 0.48, 1.0)
## 军令栏整体宽度（像素）
const ORDER_BAR_WIDTH: float = 188.0
## 军令栏距屏幕右 / 下边缘的留白
const ORDER_BAR_MARGIN: float = 20.0
## 军令栏纵向可用高度（超出后由 ScrollContainer 滚动）
const ORDER_BAR_HEIGHT: float = 300.0
## 各稀有度军令按钮的边框色（索引 0 未使用，稀有度从 1 起）
const ORDER_RARITY_COLORS: Array[Color] = [
	Color(0.6, 0.6, 0.6, 1.0),
	Color(0.78, 0.78, 0.74, 1.0),
	Color(0.52, 0.86, 0.58, 1.0),
	Color(0.48, 0.70, 1.0, 1.0),
	Color(0.95, 0.66, 1.0, 1.0),
]

## ── 英雄技能卡（#8，挂在手牌区左侧）──────────────────────────────
## 单张技能卡尺寸（比兵种卡窄，区分「技能」与「兵种」两类卡）
const SKILL_CARD_SIZE: Vector2 = Vector2(96, 140)
## 技能栏整体相对屏幕中心底边的偏移（位于 CardHand 左侧，二者水平相接）
const SKILL_BAR_OFFSET_LEFT: float = -462.0
const SKILL_BAR_OFFSET_RIGHT: float = -232.0
const SKILL_BAR_OFFSET_TOP: float = -164.0
const SKILL_BAR_OFFSET_BOTTOM: float = -20.0
## 技能卡边框色（暖金，与英雄主题一致）
const SKILL_CARD_BORDER: Color = Color(0.95, 0.78, 0.30, 1.0)

## ── 水晶血条（#209，肉鸽专属）────────────────────────────────
## 血条整体尺寸（像素）
const CRYSTAL_BAR_SIZE: Vector2 = Vector2(240.0, 26.0)
## 血条相对屏幕左上角的边距（像素）
const CRYSTAL_BAR_MARGIN: Vector2 = Vector2(20.0, 44.0)
## 血条填充色（红色，与场上水晶方块同色系）
const CRYSTAL_BAR_FILL: Color = Color(0.88, 0.20, 0.20, 1.0)
## 血条底色
const CRYSTAL_BAR_BG: Color = Color(0.10, 0.09, 0.08, 0.80)
## 血量低于此比例时血条闪烁提示危险
const CRYSTAL_DANGER_RATIO: float = 0.3

@onready var wave_label: Label = $WaveLabel
@onready var hint_label: Label = $HintLabel
@onready var gold_label: Label = $GoldLabel
@onready var card_hand: HBoxContainer = $CardHand
@onready var drag_preview: Panel = $DragPreview

## 战场节点引用，用于把鼠标屏幕坐标换算成世界坐标（由 battle_root 注入）
var _battlefield: Node2D = null
## 当前正在拖拽的手牌索引，-1 表示没有拖拽
var _drag_index: int = -1
## 拖拽预览中的兵种图标
var _preview_icon: TextureRect = null
## 己方半场高亮提示框
var _deploy_zone: Panel = null
## 军令袋整体面板（无军令时隐藏）
var _order_panel: PanelContainer = null
## 军令袋按钮列表容器（代码构建，位于屏幕右下）
var _order_list: VBoxContainer = null
## 军令袋标题（显示当前持有数量）
var _order_title: Label = null

## 英雄技能栏容器（#8，位于 CardHand 左侧）
var _skill_hand: HBoxContainer = null
## skill_id -> 技能卡 PanelContainer
var _skill_cards: Dictionary = {}
## skill_id -> 卡上 CD / 状态 Label
var _skill_cd_labels: Dictionary = {}
## skill_id -> 技能定义 Dictionary（建卡时缓存，刷新时复用）
var _skill_defs: Dictionary = {}

## 水晶血条控件（#209）
var _crystal_bar: ProgressBar = null
## 水晶血条上的读数文本
var _crystal_text: Label = null

func _ready() -> void:
	_build_drag_preview()
	RoguelikeManager.hand_changed.connect(_on_hand_changed)
	hint_label.text = HINT_DEFAULT
	_style_top_labels()
	gold_label.text = "金币 %d" % RoguelikeManager.get_gold()
	RoguelikeManager.gold_changed.connect(_on_gold_changed)
	_build_order_bar()
	RoguelikeManager.orders_changed.connect(_on_orders_changed)
	_refresh_orders()
	_refresh_hand()
	## #8：英雄技能栏（位于手牌区左侧）
	_build_skill_bar()
	## #27：肉鸽控制台入口按钮
	_build_debug_button()

func _exit_tree() -> void:
	## 场景卸载时断开单例信号，避免残留连接指向已释放节点
	if RoguelikeManager.hand_changed.is_connected(_on_hand_changed):
		RoguelikeManager.hand_changed.disconnect(_on_hand_changed)
	if RoguelikeManager.gold_changed.is_connected(_on_gold_changed):
		RoguelikeManager.gold_changed.disconnect(_on_gold_changed)
	if RoguelikeManager.orders_changed.is_connected(_on_orders_changed):
		RoguelikeManager.orders_changed.disconnect(_on_orders_changed)
	## #8：断开英雄技能相关信号（CD 变化 / 场上单位增减刷新英雄在场状态）
	if HeroSkillManager.skill_cd_changed.is_connected(_on_skill_cd_changed):
		HeroSkillManager.skill_cd_changed.disconnect(_on_skill_cd_changed)
	if BattleManager.unit_spawned.is_connected(_on_field_units_changed):
		BattleManager.unit_spawned.disconnect(_on_field_units_changed)
	if BattleManager.unit_removed.is_connected(_on_field_units_changed):
		BattleManager.unit_removed.disconnect(_on_field_units_changed)
	## 断开战场水晶耐久信号（#209）
	if _battlefield != null and is_instance_valid(_battlefield):
		if _battlefield.base_hp_changed.is_connected(_on_crystal_hp_changed):
			_battlefield.base_hp_changed.disconnect(_on_crystal_hp_changed)

## #27：构建肉鸽控制台入口按钮（左上角，避开顶部波次标签与右侧军令栏）
func _build_debug_button() -> void:
	var btn := Button.new()
	btn.text = "控制台"
	btn.position = Vector2(20, 20)
	btn.size = Vector2(80, 36)
	btn.add_theme_font_size_override("font_size", 14)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(_on_debug_panel_requested)
	add_child(btn)

## #27：弹出肉鸽专属控制台面板
func _on_debug_panel_requested() -> void:
	var panel_script := preload("res://scenes/ui/roguelike_debug_panel.gd")
	var panel: Control = panel_script.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)

## 为顶部波次/提示标签套上深色半透明底框，并改用暖色字体，
## 避免它们以纯白无底的形式悬浮在屏幕顶部中央、看起来像调试残留文本（B-5）
func _style_top_labels() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06, 0.72)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	bg.content_margin_left = 14.0
	bg.content_margin_right = 14.0
	bg.content_margin_top = 3.0
	bg.content_margin_bottom = 3.0
	if wave_label != null:
		wave_label.add_theme_stylebox_override("normal", bg)
		wave_label.add_theme_color_override("font_color", WAVE_LABEL_COLOR)
		wave_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
		wave_label.add_theme_constant_override("outline_size", 2)
	if hint_label != null:
		hint_label.add_theme_stylebox_override("normal", bg)
		hint_label.add_theme_color_override("font_color", HINT_DEFAULT_COLOR)
		hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
		hint_label.add_theme_constant_override("outline_size", 2)

## 注入战场引用（坐标换算依赖它，未注入时拖放一律判定为非法）
func setup(battlefield: Node2D) -> void:
	_battlefield = battlefield
	_create_deploy_zone()
	_build_crystal_bar()

## 构建左上角的水晶耐久条（#209）
## 战场的 base_hp_changed 在 battlefield._ready 里就已发过一次（早于本 HUD 接入），
## 因此这里除了连信号，还必须主动拉一次当前值做初始化。
func _build_crystal_bar() -> void:
	if _battlefield == null:
		return
	## 非水晶模式（普通战役/双人）不显示本血条
	if not bool(_battlefield.get("is_crystal_mode")):
		return
	var bar := ProgressBar.new()
	bar.name = "CrystalBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bar.offset_left = CRYSTAL_BAR_MARGIN.x
	bar.offset_top = CRYSTAL_BAR_MARGIN.y
	bar.offset_right = CRYSTAL_BAR_MARGIN.x + CRYSTAL_BAR_SIZE.x
	bar.offset_bottom = CRYSTAL_BAR_MARGIN.y + CRYSTAL_BAR_SIZE.y
	var bg := StyleBoxFlat.new()
	bg.bg_color = CRYSTAL_BAR_BG
	bg.set_corner_radius_all(5)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.55, 0.20, 0.18, 0.85)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = CRYSTAL_BAR_FILL
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	_crystal_bar = bar

	var txt := Label.new()
	txt.name = "CrystalText"
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.set_anchors_preset(Control.PRESET_FULL_RECT)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_font_size_override("font_size", 14)
	txt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.92, 1.0))
	txt.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	txt.add_theme_constant_override("outline_size", 3)
	bar.add_child(txt)
	_crystal_text = txt

	if not _battlefield.base_hp_changed.is_connected(_on_crystal_hp_changed):
		_battlefield.base_hp_changed.connect(_on_crystal_hp_changed)
	## 主动同步一次当前耐久（错过了 battlefield._ready 里的首次广播）
	_on_crystal_hp_changed(0, _battlefield.get_base_hp(0), _battlefield.get_base_max_hp())

## 水晶耐久变化回调（只关心玩家侧 team=0）
## team: 阵营编号；hp: 当前耐久；max_hp: 耐久上限
func _on_crystal_hp_changed(team: int, hp: int, max_hp: int) -> void:
	if team != 0 or _crystal_bar == null:
		return
	_crystal_bar.max_value = float(maxi(max_hp, 1))
	_crystal_bar.value = float(maxi(hp, 0))
	if _crystal_text != null:
		_crystal_text.text = "水晶  %d / %d" % [maxi(hp, 0), maxi(max_hp, 1)]
	## 低血量时血条转为高亮橙红，提醒玩家回防
	var ratio: float = float(hp) / float(maxi(max_hp, 1))
	var fill := _crystal_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = Color(1.0, 0.45, 0.15, 1.0) if ratio <= CRYSTAL_DANGER_RATIO else CRYSTAL_BAR_FILL

## 更新顶部的层数 / 波次文本
func set_wave_text(text: String) -> void:
	wave_label.text = text

## 金币变化时刷新顶部金币读数
func _on_gold_changed(g: int) -> void:
	if gold_label != null:
		gold_label.text = "金币 %d" % g

## 手牌变化回调（打出卡牌、波次补牌都会触发）
func _on_hand_changed(_hand_ids: Array[String]) -> void:
	_refresh_hand()

## 重建全部手牌卡面
func _refresh_hand() -> void:
	for child in card_hand.get_children():
		child.queue_free()
	var hand_res: Array[UnitResource] = RoguelikeManager.get_hand_resources()
	for i in range(hand_res.size()):
		card_hand.add_child(_create_card(hand_res[i], i))

## 创建一张卡牌控件
func _create_card(res: UnitResource, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s\nHP:%d 护甲:%d 攻:%d\n射程:%.1f 速度:%.1f" % [
		res.get_description(), res.max_hp, res.armor_value,
		res.damage, res.attack_range, res.move_speed
	]
	card.add_theme_stylebox_override("panel", _make_card_style(res.tier))
	card.gui_input.connect(_on_card_gui_input.bind(index))
	## #211 卡牌等级圆框徽章：左上角显示当前召唤等级（1~CARD_LEVEL_MAX）
	var level: int = RoguelikeManager.get_card_level(res.unit_id)
	card.add_child(_create_level_badge(level))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_unit_icon(res.unit_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = res.get_display_name()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = "T%d  HP%d  ATK%d" % [res.tier, res.max_hp, res.damage]
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.7, 1.0))
	tier_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tier_lbl)

	return card

## 在卡牌左上角生成圆形等级徽章（#211）：直径 26px，显示卡牌召唤等级 1~CARD_LEVEL_MAX。
## 颜色按等级变化（银/蓝/金），事件穿透（mouse_filter=IGNORE）不阻碍拖拽手牌。
func _create_level_badge(level: int) -> Panel:
	var badge := Panel.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(4.0, 4.0)
	badge.size = Vector2(26.0, 26.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.07, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = CARD_LEVEL_BADGE_COLORS[clampi(level, 1, CARD_LEVEL_BADGE_COLORS.size() - 1)]
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_left = 13
	style.corner_radius_bottom_right = 13
	badge.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = str(level)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge

## 按阶层生成卡面样式
func _make_card_style(tier: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.11, 0.09, 0.94)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = TIER_COLORS[clampi(tier, 1, TIER_COLORS.size() - 1)]
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

## 构建跟随鼠标的拖拽预览内容
func _build_drag_preview() -> void:
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_icon = TextureRect.new()
	_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.add_child(_preview_icon)

## 卡牌输入回调：左键按下即开始拖拽
func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_drag(index)
		get_viewport().set_input_as_handled()

## 开始拖拽指定手牌
func _begin_drag(index: int) -> void:
	if index < 0 or index >= RoguelikeManager.hand.size():
		return
	_drag_index = index
	var res := UnitDatabase.get_unit(RoguelikeManager.hand[index]) as UnitResource
	if res != null and _preview_icon != null:
		_preview_icon.texture = _load_unit_icon(res.unit_id)
	drag_preview.visible = true
	if _deploy_zone != null and is_instance_valid(_deploy_zone):
		_deploy_zone.visible = true
	_update_drag_preview()

## 全局输入：拖拽期间跟随鼠标，松开左键结算落点
func _input(event: InputEvent) -> void:
	if _drag_index < 0:
		return
	if event is InputEventMouseMotion:
		_update_drag_preview()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag()
		get_viewport().set_input_as_handled()

## 刷新拖拽预览的位置与合法性着色
func _update_drag_preview() -> void:
	var mouse_pos: Vector2 = drag_preview.get_viewport().get_mouse_position()
	drag_preview.position = mouse_pos - drag_preview.size * 0.5
	drag_preview.modulate = COLOR_VALID if _is_valid_drop() else COLOR_INVALID

## 结算一次拖放
func _finish_drag() -> void:
	var index: int = _drag_index
	_drag_index = -1
	drag_preview.visible = false
	if _deploy_zone != null and is_instance_valid(_deploy_zone):
		_deploy_zone.visible = false
	if index < 0:
		return
	if not _is_valid_drop():
		_flash_hint("只能部署在中央区域（环绕水晶）")
		return
	var world_pos: Vector2 = _get_drop_world_pos()
	## play_card 内部会发 hand_changed，卡面由 _refresh_hand 自动重建
	var res: UnitResource = RoguelikeManager.play_card(index)
	if res == null:
		return
	## 单卡召唤数量由兵种数据决定（高级兵 2 / 普通 3）并经休息升级翻倍，受肉鸽全场部署上限约束
	var deploy_count: int = RoguelikeManager.get_deploy_count(res.unit_id)
	for i in range(deploy_count):
		if BattleManager.player_units.size() >= Constants.ROGUELIKE_MAX_UNITS_PER_SIDE:
			break
		var spawn_pos: Vector2 = world_pos + _deploy_offset(i)
		spawn_pos.x = clampf(spawn_pos.x, Constants.FIELD_X_MIN, Constants.FIELD_X_MAX)
		spawn_pos.y = clampf(spawn_pos.y, Constants.FIELD_Y_MIN, Constants.FIELD_Y_MAX)
		BattleManager.spawn_unit(res, 0, spawn_pos)
	AudioManager.play_ui_click()
	card_deployed.emit(res.unit_id, world_pos)

## 第 index 个出兵点的落点偏移：前 3 枚使用 DEPLOY_OFFSETS 固定值；
## 超过 3 枚（训练强化 +2 / 文物军令加成）按网格公式生成，避免越界（原 DEPLOY_OFFSETS[i] 在
## deploy_count>=4 时抛 Out of bounds）且与前三枚及彼此不重叠。
func _deploy_offset(index: int) -> Vector2:
	if index < DEPLOY_OFFSETS.size():
		return DEPLOY_OFFSETS[index]
	var ring: int = index - DEPLOY_OFFSETS.size()
	var col: int = ring % 3
	var row: int = ring / 3
	return Vector2((col - 1) * 20.0, 10.0 + (row + 1) * 16.0)

## 创建并缓存己方半场高亮提示框
func _create_deploy_zone() -> void:
	if _battlefield == null or not is_instance_valid(_battlefield):
		return
	var unit_container: Node = _battlefield.get_node_or_null("UnitContainer")
	_deploy_zone = Panel.new()
	_deploy_zone.position = Vector2(DEPLOY_X_MIN, DEPLOY_Y_MIN)
	_deploy_zone.size = Vector2(DEPLOY_X_MAX - DEPLOY_X_MIN, DEPLOY_Y_MAX - DEPLOY_Y_MIN)
	_deploy_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = DEPLOY_ZONE_COLOR
	style.border_color = DEPLOY_ZONE_BORDER_COLOR
	style.set_border_width_all(2)
	_deploy_zone.add_theme_stylebox_override("panel", style)
	_battlefield.add_child(_deploy_zone)
	if unit_container != null:
		_battlefield.move_child(_deploy_zone, unit_container.get_index())
	_deploy_zone.visible = false

## 取当前鼠标对应的战场世界坐标，战场未注入时返回 Vector2.INF
func _get_drop_world_pos() -> Vector2:
	if _battlefield == null or not is_instance_valid(_battlefield):
		return Vector2.INF
	return _battlefield.get_global_mouse_position()

## 判断当前鼠标落点是否位于己方可部署区域
func _is_valid_drop() -> bool:
	var pos: Vector2 = _get_drop_world_pos()
	if not pos.is_finite():
		return false
	return pos.x >= DEPLOY_X_MIN and pos.x <= DEPLOY_X_MAX \
		and pos.y >= DEPLOY_Y_MIN and pos.y <= DEPLOY_Y_MAX

## 临时显示一条红色报错提示语，稍后恢复默认文本
func _flash_hint(text: String) -> void:
	_flash_hint_colored(text, COLOR_INVALID)

## 战斗层（roguelike_director）调用的正向反馈入口，例如军令生效提示
func show_hint(text: String) -> void:
	_flash_hint_colored(text, HINT_HIGHLIGHT_COLOR)

## 与 show_hint 相同，但提示停留 [duration] 秒后恢复（用于英雄特长等需较长时间展示的提示，#6）
func show_hint_duration(text: String, duration: float) -> void:
	_flash_hint_colored(text, HINT_HIGHLIGHT_COLOR, duration)

## 临时替换提示条文本与字色，[duration] 秒后恢复默认（默认 HINT_RESET_DELAY）
func _flash_hint_colored(text: String, color: Color, duration: float = HINT_RESET_DELAY) -> void:
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", color)
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(hint_label):
			return
		## 期间若又刷了新提示，则不覆盖后来的那条
		if hint_label.text != text:
			return
		hint_label.text = HINT_DEFAULT
		hint_label.add_theme_color_override("font_color", HINT_DEFAULT_COLOR)
	)

# ---------- 军令袋（战斗中一次性打出） ----------

## 构建屏幕右下角的军令袋容器（标题 + 可滚动按钮列表）
## 军令只在战斗内可打出，因此这套 UI 只存在于本 HUD，不进地图 hub。
func _build_order_bar() -> void:
	var panel := PanelContainer.new()
	panel.name = "OrderBar"
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -(ORDER_BAR_WIDTH + ORDER_BAR_MARGIN)
	panel.offset_right = -ORDER_BAR_MARGIN
	panel.offset_top = -(ORDER_BAR_HEIGHT + ORDER_BAR_MARGIN)
	panel.offset_bottom = -ORDER_BAR_MARGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _make_order_panel_style())
	add_child(panel)
	_order_panel = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_order_title = Label.new()
	_order_title.text = "军令袋"
	_order_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_title.add_theme_font_size_override("font_size", 15)
	_order_title.add_theme_color_override("font_color", HINT_HIGHLIGHT_COLOR)
	_order_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_order_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_order_list = VBoxContainer.new()
	_order_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_order_list)

## 军令袋底板样式（深色半透明，与顶部标签同一套视觉语言）
func _make_order_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.78)
	style.border_color = Color(0.62, 0.50, 0.28, 0.75)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 8.0
	return style

## 持有军令变化时重建按钮列表
func _on_orders_changed(_order_ids: Array[String]) -> void:
	_refresh_orders()

## 重建军令按钮列表；无军令时整块面板隐藏，避免空框占屏
func _refresh_orders() -> void:
	if _order_list == null or not is_instance_valid(_order_list):
		return
	for child in _order_list.get_children():
		child.queue_free()
	var ids: Array[String] = RoguelikeManager.owned_orders
	if _order_panel != null and is_instance_valid(_order_panel):
		_order_panel.visible = not ids.is_empty()
	if _order_title != null:
		_order_title.text = "军令袋 (%d)" % ids.size()
	for i in range(ids.size()):
		var od := ItemDatabase.get_order(ids[i])
		if od == null:
			continue
		_order_list.add_child(_create_order_button(od, ids[i]))

## 创建一枚军令按钮（点击即打出，一次性消耗）
func _create_order_button(od: MilitaryOrderData, order_id: String) -> Button:
	var btn := Button.new()
	btn.text = od.display_name
	btn.tooltip_text = "%s\n\n%s" % [od.display_name, od.description]
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", ORDER_RARITY_COLORS[clampi(od.rarity, 1, ORDER_RARITY_COLORS.size() - 1)])
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_order_pressed.bind(order_id))
	return btn

## 打出一张军令：一次性效果由 roguelike_director 监听 order_played 执行，
## 持续型加成由 RunModifiers 自动读取，本处只负责触发与音效反馈。
func _on_order_pressed(order_id: String) -> void:
	var od := ItemDatabase.get_order(order_id)
	if od == null:
		return
	## 先打通用提示，再执行 —— 一次性军令的具体反馈会由 director 覆盖掉这一条
	show_hint("已下达：%s" % od.display_name)
	if not RoguelikeManager.play_order(order_id):
		_flash_hint("军令已不在袋中")
		return
	AudioManager.play_ui_click()

# ---------- 英雄技能栏（#8，位于手牌区左侧） ----------

## 构建英雄技能栏：按当前英雄的技能定义建独立卡（每技能一张），并连接 CD / 在场状态刷新信号
func _build_skill_bar() -> void:
	_skill_hand = HBoxContainer.new()
	_skill_hand.name = "SkillHand"
	_skill_hand.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skill_hand.offset_left = SKILL_BAR_OFFSET_LEFT
	_skill_hand.offset_right = SKILL_BAR_OFFSET_RIGHT
	_skill_hand.offset_top = SKILL_BAR_OFFSET_TOP
	_skill_hand.offset_bottom = SKILL_BAR_OFFSET_BOTTOM
	_skill_hand.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skill_hand.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skill_hand.add_theme_constant_override("separation", 14)
	_skill_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_skill_hand)

	var skills := HeroSkillManager.get_skills_for_hero(RoguelikeManager.selected_hero)
	for def in skills:
		_build_skill_card(def)

	if not HeroSkillManager.skill_cd_changed.is_connected(_on_skill_cd_changed):
		HeroSkillManager.skill_cd_changed.connect(_on_skill_cd_changed)
	## 英雄上 / 下场会改变登场技能的可用性，故监听单位增减刷新卡面
	if not BattleManager.unit_spawned.is_connected(_on_field_units_changed):
		BattleManager.unit_spawned.connect(_on_field_units_changed)
	if not BattleManager.unit_removed.is_connected(_on_field_units_changed):
		BattleManager.unit_removed.connect(_on_field_units_changed)

## 构建单张技能卡
func _build_skill_card(def: Dictionary) -> void:
	var skill_id: String = def["id"]
	_skill_defs[skill_id] = def

	var card := PanelContainer.new()
	card.name = "Skill_" + skill_id
	card.custom_minimum_size = SKILL_CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s\n%s" % [def["name"], def["desc"]]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.06, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = SKILL_CARD_BORDER
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", style)
	card.gui_input.connect(_on_skill_card_gui_input.bind(skill_id))
	_skill_hand.add_child(card)
	_skill_cards[skill_id] = card

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	## 「技」字角标，快速区分技能卡与兵种卡
	var tag := Label.new()
	tag.text = "技"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", SKILL_CARD_BORDER)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tag)

	var name_lbl := Label.new()
	name_lbl.text = def["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var type_lbl := Label.new()
	type_lbl.text = "登场" if def["type"] == "on_field" else "非登场"
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.70, 1.0))
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(type_lbl)

	var cd_lbl := Label.new()
	cd_lbl.text = "就绪"
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_lbl.add_theme_font_size_override("font_size", 12)
	cd_lbl.add_theme_color_override("font_color", HINT_HIGHLIGHT_COLOR)
	cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cd_lbl)
	_skill_cd_labels[skill_id] = cd_lbl

	_update_skill_card_visual(skill_id)

## 刷新单张技能卡的状态显示（CD / 需英雄 / 就绪）与灰显
func _update_skill_card_visual(skill_id: String) -> void:
	var card: PanelContainer = _skill_cards.get(skill_id)
	if card == null:
		return
	var def: Dictionary = _skill_defs.get(skill_id, {})
	var cd: int = HeroSkillManager.get_cd(skill_id)
	var cd_lbl: Label = _skill_cd_labels.get(skill_id)
	var needs_hero: bool = def.get("type", "") == "on_field" and not HeroSkillManager.hero_on_field()
	var ready: bool = cd <= 0 and not needs_hero
	var cd_text: String = "就绪"
	if cd > 0:
		cd_text = "CD %d" % cd
	elif needs_hero:
		cd_text = "需英雄"
	if cd_lbl != null:
		cd_lbl.text = cd_text
		cd_lbl.add_theme_color_override("font_color", HINT_HIGHLIGHT_COLOR if ready else Color(0.7, 0.7, 0.7, 1.0))
	card.modulate = Color(1.0, 1.0, 1.0, 1.0) if ready else Color(0.5, 0.5, 0.5, 1.0)

## 刷新全部技能卡状态
func _refresh_skill_visuals() -> void:
	for sid in _skill_defs.keys():
		_update_skill_card_visual(sid)

## CD 变化回调（来自 HeroSkillManager）
func _on_skill_cd_changed(skill_id: String, _cd: int) -> void:
	_update_skill_card_visual(skill_id)

## 场上单位增减（英雄上下场 / 兵种进出）时刷新技能卡（仅登场技能受英雄在场影响，但全刷成本低）
func _on_field_units_changed(_unit: Node2D, _player_id: int = 0) -> void:
	_refresh_skill_visuals()

## 点击技能卡 → 放大 + 确认弹窗
func _on_skill_card_gui_input(event: InputEvent, skill_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_open_skill_popup(skill_id)
		get_viewport().set_input_as_handled()

## 弹出技能详情 + 确认使用弹窗
func _open_skill_popup(skill_id: String) -> void:
	var def: Dictionary = _skill_defs.get(skill_id, {})
	if def.is_empty():
		return
	var popup := Control.new()
	popup.name = "SkillPopup"
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(popup)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_child(dim)
	## 点击空白处关闭
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			popup.queue_free()
	)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360.0, 280.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = def["name"]
	title.add_theme_font_size_override("font_size", 19)
	vbox.add_child(title)

	var type_txt: String = "登场技能（需爱弥斯在场）" if def["type"] == "on_field" else "非登场技能（无需英雄在场）"
	var type_lbl := Label.new()
	type_lbl.text = type_txt
	type_lbl.add_theme_color_override("font_color", SKILL_CARD_BORDER)
	vbox.add_child(type_lbl)

	var desc := Label.new()
	desc.text = def["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var cd_max: int = HeroSkillManager.get_cd_max(skill_id)
	var cd_lbl := Label.new()
	cd_lbl.text = "冷却上限：%d 波（每刷新一波敌军自动恢复 1 点）" % cd_max
	vbox.add_child(cd_lbl)

	var hint_lbl := Label.new()
	hint_lbl.name = "Hint"
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)
	var btn_use := Button.new()
	btn_use.text = "使用"
	btn_use.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_close := Button.new()
	btn_close.text = "关闭"
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_use)
	btn_row.add_child(btn_close)

	_update_popup_button_state(btn_use, skill_id, hint_lbl)
	btn_use.pressed.connect(func() -> void: _on_skill_use_confirmed(skill_id, popup))
	btn_close.pressed.connect(func() -> void: popup.queue_free())

## 根据当前可用性设置弹窗「使用」按钮状态与提示
func _update_popup_button_state(btn_use: Button, skill_id: String, hint_lbl: Label) -> void:
	if HeroSkillManager.get_cd(skill_id) > 0:
		btn_use.disabled = true
		hint_lbl.text = "冷却中（剩余 %d 波）" % HeroSkillManager.get_cd(skill_id)
	elif _skill_defs.get(skill_id, {}).get("type", "") == "on_field" and not HeroSkillManager.hero_on_field():
		btn_use.disabled = true
		hint_lbl.text = "需先派出英雄（爱弥斯）上场"
	else:
		btn_use.disabled = false
		hint_lbl.text = "点击「使用」立即释放该技能"

## 确认释放技能：调用管理器，失败给原因提示
func _on_skill_use_confirmed(skill_id: String, popup: Control) -> void:
	var def: Dictionary = _skill_defs.get(skill_id, {})
	if HeroSkillManager.use_skill(skill_id):
		show_hint("释放：%s" % def.get("name", ""))
		AudioManager.play_ui_click()
	else:
		var reason: String = "技能未就绪"
		if HeroSkillManager.get_cd(skill_id) > 0:
			reason = "冷却中（剩余 %d 波）" % HeroSkillManager.get_cd(skill_id)
		elif def.get("type", "") == "on_field" and not HeroSkillManager.hero_on_field():
			reason = "需先派出英雄（爱弥斯）上场"
		_flash_hint(reason)
	popup.queue_free()
	_refresh_skill_visuals()

## 加载兵种行走动画首帧作为卡面图标（优先 walk > move > attack）
func _load_unit_icon(unit_id: String) -> Texture2D:
	for anim_name in ["walk", "move", "attack"]:
		var path := "res://resources/units/%s/%s_frames.tres" % [unit_id, anim_name]
		if not ResourceLoader.exists(path):
			continue
		var frames := load(path) as SpriteFrames
		if frames != null and frames.get_frame_count(anim_name) > 0:
			return frames.get_frame_texture(anim_name, 0)
	return null
