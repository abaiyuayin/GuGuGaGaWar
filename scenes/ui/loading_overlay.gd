extends CanvasLayer
## 加载提示框（2026-08-18 新增；2026-08-19 改为「每次切换都弹框」+ 暖米色风格同步）
## 场景切换时异步加载并显示居中提示框，框内自上而下分三部分：
##   ① 标题：随机提示词  ② 中部：随机兵种动画  ③ 底部：加载进度条（独立小框）
## 进入竞技场/战场模式时跳过（加载极快无需等待）；
## MIN_SHOW_MS 保证提示框至少停留 500ms 不闪而过，加载完成淡出。
## 风格与局内兵种详情弹框统一：暖米色底 + 深棕边框 + 圆角。
## 用法：GameManager.change_scene_with_loading("res://scenes/xxx.tscn")
## 注：本节点由 GameManager 在 _ready 时动态挂载（autoload 单例不可在项目设置静态声明为场景外的覆盖层，
## 故采用运行时 add_child 方式，保证任何场景切换前都存在）。

const TIPS: Array[String] = [
	"正在搬运曲奇中",
	"正在搬运橘子中",
	"正在藏运曲奇",
	"正在给橘子浇水",
	"神秘企鹅入侵中",
]

## 遮罩根控件（全屏半透明）
var _root: Control = null
## 兵种动画显示控件（TextureRect，受 CenterContainer 布局约束，局限在提示框下半部分）
var _anim_tex: TextureRect = null
## 加载进度条（第三部分，动画下方独立小框内）
var _bar: ProgressBar = null
## 进度条高度（px）
const BAR_HEIGHT: int = 14
## 伪进度爬升上限与速率：ResourceLoader 无精确百分比，故平滑模拟到 90% 等待，加载完成置 100%
const PROGRESS_CAP: float = 90.0
const PROGRESS_SPEED: float = 60.0
## 对象池预热阶段占用的进度区间（预热由实际完成数驱动，不再用伪进度）
const PREWARM_PROGRESS_START: float = 40.0
const PREWARM_PROGRESS_END: float = 95.0
## 是否处于对象池预热阶段（此期间 _process 不再推进伪进度，交由预热回调驱动）
var _prewarming: bool = false
## 当前伪进度值（0-100）
var _progress: float = 0.0
## 当前动画 SpriteFrames 与播放状态（手动切帧）
var _anim_frames: SpriteFrames = null
var _anim_name: String = ""
var _anim_frame: int = 0
var _anim_timer: float = 0.0
## 当前是否正在加载
var _loading: bool = false
## 记录待加载路径（由 GameManager.show_loading 设置）
var _pending_path: String = ""
## 提示框显示时刻（ms，用于最小展示时长，避免「一闪而过」）
var _shown_at_ms: int = 0
## 提示框最小展示时长（ms）：一旦弹出至少停留这么久再淡出
const MIN_SHOW_MS: int = 500

func _ready() -> void:
	layer = 100  ## 最高层，盖住一切 UI
	_root = Control.new()
	_root.name = "LoadingOverlay"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	## 全屏透明拦截层（防连点；不遮画面，视觉上不占屏）
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	## 居中容器（全屏），提示框水平垂直居中于屏幕
	var center := CenterContainer.new()
	center.name = "CenterBox"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	## 居中提示框（暖米色风格，与兵种详情弹框统一）
	var panel := PanelContainer.new()
	panel.name = "LoadingPanel"
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.93, 0.86, 0.70, 0.98)
	panel_style.border_color = Color(0.35, 0.25, 0.13, 1.0)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 20.0
	panel_style.content_margin_right = 20.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	## 上下两半的容器（VBox，框内垂直排列；宽度减半以匹配紧凑提示框）
	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.custom_minimum_size = Vector2(250, 0)
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	## 第一部分（标题）：随机提示词（水平垂直居中，深棕文字）
	var tip := Label.new()
	tip.name = "TipLabel"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.35, 0.12, 0.08, 1.0))
	vbox.add_child(tip)
	tip.set_meta("tip_label", tip)

	## 第二部分（动画）：兵种动画容器（固定高度，动画水平垂直居中、局限在框内）
	var anim_box := CenterContainer.new()
	anim_box.custom_minimum_size = Vector2(0, 220)
	vbox.add_child(anim_box)
	_anim_tex = TextureRect.new()
	_anim_tex.name = "AnimTexture"
	_anim_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_anim_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_anim_tex.custom_minimum_size = Vector2(250, 230)
	_anim_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anim_box.add_child(_anim_tex)

	## 第三部分：进度条区域（动画下方独立长方形小框，与提示框同风格）
	var bar_panel := PanelContainer.new()
	bar_panel.name = "BarPanel"
	var bar_panel_style := StyleBoxFlat.new()
	bar_panel_style.bg_color = Color(0.88, 0.80, 0.63, 1.0)
	bar_panel_style.border_color = Color(0.35, 0.25, 0.13, 1.0)
	bar_panel_style.set_border_width_all(2)
	bar_panel_style.set_corner_radius_all(6)
	bar_panel_style.content_margin_left = 6.0
	bar_panel_style.content_margin_right = 6.0
	bar_panel_style.content_margin_top = 5.0
	bar_panel_style.content_margin_bottom = 5.0
	bar_panel.add_theme_stylebox_override("panel", bar_panel_style)
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_panel)

	## 进度条本体（不显示百分比数字，仅看填充长度）
	_bar = ProgressBar.new()
	_bar.name = "LoadProgressBar"
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.72, 0.62, 0.45, 1.0)
	bar_bg.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.45, 0.30, 0.15, 1.0)
	bar_fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	bar_panel.add_child(_bar)

func show_loading(scene_path: String) -> void:
	## 已在加载则忽略（防连点）
	if _loading:
		return
	## 进入竞技场/战场模式时直接切换，不弹加载框（加载 ~89ms 极快，无需等待）
	## 注意：该路径也需要预热对象池，但不显示进度（切场景后由 battlefield 自行受益于缓存）
	if "battlefield_mode" in scene_path:
		get_tree().change_scene_to_file(scene_path)
		BattleManager.prewarm_unit_pool()
		return
	_loading = true
	_pending_path = scene_path
	## 回战役地图时清空对象池：下一关敌方编成可能不同，需重新预热
	## （2026-08-19 对象池改造；clear_unit_pool 同时重置 is_pool_prewarmed 幂等标志）
	if "campaign_map" in scene_path or "main_menu" in scene_path:
		BattleManager.clear_unit_pool()
	## 异步加载，并立即显示居中提示框（每次切换都弹框；MIN_SHOW_MS 保证至少停留 500ms 不闪而过）
	ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	_show_overlay()
	_await_scene_loaded()

## 若本次切换目标是战斗场景，则在加载框显示期间串行预热对象池
## （2026-08-19 对象池改造，用户拍板：进入局内时先读双方兵种→去重→按价格升序→逐个添加）
## 预热期间接管进度条：从当前伪进度推进到 PREWARM_PROGRESS_END，避免条卡住不动。
func _prewarm_pool_if_battle() -> void:
	if not _is_battle_scene(_pending_path):
		return
	## 预热接管进度：停止伪进度爬升，改由实际完成数驱动
	_prewarming = true
	var base: float = maxf(_progress, PREWARM_PROGRESS_START)
	await BattleManager.prewarm_unit_pool(func(done: int, total: int) -> void:
		if _bar == null or total <= 0:
			return
		var ratio: float = float(done) / float(total)
		_progress = base + (PREWARM_PROGRESS_END - base) * ratio
		_bar.value = _progress
	)
	_prewarming = false

## 判断目标场景是否为需要预热对象池的战斗场景
func _is_battle_scene(scene_path: String) -> bool:
	return "battle_root" in scene_path or "battlefield_mode" in scene_path

## 显示居中提示框（随机提示词 + 兵种动画 + 进度条归零）
func _show_overlay() -> void:
	var tip: Label = _root.get_node_or_null("CenterBox/LoadingPanel/VBoxContainer/TipLabel") as Label
	if tip != null:
		tip.text = TIPS[randi() % TIPS.size()]
	_play_random_unit_anim()
	_progress = 0.0
	_prewarming = false
	if _bar != null:
		_bar.value = 0.0
	_root.visible = true
	_shown_at_ms = Time.get_ticks_msec()

## 加载完成，切换场景（不弹框路径）
func _do_switch() -> void:
	var packed: PackedScene = ResourceLoader.load_threaded_get(_pending_path)
	_pending_path = ""
	get_tree().change_scene_to_packed(packed)
	_loading = false

## 随机选一个兵种的行走/奔跑动画（walk > move > attack），加载帧序列并开始播放
func _play_random_unit_anim() -> void:
	_anim_frames = null
	_anim_tex.texture = null
	var units = UnitDatabase.unit_list
	if units.is_empty():
		return
	var res = units[randi() % units.size()]
	var unit_id: String = res.unit_id if "unit_id" in res else ""
	if unit_id.is_empty():
		return
	for anim_name in ["walk", "move", "attack"]:
		var path := "res://resources/units/%s/%s_frames.tres" % [unit_id, anim_name]
		if not ResourceLoader.exists(path):
			continue
		var frames: SpriteFrames = load(path)
		## 帧数为 0 或加载失败时继续试下一个动画（原先在此直接 return，
		## 导致「文件存在但无有效帧」时只显示静态首帧甚至对 null 取值报错）
		if frames == null or frames.get_frame_count(anim_name) <= 0:
			continue
		_anim_frames = frames
		_anim_name = anim_name
		_anim_frame = 0
		_anim_timer = 0.0
		_anim_tex.texture = frames.get_frame_texture(anim_name, 0)
		return

## 每帧驱动进度条爬升 + TextureRect 手动切帧（TextureRect 不受 AnimatedSprite2D 播放控制）
func _process(delta: float) -> void:
	if not _root.visible:
		return
	## 伪进度平滑爬升到 PROGRESS_CAP 后等待真实加载完成（置 100 见 _await_scene_loaded）
	## 放在动画判断之前：没有可用动画的兵种进度条也要正常走
	## 预热阶段（_prewarming）由 prewarm_unit_pool 回调按实际完成数驱动，此处不再推进
	if _bar != null and not _prewarming and _progress < PROGRESS_CAP:
		_progress = minf(_progress + PROGRESS_SPEED * delta, PROGRESS_CAP)
		_bar.value = _progress
	if _anim_frames == null:
		return
	var count: int = _anim_frames.get_frame_count(_anim_name)
	if count <= 1:
		return
	var fps: float = _anim_frames.get_animation_speed(_anim_name)
	if fps <= 0.0:
		return
	_anim_timer += delta
	if _anim_timer >= 1.0 / fps:
		_anim_timer = 0.0
		_anim_frame = (_anim_frame + 1) % count
		_anim_tex.texture = _anim_frames.get_frame_texture(_anim_name, _anim_frame)

## 轮询异步加载结果，完成后切换场景并淡出遮罩
func _await_scene_loaded() -> void:
	if _pending_path.is_empty():
		_hide_overlay()
		return
	var st: int = ResourceLoader.load_threaded_get_status(_pending_path)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		## 场景资源就绪 → 若目标是战斗场景，先在加载框内串行预热对象池
		## （2026-08-19 对象池改造：进局前按价格升序逐个建实例，替代出兵时才创建）
		await _prewarm_pool_if_battle()
		## 再把进度条走满 100%（在停顿之前，保证「走满」肉眼可见）
		_progress = 100.0
		if _bar != null:
			_bar.value = 100.0
		## 加载完成后额外停留 0.5s（"走满100%"的停顿），再切场景并淡出
		await get_tree().create_timer(0.5).timeout
		_do_switch()
		_hide_overlay()
	elif st == ResourceLoader.THREAD_LOAD_FAILED:
		_pending_path = ""
		_hide_overlay()
	else:
		## 仍在加载：帧循环等
		await get_tree().process_frame
		_await_scene_loaded()

## 淡出遮罩（保证至少展示 MIN_SHOW_MS，避免一闪而过）
func _hide_overlay() -> void:
	## 若提示框刚弹出就加载完成（如 battle_root 765ms），补足最小展示时长再淡出
	var elapsed := Time.get_ticks_msec() - _shown_at_ms
	if elapsed < MIN_SHOW_MS:
		await get_tree().create_timer((MIN_SHOW_MS - elapsed) / 1000.0).timeout
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		_root.visible = false
		_root.modulate.a = 1.0
		_loading = false
	)
