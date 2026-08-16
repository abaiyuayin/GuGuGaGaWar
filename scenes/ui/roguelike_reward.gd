extends CanvasLayer
class_name RoguelikeReward
## 肉鸽模式单层通关奖励界面（三选一）
##
## 全代码结构：根节点为 CanvasLayer，UI 全部在 _ready() 中构建，
## 因此配套 .tscn 只保留根节点 + 脚本引用，无需手写复杂节点树。
## 由 RoguelikeDirector 在单层通关、暂停战斗时实例化，并调用 choices_ready()。

## 玩家选定某张卡（[param unit_id] 为空字符串表示跳过）
signal card_chosen(unit_id: String)
## 玩家选定某件文物（[param artifact_id] 为空字符串表示跳过），供宝箱节点三选一文物
signal artifact_chosen(artifact_id: String)

## 单张候选卡的最小尺寸
const CARD_SIZE: Vector2 = Vector2(150, 180)
## 各阶层卡面边框颜色（索引 0 未使用，阶层从 1 起）
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

## 候选卡容器（由 _build_ui 创建）
var _choices_container: HBoxContainer = null
## 标题文案（由 choices_ready 设置，_build_ui 时先显示默认值）
var _title: String = "选择一张奖励卡牌"
## 标题标签引用（_build_ui 创建后保存，choices_ready 时更新文案）
var _title_label: Label = null
## 当前选择模式："card" = 兵种卡三选一，"artifact" = 文物三选一（影响跳过按钮发出的信号）
var _mode: String = "card"

func _ready() -> void:
	## 设置为始终处理，确保战斗暂停状态下按钮仍可响应
	process_mode = Node.PROCESS_MODE_ALWAYS
	## 暂停完全由调用方（RoguelikeDirector 战斗通关 / RoguelikeMeta 宝箱）显式控制，
	## 本界面不再自行 get_tree().paused = true：
	## 宝箱页位于非战斗 hub，若此处强制暂停且后续构建异常，全局暂停将永不恢复 → 整树卡死。
	_build_ui()

## 构建半透明遮罩 + 居中内容（标题 / 候选卡 / 跳过按钮）
func _build_ui() -> void:
	## 半透明黑色背景遮罩，铺满视口并拦截下层输入
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	## 居中内容容器（铺满视口，内部元素居中排列）
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	var title := Label.new()
	title.text = _title
	_title_label = title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	_choices_container = HBoxContainer.new()
	_choices_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices_container.add_theme_constant_override("separation", 20)
	_choices_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_choices_container)

	var skip := Button.new()
	skip.text = "跳过（不获得）"
	skip.add_theme_font_size_override("font_size", 16)
	skip.pressed.connect(_on_skip_pressed)
	vbox.add_child(skip)

## 填充三张候选卡牌（[param title] 为弹窗标题，[param choices] 为兵种 ID 列表）
func choices_ready(title: String, choices: Array[String]) -> void:
	_title = title
	if _title_label != null:
		_title_label.text = _title
	if _choices_container == null:
		return
	for child in _choices_container.get_children():
		child.queue_free()
	## 空状态兜底：候选为空时给出明确提示，避免白屏 / 被误认为卡死
	if choices.is_empty():
		_show_empty_hint("牌库已无可获得的卡牌（点下方跳过继续）")
		return
	for unit_id in choices:
		var res := UnitDatabase.get_unit(unit_id) as UnitResource
		if res != null:
			_choices_container.add_child(_create_card(res))

## 填充三件候选文物（[param title] 为弹窗标题，[param artifacts] 为文物数据列表）
func choices_artifacts_ready(title: String, artifacts: Array[ArtifactData]) -> void:
	_title = title
	_mode = "artifact"
	if _title_label != null:
		## 标题下方追加「已持有文物」一览信息，作为宝物收藏的轻量列表展示
		var owned_count: int = RoguelikeManager.owned_artifacts.size() if RoguelikeManager != null else 0
		_title_label.text = "%s\n（当前已持有 %d 件文物）" % [_title, owned_count]
	if _choices_container == null:
		return
	for child in _choices_container.get_children():
		child.queue_free()
	## 空状态兜底：候选为空（已集齐 / 数据缺失）时给出明确提示，避免白屏卡死观感
	if artifacts.is_empty():
		_show_empty_hint("已集齐所有文物或暂无候选（点下方跳过继续）")
		return
	for art in artifacts:
		if art != null:
			_choices_container.add_child(_create_artifact_card(art))

## 候选为空时在候选容器内显示提示文本（空状态兜底）
func _show_empty_hint(text: String) -> void:
	if _choices_container == null:
		return
	var hint := Label.new()
	hint.text = text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(420, 120)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7, 1.0))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choices_container.add_child(hint)

## 创建一张可点击的候选文物卡
func _create_artifact_card(art: ArtifactData) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.11, 0.09, 0.96)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = art.get_rarity_color()
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", style)
	card.add_theme_stylebox_override("pressed", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = "%s〔%s〕" % [art.display_name, art.get_rarity_name()]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = art.description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.7, 1.0))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	card.pressed.connect(func() -> void: _on_artifact_chosen(art.artifact_id))
	return card

## 创建一张可点击的候选卡
func _create_card(res: UnitResource) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.11, 0.09, 0.96)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = TIER_COLORS[clampi(res.tier, 1, TIER_COLORS.size() - 1)]
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", style)
	card.add_theme_stylebox_override("pressed", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	## #211 卡牌等级圆框徽章：左上角显示当前召唤等级（1~CARD_LEVEL_MAX）
	var level: int = RoguelikeManager.get_card_level(res.unit_id)
	card.add_child(_create_level_badge(level))
	icon.texture = _load_unit_icon(res.unit_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = res.get_display_name()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var tier_lbl := Label.new()
	tier_lbl.text = "T%d  HP%d  ATK%d" % [res.tier, res.max_hp, res.damage]
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_lbl.add_theme_font_size_override("font_size", 12)
	tier_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.7, 1.0))
	tier_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tier_lbl)

	card.pressed.connect(func() -> void: _on_card_chosen(res.unit_id))
	return card

## 在卡牌左上角生成圆形等级徽章（#211）：直径 26px，显示卡牌召唤等级 1~CARD_LEVEL_MAX。
## 颜色按等级变化（银/蓝/金），事件穿透（mouse_filter=IGNORE）不阻碍点击选择。
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

## 选定某张卡：发出信号并释放本界面
func _on_card_chosen(unit_id: String) -> void:
	card_chosen.emit(unit_id)
	queue_free()

## 选定某件文物：发出信号并释放本界面
func _on_artifact_chosen(artifact_id: String) -> void:
	artifact_chosen.emit(artifact_id)
	queue_free()

## 跳过奖励：按当前模式发出空 ID（card / artifact）并释放本界面
func _on_skip_pressed() -> void:
	if _mode == "artifact":
		artifact_chosen.emit("")
	else:
		card_chosen.emit("")
	queue_free()

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
