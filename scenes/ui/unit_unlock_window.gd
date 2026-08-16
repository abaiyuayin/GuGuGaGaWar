extends Window
## 兵种解锁窗口
## 战役地图内打开，用战功购买解锁 7 个高级兵种
## 图鉴（codex_screen）仅做只读展示；战功消费集中在此窗口

## 高级兵种展示顺序（按阵营 G→D→F→N）
const UNIT_ORDER: Array[String] = ["G5", "G6", "D2", "D5", "D6", "F4", "N5"]

@onready var merit_label: Label = $VBox/MeritLabel
@onready var unit_list: VBoxContainer = $VBox/ScrollContainer/UnitList
@onready var close_button: Button = $VBox/CloseButton

## unit_id -> 购买按钮，用于刷新可购买状态
var _buy_buttons: Dictionary = {}
## unit_id -> 星星解锁状态按钮（不可购买，仅展示进度）
var _star_buttons: Dictionary = {}
## unit_id -> UnitResource 查询表
var _unit_lookup: Dictionary = {}

func _ready() -> void:
	_build_lookup()
	_populate()
	_refresh_merit()
	_refresh_buttons()
	## #12（2026-08-11）：关闭按钮放大至 180×56、字号同步放大，与设置/确认弹窗一致
	close_button.custom_minimum_size = Vector2(180, 56)
	close_button.add_theme_font_size_override("font_size", 28)
	close_button.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)

func _build_lookup() -> void:
	for res: UnitResource in UnitDatabase.unit_list:
		_unit_lookup[res.unit_id] = res

func _populate() -> void:
	for unit_id: String in UNIT_ORDER:
		if not CampaignProgress.ADVANCED_COST.has(unit_id):
			continue
		var res: UnitResource = _unit_lookup.get(unit_id, null)
		if res == null:
			continue
		var cost: int = CampaignProgress.ADVANCED_COST[unit_id]
		unit_list.add_child(_create_row(res, unit_id, cost))
	_populate_star_units()

## 星星解锁的特殊兵种（如爱弥斯 Hero1、Doro勇士 Hero2，需累计星星达阈值，不可用战功购买）
func _populate_star_units() -> void:
	for unit_id: String in CampaignProgress.STAR_UNLOCK:
		## 成就门控兵种（Doro勇士等）：对应成就未解锁时隐藏该行，避免剧透隐藏成就
		var gate_id: String = CampaignProgress.ACHIEVEMENT_GATED_UNITS.get(unit_id, "")
		if gate_id != "" and not Achievements.is_unlocked(gate_id):
			continue
		var res: UnitResource = _unit_lookup.get(unit_id, null)
		if res == null:
			continue
		var need: int = int(CampaignProgress.STAR_UNLOCK[unit_id])
		unit_list.add_child(_create_star_row(res, unit_id, need))

## 构建星星解锁行：右侧按钮只展示进度，不接购买回调
func _create_star_row(res: UnitResource, unit_id: String, need: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = res.get_display_name()
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = "★ %d" % need
	cost_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.28, 1.0))
	cost_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(cost_label)

	var state_btn := Button.new()
	state_btn.custom_minimum_size = Vector2(90, 32)
	state_btn.disabled = true
	UIButtonHelper.setup_button(state_btn)
	## #12（2026-08-11）：星星按钮未解锁时可点击，点击弹屏幕上方纯文本提示（不再纯展示）
	state_btn.pressed.connect(_on_star_pressed.bind(unit_id))
	_star_buttons[unit_id] = state_btn
	row.add_child(state_btn)
	return row

func _create_row(res: UnitResource, unit_id: String, cost: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = res.get_display_name()
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = "战功 %d" % cost
	cost_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(cost_label)

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(90, 32)
	UIButtonHelper.setup_button(buy_btn)
	_buy_buttons[unit_id] = buy_btn
	if not CampaignProgress.is_unit_unlocked(unit_id):
		buy_btn.pressed.connect(_on_buy_pressed.bind(unit_id))
	row.add_child(buy_btn)
	return row

func _on_buy_pressed(unit_id: String) -> void:
	var res: UnitResource = _unit_lookup.get(unit_id, null)
	if CampaignProgress.buy_advanced(unit_id):
		AudioManager.play_ui_click()
		_refresh_merit()
		_refresh_buttons()
		## #21：购买即检查「兵种大师」成就（解锁全部兵种后实时弹出，不等结算）
		Achievements.check_progress()
		## #19：解锁成功弹出「获得新兵种！」确认框（复用通关首通弹窗，UIButtonHelper 共享实现）
		if res != null:
			UIButtonHelper.show_unit_unlock_popup(self, res.get_display_name(), unit_id)
	else:
		## #18 + #12（2026-08-11）：战功不足不再弹确认框，改屏幕上方纯文本提示（2 秒自动消失）
		var need: int = int(CampaignProgress.ADVANCED_COST.get(unit_id, 0))
		var name_text: String = res.get_display_name() if res != null else unit_id
		_show_top_hint("战功不足！解锁「%s」需要 %d 战功，当前战功 %d。" % [
			name_text, need, CampaignProgress.get_merit()])

## #12（2026-08-11）：星星解锁按钮点击 → 屏幕上方纯文本提示（不足给差额，足够给已解锁确认）
func _on_star_pressed(unit_id: String) -> void:
	var res: UnitResource = _unit_lookup.get(unit_id, null)
	var need: int = int(CampaignProgress.STAR_UNLOCK.get(unit_id, 0))
	var name_text: String = res.get_display_name() if res != null else unit_id
	var stars: int = CampaignProgress.get_total_stars()
	if stars >= need:
		_show_top_hint("「%s」已解锁（%d/%d 星）" % [name_text, stars, need])
	else:
		_show_top_hint("星星不足！解锁「%s」需要 %d 星，当前 %d 星。" % [name_text, need, stars])

## #12：屏幕上方（窗口内顶部居中）纯文本提示，2 秒后自动消失；不弹确认框
## #10（2026-08-11）：字体放大到 22，且弹出前先清除上一轮未消失的旧 hint，
## 避免连续点击时多个提示堆叠、互相遮挡
func _show_top_hint(text: String) -> void:
	AudioManager.play_ui_click()
	## 清旧：回收上一轮残留的同名提示（用 meta 标记识别）
	for child in get_children():
		if child is Label and child.has_meta("_top_hint"):
			child.queue_free()
	var hint := Label.new()
	hint.set_meta("_top_hint", true)
	hint.text = text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("outline_size", 3)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hint.offset_top = 16.0
	add_child(hint)
	var t := Timer.new()
	t.wait_time = 2.0
	t.one_shot = true
	add_child(t)
	t.timeout.connect(func() -> void:
		if is_instance_valid(hint):
			hint.queue_free()
		t.queue_free()
	)
	t.start()

func _refresh_merit() -> void:
	## #23：战功后方追加星星数量显示（成就解锁的星星数）
	merit_label.text = "战功: %d     ★ 星星: %d" % [CampaignProgress.get_merit(), CampaignProgress.get_total_stars()]

func _refresh_buttons() -> void:
	for unit_id in _buy_buttons:
		var btn: Button = _buy_buttons[unit_id]
		if CampaignProgress.is_unit_unlocked(unit_id):
			btn.text = "已解锁"
			btn.disabled = true
		else:
			btn.text = "解锁"
			## #18：战功不足不禁用按钮——点击时弹出「战功不足」提示，给玩家明确反馈
			## （旧逻辑战功不足直接禁用，玩家不知道差多少）
			btn.disabled = false
	## 星星解锁兵种：未解锁时可点击弹提示（#12），已解锁才禁用
	var stars: int = CampaignProgress.get_total_stars()
	for unit_id in _star_buttons:
		var sbtn: Button = _star_buttons[unit_id]
		var need: int = int(CampaignProgress.STAR_UNLOCK[unit_id])
		sbtn.text = "已解锁" if stars >= need else "%d/%d" % [stars, need]
		sbtn.disabled = stars >= need  ## #12：未解锁保持可点击，点击弹屏幕上方提示

func _on_close_pressed() -> void:
	queue_free()
