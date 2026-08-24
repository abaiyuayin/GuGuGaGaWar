extends Node2D
class_name BattlefieldMode
## 战场模式（RTS 沙盒）根控制器
## 设计：无 AI、无胜负、无回合（水晶可被打爆但不触发结算）。
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

## ── 摄像机参数（照搬 battle_root）────────────────────────────
const CAMERA_SPEED: float = 600.0
const CAMERA_ZOOM_MIN_BASE: float = 0.9
const CAMERA_ZOOM_MAX: float = 4.0
const ZOOM_SPEED: float = 0.15
const MAP_LEFT: float = -656.0
const MAP_RIGHT: float = 656.0
const MAP_TOP: float = -368.0
const MAP_BOTTOM: float = 368.0

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
## 出兵范围
## #竞技场（2026-08-24 用户订正语义）：按钮 = 「编辑开关」，不是「限制开关」。
## 关闭编辑后刷出来的区域**继续生效**，并落盘到项目 data/arena_deploy_zone.json。
## deploy_zone_configured：是否配置过。未配置=全图可出兵；已配置但区域为空=全图禁止出兵。
var deploy_zone_enabled: bool = false      ## 编辑模式（左键刷格子、不出兵）
var deploy_zone_configured: bool = false   ## 是否已配置过出兵范围
var allowed_cells: Dictionary = {}  ## key=Vector2i(cell_x,cell_y) → true
const DEPLOY_ZONE_PATH: String = "res://data/arena_deploy_zone.json"

## 右键移动令点击反馈（阵营色椭圆，1 秒渐隐）
const ORDER_MARK_DURATION: float = 1.0
var _order_mark_pos: Vector2 = Vector2.INF
var _order_mark_time: float = 0.0
var _order_mark_team: int = 0

## 撤回：每次出兵（单击 1 只 / 一次框选铺兵 N 只）记为一批，可连续撤回多步
var _deploy_batches: Array = []   ## Array[Array]，末尾为最近一批
var _current_batch: Array = []    ## 当前正在填充的批次（框选分帧生成期间持续追加）
var _batch_open: bool = false     ## 批次是否处于「填充中」
const MAX_UNDO_BATCHES: int = 50

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
	_update_min_zoom()
	camera.position = Vector2(0, 0)
	camera.zoom = Vector2(camera_zoom_min, camera_zoom_min)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	## 单位生成接线：加入 UnitContainer 并连接死亡；不连 base_destroyed（无胜负）
	BattleManager.unit_spawned.connect(_on_unit_spawned)
	if DevMode.enabled:
		Unit.show_attack_ranges = true

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

	## #竞技场（2026-08-24）：读取项目内持久化的出兵范围配置
	_load_deploy_zone()

	AudioManager.play_battle_bgm()

## ── 出兵范围持久化（项目内 data/arena_deploy_zone.json）──────────────
## 编辑器运行时可写 res://；导出版 res:// 只读 → 写失败只打日志不报错。
func _load_deploy_zone() -> void:
	if not FileAccess.file_exists(DEPLOY_ZONE_PATH):
		deploy_zone_configured = false
		return
	## 文件存在即视为「配置过」（即使内容为空或损坏，也按用户配置处理）
	deploy_zone_configured = true
	var f := FileAccess.open(DEPLOY_ZONE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	allowed_cells.clear()
	var arr = parsed.get("cells", [])
	if arr is Array:
		for item in arr:
			if item is Array and item.size() >= 2:
				allowed_cells[Vector2i(int(item[0]), int(item[1]))] = true

func _save_deploy_zone() -> void:
	var cells: Array = []
	for cell in allowed_cells.keys():
		cells.append([cell.x, cell.y])
	var data := {"grid_size": GRID_SIZE, "origin": [MAP_LEFT, MAP_TOP], "cells": cells}
	var f := FileAccess.open(DEPLOY_ZONE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[竞技场] 出兵范围配置写入失败（导出版 res:// 只读属正常）")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	deploy_zone_configured = true

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

## 切换出兵范围**编辑模式**（HUD 调用）
## #竞技场（2026-08-24 用户订正）：本按钮只切换「是否在编辑」，不切换限制生效。
## 开启：左键框选刷亮格子（只刷格、不出兵）；关闭：退出编辑并把区域落盘，限制继续生效。
func toggle_deploy_zone() -> void:
	deploy_zone_enabled = not deploy_zone_enabled
	if not deploy_zone_enabled:
		_save_deploy_zone()   ## 退出编辑即持久化到项目 data/
	grid_layer.queue_redraw()
	selection_layer.queue_redraw()

## 清空出兵范围（HUD 长按/右键出兵范围按钮调用）：清空白名单并落盘
func clear_deploy_zone() -> void:
	allowed_cells.clear()
	_save_deploy_zone()
	grid_layer.queue_redraw()
	selection_layer.queue_redraw()

func is_combat_active() -> bool:
	return not peace_mode and war_started

## 将当前战斗状态应用到所有已存在单位（和平=站定不攻击；开战=主动出击）
func _apply_combat_state() -> void:
	var active = is_combat_active()
	for u in unit_container.get_children():
		if u is Unit and is_instance_valid(u) and not u.is_dead:
			u.hold_position = not active
			u.combat_enabled = active
			u.order_pos = Vector2.INF
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
		camera.position.x -= delta_pos.x / camera.zoom.x
		camera.position.y -= delta_pos.y / camera.zoom.x
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
			if deploy_zone_enabled:
				_mark_deploy_cells(_drag_box)  ## 出兵范围编辑：框选标记可出兵网格
			elif _is_left_down and not _left_dragged:
				## #竞技场（2026-08-24 用户拍板）：单击优先「取消框选」；
				## 无选中单位时才出 1 兵。
				if not selected_units.is_empty():
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
	if _is_left_down and not _left_dragged and selected_units.is_empty():
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
	if selection_layer != null and is_instance_valid(selection_layer):
		selection_layer.queue_redraw()
	## 阵营光圈随单位移动，必须与 selection_layer 一样每帧重绘
	if ground_layer != null and is_instance_valid(ground_layer):
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
	if deploy_zone_enabled:
		return  ## 出兵范围编辑模式下左键只框选区域，不出兵
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
		u.queue_free()
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
	if deploy_zone_enabled:
		return  ## 编辑模式下拖框用于标记出兵区，已在 _input 处理
	var box: Rect2 = _drag_box
	## 框内是否有当前选中阵营的存活（非基地）单位 → 框选它们
	## 2026-08-18 用户确认：选择阵营 = 只控制该阵营兵种，框选按 selected_team 过滤
	var inside: Array[Unit] = []
	for u in unit_container.get_children():
		if u is Unit and is_instance_valid(u) and not u.is_dead and not u.is_base_unit \
				and u.team == selected_team and _is_unit_boxed(u, box):
			inside.append(u)
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
## 还错位），且框沾到一点就出一个兵。现改为格子制 + 中心落点，与出兵范围格子索引统一。
## 落点入队而非当场生成——真正的实例化在 _process_deploy_queue 按帧分批完成，
## 这样一次大框选也不会在单帧同步 spawn 上百个单位（即此前卡死/闪退的根因）。
func _grid_deploy(box: Rect2, res: Resource, team: int) -> void:
	var origin := Vector2(MAP_LEFT, MAP_TOP)
	var cells: Array[Vector2i] = compute_grid_cells_in_box(box, GRID_SIZE, origin, SELECT_AREA_RATIO)
	var queued: int = 0
	for cell in cells:
		var pos := Vector2(
			MAP_LEFT + (float(cell.x) + 0.5) * GRID_SIZE,
			MAP_TOP + (float(cell.y) + 0.5) * GRID_SIZE)
		## #竞技场（2026-08-24）：出兵范围限制同样约束框选铺兵（原先只拦单击出兵）
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
const FORMATION_SPACING: float = 44.0
func _issue_move_order() -> void:
	if selected_units.is_empty():
		return
	var center: Vector2 = _clamp_to_map(battlefield.get_global_mouse_position())
	var n: int = selected_units.size()
	var cols: int = int(ceil(sqrt(float(n))))
	var rows: int = int(ceil(float(n) / float(cols)))
	var idx: int = 0
	for u in selected_units:
		if not is_instance_valid(u) or u.is_dead:
			continue
		var gx: int = idx % cols
		var gy: int = idx / cols
		## 纵向居中按实际行数算（原用 cols 导致行数≠列数时整个阵列偏心）
		var offset: Vector2 = Vector2(
			(float(gx) - float(cols - 1) * 0.5) * FORMATION_SPACING,
			(float(gy) - float(rows - 1) * 0.5) * FORMATION_SPACING)
		u.order_pos = _clamp_to_map(center + offset)
		u.hold_position = true
		idx += 1
	## #竞技场（2026-08-24 需求4）：下令点弹出阵营色椭圆，1 秒渐隐
	_order_mark_pos = center
	_order_mark_time = ORDER_MARK_DURATION
	_order_mark_team = selected_team

## ── 绘制 ───────────────────────────────────────────────────
func _draw_grid() -> void:
	var col := Color(0.6, 0.6, 0.6, 0.22)
	for x in range(int(MAP_LEFT), int(MAP_RIGHT) + 1, int(GRID_SIZE)):
		grid_layer.draw_line(Vector2(float(x), MAP_TOP), Vector2(float(x), MAP_BOTTOM), col, 1.0)
	for y in range(int(MAP_TOP), int(MAP_BOTTOM) + 1, int(GRID_SIZE)):
		grid_layer.draw_line(Vector2(MAP_LEFT, float(y)), Vector2(MAP_RIGHT, float(y)), col, 1.0)
	## 出兵范围高亮：允许的网格单元叠加半透明白色
	## #竞技场（2026-08-24 用户订正）：只要配置过就一直显示（原先仅编辑模式下可见）
	if deploy_zone_configured and not allowed_cells.is_empty():
		for cell in allowed_cells.keys():
			var cx: int = cell.x
			var cy: int = cell.y
			var x0: float = MAP_LEFT + float(cx) * GRID_SIZE
			var y0: float = MAP_TOP + float(cy) * GRID_SIZE
			grid_layer.draw_rect(Rect2(x0, y0, GRID_SIZE, GRID_SIZE), Color(1.0, 1.0, 1.0, 0.16))

func _draw_selection() -> void:
	## 框选矩形（出兵范围编辑=白；普通框选=绿）
	if _left_dragged and _drag_box.size.length() > 0.0:
		if deploy_zone_enabled:
			selection_layer.draw_rect(_drag_box, Color(1.0, 1.0, 1.0, 0.10))
			selection_layer.draw_rect(_drag_box, Color(1.0, 1.0, 1.0, 0.9), false, 2.0)
		else:
			## #竞技场（2026-08-24 用户拍板）：框选矩形改白色（原绿色）
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
	## #竞技场（2026-08-24 需求4）：右键移动令点击反馈——阵营色椭圆描边，1 秒渐隐 + 微扩
	if _order_mark_time > 0.0 and _order_mark_pos.is_finite():
		var t: float = _order_mark_time / ORDER_MARK_DURATION   ## 1→0
		var mc: Color = Unit.team_color(_order_mark_team)
		var grow: float = 1.0 + (1.0 - t) * 0.35
		ground_layer.draw_polyline(
			_ellipse_points(_order_mark_pos, SEL_ELLIPSE_HALF_W * grow, SEL_ELLIPSE_HALF_H * grow),
			Color(mc.r, mc.g, mc.b, t * 0.95), 2.5)

## 框选命中判定：单位有 1/3 以上面积落在框内即算选中（2026-08-20 用户拍板，依据单位碰撞体尺寸）
## 旧实现用 box.has_point(global_position) 只测中心点，贴边的兵会漏选。
## 单位碰撞体是 CircleShape2D（见 unit_base._setup_collision_body），这里取其外接正方形做面积近似——
## 圆与矩形的精确交集面积需要积分，正方形近似在实用精度上足够且每帧开销恒定。
func _is_unit_boxed(u: Unit, box: Rect2) -> bool:
	var half: float = _unit_half_extent(u)
	var rect := Rect2(u.global_position - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	var inter: Rect2 = box.intersection(rect)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return false
	var unit_area: float = rect.size.x * rect.size.y
	if unit_area <= 0.0:
		return box.has_point(u.global_position)
	return (inter.size.x * inter.size.y) / unit_area >= SELECT_AREA_RATIO

## 取单位碰撞体的半边长（CircleShape2D 半径；异常时回落到光圈半高，保证判定不失效）
func _unit_half_extent(u: Unit) -> float:
	var col := u.get_node_or_null("CollisionShape2D")
	if col != null and col.shape is CircleShape2D:
		var r: float = (col.shape as CircleShape2D).radius
		if r > 0.0:
			return r
	return SEL_ELLIPSE_HALF_H

## 手动绘制椭圆描边（避免 draw_ellipse 在不同 Godot 版本签名差异：本作 4.7 第二参为 float）
func _ellipse_points(center: Vector2, rx: float, ry: float, segments: int = 24) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in range(segments + 1):   ## +1 闭合首尾（draw_polyline 不自动闭环；polygon 多一点无害）
		var a: float = float(i) / float(segments) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _draw_ellipse_filled(layer: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	layer.draw_polygon(_ellipse_points(center, rx, ry), [color])

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
	var new_zoom: float = clampf(camera.zoom.x + delta_zoom, camera_zoom_min, CAMERA_ZOOM_MAX)
	camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera()

func _update_min_zoom() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var map_width: float = 1152.0
	var map_height: float = 736.0
	var zoom_by_w: float = viewport_size.x / map_width
	var zoom_by_h: float = viewport_size.y / map_height
	camera_zoom_min = maxf(CAMERA_ZOOM_MIN_BASE, minf(zoom_by_w, zoom_by_h))

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

## 标记矩形覆盖的网格为可出兵（cell 索引 = floor((x-MAP_LEFT)/GRID_SIZE)）
## #竞技场（2026-08-24 修）：原实现按世界坐标直接除 GRID_SIZE 算索引，未减 MAP_LEFT/MAP_TOP，
## 与 _is_cell_allowed / _draw_grid 的索引口径不一致（偏移 656/30 非整数 → 刷亮格与实际可出兵格错位）。
## 同时套用 1/3 面积门槛，与框选铺兵规则统一。
func _mark_deploy_cells(box: Rect2) -> void:
	var origin := Vector2(MAP_LEFT, MAP_TOP)
	for cell in compute_grid_cells_in_box(box, GRID_SIZE, origin, SELECT_AREA_RATIO):
		allowed_cells[cell] = true
	grid_layer.queue_redraw()
	selection_layer.queue_redraw()

## 世界坐标是否落在允许出兵的网格
## #竞技场（2026-08-24 用户订正）：不再看「编辑开关」，只看是否配置过。
## 未配置过 → 全图可出兵；已配置但区域为空 → 全图禁止出兵（用户拍板）。
func _is_cell_allowed(world_pos: Vector2) -> bool:
	if not deploy_zone_configured:
		return true
	if allowed_cells.is_empty():
		return false
	var cx: int = int(floor((world_pos.x - MAP_LEFT) / GRID_SIZE))
	var cy: int = int(floor((world_pos.y - MAP_TOP) / GRID_SIZE))
	return allowed_cells.has(Vector2i(cx, cy))

## 纯静态：返回矩形覆盖的网格单元索引（供标记与单测）
## #竞技场（2026-08-24 用户拍板）：新增 origin（网格原点，默认 0 保持旧签名语义）与
## min_ratio（命中所需的最小格内被框面积占比，默认 0 = 沾到即算）。
## 出兵范围刷格子与框选铺兵都传 SELECT_AREA_RATIO(1/3)，两处规则一致。
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
