class_name RoguelikeHeroSelect
extends Control
## 肉鸽英雄选择界面（#208）。5 个槽位：爱弥斯可选；其余按解锁状态动态显示
## （#8：Hero2 开发者模式默认解锁 / 战役解锁后可选，未解锁显示「暂未上线」）。
## 必须选完英雄才能开始：确认后 emit hero_confirmed(hero_id)，由调用方负责 start_run + 切场景。
## 纯代码构建 UI（无 .tscn），与 RoguelikeVictoryScreen / RoguelikeDefeatScreen 同风格。

signal hero_confirmed(hero_id: String)

var _selected_id: String = ""
var _start_btn: Button
var _toast: Label
## 英雄 ID → 该行的选择按钮，用于切换「选择 / 已选择」文案（配合锁定英雄禁用开始按钮）
var _hero_buttons: Dictionary = {}

func _ready() -> void:
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
	panel.custom_minimum_size = Vector2(760, 560)
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
	hero_confirmed.emit(_selected_id)

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
