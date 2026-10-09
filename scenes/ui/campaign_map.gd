extends Control
## 战役地图 UI（2026-10-04 美术化改造）
## 整张手绘地图底图（assets/ui/campaign/campaign_bg.png，道路/城堡/装饰已画进图里），
## 关卡标记 / 强敌徽章 / 星星 / 太阳 / 标题横幅全部走贴图，旧 draw_* 程序装饰已删除。
## Curve2D 不再绘制，仅作隐形对位工具：锚点贴合底图道路，按弧长放置 10 个关卡标记。
## 点击已解锁关卡弹出难度选择，通关进度由 CampaignProgress 单例管理。

## 总关卡数量
const LEVEL_COUNT: int = 10
## 难度定义：难度编号 -> [显示名 tr-key, 颜色]
const DIFFICULTIES: Array = [
	["DIFF_NAME_NORMAL", Color(0.35, 0.8, 0.4)],  ## 0=普通，绿色
	["DIFF_NAME_HARD", Color(1.0, 0.84, 0.35)],  ## 1=困难，金色
	["DIFF_NAME_HELL", Color(0.9, 0.35, 0.3)],  ## 2=地狱，红色
]

## 美术素材（assets/ui/campaign/，均开 mipmap）
const ART_DIR: String = "res://assets/ui/campaign/"
const TEX_MARKER_UNLOCKED: String = ART_DIR + "marker_unlocked.png"
const TEX_MARKER_LOCKED: String = ART_DIR + "marker_locked.png"
const TEX_MARKER_BOSS: String = ART_DIR + "marker_boss.png"
const TEX_MARKER_PERFECT: String = ART_DIR + "marker_perfect.png"
const TEX_BOSS_BADGE: String = ART_DIR + "boss_badge.png"
const TEX_STAR_ON: String = ART_DIR + "star_on.png"
const TEX_STAR_OFF: String = ART_DIR + "star_off.png"
const TEX_SUN: String = ART_DIR + "sun.png"
const TEX_BANNER: String = ART_DIR + "banner_title.png"
## 未锁定难度按钮的挂锁图标（与成就窗未解锁徽章同款：木牌+锁链+挂锁）
const TEX_LOCK_BADGE: String = ART_DIR + "ach_badge_locked.png"

## 关卡标记显示尺寸（素材画布 128×160，含顶部旗杆）
const MARKER_W: float = 58.0
const MARKER_H: float = 72.0
## 数字在标记贴图上的相对高度（木牌圆心位置）
const MARKER_NUM_REL_Y: float = 0.61
const STAR_SIZE: float = 14.0
## 强敌（BOSS 关）徽章尺寸，替换原红色「BOSS」文本标签
const BOSS_BADGE_SIZE: float = 40.0
const BOSS_COLOR: Color = Color(1.0, 0.35, 0.3, 1.0)

## 关卡在路径上的位置进度（0~1，按弧长）——均匀分布（2026-10-04 按底图实测重调）
const LEVEL_PROGRESS: Array[float] = [
	0.03, 0.134, 0.239, 0.343, 0.448,
	0.552, 0.657, 0.761, 0.866, 0.97
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

## 路径曲线（隐形对位工具，不绘制）
var _path_curve: Curve2D = Curve2D.new()
## 当前打开的难度选择对话框引用
var _difficulty_dialog: Window = null
## 当前选中的关卡编号
var _selected_level: int = 1
## 关卡标记控件列表
var _level_markers: Array[Control] = []
## #12：开发者模式自定义难度提示文本，key="关卡_难度"，value=提示字符串（持久化到 user://）
var _diff_tips: Dictionary = {}
## #12：难度提示持久化路径
const DIFF_TIPS_PATH: String = "user://campaign_diff_tips.cfg"

## 开发者拖拽布局（2026-10-04）：DevMode 下可直接拖动关卡标记微调位置，
## 松手即保存到 user://campaign_marker_layout.cfg；
## 该文件存在时（任何模式）优先使用保存的位置，不存在回落 Curve2D 默认布局。
const MARKER_LAYOUT_PATH: String = "user://campaign_marker_layout.cfg"
## level:int -> Vector2（map_area 局部坐标）
var _saved_marker_pos: Dictionary = {}
## 拖拽进行中的关卡编号（-1 = 未拖拽）
var _drag_level: int = -1
## 拖拽中的标记节点
var _drag_marker: Control = null
## 拖拽抓取偏移（鼠标到标记原点的距离）
var _drag_offset: Vector2 = Vector2.ZERO
## 本次拖拽是否真的移动过（区分「拖完松手」与「原地点击」）
var _drag_moved: bool = false

func _ready() -> void:
	_setup_path_curve()
	_setup_buttons()
	_apply_localization()
	_build_title_banner()
	_setup_sun_sprite()
	## 开发者拖拽布局：先读保存位置再建标记
	_load_marker_layout()
	_create_level_markers()
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
	## 开发者开关切换时重建标记，实时挂载/卸载拖拽布局功能
	refresh_levels()

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
	## 子节点靠右对齐：非开发者模式隐藏「肉鸽」按钮后，剩余按钮仍贴右缘
	navbar.alignment = BoxContainer.ALIGNMENT_END
	## 按从左到右顺序 reparent（信号连接不受 reparent 影响）
	for btn in [unlock_btn, achievements_btn, random_mode_btn]:
		if btn != null and is_instance_valid(btn):
			btn.reparent(navbar)
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

## 设置按钮样式与事件
func _setup_buttons() -> void:
	UIButtonHelper.setup_detail_frame_button(back_btn)
	for nav_btn: Button in [unlock_btn, achievements_btn, random_mode_btn]:
		UIButtonHelper.setup_topbar_button(nav_btn, Color(1, 1, 1, 1), UIButtonHelper.TEX_BUTTON_TOPBAR_3)

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

## 设置路径曲线（隐形对位工具）：锚点按底图网格实测路面坐标（2026-10-04 重调，
## 与 _artgen/layout_check.py 合成验证一致）：村庄 → 沿底部沙路 → 木桥 → 营地 → 城堡门口
func _setup_path_curve() -> void:
	_path_curve.clear_points()
	_path_curve.add_point(Vector2(212, 654), Vector2(0, 0), Vector2(55, -10))
	_path_curve.add_point(Vector2(333, 633), Vector2(-55, 10), Vector2(50, -5))
	_path_curve.add_point(Vector2(442, 621), Vector2(-45, 5), Vector2(40, -8))
	_path_curve.add_point(Vector2(517, 604), Vector2(-38, 8), Vector2(35, -25))
	_path_curve.add_point(Vector2(583, 557), Vector2(-33, 24), Vector2(40, -30))
	_path_curve.add_point(Vector2(663, 496), Vector2(-40, 30), Vector2(35, -21))
	_path_curve.add_point(Vector2(733, 454), Vector2(-35, 21), Vector2(40, -20))
	_path_curve.add_point(Vector2(813, 413), Vector2(-40, 20), Vector2(35, -19))
	_path_curve.add_point(Vector2(883, 375), Vector2(-35, 19), Vector2(30, -31))
	_path_curve.add_point(Vector2(942, 313), Vector2(-30, 31), Vector2(4, -50))
	_path_curve.add_point(Vector2(950, 213), Vector2(0, -45), Vector2(0, 0))

## 标题横幅：羊皮纸卷轴贴图 + 原标题 Label 叠加（本地化不变）
func _build_title_banner() -> void:
	var banner := TextureRect.new()
	banner.name = "TitleBanner"
	banner.texture = load(TEX_BANNER)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -105.0
	banner.offset_right = 105.0
	banner.offset_top = 6.0
	banner.offset_bottom = 104.0
	## 标题随横幅缩小一半（36 → 30，横幅 210×98）
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.reparent(banner)
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 1.0
	title_label.offset_left = 0.0
	title_label.offset_top = 0.0
	title_label.offset_right = 0.0
	title_label.offset_bottom = 0.0
	title_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_label.grow_vertical = Control.GROW_DIRECTION_BOTH

## 左上角太阳贴图（隐藏成就「日夜交替」的视觉锚点）
func _setup_sun_sprite() -> void:
	var sun := TextureRect.new()
	sun.name = "SunSprite"
	sun.texture = load(TEX_SUN)
	sun.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun.position = Vector2(32, 12)
	sun.size = Vector2(96, 96)
	map_area.add_child(sun)

## #需求10：在太阳（80,60）位置放置透明点击按钮，点击解锁隐藏成就「日夜交替」
## 按钮完全透明、比太阳大一圈，不影响地图其余交互；解锁逻辑复用 Achievements.unlock_by_id
func _setup_sun_button() -> void:
	var btn := Button.new()
	btn.name = "SunButton"
	btn.text = ""  ## 无文字，纯透明点击区
	btn.flat = true  ## 无背景
	btn.modulate = Color(1, 1, 1, 0.0)  ## 完全透明
	## 定位到太阳位置（太阳中心 80,60，按钮取 130x130 覆盖）
	btn.position = Vector2(80.0 - 65.0, 60.0 - 65.0)
	btn.size = Vector2(130, 130)
	btn.tooltip_text = ""
	## 点击解锁隐藏成就「日夜交替」（已解锁时 unlock_by_id 内部去重，不重复弹窗）
	btn.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
		Achievements.unlock_by_id("day_night")
	)
	map_area.add_child(btn)

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
		## 开发者拖拽保存过的位置优先（文件不存在回落曲线默认）
		if _saved_marker_pos.has(level):
			pos = _saved_marker_pos[level]
		var marker := _create_level_marker(level, pos, level <= unlocked_level)
		map_area.add_child(marker)
		_level_markers.append(marker)

## 按状态选标记贴图：锁定 > 强敌 > 金色全通 > 普通已解锁
func _marker_texture_path(is_unlocked: bool, is_perfect: bool, is_boss: bool) -> String:
	if not is_unlocked:
		return TEX_MARKER_LOCKED
	if is_boss:
		return TEX_MARKER_BOSS
	if is_perfect:
		return TEX_MARKER_PERFECT
	return TEX_MARKER_UNLOCKED

## 创建单个关卡标记容器（贴图版：TextureButton + 数字 + 星星行 + 强敌徽章）
func _create_level_marker(level: int, pos: Vector2, is_unlocked: bool) -> Control:
	var star_count: int = CampaignProgress.get_star_count(level)
	var is_perfect: bool = star_count == DIFFICULTIES.size()
	var is_boss: bool = level in CampaignProgress.BOSS_LEVELS

	var btn_top: float = 0.0
	if is_boss and is_unlocked:
		btn_top = BOSS_BADGE_SIZE
	var total_h: float = btn_top + MARKER_H + STAR_SIZE + 4.0

	var marker := Control.new()
	marker.name = "LevelMarker_%d" % level
	marker.custom_minimum_size = Vector2(MARKER_W, total_h)
	marker.position = pos - Vector2(MARKER_W / 2.0, btn_top + MARKER_H / 2.0)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

	## 强敌关：标记上方钉骷髅徽章（替换原红色「BOSS」文本）
	if is_boss and is_unlocked:
		var badge := TextureRect.new()
		badge.name = "BossBadge"
		badge.texture = load(TEX_BOSS_BADGE)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.position = Vector2((MARKER_W - BOSS_BADGE_SIZE) / 2.0, -4.0)
		badge.size = Vector2(BOSS_BADGE_SIZE, BOSS_BADGE_SIZE)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(badge)

	var btn := TextureButton.new()
	btn.name = "LevelButton"
	btn.texture_normal = load(_marker_texture_path(is_unlocked, is_perfect, is_boss))
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(MARKER_W, MARKER_H)
	btn.position = Vector2(0.0, btn_top)
	btn.size = Vector2(MARKER_W, MARKER_H)
	## 开发者布局模式下不锁定按钮：锁定关也要能拖动位置（点击弹难度框无碍，框内难度按钮仍锁定）
	btn.disabled = not is_unlocked and not DevMode.enabled
	btn.pressed.connect(_on_level_pressed.bind(level))
	marker.add_child(btn)

	if DevMode.enabled:
		## 开发者布局工具：按住拖动标记，松手自动保存位置
		btn.button_down.connect(_on_marker_drag_start.bind(level, marker))
		btn.button_up.connect(_on_marker_drag_end.bind(level, marker))

	if is_unlocked:
		## 数字钉在标记木牌圆心（锁定关不显示数字，贴图自带挂锁）
		var num := Label.new()
		num.name = "LevelNum"
		num.text = str(level)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 20)
		var num_color: Color = Color(0.35, 0.22, 0.12, 1.0)
		if is_boss:
			num_color = Color(1.0, 0.92, 0.88, 1.0)
		elif is_perfect:
			num_color = Color(0.35, 0.22, 0.08, 1.0)
		num.add_theme_color_override("font_color", num_color)
		num.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.45))
		num.add_theme_constant_override("shadow_offset_x", 1)
		num.add_theme_constant_override("shadow_offset_y", 1)
		num.position = Vector2(0.0, MARKER_H * MARKER_NUM_REL_Y - 15.0)
		num.size = Vector2(MARKER_W, 30.0)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(num)

		## 已解锁时添加悬停动画
		btn.mouse_entered.connect(func():
			if is_instance_valid(btn):
				btn.modulate = Color(1.2, 1.15, 1.05)
				btn.scale = Vector2(1.12, 1.12)
				btn.pivot_offset = Vector2(MARKER_W / 2.0, MARKER_H / 2.0)
		)
		btn.mouse_exited.connect(func():
			if is_instance_valid(btn):
				btn.modulate = Color.WHITE
				btn.scale = Vector2(1.0, 1.0)
		)

	## 星星行（点亮/灰星贴图）
	var star_row := HBoxContainer.new()
	star_row.name = "Stars"
	star_row.position = Vector2((MARKER_W - STAR_SIZE * 3) / 2.0, btn_top + MARKER_H + 2)
	star_row.custom_minimum_size = Vector2(STAR_SIZE * 3, STAR_SIZE)
	star_row.add_theme_constant_override("separation", 0)
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(star_row)

	var star_on_tex: Texture2D = load(TEX_STAR_ON)
	var star_off_tex: Texture2D = load(TEX_STAR_OFF)
	for star_i in range(DIFFICULTIES.size()):
		var star := TextureRect.new()
		star.texture = star_on_tex if star_i < star_count else star_off_tex
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.custom_minimum_size = Vector2(STAR_SIZE, STAR_SIZE)
		star.size = Vector2(STAR_SIZE, STAR_SIZE)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_row.add_child(star)

	return marker

## —— 开发者拖拽布局 ——
func _on_marker_drag_start(level: int, marker: Control) -> void:
	_drag_level = level
	_drag_marker = marker
	_drag_offset = marker.get_global_mouse_position() - marker.global_position
	_drag_moved = false
	print("[战役地图] 开始拖拽关卡 %d" % level)

func _on_marker_drag_end(_level: int, _marker: Control) -> void:
	## button_up 路径；全局松手兜底见 _input（两者幂等，_finish_drag 内去重）
	_finish_drag()

func _finish_drag() -> void:
	if _drag_level < 0:
		return
	var level := _drag_level
	var marker := _drag_marker
	_drag_level = -1
	_drag_marker = null
	if _drag_moved and marker != null and is_instance_valid(marker):
		## 保存语义 = 标记按钮中心点（与 _create_level_markers 的加载语义一致：
		## 加载时把该值当 pos，容器左上角 = pos - (半宽, 半高)。存左上角会导致每次刷新整体漂移）
		var center := marker.position + Vector2(MARKER_W / 2.0, MARKER_H / 2.0)
		var btn: Control = marker.get_node_or_null("LevelButton")
		if btn != null:
			center = marker.position + btn.position + btn.size / 2.0
		_saved_marker_pos[level] = center
		_save_marker_layout()
		print("[战役地图] 关卡 %d 位置已保存: %s" % [level, center])

func _input(event: InputEvent) -> void:
	if _drag_level < 0 or _drag_marker == null or not is_instance_valid(_drag_marker):
		return
	if event is InputEventMouseMotion:
		var new_pos: Vector2 = _drag_marker.get_global_mouse_position() - _drag_offset
		var max_x: float = map_area.size.x - _drag_marker.size.x
		var max_y: float = map_area.size.y - _drag_marker.size.y
		new_pos.x = clampf(new_pos.x, 8.0, max_x - 8.0)
		new_pos.y = clampf(new_pos.y, 8.0, max_y - 8.0)
		if new_pos.distance_to(_drag_marker.position) > 2.0:
			_drag_moved = true
		_drag_marker.position = new_pos
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		## 全局兜底：左键松开必结束拖拽，不依赖 button_up 是否触发
		_finish_drag()

## 读取开发者保存的标记布局（无文件 = 使用 Curve2D 默认布局）
func _load_marker_layout() -> void:
	_saved_marker_pos.clear()
	var cfg := ConfigFile.new()
	if cfg.load(MARKER_LAYOUT_PATH) != OK:
		return
	for level in range(1, LEVEL_COUNT + 1):
		if not cfg.has_section_key("markers", str(level)):
			continue
		var v: Variant = cfg.get_value("markers", str(level))
		_saved_marker_pos[level] = Vector2(v)
	if not _saved_marker_pos.is_empty():
		print("[战役地图] 已加载保存的关卡布局（%d 项）" % _saved_marker_pos.size())

func _save_marker_layout() -> void:
	var cfg := ConfigFile.new()
	for level: int in _saved_marker_pos:
		cfg.set_value("markers", str(level), _saved_marker_pos[level])
	if cfg.save(MARKER_LAYOUT_PATH) != OK:
		push_error("CampaignMap: 关卡布局写入失败 %s" % MARKER_LAYOUT_PATH)

## 关卡按钮点击回调
func _on_level_pressed(level: int) -> void:
	if _drag_moved:
		## 拖拽结束的松手不当作点击（button_up 先于 pressed 触发，此处能拦住）
		_drag_moved = false
		return
	AudioManager.play_ui_click()
	_show_difficulty_dialog(level)

## 显示难度选择对话框
func _show_difficulty_dialog(level: int) -> void:
	_selected_level = level
	if _difficulty_dialog != null and is_instance_valid(_difficulty_dialog):
		_difficulty_dialog.queue_free()
		_difficulty_dialog = null

	_difficulty_dialog = Window.new()
	_difficulty_dialog.title = ""  ## 标题栏已隐藏，标题改在框内以 Label 呈现
	_difficulty_dialog.unresizable = true
	add_child(_difficulty_dialog)
	## 2026-10-04：难度选择弹窗美术化——羊皮纸九宫格底 + 雕花金边标题牌匾（与成就窗口同套美术）
	## 2026-10-04（晚）：标题同款牌匾后高度 64→72（文案「第 X 关 · 选择难度」较长，牌匾要够宽）
	var vbox := UIButtonHelper.setup_campaign_popup(_difficulty_dialog, tr("CAMPAIGN_SELECT_DIFF") % level, 72.0, 20)
	_difficulty_dialog.close_requested.connect(_close_difficulty_dialog)

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
		btn.text = btn_text
		if not is_diff_unlocked:
			## 2026-10-04：锁定视觉改用挂锁贴图（替换原「锁 」文字前缀）
			## icon_disabled_color 默认 50% 透明，会把挂锁洗白——覆盖为不透明（文字仍走置灰字色）
			btn.icon = load(TEX_LOCK_BADGE)
			btn.add_theme_constant_override("icon_max_width", 26)
			btn.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 1))
		btn.custom_minimum_size = Vector2(170, 40)
		btn.disabled = not is_diff_unlocked
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		## #5（2026-08-26）：难度模式按钮统一为「兵种详情框」同款米色描边样式。
		## 难度区分改用字色（原 modulate 会把米色底整体染色，无法与返回/取消同款）。
		var diff_font: Color = Color(0.35, 0.12, 0.08, 1.0)
		if is_diff_completed:
			diff_font = Color(0.13, 0.42, 0.15, 1.0)
		elif is_diff_unlocked:
			diff_font = diff_color.darkened(0.45)
		else:
			diff_font = Color(0.45, 0.4, 0.35, 1.0)
		UIButtonHelper.setup_detail_frame_button(btn, diff_font)
		## #12：难度提示支持开发者模式自定义编辑，悬停显示 tooltip
		btn.tooltip_text = _get_diff_tip(level, i)
		if not is_diff_unlocked:
			btn.tooltip_text = tr("CAMPAIGN_LOCKED_HINT")

		btn.pressed.connect(func():
			## #需求20：难度按钮点击直接开战
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
		UIButtonHelper.setup_detail_frame_button(win_btn)
		win_btn.modulate = Color(1, 1, 1)
		win_btn.pressed.connect(func():
			AudioManager.play_ui_click()
			_close_difficulty_dialog()
			CampaignProgress.mark_difficulty_completed(level, i)
			## 首通弹窗由 level_first_cleared 信号驱动（见 _on_level_first_cleared），
			## 这里不再手动调用，避免重复点「获得胜利」重复弹窗
			refresh_levels()
		)
		row.add_child(win_btn)

	## 底部「取消」按钮（原 AcceptDialog ok 按钮改为框内自建，样式与内容按钮统一）
	var btn_cancel := Button.new()
	btn_cancel.text = tr("CAMPAIGN_CANCEL")
	btn_cancel.custom_minimum_size = Vector2(150, 42)
	btn_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UIButtonHelper.setup_dialog_action_button(btn_cancel)
	btn_cancel.pressed.connect(_close_difficulty_dialog)
	vbox.add_child(btn_cancel)

	_difficulty_dialog.size = Vector2i(360, 340)
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

## 打开肉鸽英雄选择界面；确认后由界面回调负责 start_run + 进入地图。
## 界面同时承载「继续上次征程」（读档）与进阶难度选择。
func _open_hero_select() -> void:
	var hero_select := RoguelikeHeroSelect.new()
	add_child(hero_select)
	hero_select.hero_confirmed.connect(_on_hero_confirmed)
	hero_select.continue_run_requested.connect(_on_roguelike_continue_requested)

## 英雄选择确认：拿到英雄 ID 与进阶等级，开启 run 并进入地图总控台
func _on_hero_confirmed(hero_id: String, ascension: int) -> void:
	RoguelikeManager.start_run(hero_id, ascension)
	GameManager.enter_roguelike_map()

## 继续上次征程：读档成功才切到 hub；存档损坏时留在战役地图并提示
func _on_roguelike_continue_requested() -> void:
	if not RoguelikeManager.load_run():
		push_warning("CampaignMap: 肉鸽存档读取失败，已忽略")
		return
	GameManager.enter_roguelike_map()

## 刷新关卡标记（通关后调用）
func refresh_levels() -> void:
	_create_level_markers()
