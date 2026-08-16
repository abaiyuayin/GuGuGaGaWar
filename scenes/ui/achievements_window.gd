extends Window
## 成就展示窗口（战役地图内打开）
## 列出全部成就，显示已解锁 / 未解锁状态（纯荣誉，无数值奖励）

@onready var ach_list: VBoxContainer = $VBox/ScrollContainer/AchList
@onready var close_button: Button = $VBox/CloseButton

func _ready() -> void:
	_populate()
	## #12（2026-08-11）：关闭按钮放大至 180×56、字号同步放大，与设置/确认弹窗一致
	close_button.custom_minimum_size = Vector2(180, 56)
	close_button.add_theme_font_size_override("font_size", 28)
	close_button.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)
	## 监听开发者模式切换：关闭时禁用图标上传功能
	DevMode.dev_mode_changed.connect(_on_dev_mode_changed)

## 图标尺寸（左侧圆徽）
const ICON_SIZE: int = 44
## 已解锁金色
const COLOR_GOLD: Color = Color(0.95, 0.78, 0.28, 1.0)
## 已解锁状态文字绿
const COLOR_UNLOCKED_TEXT: Color = Color(0.4, 0.85, 0.4, 1.0)
## 未解锁成就名（保持高亮度，必须清晰可读）
const COLOR_LOCKED_NAME: Color = Color(0.94, 0.94, 0.94, 1.0)
## 未解锁成就描述
const COLOR_LOCKED_DESC: Color = Color(0.82, 0.82, 0.82, 1.0)
## 未解锁状态文字
const COLOR_LOCKED_STATUS: Color = Color(0.78, 0.78, 0.78, 1.0)
## 已解锁徽章底色（暖金）
const COLOR_ICON_BG_UNLOCKED: Color = Color(0.22, 0.18, 0.07, 1.0)
## 未解锁徽章底色（冷暗）
const COLOR_ICON_BG_LOCKED: Color = Color(0.08, 0.08, 0.10, 1.0)
## 未解锁时对「自定义上传图标」施加的置灰调制
## 只作用在图标按钮上，不会波及名称/描述的亮度
const LOCKED_ICON_MODULATE: Color = Color(0.42, 0.42, 0.48, 1.0)
## 成就图标可点击上传的按钮引用（开发者模式用，关闭时统一禁用）
var _icon_buttons: Array[Button] = []
## #13（2026-08-11）：成就「解锁」按钮引用（开发者模式可见，点击直接解锁成就）
var _unlock_buttons: Array[Button] = []
## 自定义成就图标存储目录
## 用 user:// 而非 res://：res:// 在导出版只读，且运行时拷入的图片不走导入管线无法 load()
const ICON_DIR: String = "user://achievement_icons"

func _populate() -> void:
	for entry in Achievements.get_catalog():
		ach_list.add_child(_create_row(entry))

## 成就行：最左侧图标 → 中间成就名称+描述 → 最右侧解锁状态
func _create_row(entry: Dictionary) -> HBoxContainer:
	var unlocked: bool = Achievements.is_unlocked(entry.id)
	## #13（2026-08-09）：隐藏成就（日夜交替）未解锁时以「？？？」遮盖名称与描述
	var is_hidden: bool = bool(entry.get("hidden", false)) and not unlocked
	## #需求11：开发者模式下「揭露」隐藏成就——显示真实名称/描述，并标记这是隐藏成就
	var dev_reveal: bool = is_hidden and DevMode.enabled
	var show_name: String = tr("ACH_NAME_" + entry.id) if (not is_hidden or dev_reveal) else "？？？"
	var show_desc: String = tr("ACH_DESC_" + entry.id) if (not is_hidden or dev_reveal) else tr("ACH_HIDDEN_DESC")
	if dev_reveal:
		show_desc = tr("ACH_HIDDEN_PREFIX") + show_desc
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## 注意：不要用 row.modulate 置灰整行——modulate 是乘算，会把名字/描述的高亮度一起压暗。
	## 视觉差改为只体现在图标与状态文字上，正文始终保持可读。

	## —— 左：圆形图标（已解锁金色 ★，未解锁灰 ★；开发者模式下可点击上传图片）——
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style := StyleBoxFlat.new()
	## 已解锁：暖金底 + 金边 + 加粗描边；未解锁：冷暗底 + 细灰边
	## 视觉差集中在徽章上，正文文字保持高亮度（可读性优先，见下方注释）
	icon_style.bg_color = COLOR_ICON_BG_UNLOCKED if unlocked else COLOR_ICON_BG_LOCKED
	icon_style.set_corner_radius_all(int(ICON_SIZE / 2.0))
	icon_style.set_border_width_all(3 if unlocked else 1)
	icon_style.border_color = COLOR_GOLD if unlocked else Color(0.32, 0.32, 0.36, 1.0)
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	row.add_child(icon_panel)

	## 图标本体：用 Button 承载（开发者模式可点击上传图片；非开发者模式仅展示）
	var icon_btn := Button.new()
	icon_btn.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_btn.text = "★"
	icon_btn.add_theme_font_size_override("font_size", 24)
	icon_btn.add_theme_color_override("font_color", COLOR_GOLD if unlocked else Color(0.4, 0.4, 0.4, 1.0))
	icon_panel.add_child(icon_btn)
	icon_btn.expand_icon = true
	icon_btn.tooltip_text = tr("ACH_ICON_TOOLTIP")
	## 若已上传自定义图标则显示该图片
	var saved_tex: Texture2D = _load_achievement_icon(entry.id)
	if saved_tex != null:
		icon_btn.text = ""
		icon_btn.icon = saved_tex
		## 未解锁时把自定义图标压暗去色——否则上传过图标的成就无论解锁与否都一样鲜亮，
		## 灰度区分完全失效（这是「未解锁看不出区别」的主要漏点）
		if not unlocked:
			icon_btn.modulate = LOCKED_ICON_MODULATE
	elif not unlocked:
		## 未上传图标时用锁形符号替代星形，进一步拉开辨识度
		icon_btn.text = "🔒"
		icon_btn.add_theme_font_size_override("font_size", 18)
	## 无论当前开发者模式开关状态都先连好信号并登记，
	## 否则「窗口已打开 → 再开启开发者模式」时数组为空，功能无法恢复
	icon_btn.pressed.connect(_on_icon_pressed.bind(entry.id, icon_panel))
	_icon_buttons.append(icon_btn)
	_apply_dev_state(icon_btn, DevMode.enabled)

	## —— 左2（#13 2026-08-11）：成就「解锁」按钮（开发者模式可见；点击直接解锁该成就）——
	var unlock_btn := Button.new()
	unlock_btn.custom_minimum_size = Vector2(56, 32)
	unlock_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	unlock_btn.text = tr("ACH_UNLOCKED") if unlocked else tr("ACH_UNLOCK_BTN")
	unlock_btn.disabled = unlocked
	unlock_btn.tooltip_text = tr("ACH_UNLOCK_TOOLTIP")
	UIButtonHelper.setup_button(unlock_btn)
	unlock_btn.pressed.connect(_on_unlock_pressed.bind(entry.id))
	row.add_child(unlock_btn)
	_unlock_buttons.append(unlock_btn)
	unlock_btn.visible = DevMode.enabled  ## 非开发者模式隐藏（普通玩家不可见）

	## —— 中：成就名称 + 描述（解锁说明）——
	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_box.add_theme_constant_override("separation", 2)
	row.add_child(info_box)

	var name_label := Label.new()
	name_label.text = show_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", COLOR_GOLD if unlocked else COLOR_LOCKED_NAME)
	info_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = show_desc
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", COLOR_LOCKED_DESC if not unlocked else Color(0.90, 0.90, 0.90, 1.0))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(desc_label)

	## —— 右：解锁状态（已解锁 / 未解锁）——
	var status := Label.new()
	status.custom_minimum_size = Vector2(70, 0)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if unlocked:
		status.text = tr("ACH_UNLOCKED")
		status.add_theme_color_override("font_color", COLOR_UNLOCKED_TEXT)
	else:
		status.text = tr("ACH_LOCKED")
		status.add_theme_color_override("font_color", COLOR_LOCKED_STATUS)
	row.add_child(status)
	return row

func _on_close_pressed() -> void:
	queue_free()

## 开发者模式切换：关闭时统一禁用图标上传按钮（开启时恢复）
func _on_dev_mode_changed(on: bool) -> void:
	for b in _icon_buttons:
		if is_instance_valid(b):
			_apply_dev_state(b, on)
	## #13：解锁按钮随开发者模式显隐
	for b in _unlock_buttons:
		if is_instance_valid(b):
			b.visible = on
	## #需求11：开发者模式切换时重建成就列表——隐藏成就的「揭露/遮盖」状态随模式实时刷新
	_rebuild_list()

## #13（2026-08-11）：点击「解锁」按钮直接解锁成就（仅开发者模式可达，双保险校验）
func _on_unlock_pressed(id: String) -> void:
	if not DevMode.enabled:
		return
	AudioManager.play_ui_click()
	CampaignProgress.unlock_achievement(id)
	_rebuild_list()

## 重建成就列表（清空后按目录重建，供开发者模式切换时刷新隐藏成就显示）
func _rebuild_list() -> void:
	for child in ach_list.get_children():
		child.queue_free()
	_icon_buttons.clear()
	_unlock_buttons.clear()
	_populate()

## 按开发者模式开关设置单个图标按钮的可交互状态
func _apply_dev_state(btn: Button, on: bool) -> void:
	btn.disabled = not on
	btn.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW

## 点击图标：打开文件对话框选择图片（仅开发者模式可达）
func _on_icon_pressed(id: String, panel: PanelContainer) -> void:
	## 双保险：即便按钮状态被外部改动，也不允许非开发者模式触发上传
	if not DevMode.enabled:
		return
	var fd := FileDialog.new()
	fd.title = tr("ACH_ICON_TITLE")
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray([tr("ACH_ICON_FILTER")])
	add_child(fd)
	fd.file_selected.connect(func(path: String) -> void:
		_apply_achievement_icon(id, path, panel)
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(720, 520))

## 复制所选图片到 user:// 并应用到图标
func _apply_achievement_icon(id: String, src_path: String, panel: PanelContainer) -> void:
	DirAccess.make_dir_recursive_absolute(ICON_DIR)
	var ext: String = src_path.get_extension().to_lower()
	if ext == "":
		ext = "png"
	var dest: String = "%s/%s.%s" % [ICON_DIR, id, ext]
	var err: int = DirAccess.copy_absolute(src_path, dest)
	if err != OK:
		push_warning("[成就图标] 复制失败: %s -> %s (错误码 %d)" % [src_path, dest, err])
		return
	var tex: Texture2D = _texture_from_file(dest)
	if tex == null:
		push_warning("[成就图标] 图片解析失败: %s" % dest)
		return
	for child in panel.get_children():
		if child is Button:
			var b: Button = child as Button
			b.text = ""
			b.icon = tex
			b.expand_icon = true
	_save_achievement_icon_path(id, dest)

## 从磁盘原始图片文件构建纹理
## 绕开 res:// 导入管线，运行时（含导出版）均可用
func _texture_from_file(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

## 读取已保存的成就图标纹理
func _load_achievement_icon(id: String) -> Texture2D:
	var path: String = _get_achievement_icon_path(id)
	if path == "":
		return null
	return _texture_from_file(path)

func _get_achievement_icon_path(id: String) -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://achievement_icons.cfg")
	return str(cfg.get_value("icons", id, ""))

func _save_achievement_icon_path(id: String, path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://achievement_icons.cfg")
	cfg.set_value("icons", id, path)
	cfg.save("user://achievement_icons.cfg")
