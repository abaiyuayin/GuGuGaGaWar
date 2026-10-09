extends Node2D
class_name BattlefieldMode
## 战场模式（RTS 沙盒）根控制器
## 设计：无 AI、无胜负、无回合、无水晶的自由布兵沙盘。
## 玩家自由布兵（点选/长按连出/框选网格铺满，无限免费兵），框选已有单位、右键下令移动。

@onready var battlefield: Node2D = $Battlefield
@onready var camera: Camera2D = $Battlefield/Camera2D
@onready var unit_container: Node2D = $Battlefield/UnitContainer
@onready var hud: CanvasLayer = $HUD

## 绘制层（运行时挂到 Battlefield 之下/之上，见 _ready）
var grid_layer: Node2D = null
var ground_layer: Node2D = null   ## 阵营光圈层（单位之下、网格之上）
var selection_layer: Node2D = null
const DRAW_LAYER_SCRIPT := preload("res://scenes/battle/battle_draw_layer.gd")
## #框选（2026-09-04）：框选判定 / 编队移动令 / 攻击锁定令的共享实现（与肉鸽指挥层同源，
## 保证两个模式的指挥手感完全一致）
const UNIT_COMMAND := preload("res://scripts/battle/unit_command.gd")

## ── 竞技场沙盘与摄像机参数 ─────────────────────────────────
const CAMERA_SPEED: float = 600.0
const CAMERA_ZOOM_MIN_BASE: float = 0.55
const CAMERA_ZOOM_MAX: float = 4.0
const ZOOM_SPEED: float = 0.15
const MAP_LEFT: float = Constants.ARENA_BOUNDS.position.x
const MAP_RIGHT: float = Constants.ARENA_BOUNDS.end.x
const MAP_TOP: float = Constants.ARENA_BOUNDS.position.y
const MAP_BOTTOM: float = Constants.ARENA_BOUNDS.end.y
const SAND_TEXTURE := preload("res://assets/backgrounds/arena_sand.png")

## ── 战场交互常量 ────────────────────────────────────────────
const GRID_SIZE: float = 30.0          ## 网格 / 编队偏移间距
const DRAG_THRESHOLD: float = 6.0      ## 左键拖动超过此像素视为框选
const PAN_THRESHOLD: float = 8.0       ## 右键位移低于此像素视为「点按下令」，高于则视为「拖动平移」
const LONG_PRESS_INTERVAL: float = 1.0 ## 左键按住不动每隔 1s 连出 1 兵
const MAX_SPAWN_UNITS: int = 300       ## ponytail 性能护栏：单位总数上限，避免网格铺满卡死
const SEL_ELLIPSE_HALF_W: float = 28.0
const SEL_ELLIPSE_HALF_H: float = 12.0
## 框选命中所需的最小面积占比（2026-08-20 用户拍板：兵种 1/3 区域被框住即算选中）
const SELECT_AREA_RATIO: float = 1.0 / 3.0

var camera_zoom_min: float = CAMERA_ZOOM_MIN_BASE

## 右键拖动平移状态
var _is_panning: bool = false
var _pan_start_pos: Vector2 = Vector2.ZERO
var _pan_last_pos: Vector2 = Vector2.ZERO
var _pan_moved: float = 0.0

## 左键框选 / 出兵状态
var _is_left_down: bool = false
var _left_start_world: Vector2 = Vector2.ZERO
var _left_dragged: bool = false
var _drag_box: Rect2 = Rect2()
var _hold_timer: float = 0.0

## 网格批量出兵：落点入队、按帧分批生成，避免一次框选在单帧同步实例化过多单位导致卡死/闪退
const DEPLOY_BATCH_PER_FRAME: int = 12   ## 每帧最多生成的网格出兵数量
var _pending_deploy_positions: Array[Vector2] = []
var _pending_deploy_res: Array = []
var _pending_deploy_team: Array[int] = []

## 选中单位集合（战场私有，不写 BattleManager.selected_units）
var selected_units: Array[Unit] = []

## F3 红蓝判定框
var _show_hitboxes: bool = false
## 网格显示开关（G 键 / HUD 按钮切换）
var show_grid: bool = true

## 多阵营（阵容控制）：默认仅阵营1，最多4阵营；selected_team 决定出兵/控制归属
const MAX_TEAMS: int = 4
var team_count: int = 1
var selected_team: int = 0
## 和平/战争 + 开战状态：combat_active = 战争模式 且 已开战
var peace_mode: bool = true
var war_started: bool = false

## 右键移动令点击反馈（阵营色椭圆，1 秒渐隐）
const ORDER_MARK_DURATION: float = 1.0
var _order_mark_pos: Vector2 = Vector2.INF
var _order_mark_time: float = 0.0
var _order_mark_team: int = 0
## #框选攻击锁定（2026-09-04）：本次反馈是攻击令（红）还是移动令（阵营色）
var _order_mark_is_attack: bool = false
## 当前全体锁定的敌人：有效期内常驻画红圈，供玩家确认在集火谁
var _attack_lock_target: Unit = null
## 攻击锁定标记配色（红，与阵营色区分开）
const ATTACK_MARK_COLOR: Color = Color(1.0, 0.30, 0.24, 1.0)

## 撤回：每次出兵（单击 1 只 / 一次框选铺兵 N 只）记为一批，可连续撤回多步
var _deploy_batches: Array = []   ## Array[Array]，末尾为最近一批
var _current_batch: Array = []    ## 当前正在填充的批次（框选分帧生成期间持续追加）
var _batch_open: bool = false     ## 批次是否处于「填充中」
const MAX_UNDO_BATCHES: int = 50

func _enter_tree() -> void:
	## F6 直接运行也要在 Battlefield / HUD 的 _ready 之前确定模式。
	GameManager.is_battlefield_mode = true
	GameManager.is_campaign_mode = false

func _ready() -> void:
	## 根节点常驻处理（结算/暂停期间仍可操作；沙盒无暂停但保持与战斗一致）
	process_mode = Node.PROCESS_MODE_ALWAYS
	battlefield.process_mode = Node.PROCESS_MODE_PAUSABLE
	camera.process_mode = Node.PROCESS_MODE_ALWAYS

	## 模式标志（start_battlefield 已置 true，这里再保险一次）
	GameManager.is_battlefield_mode = true
	GameManager.is_campaign_mode = false
	BattleManager.is_two_player = false
	## 重置战斗系统（清 selected_units 等），手动激活、关回合倒计时（永不结算 → 无回合）
	BattleManager.reset()
	_clear_deploy_queue()  ## 清空遗留的批量出兵队列，确保从干净状态开始
	BattleManager.is_battle_active = true
	BattleManager.countdown_timer = 1e12

	## 摄像机初始化
	_setup_arena_map()
	_update_min_zoom()
	camera.position = Vector2(0, 0)
	camera.zoom = Vector2.ONE * maxf(1.0, camera_zoom_min)
	_clamp_camera()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	## 单位生成接线：加入 UnitContainer 并连接死亡；不连 base_destroyed（无胜负）
	BattleManager.unit_spawned.connect(_on_unit_spawned)
	## #性能（2026-08-27）：不再进场就开攻击范围圈。竞技场是 DevMode 专属入口，
	## 旧代码等于「一进沙盒就给每个远程兵每帧画 64 段 draw_arc」，300 兵时纯粹白烧帧。
	## 需要看范围圈时从开发工具菜单「显示兵种攻击距离」手动开（F3 判定框同理，不受影响）。
	Unit.show_attack_ranges = false

	## 创建绘制层：grid 与 ground 插到 UnitContainer 之前（背景之上、单位之下），
	## selection 追加到最后（单位之上）。
	## ground_layer 专画阵营光圈——必须在单位之下，否则光圈盖在贴图上会糊成一片。
	grid_layer = DRAW_LAYER_SCRIPT.new()
	grid_layer.name = "GridLayer"
	ground_layer = DRAW_LAYER_SCRIPT.new()
	ground_layer.name = "GroundLayer"
	selection_layer = DRAW_LAYER_SCRIPT.new()
	selection_layer.name = "SelectionLayer"
	## #25（2026-08-23）：进入战场模式即把 BGM 上下文锁为 "battle"，避免初始化阶段 emit 的
	## settings_changed 按 "menu" 上下文 deferred 播主菜单 BGM 覆盖战斗 BGM。
	AudioManager.set_bgm_context("battle")
	battlefield.add_child(grid_layer)
	battlefield.add_child(ground_layer)
	## 显式排序：把两层依次插到 UnitContainer 之前，最终子节点顺序为
	## [... 背景 ...] GridLayer → GroundLayer → UnitContainer → SelectionLayer
	## 注意每次 move_child 都会改变 UnitContainer 的下标，必须重新取。
	battlefield.move_child(grid_layer, unit_container.get_index())
	battlefield.move_child(ground_layer, unit_container.get_index())
	battlefield.add_child(selection_layer)         ## 追加到末尾（绘制在最上层）
	grid_layer.draw_func = _draw_grid
	ground_layer.draw_func = _draw_team_rings
	selection_layer.draw_func = _draw_selection
	grid_layer.visible = show_grid


	AudioManager.play_battle_bgm()

func _setup_arena_map() -> void:
	## 原背景中部沙地裁片柔边拼接成大贴图，仅替换竞技场实例。
	## 原生镜像重复铺图，不拉伸整张风景，不新增地形系统。
	var background := battlefield.get_node("Background") as Sprite2D
	background.texture = SAND_TEXTURE
	background.scale = Vector2(2.0, 2.0)
	background.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	background.region_enabled = true
	background.region_rect = Rect2(Vector2.ZERO, Constants.ARENA_BOUNDS.size / background.scale)
	background.position = Constants.ARENA_BOUNDS.get_center()
	battlefield.get_node("BGUI").hide()


func _on_unit_spawned(unit: Node2D, _player_id: int) -> void:
	unit_container.add_child(unit)
	## #竞技场（2026-08-24 需求5 撤回）：批次开启期间生成的单位记入当前批
	if _batch_open and unit is Unit and not (unit as Unit).is_base_unit:
		_current_batch.append(unit)
	if unit is Unit:
		## 兵出在哪站哪（默认 hold），敌人进射程才打，符合沙盒「自由放置」预期
		unit.hold_position = not is_combat_active()
		unit.combat_enabled = is_combat_active()
		unit.order_pos = Vector2.INF
		## 对象池复用：先断开旧连接再连，避免死亡回调重复触发
		if unit.unit_died.is_connected(_on_unit_died):
			unit.unit_died.disconnect(_on_unit_died)
		unit.unit_died.connect(_on_unit_died)

func _on_unit_died(unit: Unit, _killer_team: int, _killer_id: String) -> void:
	selected_units.erase(unit)
	## 集火目标阵亡 → 撤掉红圈（forced_target 由各单位的 sync_forced_target 自行清理）
	if _attack_lock_target == unit:
		_attack_lock_target = null

## 切换网格显隐（G 键 / HUD 按钮共用），并同步刷新 HUD 按钮文案
func toggle_grid() -> void:
	show_grid = not show_grid
	if grid_layer != null and is_instance_valid(grid_layer):
		grid_layer.visible = show_grid
	if hud != null and is_instance_valid(hud) and hud.has_method("_refresh_grid_btn_label"):
		hud._refresh_grid_btn_label()

## 选择当前出兵/控制阵营（HUD 阵容按钮调用）
func select_team(t: int) -> void:
	if t >= 0 and t < team_count:
		selected_team = t

## 添加下一个阵营（最多 MAX_TEAMS），返回是否成功
func add_team() -> bool:
	if team_count >= MAX_TEAMS:
		return false
	team_count += 1
	return true

## 切换和平/战争模式（HUD 调用）
func toggle_peace() -> void:
	peace_mode = not peace_mode
	_apply_combat_state()

## 切换开战/停战（仅战争模式有效）
func toggle_war_started() -> void:
	war_started = not war_started
	_apply_combat_state()


func is_combat_active() -> bool:
	return not peace_mode and war_started

## 将当前战斗状态应用到所有已存在单位（和平=站定不攻击；开战=主动出击）
func _apply_combat_state() -> void:
	var active = is_combat_active()
	_attack_lock_target = null  ## 切换和平/开战即撤销全体集火令
	for u in unit_container.get_children():
		if u is Unit and is_instance_valid(u) and not u.is_dead:
			u.hold_position = not active
			u.combat_enabled = active
			u.order_pos = Vector2.INF
			u.clear_forced_target()  ## #框选攻击锁定：切换战斗状态时一并撤销玩家指定的目标
			## #竞技场（2026-08-24）：切回和平/停战时，正处于攻击状态的单位必须立刻拉回
			## move（沙盒站定分支），否则它会把当前攻击周期打完才停手。
			if not active:
				u.target = null
				u.change_state("move")
## ── 输入处理 ───────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	## F3 切换红蓝判定框
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_show_hitboxes = not _show_hitboxes
		Unit.show_hitboxes = _show_hitboxes
		for u in unit_container.get_children():
			if u is Unit:
				u.queue_redraw()
		return
	## F5 切换全屏 / 窗口
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		var new_mode: int = SettingsManager.WINDOW_MODE_WINDOWED
		if SettingsManager.window_mode != SettingsManager.WINDOW_MODE_FULLSCREEN:
			new_mode = SettingsManager.WINDOW_MODE_FULLSCREEN
		SettingsManager.set_window_mode(new_mode)
		return
	## G 切换网格显隐
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		toggle_grid()
		return

	## 鼠标落在 HUD 控件上（兵种栏/顶栏按钮等）时，战场不处理任何鼠标输入
	## 这能避免「点兵种按钮」被误判为地图出兵点击
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and _is_mouse_over_hud_control():
		## 拖图 / 框选在 HUD 上松手也必须收尾，防止手势粘住或继续出兵。
		if event is InputEventMouseButton and not event.pressed:
			_is_panning = false
			_is_left_down = false
			_left_dragged = false
			_drag_box = Rect2()
			selection_layer.queue_redraw()
		return

	## 滚轮缩放（悬停 HUD 控件时交给控件自己处理，已在上面拦截）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_camera(ZOOM_SPEED)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_camera(-ZOOM_SPEED)

	## 右键：按下记录起点；移动超阈值→平移镜头；松开位移小→对选中单位下达移动令
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_is_panning = true
			_pan_start_pos = event.position
			_pan_last_pos = event.position
			_pan_moved = 0.0
		else:
			if _is_panning and _pan_moved < PAN_THRESHOLD:
				_issue_move_order()
			_is_panning = false

	if event is InputEventMouseMotion and _is_panning:
		var delta_pos: Vector2 = event.position - _pan_last_pos
		_pan_moved += delta_pos.length()
		if _pan_moved >= PAN_THRESHOLD:
			camera.position -= delta_pos / camera.zoom
			_clamp_camera()
		_pan_last_pos = event.position

	## 左键：按下记录起点；拖动超阈值→框选；松开按状态出兵/框选
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_left_down = true
			_left_start_world = battlefield.get_global_mouse_position()
			_left_dragged = false
			_drag_box = Rect2(_left_start_world, Vector2.ZERO)
			_hold_timer = 0.0
		else:
			if _is_left_down and not _left_dragged:
				## #竞技场（2026-08-24 用户拍板）：单击优先「取消框选」；
				## 无选中单位时才出 1 兵。
				## #框选攻击锁定（2026-09-04）：有选中单位且点到敌方单位 → 全体集火，
				## 优先级高于「取消框选」（点空地才是取消）。
				if not selected_units.is_empty():
					var picked: Unit = UNIT_COMMAND.pick_enemy_at(
							unit_container, battlefield.get_global_mouse_position(), selected_team)
					if picked != null:
						_issue_attack_order(picked)
					else:
						selected_units.clear()
						if ground_layer != null and is_instance_valid(ground_layer):
							ground_layer.queue_redraw()
				else:
					_spawn_one_at_mouse()
			elif _is_left_down and _left_dragged:
				_on_drag_release()            ## 拖框松开 → 框选单位 or 网格铺兵
			_is_left_down = false
			## #竞技场（2026-08-24）：松手即清框选矩形，否则 _draw_selection 会一直画着旧框
			_left_dragged = false
			_drag_box = Rect2()
			if selection_layer != null and is_instance_valid(selection_layer):
				selection_layer.queue_redraw()

	if event is InputEventMouseMotion and _is_left_down:
		var d: Vector2 = battlefield.get_global_mouse_position() - _left_start_world
		if not _left_dragged and d.length() > DRAG_THRESHOLD:
			_left_dragged = true
		if _left_dragged:
			var cur: Vector2 = battlefield.get_global_mouse_position()
			_drag_box = Rect2(_left_start_world, cur - _left_start_world).abs()
			selection_layer.queue_redraw()

## 每帧：键盘镜头 + 长按连出 + 选中标记持续重绘（单位会移动）
func _process(delta: float) -> void:
	_update_camera_keys(delta)
	## 长按连出：仅在「无选中单位」时生效（有选中时左键是取消框选，不该连出兵）
	if _is_left_down and not _left_dragged and not _is_panning and selected_units.is_empty() and not _is_mouse_over_hud_control():
		var res = _current_spawn_res()
		if res != null:
			_hold_timer += delta
			if _hold_timer >= LONG_PRESS_INTERVAL:
				_hold_timer = 0.0
				_spawn_one_at_mouse()
	_process_deploy_queue()  ## 按帧分批消化网格出兵队列（避免框选瞬间卡死）
	## 右键移动令反馈计时（阵营色椭圆 1 秒渐隐）
	if _order_mark_time > 0.0:
		_order_mark_time = maxf(0.0, _order_mark_time - delta)
	## #框选攻击锁定（2026-09-04）：集火目标失效（回池/阵亡）时撤掉红圈
	if _attack_lock_target != null and (not is_instance_valid(_attack_lock_target) \
			or _attack_lock_target.is_dead):
		_attack_lock_target = null
	## #性能（2026-08-27）：两层重绘加内容守卫。
	## _draw_selection 只在拖框时有内容，_draw_team_rings 只在有选中单位或移动令反馈时有内容 ——
	## 旧代码无条件每帧各排一次重绘，空场也在白付两次 CanvasItem 重绘调度。
	if _left_dragged and selection_layer != null and is_instance_valid(selection_layer):
		selection_layer.queue_redraw()
	## 阵营光圈随单位移动，有选中单位（或移动令反馈未渐隐完 / 集火红圈仍在）时必须每帧重绘
	if (not selected_units.is_empty() or _order_mark_time > 0.0 or _attack_lock_target != null) \
			and ground_layer != null and is_instance_valid(ground_layer):
		ground_layer.queue_redraw()

## ── 出兵 / 框选 / 移动 ─────────────────────────────────────
func _current_spawn_res() -> Resource:
	if hud == null or not is_instance_valid(hud):
		return null
	return hud.battlefield_spawn_res

## 当前出兵归属阵营（#竞技场 2026-08-24 修）：
## 直接返回 selected_team，不再读 hud.battlefield_spawn_team ——
## 后者只在「点击兵种按钮」那一刻快照一次，之后切换阵营按钮不会更新，
## 表现为「无论怎么切阵营，出的兵都还是上次点兵种时那个阵营」。
func _current_spawn_team() -> int:
	return selected_team

## 单击 / 长按连出：出 1 兵，并单独记为一个可撤回批次
func _spawn_one_at_mouse() -> void:
	_begin_batch()
	_try_spawn_at_mouse()
	_commit_batch()

func _try_spawn_at_mouse() -> void:
	var res = _current_spawn_res()
	if res == null:
		return
	if unit_container.get_child_count() >= MAX_SPAWN_UNITS:
		return
	var pos: Vector2 = _clamp_to_map(battlefield.get_global_mouse_position())
	if not _is_cell_allowed(pos):
		return  ## 不在允许出兵的网格区域内，忽略
	BattleManager.spawn_unit(res, _current_spawn_team(), pos)

## ── 撤回（需求5，2026-08-24）────────────────────────────────
## 一次出兵操作 = 一批：单击/长按 1 只，框选铺兵 N 只（分帧生成期间批次保持开启）。
## 撤回 = 弹出最近一批并移除其中所有存活单位，可连续撤回多步。
func _begin_batch() -> void:
	_current_batch = []
	_batch_open = true

func _commit_batch() -> void:
	_batch_open = false
	if _current_batch.is_empty():
		return
	_deploy_batches.append(_current_batch)
	if _deploy_batches.size() > MAX_UNDO_BATCHES:
		_deploy_batches.pop_front()
	_current_batch = []
	_refresh_undo_btn()

## 撤回上一次出兵（HUD 撤回按钮调用）；返回是否真的撤掉了东西
func undo_last_deploy() -> bool:
	## 框选铺兵仍在分帧生成中 → 先清掉未生成的落点，避免撤完又冒出来
	if not _pending_deploy_positions.is_empty():
		_clear_deploy_queue()
		if _batch_open:
			_commit_batch()
	if _deploy_batches.is_empty():
		_refresh_undo_btn()
		return false
	var batch: Array = _deploy_batches.pop_back()
	for item in batch:
		if item == null or not (item is Unit):
			continue
		var u := item as Unit
		if not is_instance_valid(u):
			continue
		selected_units.erase(u)
		BattleManager.remove_unit(u, u.team if u.team <= 1 else 1)
		## #性能（2026-08-27）：撤回改为回收进对象池，替代 queue_free。
		## 旧实现每次撤回都把实例永久销毁，撤回后再铺兵只能重新 instantiate ——
		## 与 2026-08-20「清空后再出兵特别卡」同一类问题（见 clear_all_units 注释）。
		u.is_dead = true  ## 标记死亡，避免回池后残留状态机继续跑（recycle 会关物理处理）
		BattleManager.recycle_unit(u)
	_refresh_undo_btn()
	if selection_layer != null and is_instance_valid(selection_layer):
		selection_layer.queue_redraw()
	if ground_layer != null and is_instance_valid(ground_layer):
		ground_layer.queue_redraw()
	return true

## 是否还有可撤回的批次（HUD 用于置灰按钮）
func has_undoable_deploy() -> bool:
	return not _deploy_batches.is_empty() or not _pending_deploy_positions.is_empty()

func _refresh_undo_btn() -> void:
	if hud != null and is_instance_valid(hud) and hud.has_method("_refresh_undo_btn_state"):
		hud._refresh_undo_btn_state()

func _on_drag_release() -> void:
	var box: Rect2 = _drag_box
	## 框内是否有当前选中阵营的存活（非基地）单位 → 框选它们
	## 2026-08-18 用户确认：选择阵营 = 只控制该阵营兵种，框选按 selected_team 过滤
	var inside: Array[Unit] = UNIT_COMMAND.collect_boxed_units(unit_container, box, selected_team)
	if not inside.is_empty():
		selected_units = inside
		selection_layer.queue_redraw()
		return
	## 框内无该阵营单位 → 若已选兵种，按网格铺兵（归属当前选中阵营）
	var res = _current_spawn_res()
	if res != null:
		_grid_deploy(box, res, _current_spawn_team())
	selection_layer.queue_redraw()

## 在矩形区域内按格子铺兵：仅「被框住面积 ≥ 格子面积 1/3」的格子出兵，落点取格子中心。
## #竞技场（2026-08-24 用户拍板）：原实现按 GRID_SIZE 整数倍交点铺兵（与画出来的网格线
## 还错位），且框沾到一点就出一个兵。现改为格子制 + 中心落点，与显示网格对齐。
## 落点入队而非当场生成——真正的实例化在 _process_deploy_queue 按帧分批完成，
## 这样一次大框选也不会在单帧同步 spawn 上百个单位（即此前卡死/闪退的根因）。
func _grid_deploy(box: Rect2, res: Resource, team: int) -> void:
	var origin := Vector2(MAP_LEFT, MAP_TOP)
	var cells: Array[Vector2i] = compute_grid_cells_in_box(box.intersection(Constants.ARENA_BOUNDS), GRID_SIZE, origin, SELECT_AREA_RATIO)
	var queued: int = 0
	var remaining: int = MAX_SPAWN_UNITS - unit_container.get_child_count() - _pending_deploy_positions.size()
	for cell in cells:
		if queued >= remaining:
			break
		var pos := Vector2(
			MAP_LEFT + (float(cell.x) + 0.5) * GRID_SIZE,
			MAP_TOP + (float(cell.y) + 0.5) * GRID_SIZE)
		## 框选铺兵同样不能越出地图边界。
		if not _is_cell_allowed(pos):
			continue
		_pending_deploy_positions.append(pos)
		_pending_deploy_res.append(res)
		_pending_deploy_team.append(team)
		queued += 1
	## 一次框选铺兵 = 一个撤回批次；批次在分帧生成完毕后才 commit
	if queued > 0:
		_begin_batch()

## 每帧从队列取出最多 DEPLOY_BATCH_PER_FRAME 个落点生成单位（根因修复：摊平单帧开销）
func _process_deploy_queue() -> void:
	if _pending_deploy_positions.is_empty():
		return
	var spawned: int = 0
	while not _pending_deploy_positions.is_empty() and spawned < DEPLOY_BATCH_PER_FRAME:
		spawned += 1
		var pos: Vector2 = _pending_deploy_positions.pop_front()
		var res: Resource = _pending_deploy_res.pop_front()
		var team: int = _pending_deploy_team.pop_front()
		if res == null:
			continue
		if unit_container.get_child_count() >= MAX_SPAWN_UNITS:
			_clear_deploy_queue()
			_commit_batch()
			return
		BattleManager.spawn_unit(res, team, pos)
	## 队列刚刚排空 → 本批铺兵全部生成完毕，收口成一个可撤回批次
	if _pending_deploy_positions.is_empty() and _batch_open:
		_commit_batch()

## 清空批量出兵队列（模式重置/切换时调用，避免遗留落点继续生成）
func _clear_deploy_queue() -> void:
	_pending_deploy_positions.clear()
	_pending_deploy_res.clear()
	_pending_deploy_team.clear()

## 纯静态（保留供旧回归用例）：给定矩形与网格尺寸，返回所有网格交点坐标
static func compute_grid_deploy_positions(box: Rect2, grid_size: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if box.size.x <= 0.0 or box.size.y <= 0.0 or grid_size <= 0.0:
		return result
	var start_x: float = ceil(box.position.x / grid_size) * grid_size
	var start_y: float = ceil(box.position.y / grid_size) * grid_size
	var cols: int = int(floor((box.end.x - start_x) / grid_size)) + 1
	var rows: int = int(floor((box.end.y - start_y) / grid_size)) + 1
	for c in range(cols):
		for r in range(rows):
			result.append(Vector2(start_x + float(c) * grid_size, start_y + float(r) * grid_size))
	return result

## 右键点按：对当前框选单位下达移动令（以点击点为中心按网格分配编队偏移）
## #竞技场（2026-08-24 需求3 修）：编队间距原用 GRID_SIZE(30) < 友军分离半径(40)，
## 相邻编队位永远处在互推范围内 → 分离推力抵消前进速度（表现为「某只兵移速特别慢」），
## 且两兵目标点互相在分离半径内时谁都进不到到达阈值 → 永远播 move 动画原地狂奔。
## 改为间距 = max(GRID_SIZE, SEPARATION_RADIUS + 4)，让编队位彼此落在分离感知范围之外。
## #框选（2026-09-04）：编队分配与下令本体已抽到 UNIT_COMMAND（与肉鸽共用），此处只做反馈
const FORMATION_SPACING: float = UNIT_COMMAND.FORMATION_SPACING
func _issue_move_order() -> void:
	if selected_units.is_empty():
		return
	var center: Vector2 = _clamp_to_map(battlefield.get_global_mouse_position())
	var map_bounds := Rect2(Vector2(MAP_LEFT, MAP_TOP),
			Vector2(MAP_RIGHT - MAP_LEFT, MAP_BOTTOM - MAP_TOP))
	if UNIT_COMMAND.issue_move_order(selected_units, center, map_bounds, FORMATION_SPACING) <= 0:
		return
	## #竞技场（2026-08-24 需求4）：下令点弹出阵营色椭圆，1 秒渐隐
	_attack_lock_target = null  ## 移动令与集火令互斥，撤掉集火红圈
	_order_mark_pos = center
	_order_mark_time = ORDER_MARK_DURATION
	_order_mark_team = selected_team
	_order_mark_is_attack = false

## #框选攻击锁定（2026-09-04）：左键点敌人 → 当前框选单位全体集火该目标。
## 锁定期间不自动换目标、不受肉鸽牵引半径约束，直到目标阵亡或玩家改令（再点一个敌人 / 下移动令）。
## enemy: 被点中的敌方单位
func _issue_attack_order(enemy: Unit) -> void:
	var count: int = UNIT_COMMAND.issue_attack_order(selected_units, enemy)
	if count <= 0:
		return
	_attack_lock_target = enemy
	_order_mark_pos = enemy.global_position
	_order_mark_time = ORDER_MARK_DURATION
	_order_mark_team = selected_team
	_order_mark_is_attack = true

## ── 绘制 ───────────────────────────────────────────────────
func _draw_grid() -> void:
	var col := Color(0.6, 0.6, 0.6, 0.22)
	for x in range(int(MAP_LEFT), int(MAP_RIGHT) + 1, int(GRID_SIZE)):
		grid_layer.draw_line(Vector2(float(x), MAP_TOP), Vector2(float(x), MAP_BOTTOM), col, 1.0)
	for y in range(int(MAP_TOP), int(MAP_BOTTOM) + 1, int(GRID_SIZE)):
		grid_layer.draw_line(Vector2(MAP_LEFT, float(y)), Vector2(MAP_RIGHT, float(y)), col, 1.0)

func _draw_selection() -> void:
	## 框选矩形保持白色。
	if _left_dragged and _drag_box.size.length() > 0.0:
		selection_layer.draw_rect(_drag_box, Color(1.0, 1.0, 1.0, 0.12))
		selection_layer.draw_rect(_drag_box, Color(1.0, 1.0, 1.0, 0.9), false, 2.0)
	## #竞技场（2026-08-24 用户拍板）：选中态的绿色椭圆描边已删除 ——
	## 选中反馈统一由 ground_layer 的阵营色光圈承担（且光圈只在选中时才画）。

## 绘制**被选中单位**脚下的阵营光圈（画在 ground_layer：单位之下、网格之上）
## #竞技场（2026-08-24 用户拍板）：从「所有单位常驻显示」改为「仅框选中的单位显示」，
## 未选中的兵脚下保持干净。颜色仍取 Unit.team_color()（与血条同源，阵营1 = #D93025 红）。
func _draw_team_rings() -> void:
	for u in selected_units:
		if u is Unit and is_instance_valid(u) and not u.is_dead and not u.is_base_unit:
			var c: Color = Unit.team_color(u.team)
			var p: Vector2 = u.global_position + Vector2(0.0, 12.0)
			_draw_ellipse_filled(ground_layer, p, SEL_ELLIPSE_HALF_W, SEL_ELLIPSE_HALF_H, Color(c.r, c.g, c.b, 0.55))
	## #框选攻击锁定（2026-09-04）：集火目标常驻红圈，只要锁定还有效就一直画
	if _attack_lock_target != null and is_instance_valid(_attack_lock_target) \
			and not _attack_lock_target.is_dead:
		ground_layer.draw_polyline(
			_ellipse_points(_attack_lock_target.global_position + Vector2(0.0, 12.0),
					SEL_ELLIPSE_HALF_W, SEL_ELLIPSE_HALF_H),
			ATTACK_MARK_COLOR, 2.0)
	## #竞技场（2026-08-24 需求4）：右键移动令点击反馈——阵营色椭圆描边，1 秒渐隐 + 微扩
	## #框选攻击锁定（2026-09-04）：攻击令用红色，与移动令区分
	if _order_mark_time > 0.0 and _order_mark_pos.is_finite():
		var t: float = _order_mark_time / ORDER_MARK_DURATION   ## 1→0
		var mc: Color = ATTACK_MARK_COLOR if _order_mark_is_attack else Unit.team_color(_order_mark_team)
		var grow: float = 1.0 + (1.0 - t) * 0.35
		ground_layer.draw_polyline(
			_ellipse_points(_order_mark_pos, SEL_ELLIPSE_HALF_W * grow, SEL_ELLIPSE_HALF_H * grow),
			Color(mc.r, mc.g, mc.b, t * 0.95), 2.5)

## 框选命中判定（实现在 UNIT_COMMAND，与肉鸽指挥层共用同一套面积占比规则）
func _is_unit_boxed(u: Unit, box: Rect2) -> bool:
	return UNIT_COMMAND.is_unit_boxed(u, box, SELECT_AREA_RATIO)

## 手动绘制椭圆描边取点（实现在 UNIT_COMMAND）
func _ellipse_points(center: Vector2, rx: float, ry: float, segments: int = 24) -> PackedVector2Array:
	return UNIT_COMMAND.ellipse_points(center, rx, ry, segments)

func _draw_ellipse_filled(layer: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	UNIT_COMMAND.draw_ellipse_filled(layer, center, rx, ry, color)

## ── 摄像机辅助 ─────────────────────────────────────────────
func _update_camera_keys(delta: float) -> void:
	var move_x: float = 0.0
	var move_y: float = 0.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		move_x -= 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move_y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move_y += 1.0
	if move_x != 0.0 or move_y != 0.0:
		camera.position.x += move_x * CAMERA_SPEED * delta
		camera.position.y += move_y * CAMERA_SPEED * delta
		_clamp_camera()

func _zoom_camera(delta_zoom: float) -> void:
	var new_zoom: float = clampf(camera.zoom.x + delta_zoom, camera_zoom_min, maxf(CAMERA_ZOOM_MAX, camera_zoom_min))
	camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera()

func _update_min_zoom() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var map_width: float = Constants.ARENA_BOUNDS.size.x
	var map_height: float = Constants.ARENA_BOUNDS.size.y
	var zoom_by_w: float = viewport_size.x / map_width
	var zoom_by_h: float = viewport_size.y / map_height
	## 两方向都盖满视口（缩到此值不露地图外）
	var zoom_cover: float = maxf(zoom_by_w, zoom_by_h)
	## 整张地图进视口（缩到此值可全图总览）
	var zoom_fit: float = minf(zoom_by_w, zoom_by_h)
	## #全图可放（2026-10-02）：原实现取 zoom_cover，1280×720 下最小 zoom 被钉在 0.55 ——
	## 视野 2327×1309 < 地图 3840×1440，玩家缩到底也看不到地图外围，
	## 观感即「只允许在地图中间放置兵种」。现允许一路缩到 zoom_fit（全图进视口），
	## 缩到最小时地图外露空属正常沙盘总览，不影响放置判定。
	camera_zoom_min = minf(maxf(CAMERA_ZOOM_MIN_BASE, zoom_cover), zoom_fit)

func _on_viewport_size_changed() -> void:
	_update_min_zoom()
	if camera.zoom.x < camera_zoom_min:
		camera.zoom = Vector2(camera_zoom_min, camera_zoom_min)
	_clamp_camera()

func _clamp_camera() -> void:
	var zoom_val: float = camera.zoom.x
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_view_w: float = viewport_size.x / zoom_val * 0.5
	var half_view_h: float = viewport_size.y / zoom_val * 0.5
	var min_x: float = MAP_LEFT + half_view_w
	var max_x: float = MAP_RIGHT - half_view_w
	var min_y: float = MAP_TOP + half_view_h
	var max_y: float = MAP_BOTTOM - half_view_h
	if min_x > max_x:
		camera.position.x = (MAP_LEFT + MAP_RIGHT) * 0.5
	else:
		camera.position.x = clampf(camera.position.x, min_x, max_x)
	if min_y > max_y:
		camera.position.y = (MAP_TOP + MAP_BOTTOM) * 0.5
	else:
		camera.position.y = clampf(camera.position.y, min_y, max_y)

func _clamp_to_map(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, MAP_LEFT, MAP_RIGHT), clampf(p.y, MAP_TOP, MAP_BOTTOM))

## 竞技场全图自由布兵，仅保留地图边界。
func _is_cell_allowed(world_pos: Vector2) -> bool:
	return Constants.ARENA_BOUNDS.has_point(world_pos)

## 纯静态：返回矩形覆盖的网格单元索引（供标记与单测）
## #竞技场（2026-08-24 用户拍板）：新增 origin（网格原点，默认 0 保持旧签名语义）与
## min_ratio（命中所需的最小格内被框面积占比，默认 0 = 沾到即算）。
## 框选铺兵使用 SELECT_AREA_RATIO(1/3) 作为格内覆盖门槛。
static func compute_grid_cells_in_box(box: Rect2, grid_size: float, origin: Vector2 = Vector2.ZERO, min_ratio: float = 0.0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if box.size.x <= 0.0 or box.size.y <= 0.0 or grid_size <= 0.0:
		return result
	var local := Rect2(box.position - origin, box.size)
	var min_cx: int = int(floor(local.position.x / grid_size))
	var max_cx: int = int(floor((local.end.x - 0.001) / grid_size))
	var min_cy: int = int(floor(local.position.y / grid_size))
	var max_cy: int = int(floor((local.end.y - 0.001) / grid_size))
	var cell_area: float = grid_size * grid_size
	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			if min_ratio > 0.0:
				var cell_rect := Rect2(float(cx) * grid_size, float(cy) * grid_size, grid_size, grid_size)
				var inter: Rect2 = local.intersection(cell_rect)
				if inter.size.x <= 0.0 or inter.size.y <= 0.0:
					continue
				if (inter.size.x * inter.size.y) / cell_area < min_ratio:
					continue
			result.append(Vector2i(cx, cy))
	return result

## 鼠标是否悬停在 HUD 任意控件上（用于让战场忽略落在 UI 上的鼠标输入）
func _is_mouse_over_hud_control() -> bool:
	if hud == null or not is_instance_valid(hud):
		return false
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	return hud.is_ancestor_of(hovered)
