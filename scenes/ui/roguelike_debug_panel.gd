extends Control
## 肉鸽专属控制台（#26）
## 数值调整只对肉鸽模式生效，持久化到 user://roguelike_unit_override.json，不影响全局 .tres。
## 兵种资源在 unit_base.setup 中被 duplicate 后应用覆盖层，确保不污染共享 .tres。
## 入口由 roguelike_hud 提供（#27）。

const UNIT_ORDER: Array[String] = [
	"G1", "G2", "G3", "G4", "G5", "G6",
	"D1", "D2", "D3", "D4", "D5", "D6",
	"F1", "F2", "F3", "F4", "F5",
	"N1", "N2", "N3", "N4", "N5",
	"Hero1",
]
const FACTION_GROUPS: Array = [["G", "咕嘎"], ["D", "Doro"], ["F", "菲比"], ["N", "糯糯"], ["H", "英雄"]]
## 可调属性定义：prop=字段名 / label=显示 / min/max/step / is_int
const STATS: Array = [
	{"prop": "max_hp", "label": "血量", "min": 1.0, "max": 99999.0, "step": 10.0, "is_int": true},
	{"prop": "damage", "label": "伤害", "min": 0.0, "max": 9999.0, "step": 5.0, "is_int": true},
	{"prop": "attack_speed", "label": "攻速", "min": 0.1, "max": 10.0, "step": 0.1, "is_int": false},
	{"prop": "move_speed", "label": "移速", "min": 0.0, "max": 500.0, "step": 5.0, "is_int": false},
	{"prop": "armor_value", "label": "护甲", "min": 0.0, "max": 999.0, "step": 1.0, "is_int": true},
	{"prop": "attack_range", "label": "射程", "min": 0.0, "max": 20.0, "step": 0.1, "is_int": false},
	{"prop": "cost", "label": "造价", "min": 0.0, "max": 9999.0, "step": 10.0, "is_int": true},
]
const RES_ROOT := "res://resources/units"

var _resources: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	## #1：肉鸽调试控制台用引擎默认字体（避开全局书法体）
	theme = UIButtonHelper.make_dev_system_theme()
	_load_resources()
	_build_ui()

func _load_resources() -> void:
	for uid in UNIT_ORDER:
		var path := "%s/%s.tres" % [RES_ROOT, uid]
		var res := load(path) as UnitResource
		if res != null:
			_resources[uid] = res

func _build_ui() -> void:
	## 半透明背景遮罩，拦截点击
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	## 主面板
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 40
	panel.offset_right = -40
	panel.offset_bottom = -40
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	## 标题行 + 关闭按钮
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "肉鸽专属控制台（修改只对肉鸽生效，自动持久化）"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var btn_close := Button.new()
	btn_close.text = "关闭"
	btn_close.pressed.connect(queue_free)
	header.add_child(btn_close)
	## 滚动区
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	## 兵种数值网格
	var override_data := RoguelikeManager.get_unit_override_raw()
	for group in FACTION_GROUPS:
		var prefix: String = group[0]
		var fname: String = group[1]
		var faction_units: Array[String] = []
		for uid in UNIT_ORDER:
			if uid.begins_with(prefix):
				faction_units.append(uid)
		if faction_units.is_empty():
			continue
		var flabel := Label.new()
		flabel.text = "—— %s ——" % fname
		flabel.add_theme_color_override("font_color", Color(1, 0.7, 0.3, 1))
		flabel.add_theme_font_size_override("font_size", 15)
		content.add_child(flabel)
		for uid in faction_units:
			var res: UnitResource = _resources.get(uid)
			if res == null:
				continue
			content.add_child(_create_unit_row(uid, res, override_data))
	## AI 调参区
	_append_ai_tuning(content)
	## #8：英雄技能 CD 配置区
	_append_skill_cd_tuning(content)

## 创建单兵种数值行：兵种名 + 7 个属性 SpinBox
func _create_unit_row(uid: String, res: UnitResource, override_data: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_lbl := Label.new()
	name_lbl.text = uid
	name_lbl.custom_minimum_size = Vector2(60, 0)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	row.add_child(name_lbl)
	var unit_ov: Dictionary = override_data.get(uid, {})
	for stat in STATS:
		var prop: String = stat["prop"]
		var label: String = stat["label"]
		var smin: float = stat["min"]
		var smax: float = stat["max"]
		var step: float = stat["step"]
		var is_int: bool = stat["is_int"]
		var sl := Label.new()
		sl.text = label
		sl.add_theme_font_size_override("font_size", 11)
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(sl)
		var spin := SpinBox.new()
		spin.min_value = smin
		spin.max_value = smax
		spin.step = step
		## 初始值：覆盖层优先，否则兵种基础值
		var base_val: float = float(res.get(prop))
		spin.value = float(unit_ov.get(prop, base_val))
		spin.custom_minimum_size = Vector2(70, 0)
		spin.value_changed.connect(func(v: float) -> void:
			var val: Variant = int(v) if is_int else v
			RoguelikeManager.set_unit_override(uid, prop, val)
		)
		row.add_child(spin)
	return row

## 肉鸽 AI 调参区（运行态，下一局自动复位）
func _append_ai_tuning(content: VBoxContainer) -> void:
	var section := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.14, 0.18, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	section.add_theme_stylebox_override("panel", style)
	content.add_child(section)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	section.add_child(vbox)
	var header := Label.new()
	header.text = "—— 肉鸽 AI 调参（仅肉鸽模式生效，下一局自动复位） ——"
	header.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9, 1))
	header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(header)
	_add_ai_slider_row(vbox, "追击敌方范围 (px):", RoguelikeManager.chase_range_px, 50.0, 800.0, 5.0,
		func(v: float) -> void: RoguelikeManager.chase_range_px = v)
	_add_ai_slider_row(vbox, "追击牵引半径 (px):", RoguelikeManager.chase_leash_px, 50.0, 1200.0, 5.0,
		func(v: float) -> void: RoguelikeManager.chase_leash_px = v)
	var note := Label.new()
	note.text = "数值调整已自动持久化到 user://roguelike_unit_override.json，跨 run 保留；AI 调参为运行态，下一局复位。"
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)

func _add_ai_slider_row(parent: Control, label_text: String, cur_val: float, smin: float, smax: float, step: float, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = smin
	spin.max_value = smax
	spin.step = step
	spin.value = cur_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float) -> void: on_changed.call(v))
	row.add_child(spin)

## #8：英雄技能 CD 配置区（波次上限，可覆盖并持久化到 user://）
## 仅展示当前英雄所属技能；其余英雄技能并发显示以备后续扩展。
func _append_skill_cd_tuning(content: VBoxContainer) -> void:
	var section := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.10, 0.16, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	section.add_theme_stylebox_override("panel", style)
	content.add_child(section)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	section.add_child(vbox)
	var header := Label.new()
	header.text = "—— 英雄技能 CD 配置（波次上限，持久化） ——"
	header.add_theme_color_override("font_color", Color(0.95, 0.78, 0.30, 1))
	header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(header)
	## 空表时给占位提示，避免面板空白
	if HeroSkillManager.SKILL_DEFS.is_empty():
		var none := Label.new()
		none.text = "（当前无可用技能）"
		none.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		vbox.add_child(none)
		return
	for def in HeroSkillManager.SKILL_DEFS:
		var sid: String = def["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = "%s" % def["name"]
		name_lbl.custom_minimum_size = Vector2(150, 0)
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)
		var spin := SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = 20.0
		spin.step = 1.0
		spin.value = float(HeroSkillManager.get_cd_max(sid))
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(func(v: float) -> void:
			HeroSkillManager.set_skill_cd_override(sid, int(v))
		)
		row.add_child(spin)
	var note := Label.new()
	note.text = "CD 单位为「波次」：释放后进入冷却，每刷新一波敌军自动恢复 1 点。改动即时持久化。"
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)
