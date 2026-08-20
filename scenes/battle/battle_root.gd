extends Node2D
## 战斗根场景脚本
## 管理摄像机移动（Q/E/方向键 + 右键拖动）、滚轮缩放、信号连接

@onready var battlefield: Node2D = $Battlefield
@onready var camera: Camera2D = $Battlefield/Camera2D
@onready var hud: CanvasLayer = $HUD
@onready var ai_controller: Node = $AIController

## 摄像机移动速度（像素/秒）
const CAMERA_SPEED: float = 600.0
## 摄像机缩放范围下限基准（运行时根据视口动态调整）
const CAMERA_ZOOM_MIN_BASE: float = 0.9
## 摄像机最大缩放值
const CAMERA_ZOOM_MAX: float = 4.0
## 滚轮缩放速度系数
const ZOOM_SPEED: float = 0.15
## 战场边界（与 battlefield.tscn 一致，Background 贴图 1312×736）
const MAP_LEFT: float = -656.0
const MAP_RIGHT: float = 656.0
const MAP_TOP: float = -368.0
const MAP_BOTTOM: float = 368.0

## 肉鸽模式专用 HUD 场景与波次导演脚本（仅肉鸽模式下实例化）
const ROGUELIKE_HUD_SCENE := preload("res://scenes/ui/roguelike_hud.tscn")

## 运行时最小缩放值（根据窗口尺寸动态计算，确保地图始终填满视口）
var camera_zoom_min: float = CAMERA_ZOOM_MIN_BASE

## 右键拖动状态：是否正在拖动
var _is_dragging: bool = false
## 右键拖动上一帧的鼠标位置（用于计算位移）
var _drag_last_pos: Vector2 = Vector2.ZERO

## 调试开关：是否显示红蓝判定框（F3 切换）
## 红框=攻击判定框，蓝框=受击框
var _show_hitboxes: bool = false
## 锁定跟随的单位（左键点击单位后锁定，null 表示未锁定）
var _locked_unit: Unit = null
## 点击锁定阈值（世界坐标像素），点击此距离内的单位会锁定
const CLICK_LOCK_THRESHOLD: float = 40.0
## 选中红圈节点（显示在锁定单位脚下）
var _selection_circle: Sprite2D = null

## 玩家基地上一帧血量，用于计算累计受创（成就：无伤）
var _prev_player_base_hp: int = -1

## —— ESC 呼出设置 ——
## 语义：点按 ESC 打开设置界面并暂停游戏，再次按下（或关闭设置）恢复游戏。
## 旧的「长按 ESC 暂停 / 松开恢复」已按需求移除（#186）。
## 之所以能在暂停期间继续检测按键，是因为本节点 process_mode = PROCESS_MODE_ALWAYS，
## 而战场子树被显式改回 PAUSABLE（见 _ready），暂停语义不会被污染。
## ESC 上一帧按下状态（自行做边沿检测，暂停期间 InputMap 的 just_pressed 不可靠）
var _esc_was_pressed: bool = false
## 空格上一帧按下状态（自行做边沿检测，暂停期间 InputMap 的 just_pressed 不可靠）
var _space_was_pressed: bool = false

## 本场战斗战绩（成就系统数据源），含安全默认值避免帧更新访问空键
var _battle_stats: Dictionary = {
	winner_team = -1,
	elapsed = 0.0,
	player_units_lost = 0,
	enemy_units_killed = 0,
	player_base_damage_taken = 0,
	level = 1,
	difficulty = 1,
	is_campaign = false,
}

func _ready() -> void:
	## 根节点设为始终处理，确保游戏结束后（paused）摄像机仍可拖动/缩放
	## 注意：子节点默认 INHERIT，会连带继承「永不暂停」——必须把战场子树显式改回
	## PAUSABLE，否则 get_tree().paused = true 对单位完全无效（结算后单位仍在互殴）
	process_mode = Node.PROCESS_MODE_ALWAYS
	## 战场（单位/基地/投射物）随暂停冻结：结算与暂停菜单期间不得继续战斗
	battlefield.process_mode = Node.PROCESS_MODE_PAUSABLE
	## 摄像机自身不受暂停影响，保证结算后仍可自由观察战场
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	## 根据视口尺寸计算最小缩放，确保地图（1200x600）始终填满视口
	_update_min_zoom()
	## 摄像机初始位置 = 战场中心，初始缩放 = 最小缩放（能看到全图）
	camera.position = Vector2(0, 0)
	camera.zoom = Vector2(camera_zoom_min, camera_zoom_min)
	## 监听窗口尺寸变化，重新计算最小缩放
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	## 移动端触屏输入层：安卓/iOS 导出时自动启用，桌面可在设置里手动开（便于测试）
	if SettingsManager.is_touch_input():
		_setup_mobile_overlay()

	## 创建选中红圈（添加到战场节点下，坐标与世界一致）
	_selection_circle = Sprite2D.new()
	_selection_circle.texture = _create_circle_texture()
	_selection_circle.scale = Vector2(0.35, 0.35)
	_selection_circle.visible = false
	battlefield.add_child(_selection_circle)

	## 双人模式禁用 AI 控制器；肉鸽模式敌军由波次导演统一刷新，同样不需要金币 AI
	if BattleManager.is_two_player or RoguelikeManager.is_active:
		ai_controller.queue_free()
		ai_controller = null
	else:
		## AI 同样必须随暂停冻结，否则结算后 AI 还在继续买兵
		ai_controller.process_mode = Node.PROCESS_MODE_PAUSABLE

	## 连接信号
	battlefield.base_destroyed.connect(_on_base_destroyed)
	battlefield.base_hp_changed.connect(_on_base_hp_changed)
	BattleManager.unit_spawned.connect(_on_unit_spawned)
	BattleManager.game_over.connect(_on_game_over)
	BattleManager.selection_changed.connect(_on_selection_changed)
	## 开发工具：扣除敌方/我方水晶血量（转发给 battlefield）
	BattleManager.dev_base_damage_requested.connect(_on_dev_base_damage_requested)
	BattleManager.dev_base_boost_requested.connect(_on_dev_base_boost_requested)
	## #4（2026-08-11）：异象入侵/特殊事件单位生成后镜头自动聚焦数秒
	BattleManager.event_unit_focus_requested.connect(_on_event_unit_focus_requested)
	## 战内设置变更（如伤害飘字开关）实时同步到正在进行的战斗
	SettingsManager.settings_changed.connect(_on_settings_changed)
	## #15（2026-08-09）：开发者模式下进入战斗即默认开启兵种攻击距离显示，
	## 不必先打开开发工具菜单（hud 菜单里仍是切换开关，幂等无副作用）
	if DevMode.enabled:
		Unit.show_attack_ranges = true

	## 初始化本场战绩（成就系统数据源），在开战前读取当前关卡/难度/模式
	_battle_stats.level = GameManager.selected_campaign_level
	_battle_stats.difficulty = GameManager.current_difficulty
	_battle_stats.is_campaign = GameManager.is_campaign_mode

	## #需求12：骑士精神判定数据源 —— 每局开始时清空本局部署兵种集合
	Achievements.reset_deployed_units()

	BattleManager.start_battle()
	## #6：战斗开始清零 HUD 总计时，避免「再来一局」累加上一局用时
	hud.reset_battle_elapsed()
	## 强制刷新 HUD 经济/人口显示（#151）：
	## 场景切换后，子节点 HUD._ready 早于 battle_root._ready 的 start_battle() 执行，
	## 此刻 HUD 读到的是上一局残留的金币/人口/收入；reset() 不会主动发信号，
	## 这里在 start_battle()（已 reset）之后显式刷新一次，确保「再来一局」后数值立即归零。
	hud._update_gold_display(0, EconomyManager.get_gold(0), EconomyManager.get_income(0))
	hud._update_gold_display(1, EconomyManager.get_gold(1), EconomyManager.get_income(1))
	hud._update_population_display()
	## 肉鸽模式下实例化专用 HUD 与波次导演（常规战役/双人流程完全不受影响）
	if RoguelikeManager.is_active:
		_setup_roguelike()
	## 播放战斗背景音乐（根据设置选择默认或自定义BGM）
	AudioManager.play_battle_bgm()

## 生成选中单位脚下的椭圆环纹理（战场模式全局生效：红圈改为脚下椭圆）
func _create_circle_texture() -> Texture2D:
	var w := 96
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	var rx := cx - 4.0
	var ry := cy - 4.0
	var ring_width := 5.0
	for y in range(h):
		for x in range(w):
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - 1.0) < ring_width / maxf(rx, ry):
				var alpha: float = 1.0 - absf(d - 1.0) / (ring_width / maxf(rx, ry))
				img.set_pixel(x, y, Color(1.0, 0.15, 0.15, alpha))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	## 游戏结束后（paused）仍允许摄像机拖动/缩放，但跳过暂停和单位锁定逻辑
	var game_ended: bool = not BattleManager.is_battle_active
	## 暂停输入统一在此处理（放在最前，避免下方 locked_unit 分支 return 导致漏检）
	_update_pause_input(delta, game_ended)
	## 战斗进行中累计用时（成就：速通/闪击/无伤）
	## 暂停期间不计时：ESC 呼出设置暂停时，逻辑与计时同步冻结
	if not game_ended and not BattleManager.is_paused:
		_battle_stats.elapsed += delta
	## 使用物理按键直接检测，避免输入法或 InputMap 事件丢失导致 Q/E 无效
	var move_dir: float = 0.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		move_dir -= 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_dir += 1.0

	if move_dir != 0.0:
		## 键盘手动移动时解除锁定跟随
		_unlock_camera()
		camera.position.x += move_dir * CAMERA_SPEED * delta
	elif not game_ended and _locked_unit != null and is_instance_valid(_locked_unit) and not _locked_unit.is_dead:
		## 锁定单位时摄像机跟随单位移动（游戏结束后不再跟随）
		## 直接设置 global_position，镜头中心对准单位（场景中已禁用 smoothing）
		camera.global_position = _locked_unit.global_position
		## 钳制摄像机位置，避免看到地图外区域
		_clamp_camera()
		## 更新红圈位置到单位脚下（椭圆标记偏移到脚下 +12px）
		if _selection_circle:
			_selection_circle.global_position = _locked_unit.global_position + Vector2(0.0, 12.0)
		return
	elif _locked_unit != null:
		## 锁定单位已失效（死亡或销毁），自动解锁
		_unlock_camera()

	## 根据缩放动态钳制摄像机位置，确保视口不超出地图边界
	_clamp_camera()

## 暂停输入：空格点按切换暂停；ESC 点按呼出设置界面（并暂停游戏）
## 暂停的具体开关由 HUD.toggle_settings_pause() 内部负责，保证「设置开=暂停、设置关=恢复」严格配对
## game_ended 为 true 时不响应任何暂停输入，并清空边沿检测状态
func _update_pause_input(_delta: float, game_ended: bool) -> void:
	if game_ended:
		_esc_was_pressed = false
		_space_was_pressed = false
		return

	## —— 空格：边沿触发的切换式暂停 ——
	var space_now: bool = Input.is_physical_key_pressed(KEY_SPACE)
	if space_now and not _space_was_pressed:
		BattleManager.toggle_pause()
	_space_was_pressed = space_now

	## —— ESC：边沿触发，打开/关闭设置界面（#186/#18）——
	## #18：AcceptDialog 在 input 阶段会消费 ESC（canceled → 关闭），本节点是 PROCESS_MODE_ALWAYS，
	## process 阶段轮询到同一 ESC 边沿时，若此时设置刚被关掉（can_toggle_settings 返回 false），
	## 不再调用 toggle_settings_pause，避免「按一次 ESC 设置关了又立刻重开」。
	## #11（2026-08-09）：编辑提示文本/帮助等其他弹窗打开时，ESC 由该弹窗自己消费（关闭弹窗），
	## battle_root 不得抢同一按键去呼出设置并暂停游戏——否则编辑过程中按 ESC 会「关弹窗 + 开设置 + 暂停」三连。
	var esc_now: bool = Input.is_physical_key_pressed(KEY_ESCAPE)
	if esc_now and not _esc_was_pressed:
		var other_dialog_open: bool = _any_dialog_open()
		var settings_open: bool = hud != null and is_instance_valid(hud) \
				and hud.has_method("is_settings_open") and hud.is_settings_open()
		if other_dialog_open and not settings_open:
			pass  ## 其他弹窗独占 ESC（关闭自身），本流程跳过
		elif hud != null and is_instance_valid(hud) and hud.has_method("can_toggle_settings"):
			if hud.can_toggle_settings():
				hud.toggle_settings_pause()
		else:
			## 旧 HUD（无 can_toggle_settings）兜底：仅设置未打开时切换，避免双重关闭
			if hud != null and is_instance_valid(hud) and hud.has_method("toggle_settings_pause") \
					and not (hud.has_method("is_settings_open") and hud.is_settings_open()):
				hud.toggle_settings_pause()
	_esc_was_pressed = esc_now

## #11（2026-08-09）：场景内是否有「除设置对话框以外」的弹窗（AcceptDialog / ConfirmationDialog / PopupMenu）打开。
## 这些弹窗都会消费 ESC 关闭自身，battle_root 若同时响应同一 ESC 会误开设置并暂停游戏。
## 返回 true 表示 ESC 应由弹窗独占处理。
func _any_dialog_open() -> bool:
	var main_window: Window = get_window()
	var root_window: Window = get_tree().root
	for w: Window in root_window.find_children("*", "Window", true, false):
		if w == null or w == root_window or w == main_window:
			continue
		if w is Window and w.visible:
			return true
	return false

## 根据视口尺寸动态计算最小缩放，确保地图（水晶间距 1152px）完全可见
func _update_min_zoom() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	## 水晶间距 = 576*2 = 1152px，确保能看到完整宽度
	var map_width: float = 1152.0
	## 地图高度（Background 贴图高度 736px，铺满屏幕）
	var map_height: float = 736.0
	## 缩放为此值时，地图宽度/高度刚好填满视口
	var zoom_by_w: float = viewport_size.x / map_width
	var zoom_by_h: float = viewport_size.y / map_height
	## 取较小值确保地图完全可见（不裁剪水晶），允许另一方向有少量灰边由背景图覆盖
	camera_zoom_min = maxf(CAMERA_ZOOM_MIN_BASE, minf(zoom_by_w, zoom_by_h))

## 窗口尺寸变化时重新计算最小缩放，并确保当前缩放不越界
func _on_viewport_size_changed() -> void:
	var old_zoom: float = camera.zoom.x
	_update_min_zoom()
	## 若当前缩放小于新的最小值，提升到最小值
	if camera.zoom.x < camera_zoom_min:
		camera.zoom = Vector2(camera_zoom_min, camera_zoom_min)
	_clamp_camera()

## 根据当前缩放钳制摄像机位置，确保视口不显示地图外的区域
func _clamp_camera() -> void:
	var zoom_val: float = camera.zoom.x
	## 视口实际尺寸（像素），用真实窗口尺寸而非硬编码
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	## 视口可见半宽/半高（世界坐标）
	var half_view_w: float = viewport_size.x / zoom_val * 0.5
	var half_view_h: float = viewport_size.y / zoom_val * 0.5
	## 摄像机中心活动范围：地图边界减去视口半宽/半高
	var min_x: float = MAP_LEFT + half_view_w
	var max_x: float = MAP_RIGHT - half_view_w
	var min_y: float = MAP_TOP + half_view_h
	var max_y: float = MAP_BOTTOM - half_view_h
	## 若地图比视口小，退化为居中
	if min_x > max_x:
		camera.position.x = (MAP_LEFT + MAP_RIGHT) * 0.5
	else:
		camera.position.x = clampf(camera.position.x, min_x, max_x)
	if min_y > max_y:
		camera.position.y = (MAP_TOP + MAP_BOTTOM) * 0.5
	else:
		camera.position.y = clampf(camera.position.y, min_y, max_y)

## 移动端触屏输入层：实例化 CanvasLayer 叠加层并接入当前相机
## 仅在 SettingsManager.is_touch_input() 为 true 时由 _ready 调用
func _setup_mobile_overlay() -> void:
	var overlay: CanvasLayer = load("res://scenes/ui/mobile_input_overlay.gd").new()
	add_child(overlay)  ## 作为子节点，随本场景一起释放
	overlay.setup(self, camera)

func _input(event: InputEvent) -> void:
	## 游戏结束后仍允许摄像机拖动/缩放，但跳过单位锁定
	var game_ended: bool = not BattleManager.is_battle_active

	## F3 切换红蓝判定框显示
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed:
		_show_hitboxes = not _show_hitboxes
		Unit.show_hitboxes = _show_hitboxes
		## 触发所有单位的重绘
		var unit_container = battlefield.get_node_or_null("UnitContainer")
		if unit_container:
			for unit in unit_container.get_children():
				if unit is Unit:
					unit.queue_redraw()
		print("[调试] 红蓝判定框显示: ", "开" if _show_hitboxes else "关")
		return

	## F5 切换全屏 / 窗口模式（复用 SettingsManager，保证与设置面板状态一致并持久化）
	if event is InputEventKey and event.keycode == KEY_F5 and event.pressed:
		var new_mode: int = SettingsManager.WINDOW_MODE_WINDOWED
		if SettingsManager.window_mode != SettingsManager.WINDOW_MODE_FULLSCREEN:
			new_mode = SettingsManager.WINDOW_MODE_FULLSCREEN
		SettingsManager.set_window_mode(new_mode)
		print("[调试] 全屏切换: ", "全屏" if new_mode == SettingsManager.WINDOW_MODE_FULLSCREEN else "窗口")
		return

	## 左键点击：锁定/解锁单位跟随（游戏结束后禁用）
	if not game_ended and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:  ## 按下左键
			_try_lock_unit()  ## 尝试锁定点击位置附近的单位

	## 滚轮事件：若鼠标悬停在 HUD 控件上（如兵种滚动列表），则不处理地图缩放，交给控件处理
	var is_wheel: bool = event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN)
	if is_wheel and _is_mouse_over_hud_control():
		return  ## 鼠标在 HUD 控件上，跳过地图缩放，让控件自己处理滚轮

	## 滚轮向前推（WHEEL_UP）放大画面（固定步长，避免增量失控）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		var new_zoom = camera.zoom.x + ZOOM_SPEED
		camera.zoom = Vector2(clampf(new_zoom, camera_zoom_min, CAMERA_ZOOM_MAX), clampf(new_zoom, camera_zoom_min, CAMERA_ZOOM_MAX))
		_clamp_camera()
	## 滚轮向后拉（WHEEL_DOWN）缩小画面（固定步长，避免减量失控）
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var new_zoom = camera.zoom.x - ZOOM_SPEED
		camera.zoom = Vector2(clampf(new_zoom, camera_zoom_min, CAMERA_ZOOM_MAX), clampf(new_zoom, camera_zoom_min, CAMERA_ZOOM_MAX))

	## 右键拖动地图：按下右键开始拖动，释放停止
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:  ## 按下右键
			_unlock_camera()  ## 右键拖动时解除锁定跟随
			_is_dragging = true  ## 开始拖动
			_drag_last_pos = event.position  ## 记录起始位置
		else:  ## 释放右键
			_is_dragging = false  ## 停止拖动

	## 右键拖动中：根据鼠标移动量平移摄像机
	if event is InputEventMouseMotion and _is_dragging:  ## 如果正在拖动且鼠标移动
		var delta_pos: Vector2 = event.position - _drag_last_pos  ## 计算鼠标位移
		## 鼠标向右移动 = 摄像机向左移动（反向），除以 zoom 是因为缩放后屏幕像素与世界坐标不同步
		var zoom_factor: float = camera.zoom.x  ## 当前缩放值
		camera.position.x -= delta_pos.x / zoom_factor  ## X 方向平移（反向）
		camera.position.y -= delta_pos.y / zoom_factor  ## Y 方向平移（反向）
		_clamp_camera()
		_drag_last_pos = event.position  ## 更新上一帧位置


## 判断鼠标是否悬停在 HUD 的可交互控件上（如兵种滚动列表）
## 用于避免滚轮事件同时触发地图缩放和列表滚动
## 用 gui_get_hovered_control 精确判断鼠标实际悬停的控件，
## 避免旧实现用矩形包含判断把与列表矩形重叠的战场/攻击距离红圈误判为"HUD 上"（#20）
func _is_mouse_over_hud_control() -> bool:
	if hud == null or not is_instance_valid(hud):
		return false
	## 获取鼠标实际悬停的 Control
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	## 向上遍历祖先链：若悬停控件属于 HUD 内某个 ScrollContainer（含其滚动条/子控件），返回 true
	var node: Node = hovered
	while node != null:
		if node is ScrollContainer and hud.is_ancestor_of(node):
			return true
		node = node.get_parent()
	return false

## 尝试锁定鼠标点击位置附近的单位
## 点击单位附近（CLICK_LOCK_THRESHOLD 像素内）则锁定跟随；点击空地则解锁
func _try_lock_unit() -> void:
	## 如果鼠标悬停在信息面板（CanvasLayer layer=1）上，跳过单位锁定
	## 避免点击关闭按钮时同时锁定下方的单位
	## 只检查信息面板，不检查 HUD 其他控件（HUD 在 CanvasLayer layer=0 或更低）
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered != null:
		## 检查是否是信息面板或其子控件（Button/Label等）
		var node = hovered
		while node != null:
			if node is Panel and node.get_parent() is CanvasLayer:
				return  ## 悬停在信息面板上，跳过锁定
			node = node.get_parent()
	## Camera2D 没有 get_global_mouse_position()，用 battlefield（Node2D/CanvasItem）获取鼠标世界坐标
	var world_pos: Vector2 = battlefield.get_global_mouse_position()  ## 获取鼠标世界坐标
	var unit_container = battlefield.get_node_or_null("UnitContainer")  ## 获取单位容器
	if unit_container == null:  ## 如果容器不存在
		_unlock_camera()  ## 解锁
		return
	var nearest_unit: Unit = null  ## 最近的单位
	var nearest_dist: float = CLICK_LOCK_THRESHOLD  ## 阈值距离
	for body in unit_container.get_children():  ## 遍历所有单位
		if not (body is Unit) or not is_instance_valid(body) or body.is_dead:  ## 跳过非单位、已销毁和已死亡
			continue
		var d: float = body.global_position.distance_to(world_pos)  ## 计算距离
		if d < nearest_dist:  ## 如果在阈值内且更近
			nearest_dist = d  ## 更新最近距离
			nearest_unit = body  ## 更新最近单位
	if nearest_unit != null:  ## 如果找到单位
		## 先解锁旧单位（隐藏其信息面板），再锁定新单位，避免多个信息面板同时显示
		if _locked_unit != null and _locked_unit != nearest_unit:
			_unlock_camera()
		_lock_unit(nearest_unit)  ## 锁定
	else:  ## 没有点击到单位
		_unlock_camera()  ## 解锁

## 锁定单位跟随
func _lock_unit(u: Unit) -> void:
	_locked_unit = u  ## 设置锁定单位
	## 显示选中红圈
	if _selection_circle:
		_selection_circle.global_position = u.global_position
		_selection_circle.visible = true
	## 设置该兵种攻击音效为优先（必播放，不受 10 个上限限制）
	if u.unit_resource != null:
		AudioManager.set_priority_unit_id(u.unit_resource.unit_id)
	## 通知单位被选中，显示属性面板
	u.set_selected(true)

## 解锁单位跟随
func _unlock_camera() -> void:
	if _locked_unit != null:  ## 如果当前有锁定
		## 通知单位取消选中，隐藏属性面板
		if is_instance_valid(_locked_unit):
			_locked_unit.set_selected(false)
		AudioManager.set_priority_unit_id("")  ## 清除攻击音效优先
	_locked_unit = null  ## 清空锁定
	## 隐藏选中红圈
	if _selection_circle:
		_selection_circle.visible = false

## #4（2026-08-11）：异象入侵/特殊事件触发时镜头自动聚焦事件单位（数秒后恢复）
## 复用 _lock_unit 的锁定跟随逻辑；超时后仅当镜头仍锁定在该单位上才解锁，
## 不打断玩家在此期间手动锁定的其它单位。聚焦期间单位死亡会自动走 _process 的失效解锁。
func _on_event_unit_focus_requested(unit: Node2D) -> void:
	if unit == null or not is_instance_valid(unit) or not (unit is Unit):
		return
	var focus_unit := unit as Unit
	_lock_unit(focus_unit)
	get_tree().create_timer(EVENT_FOCUS_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(focus_unit) and _locked_unit == focus_unit:
			_unlock_camera()
	)

## 事件单位镜头自动聚焦时长（秒）
const EVENT_FOCUS_DURATION: float = 3.0

func _on_unit_spawned(unit: Node2D, player_id: int) -> void:
	battlefield.add_unit(unit)
	## 连接单位死亡信号，统计战绩（成就系统数据源）
	if unit is Unit:
		## 对象池复用：单位可能已带上次的连接，先断开再连，避免重复连接累积
		## （Godot 4 默认允许同一 Callable 重复连接，复用 N 次则死亡时回调 N 次）
		if unit.unit_died.is_connected(_on_unit_died):
			unit.unit_died.disconnect(_on_unit_died)
		unit.unit_died.connect(_on_unit_died)
		## #需求12：骑士精神 —— 记录玩家（红方 pid=0）本局部署过的兵种
		if player_id == 0:
			Achievements.record_player_deploy(unit.unit_resource.unit_id)
		## #自由事件成就（2026-08-15）：第一次召唤蓝女巫/死亡使者/仓鼠士兵
		## 模式门：开发者模式战役/全面/双人都判定，非开发者仅战役（Achievements 内部拦截）
		var _uid: String = unit.unit_resource.unit_id
		if _uid == "S1":
			Achievements.unlock_by_id_in_mode("blue_witch_summon")
		elif _uid == "Y1":
			Achievements.unlock_by_id_in_mode("death_reaper_summon")
		elif _uid == "S2":
			Achievements.unlock_by_id_in_mode("hamster_summon")

## 设置变更回调：让「伤害飘字」「血量/护盾数值」开关在战斗进行中实时生效
## 默认情况下 unit_base 仅在生成飘字/建条时读取该开关，已存在的显示不会随开关变化消失/出现
func _on_settings_changed() -> void:
	var unit_container = battlefield.get_node_or_null("UnitContainer")
	if unit_container == null:
		return
	var show_nums: bool = SettingsManager.show_damage_numbers
	var show_values: bool = SettingsManager.show_hp_armor_bar
	for unit in unit_container.get_children():
		if is_instance_valid(unit) and unit is Unit:
			## #4：血条/护盾数值 Label 实时显隐（unit_base 已按开关建好标签，这里只切可见性）
			unit.set_hp_armor_value_labels_visible(show_values)
			for child in unit.get_children():
				if is_instance_valid(child) and child is DamageNumber:
					child.visible = show_nums

## 单位死亡回调：统计玩家损失与击杀敌方数量
## 第三参 killer_unit_id 供成就判定（剑术大师等按兵种累计击杀），此处无需按兵种细分，忽略即可
func _on_unit_died(unit: Unit, killer_team: int, _killer_unit_id: String) -> void:
	if unit.team == 0:
		_battle_stats.player_units_lost += 1
	if killer_team == 0:
		_battle_stats.enemy_units_killed += 1
		## #21：实时击杀入账（战役模式累计击杀成就即时判定，双人/全面战争由 Achievements 内部拦截）
		Achievements.record_kill(1)
	## #自由事件成就（2026-08-15）：凑企鹅（Y2）死亡时己方（红方）水晶还存在 → 偏我来时不逢春
	if unit.team == 1 and unit.unit_resource != null and unit.unit_resource.unit_id == "Y2":
		if battlefield != null and battlefield.get_base_hp(0) > 0:
			Achievements.unlock_by_id_in_mode("penguin_sacrifice")

func _on_base_hp_changed(team: int, hp: int, max_hp: int) -> void:
	hud.update_base_hp(team, hp, max_hp)
	## 统计玩家基地累计受创（成就：无伤通关）。team 0 = 玩家红方
	if team == 0:
		if _prev_player_base_hp < 0:
			_prev_player_base_hp = hp
		elif hp < _prev_player_base_hp:
			_battle_stats.player_base_damage_taken += _prev_player_base_hp - hp
			_prev_player_base_hp = hp

## 开发工具：对指定阵营水晶（基地）造成固定伤害（#1 扣除敌方水晶 100 血即传 team=1）
## battlefield.damage_base 会触发 base_hp_changed，成就统计已在上方统一处理
func _on_dev_base_damage_requested(team: int, amount: int) -> void:
	if battlefield != null and battlefield.has_method("damage_base"):
		battlefield.damage_base(team, amount, null)

## 开发工具：对指定阵营水晶直接加血，可超上限（#21）
## battlefield.boost_base_hp 不截断上限，血条按满格显示
func _on_dev_base_boost_requested(team: int, amount: int) -> void:
	if battlefield != null and battlefield.has_method("boost_base_hp"):
		battlefield.boost_base_hp(team, amount)

func _on_base_destroyed(winner_team: int) -> void:
	## #自由事件成就（2026-08-15）：我方（红方，team 0）水晶死亡（游戏结束）时，
	## 场上仍存在存活凑企鹅（Y2）→ 我草了老铁，那本来是属于我的
	if winner_team == 1:
		var _penguin_alive: bool = false
		for u in BattleManager.enemy_units:
			if is_instance_valid(u) and not u.is_dead and u.unit_resource != null and u.unit_resource.unit_id == "Y2":
				_penguin_alive = true
				break
		if _penguin_alive:
			Achievements.unlock_by_id_in_mode("penguin_irony")
	BattleManager.end_game(winner_team)

func _on_selection_changed(_player_id: int, _unit_res: Resource) -> void:
	## 预留：后续如需在战斗场景层处理选兵联动，可在此扩展
	pass

## 肉鸽模式：实例化专用 HUD 与波次导演，并注入战场引用
func _setup_roguelike() -> void:
	var hud_rl := ROGUELIKE_HUD_SCENE.instantiate() as CanvasLayer
	add_child(hud_rl)
	## 手牌 UI 随暂停冻结，避免结算/奖励界面弹出后玩家还能拖卡部署
	hud_rl.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud_rl.setup(battlefield)
	var director := RoguelikeDirector.new() as RoguelikeDirector
	add_child(director)
	## 波次导演随暂停冻结，避免奖励界面打开期间继续刷怪
	director.process_mode = Node.PROCESS_MODE_PAUSABLE
	director.setup(battlefield, hud_rl)

func _on_game_over(winner_team: int) -> void:
	_battle_stats.winner_team = winner_team
	## 解除锁定单位，避免结算后访问已释放单位
	if _locked_unit != null:
		_unlock_camera()
	## 肉鸽模式失败：结算前重置运行态，让结算界面的「重开」能开启新的一局
	var is_roguelike: bool = RoguelikeManager.is_active
	if is_roguelike:
		RoguelikeManager.end_run()
		## 隐藏肉鸽专用 HUD（layer 3），避免其卡牌/波次文本覆盖在结算界面（layer 2）之上
		var rl_hud := get_node_or_null("RoguelikeHUD") as CanvasLayer
		if rl_hud != null and is_instance_valid(rl_hud):
			rl_hud.visible = false
		## 专属肉鸽失败界面（国风羊皮纸），不再复用战役/双人的 game_over_screen
		var defeat := RoguelikeDefeatScreen.new()
		hud.add_child(defeat)
		return
	var scene = load("res://scenes/ui/game_over_screen.tscn")
	var go = scene.instantiate()
	hud.add_child(go)
	go.set_winner(winner_team, _battle_stats, false)
