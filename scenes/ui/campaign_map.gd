extends Control
## 战役地图 UI
## 中世纪手绘羊皮纸风格，10 个关卡沿蜿蜒路径从「起始」延伸至「城堡」
## 点击已解锁关卡弹出难度选择，通关进度由 CampaignProgress 单例管理

## 总关卡数量
const LEVEL_COUNT: int = 10
## 难度定义：难度编号 -> [显示名 tr-key, 颜色]
const DIFFICULTIES: Array = [
	["DIFF_NAME_NORMAL", Color(0.35, 0.8, 0.4)],  ## 0=普通，绿色
	["DIFF_NAME_HARD", Color(1.0, 0.84, 0.35)],  ## 1=困难，金色
	["DIFF_NAME_HELL", Color(0.9, 0.35, 0.3)],  ## 2=地狱，红色
]

## 路径颜色与宽度
const PATH_COLOR: Color = Color(0.62, 0.45, 0.29, 1.0)
const PATH_OUTLINE_COLOR: Color = Color(0.43, 0.30, 0.18, 1.0)
const PATH_WIDTH: float = 14.0
const PATH_OUTLINE_WIDTH: float = 20.0

## 关卡标记尺寸
const MARKER_SIZE: float = 56.0
const MARKER_RADIUS: float = 28.0
const STAR_SIZE: float = 14.0
## BOSS 关卡标记上方提示标签高度
const BOSS_LABEL_H: float = 18.0
const BOSS_COLOR: Color = Color(1.0, 0.35, 0.3, 1.0)

## 关卡在路径上的位置进度（0~1，按弧长）
const LEVEL_PROGRESS: Array[float] = [
	0.06, 0.16, 0.27, 0.38, 0.49,
	0.59, 0.69, 0.79, 0.88, 0.96
]

## 地图区域节点
@onready var map_area: Control = $MapArea
## 标题标签
@onready var title_label: Label = $Title
## 返回主菜单按钮
@onready var back_btn: Button = $BackButton
## 兵种解锁按钮
@onready var unlock_btn: Button = $UnlockButton
## 成就按钮
@onready var achievements_btn: Button = $AchievementsButton
## 肉鸽模式按钮
@onready var random_mode_btn: Button = $RandomModeButton

## 路径曲线
var _path_curve: Curve2D = Curve2D.new()
## 当前打开的难度选择对话框引用
var _difficulty_dialog: AcceptDialog = null
## 当前选中的关卡编号
var _selected_level: int = 1
## 关卡标记控件列表
var _level_markers: Array[Control] = []
## #12：开发者模式自定义难度提示文本，key="关卡_难度"，value=提示字符串（持久化到 user://）
var _diff_tips: Dictionary = {}
## #12：难度提示持久化路径
const DIFF_TIPS_PATH: String = "user://campaign_diff_tips.cfg"

func _ready() -> void:
	_setup_path_curve()
	_setup_buttons()
	_apply_localization()
	_create_level_markers()
	map_area.draw.connect(_on_map_area_draw)
	map_area.queue_redraw()
	## #需求10：左上角太阳位置添加透明点击按钮，点击解锁隐藏成就「日夜交替」
	_setup_sun_button()
	## #25：顶部导航栏收纳原右上角散落按钮
	_build_top_navbar()
	## #12：加载开发者自定义难度提示
	_load_diff_tips()
	## #10：「获得胜利」走 mark_difficulty_completed，首通信号只 emit 一次，
	## 在这里接收信号弹解锁弹窗——重复点「获得胜利」不会重复弹窗
	CampaignProgress.level_first_cleared.connect(_on_level_first_cleared)
	## #新需求：肉鸽模式入口属开发者工具，仅 DevMode 显示——初始化显隐并监听切换
	DevMode.dev_mode_changed.connect(_apply_dev_gating)
	_apply_dev_gating()

## #新需求：开发者专属入口仅 DevMode 可见（右上角「肉鸽模式」按钮）
## 非开发者模式隐藏按钮，F11 开启后恢复显示
func _apply_dev_gating(_on: bool = false) -> void:
	random_mode_btn.visible = DevMode.enabled

## #12：加载自定义难度提示（无自定义时回落内置默认文本）
func _load_diff_tips() -> void:
	_diff_tips.clear()
	var cfg := ConfigFile.new()
	if cfg.load(DIFF_TIPS_PATH) == OK:
		for key: String in cfg.get_section_keys("tips"):
			_diff_tips[key] = String(cfg.get_value("tips", key, ""))

## #12：读取关卡/难度的提示文本（自定义优先，回落默认）
func _get_diff_tip(level: int, difficulty: int) -> String:
	var key: String = "%d_%d" % [level, difficulty]
	if _diff_tips.has(key) and String(_diff_tips[key]) != "":
		return String(_diff_tips[key])
	match difficulty:
		0: return tr("DIFF_NORMAL_DESC")
		1: return tr("DIFF_HARD_DESC")
		2: return tr("DIFF_HELL_DESC")
	return ""

## #25：构建顶部导航栏，将原右上角垂直排列的按钮（解锁/成就/肉鸽）收纳为横向条
func _build_top_navbar() -> void:
	var navbar := HBoxContainer.new()
	navbar.name = "TopNavBar"
	navbar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	navbar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	navbar.offset_left = -520.0
	navbar.offset_top = 12.0
	navbar.offset_right = -16.0
	navbar.offset_bottom = 88.0
	navbar.add_theme_constant_override("separation", 10)
	add_child(navbar)
	## 按从左到右顺序 reparent（信号连接不受 reparent 影响）
	for btn in [unlock_btn, achievements_btn, random_mode_btn]:
		if btn != null and is_instance_valid(btn):
			btn.reparent(navbar)
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

## 设置按钮样式与事件
func _setup_buttons() -> void:
	UIButtonHelper.setup_button(back_btn)
	## #25：兵种解锁/成就按钮统一为米色羊皮卷纸风格，与详情框/面板保持一致
	UIButtonHelper.setup_parchment_button(unlock_btn)
	UIButtonHelper.setup_parchment_button(achievements_btn)
	UIButtonHelper.setup_button(random_mode_btn)
	## #20：右上角导航按钮放大 ×2，便于触屏点击（尺寸 160×64，字号 26）
	for nav_btn: Button in [unlock_btn, achievements_btn, random_mode_btn]:
		nav_btn.custom_minimum_size = Vector2(160, 64)
		nav_btn.add_theme_font_size_override("font_size", 26)
	back_btn.pressed.connect(_on_back_pressed)
	unlock_btn.pressed.connect(_on_unlock_pressed)
	achievements_btn.pressed.connect(_on_achievements_pressed)
	random_mode_btn.pressed.connect(_on_random_mode_pressed)

## 应用本地化文本
func _apply_localization() -> void:
	title_label.text = tr("CAMPAIGN_TITLE") if tr("CAMPAIGN_TITLE") != "CAMPAIGN_TITLE" else "战役模式"
	back_btn.text = tr("BACK") if tr("BACK") != "BACK" else "返回主菜单"
	unlock_btn.text = tr("UNIT_UNLOCK") if tr("UNIT_UNLOCK") != "UNIT_UNLOCK" else "兵种解锁"
	achievements_btn.text = tr("ACHIEVEMENTS") if tr("ACHIEVEMENTS") != "ACHIEVEMENTS" else "成就"
	random_mode_btn.text = tr("ROGUELIKE_MODE") if tr("ROGUELIKE_MODE") != "ROGUELIKE_MODE" else "肉鸽模式"

## 设置蜿蜒路径曲线
func _setup_path_curve() -> void:
	_path_curve.clear_points()
	_path_curve.add_point(Vector2(80, 500), Vector2(0, -40), Vector2(50, -20))
	_path_curve.add_point(Vector2(240, 430), Vector2(-60, 10), Vector2(40, -10))
	_path_curve.add_point(Vector2(220, 330), Vector2(30, 40), Vector2(-30, 50))
	_path_curve.add_point(Vector2(360, 280), Vector2(-40, 40), Vector2(40, -20))
	_path_curve.add_point(Vector2(500, 390), Vector2(-30, -40), Vector2(30, 20))
	_path_curve.add_point(Vector2(640, 300), Vector2(-20, 30), Vector2(30, -20))
	_path_curve.add_point(Vector2(780, 410), Vector2(-20, -30), Vector2(30, 10))
	_path_curve.add_point(Vector2(920, 250), Vector2(-30, 30), Vector2(30, -30))
	_path_curve.add_point(Vector2(1060, 360), Vector2(-30, -20), Vector2(20, 20))
	_path_curve.add_point(Vector2(1120, 180), Vector2(-30, 30), Vector2(0, -30))
	_path_curve.add_point(Vector2(1120, 100), Vector2(-20, 20), Vector2(0, 0))

## 地图区域绘制回调
func _on_map_area_draw() -> void:
	_draw_decorations()
	_draw_path()

## 绘制路径（带描边）
func _draw_path() -> void:
	var points := _path_curve.get_baked_points()
	if points.size() < 2:
		return
	
	## 底层描边，增加立体感
	map_area.draw_polyline(points, PATH_OUTLINE_COLOR, PATH_OUTLINE_WIDTH, true)
	## 主路径
	map_area.draw_polyline(points, PATH_COLOR, PATH_WIDTH, true)
	
	## 沿路径绘制小圆点装饰
	var length := _path_curve.get_baked_length()
	var step := 24.0
	var t := step
	while t < length - step:
		var pos := _path_curve.sample_baked(t)
		map_area.draw_circle(pos, 4.0, Color(0.48, 0.32, 0.18, 0.8))
		t += step

## 绘制地图装饰：太阳、云朵、山脉、河流、城堡、起始点
func _draw_decorations() -> void:
	_draw_sun(Vector2(80, 60))
	_draw_cloud(Vector2(220, 80), 1.0)
	_draw_cloud(Vector2(520, 50), 0.8)
	_draw_cloud(Vector2(920, 90), 1.1)
	_draw_mountains()
	_draw_river()
	_draw_castle(Vector2(1120, 70))
	_draw_start_point(Vector2(80, 500))

## 绘制太阳
func _draw_sun(pos: Vector2) -> void:
	map_area.draw_circle(pos, 36.0, Color(1.0, 0.85, 0.35, 0.9))
	map_area.draw_circle(pos, 28.0, Color(1.0, 0.92, 0.55, 0.95))
	## 光芒
	var ray_count := 10
	for i in range(ray_count):
		var angle := (TAU / ray_count) * i
		var inner := pos + Vector2.from_angle(angle) * 42.0
		var outer := pos + Vector2.from_angle(angle) * 58.0
		map_area.draw_line(inner, outer, Color(1.0, 0.85, 0.35, 0.7), 3.0, true)

## #需求10：在太阳（80,60）位置放置透明点击按钮，点击解锁隐藏成就「日夜交替」
## 按钮完全透明、比太阳大一圈，不影响地图其余交互；解锁逻辑复用 Achievements.unlock_by_id
func _setup_sun_button() -> void:
	var btn := Button.new()
	btn.name = "SunButton"
	btn.text = ""  ## 无文字，纯透明点击区
	btn.flat = true  ## 无背景
	btn.modulate = Color(1, 1, 1, 0.0)  ## 完全透明
	## 定位到太阳位置（太阳中心 80,60，光芒半径 58，按钮取 130x130 覆盖）
	btn.position = Vector2(80.0 - 65.0, 60.0 - 65.0)
	btn.size = Vector2(130, 130)
	btn.tooltip_text = ""
	## 点击解锁隐藏成就「日夜交替」（已解锁时 unlock_by_id 内部去重，不重复弹窗）
	btn.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
		Achievements.unlock_by_id("day_night")
	)
	map_area.add_child(btn)

## 绘制云朵（由多个重叠圆组成）
func _draw_cloud(pos: Vector2, cloud_scale: float) -> void:
	var color := Color(1.0, 1.0, 1.0, 0.75)
	map_area.draw_circle(pos + Vector2(0, 0) * cloud_scale, 30.0 * cloud_scale, color)
	map_area.draw_circle(pos + Vector2(20, 5) * cloud_scale, 25.0 * cloud_scale, color)
	map_area.draw_circle(pos + Vector2(-20, 8) * cloud_scale, 22.0 * cloud_scale, color)

## 绘制山脉
func _draw_mountains() -> void:
	var mountain_color := Color(0.55, 0.42, 0.30, 0.85)
	var peaks := [
		[Vector2(180, 180), Vector2(260, 80), Vector2(340, 180)],
		[Vector2(280, 200), Vector2(360, 100), Vector2(440, 200)],
		[Vector2(780, 160), Vector2(860, 60), Vector2(940, 160)],
	]
	for peak in peaks:
		var pts := PackedVector2Array([peak[0], peak[1], peak[2]])
		map_area.draw_colored_polygon(pts, mountain_color)

## 绘制河流
func _draw_river() -> void:
	var river_points := PackedVector2Array([
		Vector2(1000, 520),
		Vector2(940, 460),
		Vector2(860, 480),
		Vector2(760, 440),
		Vector2(620, 480),
		Vector2(520, 440),
	])
	map_area.draw_polyline(river_points, Color(0.45, 0.65, 0.85, 0.7), 14.0, true)
	map_area.draw_polyline(river_points, Color(0.6, 0.78, 0.92, 0.5), 8.0, true)

## 绘制城堡
func _draw_castle(pos: Vector2) -> void:
	var wall_color := Color(0.65, 0.62, 0.58, 1.0)
	var roof_color := Color(0.55, 0.25, 0.20, 1.0)
	var dark := Color(0.35, 0.32, 0.30, 1.0)
	
	## 主墙体
	map_area.draw_rect(Rect2(pos + Vector2(-50, -20), Vector2(100, 50)), wall_color, true)
	map_area.draw_rect(Rect2(pos + Vector2(-50, -20), Vector2(100, 50)), dark, false, 2.0)
	
	## 左塔
	map_area.draw_rect(Rect2(pos + Vector2(-70, -50), Vector2(30, 80)), wall_color, true)
	map_area.draw_rect(Rect2(pos + Vector2(-70, -50), Vector2(30, 80)), dark, false, 2.0)
	var left_roof := PackedVector2Array([
		pos + Vector2(-75, -50),
		pos + Vector2(-55, -80),
		pos + Vector2(-35, -50)
	])
	map_area.draw_colored_polygon(left_roof, roof_color)
	
	## 右塔
	map_area.draw_rect(Rect2(pos + Vector2(40, -50), Vector2(30, 80)), wall_color, true)
	map_area.draw_rect(Rect2(pos + Vector2(40, -50), Vector2(30, 80)), dark, false, 2.0)
	var right_roof := PackedVector2Array([
		pos + Vector2(35, -50),
		pos + Vector2(55, -80),
		pos + Vector2(75, -50)
	])
	map_area.draw_colored_polygon(right_roof, roof_color)
	
	## 中央高塔
	map_area.draw_rect(Rect2(pos + Vector2(-20, -70), Vector2(40, 100)), wall_color, true)
	map_area.draw_rect(Rect2(pos + Vector2(-20, -70), Vector2(40, 100)), dark, false, 2.0)
	var center_roof := PackedVector2Array([
		pos + Vector2(-25, -70),
		pos + Vector2(0, -105),
		pos + Vector2(25, -70)
	])
	map_area.draw_colored_polygon(center_roof, roof_color)
	
	## 城门
	map_area.draw_rect(Rect2(pos + Vector2(-12, 0), Vector2(24, 30)), dark, true)
	map_area.draw_arc(pos + Vector2(0, 0), 12.0, PI, TAU, 16, dark, 2.0, true)

## 绘制起始点
func _draw_start_point(pos: Vector2) -> void:
	map_area.draw_circle(pos, 20.0, Color(0.35, 0.22, 0.12, 0.9))
	map_area.draw_circle(pos, 14.0, Color(0.85, 0.78, 0.60, 1.0))

## 创建关卡标记
func _create_level_markers() -> void:
	## 清空已有标记
	for marker in _level_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_level_markers.clear()
	
	var unlocked_level: int = CampaignProgress.get_unlocked_level()
	var length := _path_curve.get_baked_length()
	
	for i in range(LEVEL_COUNT):
		var level: int = i + 1
		var t: float = LEVEL_PROGRESS[i] * length
		var pos: Vector2 = _path_curve.sample_baked(t)
		var marker := _create_level_marker(level, pos, level <= unlocked_level)
		map_area.add_child(marker)
		_level_markers.append(marker)

## 创建单个关卡标记容器
func _create_level_marker(level: int, pos: Vector2, is_unlocked: bool) -> Control:
	var star_count: int = CampaignProgress.get_star_count(level)
	var is_perfect: bool = star_count == DIFFICULTIES.size()
	var is_boss: bool = level in CampaignProgress.BOSS_LEVELS
	
	var btn_top: float = 0.0
	if is_boss:
		btn_top = BOSS_LABEL_H
	
	var marker := Control.new()
	marker.name = "LevelMarker_%d" % level
	marker.custom_minimum_size = Vector2(MARKER_SIZE, MARKER_SIZE + STAR_SIZE + 4 + btn_top)
	marker.position = pos - Vector2(MARKER_SIZE / 2.0, btn_top + MARKER_SIZE / 2.0)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	## BOSS 关卡：在按钮上方加红色「BOSS」提示标签
	if is_boss:
		var boss_label := Label.new()
		boss_label.name = "BossLabel"
		boss_label.text = tr("CAMPAIGN_BOSS")
		boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		boss_label.add_theme_font_size_override("font_size", 13)
		boss_label.add_theme_color_override("font_color", BOSS_COLOR)
		boss_label.custom_minimum_size = Vector2(MARKER_SIZE, BOSS_LABEL_H)
		boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(boss_label)
	
	var btn := Button.new()
	btn.name = "LevelButton"
	btn.custom_minimum_size = Vector2(MARKER_SIZE, MARKER_SIZE)
	btn.position = Vector2(0.0, btn_top)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.text = str(level)
	btn.disabled = not is_unlocked
	_setup_marker_button_style(btn, is_unlocked, is_perfect, is_boss)
	btn.pressed.connect(_on_level_pressed.bind(level))
	marker.add_child(btn)
	
	## 已解锁时添加悬停动画
	if is_unlocked:
		btn.mouse_entered.connect(func():
			if is_instance_valid(btn):
				btn.modulate = Color(1.2, 1.15, 1.05)
				btn.scale = Vector2(1.12, 1.12)
				btn.pivot_offset = Vector2(MARKER_SIZE / 2.0, MARKER_SIZE / 2.0)
		)
		btn.mouse_exited.connect(func():
			if is_instance_valid(btn):
				btn.modulate = Color.WHITE
				btn.scale = Vector2(1.0, 1.0)
		)
	else:
		btn.text = ""
		## 未解锁显示锁图标
		var lock := Label.new()
		lock.text = "🔒"
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock.add_theme_font_size_override("font_size", 22)
		lock.anchors_preset = Control.PRESET_FULL_RECT
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(lock)
	
	## 星星行
	var star_row := HBoxContainer.new()
	star_row.name = "Stars"
	star_row.position = Vector2((MARKER_SIZE - STAR_SIZE * 3) / 2.0, btn_top + MARKER_SIZE + 2)
	star_row.custom_minimum_size = Vector2(STAR_SIZE * 3, STAR_SIZE)
	star_row.add_theme_constant_override("separation", 0)
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(star_row)
	
	for star_i in range(DIFFICULTIES.size()):
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", int(STAR_SIZE))
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star.custom_minimum_size = Vector2(STAR_SIZE, STAR_SIZE)
		if star_i < star_count:
			star.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
		else:
			star.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 0.5))
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_row.add_child(star)
	
	return marker

## 设置关卡按钮样式
func _setup_marker_button_style(btn: Button, is_unlocked: bool, is_perfect: bool, is_boss: bool = false) -> void:
	var bg_normal: Color
	var bg_hover: Color
	var border_color: Color
	var font_color: Color
	
	if not is_unlocked:
		bg_normal = Color(0.25, 0.23, 0.20, 0.9)
		bg_hover = bg_normal
		border_color = Color(0.4, 0.38, 0.35, 0.8)
		font_color = Color(0.55, 0.52, 0.48, 0.8)
	elif is_boss:
		bg_normal = Color(0.6, 0.2, 0.2, 1.0)
		bg_hover = Color(0.78, 0.3, 0.28, 1.0)
		border_color = BOSS_COLOR
		font_color = Color(1.0, 0.92, 0.88, 1.0)
	elif is_perfect:
		bg_normal = Color(0.95, 0.82, 0.45, 1.0)
		bg_hover = Color(1.0, 0.9, 0.55, 1.0)
		border_color = Color(0.75, 0.55, 0.1, 1.0)
		font_color = Color(0.35, 0.22, 0.08, 1.0)
	else:
		bg_normal = Color(0.88, 0.79, 0.62, 1.0)
		bg_hover = Color(0.98, 0.89, 0.72, 1.0)
		border_color = Color(0.55, 0.35, 0.2, 1.0)
		font_color = Color(0.35, 0.22, 0.12, 1.0)
	
	var normal := _make_round_style(bg_normal, border_color)
	var hover := _make_round_style(bg_hover, Color(border_color.r * 1.2, border_color.g * 1.2, border_color.b * 1.2, 1.0))
	var pressed := _make_round_style(Color(bg_hover.r * 0.9, bg_hover.g * 0.9, bg_hover.b * 0.9, 1.0), border_color)
	var disabled := _make_round_style(bg_normal, border_color)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)
	
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_disabled_color", font_color)

## 创建圆形样式盒
func _make_round_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(MARKER_RADIUS))
	style.set_content_margin_all(0)
	return style

## 关卡按钮点击回调
func _on_level_pressed(level: int) -> void:
	AudioManager.play_ui_click()
	_show_difficulty_dialog(level)

## 显示难度选择对话框
func _show_difficulty_dialog(level: int) -> void:
	_selected_level = level
	if _difficulty_dialog != null and is_instance_valid(_difficulty_dialog):
		_difficulty_dialog.queue_free()
		_difficulty_dialog = null
	
	_difficulty_dialog = AcceptDialog.new()
	_difficulty_dialog.title = tr("CAMPAIGN_SELECT_DIFF") % level
	_difficulty_dialog.dialog_text = ""
	_difficulty_dialog.ok_button_text = tr("CAMPAIGN_CANCEL")
	add_child(_difficulty_dialog)
	UIButtonHelper.setup_wood_panel(_difficulty_dialog)
	
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", 8)
	_difficulty_dialog.add_child(vbox)

	var unlocked_diff: int = CampaignProgress.get_unlocked_difficulty(level)

	for i in range(DIFFICULTIES.size()):
		var diff_name: String = tr(DIFFICULTIES[i][0])
		var diff_color: Color = DIFFICULTIES[i][1]
		var is_diff_unlocked: bool = i <= unlocked_diff
		var is_diff_completed: bool = CampaignProgress.is_difficulty_completed(level, i)

		## 每个难度一行：左侧难度按钮，右侧「获得胜利」快捷通关按钮（#10）
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var btn := Button.new()
		var btn_text: String = diff_name
		if is_diff_completed:
			btn_text += " ✓"
		if not is_diff_unlocked:
			btn_text = "🔒 " + btn_text
		btn.text = btn_text
		btn.custom_minimum_size = Vector2(170, 40)
		btn.disabled = not is_diff_unlocked
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIButtonHelper.setup_button(btn)
		## #12：难度提示支持开发者模式自定义编辑，悬停显示 tooltip（Godot 4 无 tooltip_delay 属性，
		## 延迟用引擎默认值，已删除 Godot 3 遗留的 tooltip_delay 赋值，避免运行时 Invalid assignment）
		btn.tooltip_text = _get_diff_tip(level, i)
		if not is_diff_unlocked:
			btn.tooltip_text = tr("CAMPAIGN_LOCKED_HINT")

		if is_diff_completed:
			btn.modulate = Color(0.6, 1.0, 0.6)
		elif is_diff_unlocked:
			btn.modulate = diff_color
		else:
			btn.modulate = Color(0.5, 0.5, 0.5)

		btn.pressed.connect(func():
			## #需求20：难度按钮点击直接开战（原 #12 的开发者模式「编辑难度提示」弹框已删除）
			_close_difficulty_dialog_and_start(i)
		)
		row.add_child(btn)

		## #10：「获得胜利」按钮——点击直接以该难度通关本关（完整首通流程：
		## 战功/星/解锁/成就检查全部走 CampaignProgress.mark_difficulty_completed）
		## #新需求：快捷通关属开发者工具，仅 DevMode 显示
		var win_btn := Button.new()
		win_btn.text = tr("CAMPAIGN_VICTORY")
		win_btn.custom_minimum_size = Vector2(110, 40)
		win_btn.disabled = not is_diff_unlocked
		win_btn.visible = DevMode.enabled
		UIButtonHelper.setup_button(win_btn)
		win_btn.modulate = Color(0.9, 0.9, 0.9)
		win_btn.pressed.connect(func():
			AudioManager.play_ui_click()
			_close_difficulty_dialog()
			CampaignProgress.mark_difficulty_completed(level, i)
			## 首通弹窗由 level_first_cleared 信号驱动（见 _on_level_first_cleared），
			## 这里不再手动调用，避免重复点「获得胜利」重复弹窗
			refresh_levels()
		)
		row.add_child(win_btn)

	_difficulty_dialog.popup_centered()

## 关闭难度选择对话框（不清空引用）
func _close_difficulty_dialog() -> void:
	if _difficulty_dialog != null and is_instance_valid(_difficulty_dialog):
		_difficulty_dialog.hide()
		_difficulty_dialog.queue_free()
		_difficulty_dialog = null

## 关闭难度对话框并启动战斗（难度按钮正常点击路径）
func _close_difficulty_dialog_and_start(difficulty: int) -> void:
	## 先禁用对话框内所有按钮输入，避免场景跳转延迟窗口内误触发（与结算界面同款防护）
	## 注：按钮嵌在 vbox > row(HBox) 层级，需用 find_children 递归查找而非 get_children()
	for b in _difficulty_dialog.find_children("*", "Button", true, false):
		if is_instance_valid(b):
			b.set_process_input(false)
			b.set_process_unhandled_input(false)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.disabled = true
	_close_difficulty_dialog()
	_on_difficulty_selected(difficulty)

## #10：「获得胜利」快捷通关后的首通弹窗——由 level_first_cleared 信号驱动，
## 该信号只在 mark_difficulty_completed 首次标记某关时 emit 一次，杜绝重复弹窗
func _on_level_first_cleared(level: int, unlocked_unit_id: String) -> void:
	if unlocked_unit_id == "":
		return
	## 查找兵种显示名
	var display_name: String = unlocked_unit_id
	for res in UnitDatabase.unit_list:
		if res.unit_id == unlocked_unit_id:
			display_name = res.get_display_name()
			break
	## #19（2026-08-11）：弹窗实现上移 UIButtonHelper.show_unit_unlock_popup 共享，
	## 战功购买解锁（unit_unlock_window）弹同一款确认框，不再维护两份代码。
	UIButtonHelper.show_unit_unlock_popup(self, display_name, unlocked_unit_id)

## 难度选择回调
func _on_difficulty_selected(difficulty: int) -> void:
	GameManager.is_campaign_mode = true
	GameManager.selected_campaign_level = _selected_level
	GameManager.start_game(difficulty)

## 返回按钮回调
func _on_back_pressed() -> void:
	AudioManager.play_ui_click()
	GameManager.is_campaign_mode = false
	GameManager.return_to_menu()

## #11（2026-08-11）：打开战役地图内的子窗口（兵种解锁 / 成就）时统一套一层暗色遮罩，
## 窗口设为 borderless + unresizable + 固定居中，不可拖动；关闭窗口时遮罩同步释放。
## 遮罩挂在 campaign_map 上（窗口的同级），挡住下层点击；窗口与遮罩一并居中。
func _open_map_window(window: Window) -> void:
	AudioManager.play_ui_click()
	window.borderless = true
	window.unresizable = true
	add_child(window)
	window.popup_centered()
	## 暗色半透明遮罩：盖住下层战役地图，拦截点击（MOUSE_FILTER_STOP）
	var backdrop := ColorRect.new()
	backdrop.name = "_WindowBackdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	## 窗口关闭时释放遮罩（避免遮罩残留挡住地图交互）
	window.close_requested.connect(backdrop.queue_free)
	window.tree_exiting.connect(backdrop.queue_free)

## 兵种解锁按钮回调
func _on_unlock_pressed() -> void:
	var window := load("res://scenes/ui/unit_unlock_window.tscn").instantiate() as Window
	_open_map_window(window)

## 成就按钮回调（打开成就展示窗口，位于「兵种解锁」按钮下方）
func _on_achievements_pressed() -> void:
	var window := load("res://scenes/ui/achievements_window.tscn").instantiate() as Window
	_open_map_window(window)

## 肉鸽模式按钮回调（位于「成就」按钮下方）
## 开启一次全新的肉鸽 run：兵种以卡牌形式出场，无水晶基地，目标是清光所有敌军
func _on_random_mode_pressed() -> void:
	AudioManager.play_ui_click()
	## 肉鸽模式与战役/双人模式互斥，先关掉其它模式标志
	GameManager.is_campaign_mode = false
	BattleManager.is_two_player = false
	## 先弹出英雄选择界面，选完英雄才能开局（#208）
	_open_hero_select()

## 打开肉鸽英雄选择界面；确认后由界面回调负责 start_run + 进入地图
func _open_hero_select() -> void:
	var hero_select := RoguelikeHeroSelect.new()
	add_child(hero_select)
	hero_select.hero_confirmed.connect(_on_hero_confirmed)

## 英雄选择确认：拿到英雄 ID，开启 run 并进入地图总控台
func _on_hero_confirmed(hero_id: String) -> void:
	RoguelikeManager.start_run(hero_id)
	GameManager.enter_roguelike_map()

## 刷新关卡标记（通关后调用）
func refresh_levels() -> void:
	_create_level_markers()
	map_area.queue_redraw()
