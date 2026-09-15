class_name RoguelikeHeroSelect
extends Control
## 肉鸽英雄选择界面（#208）。5 个槽位：爱弥斯可选；其余按解锁状态动态显示
## （#8：Hero2 开发者模式默认解锁 / 战役解锁后可选，未解锁显示「暂未上线」）。
## 必须选完英雄才能开始：确认后 emit hero_confirmed(hero_id, ascension)，由调用方负责 start_run + 切场景。
## 另外承载两件事：
##   1. 「继续上次征程」——存在 run 存档时置顶显示，emit continue_run_requested 走读档流程
##   2. 进阶难度选择器——只能选到已解锁等级（通关一次解锁下一级）
## 纯代码构建 UI（无 .tscn），与 RoguelikeVictoryScreen / RoguelikeDefeatScreen 同风格。

signal hero_confirmed(hero_id: String, ascension: int)
## 玩家点「继续上次征程」：由调用方执行 RoguelikeManager.load_run() 并切到 hub
signal continue_run_requested()

var _selected_id: String = ""
var _start_btn: Button
var _toast: Label
## 英雄 ID → 该行的选择按钮，用于切换「选择 / 已选择」文案（配合锁定英雄禁用开始按钮）
var _hero_buttons: Dictionary = {}
## 进阶难度下拉（只列出已解锁等级）与其效果说明
var _ascension_option: OptionButton = null
var _ascension_desc: Label = null

func _ready() -> void:
	## 进阶解锁等级与历史记录来自 user://，读界面前先懒加载一次
	RoguelikeManager.load_progress()
	## 用 set_anchors_and_offsets_preset 而非 set_anchors_preset：
	## 后者只改锚点、不动 offset，一旦有残留偏移量整个面板就会偏离屏幕中心。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	## 半透明遮罩，盖住下层战役地图
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.03, 0.02, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	## 居中主面板：CenterContainer 铺满整屏，面板才会落在页面正中
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 660)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.16, 0.12, 0.09, 1)
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	## 标题
	var title := Label.new()
	title.text = "选择英雄"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45, 1.0))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "必须选择英雄才能开始肉鸽模式"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75, 1.0))
	vbox.add_child(subtitle)

	## 「继续上次征程」置顶：只在存在 run 存档时出现
	_build_continue_row(vbox)

	## 英雄槽位
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)
	## 表头：英雄 / 军团 / 特长 三栏（#5）
	grid.add_child(_create_hero_header())
	for hero in RoguelikeManager.get_hero_defs():
		grid.add_child(_create_hero_row(hero))

	## 进阶难度选择器（仅列出已解锁等级）
	_build_ascension_row(vbox)

	## 底部按钮行
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	_start_btn = Button.new()
	_start_btn.text = "开始"
	_start_btn.disabled = true
	_start_btn.custom_minimum_size = Vector2(160, 44)
	_start_btn.add_theme_font_size_override("font_size", 18)
	_start_btn.pressed.connect(_on_start_pressed)
	btn_row.add_child(_start_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "返回"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.pressed.connect(queue_free)
	btn_row.add_child(cancel_btn)

	## 提示条（暂未上线等）
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 14)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5, 1.0))
	_toast.visible = false
	vbox.add_child(_toast)

## 「继续上次征程」行：存在 hub 层面的 run 存档时才构建。
## 存档只记录 hub 状态，因此文案明确写出「回到该节点开始前」，避免玩家以为战斗进度也能续上。
func _build_continue_row(parent: Control) -> void:
	if not RoguelikeManager.has_save():
		return
	var summary: Dictionary = RoguelikeManager.peek_save_summary()
	if summary.is_empty():
		return
	var hero_name: String = _hero_display_name(String(summary.get("hero", "")))
	var asc: int = int(summary.get("ascension", 0))
	var btn := Button.new()
	btn.text = "继续上次征程（%s · 第 %d 层 · 金币 %d · 牌库 %d 张%s）" % [
		hero_name,
		int(summary.get("floor", 1)),
		int(summary.get("gold", 0)),
		int(summary.get("deck_size", 0)),
		"" if asc <= 0 else " · 进阶 %d" % asc,
	]
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.62, 1.0, 0.72, 1.0))
	btn.pressed.connect(_on_continue_pressed)
	parent.add_child(btn)

	var hint := Label.new()
	hint.text = "读档回到地图总控台（战斗中退出会退回该节点开始前）；下方新开一局会覆盖此存档"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.68, 1.0))
	parent.add_child(hint)

## 英雄 ID 的展示名（存档里只有 ID，取 HERO_DEFS 里的中文名，查不到就回落 ID）
func _hero_display_name(hero_id: String) -> String:
	if hero_id.is_empty():
		return "未知英雄"
	for hero in RoguelikeManager.HERO_DEFS:
		if String(hero["id"]) == hero_id:
			return String(hero["name"])
	return hero_id

## 进阶难度行：下拉只列出 0 ~ ascension_unlocked，选中后实时刷新效果说明
func _build_ascension_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var label := Label.new()
	label.text = "进阶难度"
	label.custom_minimum_size = Vector2(120, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45, 1.0))
	row.add_child(label)

	_ascension_option = OptionButton.new()
	_ascension_option.custom_minimum_size = Vector2(200, 36)
	_ascension_option.add_theme_font_size_override("font_size", 15)
	var unlocked: int = clampi(RoguelikeManager.ascension_unlocked, 0, RoguelikeManager.ASCENSION_MAX_LEVEL)
	for lvl in range(unlocked + 1):
		_ascension_option.add_item("标准（无进阶）" if lvl == 0 else "进阶 %d" % lvl, lvl)
	## 沿用上一局选择（受当前解锁上限夹断），方便连续挑战同难度
	_ascension_option.select(clampi(RoguelikeManager.ascension_level, 0, unlocked))
	_ascension_option.item_selected.connect(_on_ascension_selected)
	row.add_child(_ascension_option)

	_ascension_desc = Label.new()
	_ascension_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ascension_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ascension_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ascension_desc.add_theme_font_size_override("font_size", 12)
	_ascension_desc.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70, 1.0))
	row.add_child(_ascension_desc)
	_refresh_ascension_desc()

## 当前下拉选中的进阶等级（下拉未构建时回落 0）
func _current_ascension() -> int:
	if _ascension_option == null or not is_instance_valid(_ascension_option):
		return 0
	return maxi(_ascension_option.get_selected_id(), 0)

func _on_ascension_selected(_index: int) -> void:
	_refresh_ascension_desc()

## 刷新进阶效果说明；尚未解锁任何进阶时提示解锁条件
func _refresh_ascension_desc() -> void:
	if _ascension_desc == null or not is_instance_valid(_ascension_desc):
		return
	if RoguelikeManager.ascension_unlocked <= 0:
		_ascension_desc.text = "通关一次（击败最终 Boss）后解锁进阶 1"
		return
	_ascension_desc.text = RoguelikeManager.ascension_desc(_current_ascension())

## 点「继续上次征程」：交给调用方读档并切场景，本界面随即关闭
func _on_continue_pressed() -> void:
	continue_run_requested.emit()
	queue_free()

## 创建单个英雄行（名称 / 军团 / 特长 / 选择），三栏布局（#5）
func _create_hero_row(hero: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = hero["name"]
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0) if not hero["locked"] else Color(0.6, 0.6, 0.6, 1.0))
	row.add_child(name_label)

	var army_label := Label.new()
	army_label.text = hero.get("army", "")
	army_label.custom_minimum_size = Vector2(200, 0)
	army_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	army_label.add_theme_font_size_override("font_size", 13)
	army_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75, 1.0))
	row.add_child(army_label)

	var special_label := Label.new()
	special_label.text = hero.get("special", "")
	special_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	special_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	special_label.add_theme_font_size_override("font_size", 13)
	special_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45, 1.0))
	row.add_child(special_label)

	var btn := Button.new()
	var hero_id: String = hero["id"]
	btn.custom_minimum_size = Vector2(100, 36)
	if hero["locked"]:
		btn.text = "暂未上线"
		btn.pressed.connect(func() -> void: _on_locked_hero_picked())
	else:
		btn.text = "选择"
		btn.pressed.connect(func() -> void: _on_hero_picked(hero_id))
		_hero_buttons[hero_id] = btn
	row.add_child(btn)
	return row

## 英雄选择表头（列宽与 _create_hero_row 对齐，#5）
func _create_hero_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var headers := ["英雄", "军团", "特长", ""]
	var widths := [120, 200, 0, 100]
	for i in range(headers.size()):
		var lbl := Label.new()
		lbl.text = headers[i]
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7, 1.0))
		if widths[i] > 0:
			lbl.custom_minimum_size = Vector2(widths[i], 0)
		if i == 2:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
	return row

## 选中某个已上线英雄：记录 ID 并启用开始按钮
func _on_hero_picked(hero_id: String) -> void:
	_selected_id = hero_id
	_start_btn.disabled = false
	_toast.visible = false
	_refresh_hero_buttons()

## 点选未上线英雄：清空选择并禁用开始按钮，避免带着上一次的选择直接开局
func _on_locked_hero_picked() -> void:
	_selected_id = ""
	_start_btn.disabled = true
	_refresh_hero_buttons()
	_show_toast("该英雄暂未上线，无法开始")

## 同步各英雄按钮文案，让当前选中项一目了然
func _refresh_hero_buttons() -> void:
	for hero_id in _hero_buttons:
		var btn := _hero_buttons[hero_id] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		btn.text = "已选择" if hero_id == _selected_id else "选择"

func _on_start_pressed() -> void:
	if _selected_id.is_empty():
		_show_toast("请先选择一个英雄")
		return
	hero_confirmed.emit(_selected_id, _current_ascension())

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
