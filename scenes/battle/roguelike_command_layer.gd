extends Node2D
## 肉鸽模式框选指挥层（#框选 2026-09-04）
##
## 把竞技场（battlefield_mode）的「左键框选己方单位 → 右键点按下达编队移动令」
## 整套交互搬到肉鸽战斗里，并额外提供「框选后左键点敌人 = 全体集火锁定」。
##
## 由 battle_root._setup_roguelike 实例化并 setup()，输入不是自己抢的 ——
## battle_root._input 显式调用 handle_input()，返回 true 表示本层已消费该事件。
## 这样「框选起框」与 battle_root 原有的「左键点单位看详情」之间的优先级是确定的，
## 不依赖 Godot 的 _input 遍历顺序。
##
## 与竞技场共用的判定 / 下令逻辑全在 scripts/battle/unit_command.gd，本文件只做
## 输入采集、绘制层挂载与反馈提示。

const UNIT_COMMAND := preload("res://scripts/battle/unit_command.gd")
const DRAW_LAYER_SCRIPT := preload("res://scenes/battle/battle_draw_layer.gd")

## 肉鸽玩家阵营固定为 0（敌军为 1）
const OWN_TEAM: int = 0
## 左键拖动超过此像素（世界坐标）视为框选，而不是单击
const DRAG_THRESHOLD: float = 6.0
## 右键位移低于此像素（屏幕坐标）视为「点按下令」，高于则视为拖动平移镜头
const PAN_THRESHOLD: float = 8.0
## 框选矩形配色（与竞技场一致：白色半透明填充 + 白色描边）
const BOX_FILL: Color = Color(1.0, 1.0, 1.0, 0.12)
const BOX_LINE: Color = Color(1.0, 1.0, 1.0, 0.9)
## 攻击锁定标记配色（红，与阵营色区分开）
const ATTACK_MARK_COLOR: Color = Color(1.0, 0.30, 0.24, 1.0)
## 脚下光圈相对单位原点的偏移（与竞技场一致，落在脚底）
const RING_OFFSET: Vector2 = Vector2(0.0, 12.0)

## 当前选中的己方单位（本层私有，不写 BattleManager.selected_units）
var selected_units: Array[Unit] = []

var _root: Node = null
var _battlefield: Node2D = null
var _hud: CanvasLayer = null
var _unit_container: Node = null
var _ground_layer: Node2D = null      ## 脚下光圈层（单位之下）
var _selection_layer: Node2D = null   ## 框选矩形层（单位之上）

## 左键框选状态
var _is_left_down: bool = false
var _left_dragged: bool = false
var _left_start: Vector2 = Vector2.ZERO
var _drag_box: Rect2 = Rect2()

## 右键点按 / 拖动平移的区分状态
var _right_down: bool = false
var _pan_last: Vector2 = Vector2.ZERO
var _pan_moved: float = 0.0

## 下令反馈标记（1 秒渐隐）：移动令取阵营色，攻击令取红色
var _order_mark_pos: Vector2 = Vector2.INF
var _order_mark_time: float = 0.0
var _order_mark_is_attack: bool = false
## 当前全体锁定的敌人（有效期内常驻画红圈，供玩家确认在集火谁）
var _attack_lock_target: Unit = null

## 单位可活动范围：移动令落点夹断在此矩形内，避免把兵指到空气墙外原地卡住
var _bounds: Rect2 = Rect2()

## 注入依赖并挂载绘制层
## root: battle_root（单击空地时回调它的 try_lock_unit）
## battlefield: 战场 Node2D（世界坐标换算与绘制层父节点）
## hud: 肉鸽 HUD（下令后打一条提示条，可为 null）
func setup(root: Node, battlefield: Node2D, hud: CanvasLayer = null) -> void:
	_root = root
	_battlefield = battlefield
	_hud = hud
	_bounds = Rect2(
		Vector2(Constants.FIELD_X_MIN, Constants.FIELD_Y_MIN),
		Vector2(Constants.FIELD_X_MAX - Constants.FIELD_X_MIN,
				Constants.FIELD_Y_MAX - Constants.FIELD_Y_MIN))
	if _battlefield == null or not is_instance_valid(_battlefield):
		return
	_unit_container = _battlefield.get_node_or_null("UnitContainer")
	_build_draw_layers()

## 建两层绘制代理：光圈层插到 UnitContainer 之前（画在单位脚下），框选层追加到最后（画在单位之上）
func _build_draw_layers() -> void:
	_ground_layer = DRAW_LAYER_SCRIPT.new()
	_ground_layer.name = "RoguelikeCommandGround"
	_battlefield.add_child(_ground_layer)
	if _unit_container != null and is_instance_valid(_unit_container):
		_battlefield.move_child(_ground_layer, _unit_container.get_index())
	_ground_layer.draw_func = _draw_ground

	_selection_layer = DRAW_LAYER_SCRIPT.new()
	_selection_layer.name = "RoguelikeCommandSelection"
	_battlefield.add_child(_selection_layer)
	_selection_layer.draw_func = _draw_selection

# ── 输入 ─────────────────────────────────────────────────────

## 由 battle_root._input 显式调用；返回 true 表示事件已被本层消费
func handle_input(event: InputEvent) -> bool:
	if _battlefield == null or not is_instance_valid(_battlefield):
		return false
	## 结算 / 暂停期间不接受指挥：单位已冻结，此时下令只会留下一堆执行不到的状态
	if not BattleManager.is_battle_active or get_tree().paused:
		_reset_drag()
		return false
	if event is InputEventMouseButton:
		var btn := event as InputEventMouseButton
		if btn.button_index == MOUSE_BUTTON_RIGHT:
			return _handle_right_button(btn)
		if btn.button_index == MOUSE_BUTTON_LEFT:
			return _handle_left_button(btn)
		return false
	if event is InputEventMouseMotion:
		return _handle_motion(event as InputEventMouseMotion)
	return false

## 右键：一律不消费（battle_root 仍需用它拖动镜头），只负责区分「点按下令」与「拖动平移」
func _handle_right_button(event: InputEventMouseButton) -> bool:
	if event.pressed:
		_right_down = true
		_pan_last = event.position
		_pan_moved = 0.0
		return false
	if _right_down and _pan_moved < PAN_THRESHOLD and not selected_units.is_empty():
		_issue_move_order()
	_right_down = false
	return false

## 左键：按下起框、松开按「是否拖动过」分流
func _handle_left_button(event: InputEventMouseButton) -> bool:
	if event.pressed:
		## 点在手牌 / HUD 控件上（拖卡部署、控制台按钮）→ 交给 UI，本层不起框
		if _is_mouse_over_ui():
			return false
		_is_left_down = true
		_left_dragged = false
		_left_start = _battlefield.get_global_mouse_position()
		_drag_box = Rect2(_left_start, Vector2.ZERO)
		return true
	## 起点不在战场（例如从手牌起拖）→ 本层不接管这次松手
	if not _is_left_down:
		return false
	var box: Rect2 = _drag_box
	var was_dragged: bool = _left_dragged
	_reset_drag()
	if was_dragged:
		_apply_box_selection(box)
		return true
	## 单击：有选中单位时优先「点敌人下攻击令」，其次取消框选；
	## 无选中单位时沿用 battle_root 原有的「点单位锁定镜头 + 看属性面板」
	if not selected_units.is_empty():
		var enemy: Unit = UNIT_COMMAND.pick_enemy_at(
				_unit_container, _battlefield.get_global_mouse_position(), OWN_TEAM)
		if enemy != null:
			_issue_attack_order(enemy)
			return true
		_clear_selection()
		return true
	if _root != null and is_instance_valid(_root) and _root.has_method("try_lock_unit"):
		_root.try_lock_unit()
	return true

## 鼠标移动：右键累计位移用于区分点按/拖动；左键按下时更新框选矩形
func _handle_motion(event: InputEventMouseMotion) -> bool:
	if _right_down:
		_pan_moved += (event.position - _pan_last).length()
		_pan_last = event.position
	if not _is_left_down:
		return false
	var cur: Vector2 = _battlefield.get_global_mouse_position()
	if not _left_dragged and cur.distance_to(_left_start) > DRAG_THRESHOLD:
		_left_dragged = true
	if _left_dragged:
		_drag_box = Rect2(_left_start, cur - _left_start).abs()
		_redraw_selection()
		return true
	return false

## 清空左键框选的中间状态（松手 / 战斗结束时调用）
func _reset_drag() -> void:
	_is_left_down = false
	_left_dragged = false
	_drag_box = Rect2()
	_redraw_selection()

## 鼠标是否悬停在任意 UI 控件上（悬停控件挂在某个 CanvasLayer 下即视为 UI）
func _is_mouse_over_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	var node: Node = hovered
	while node != null:
		if node is CanvasLayer:
			return true
		node = node.get_parent()
	return false

# ── 选中与下令 ────────────────────────────────────────────────

## 框选结算：框内有己方存活单位就选中它们，一个都没有则清空选中
func _apply_box_selection(box: Rect2) -> void:
	var inside: Array[Unit] = UNIT_COMMAND.collect_boxed_units(_unit_container, box, OWN_TEAM)
	if inside.is_empty():
		_clear_selection()
		return
	selected_units = inside
	_redraw_ground()
	_flash_hint("已选中 %d 个单位：右键点地面移动，左键点敌人集火" % inside.size())

## 取消选中（不影响单位已经接到的指令）
func _clear_selection() -> void:
	if selected_units.is_empty():
		return
	selected_units.clear()
	_redraw_ground()

## 右键点按：对选中单位下达编队移动令
func _issue_move_order() -> void:
	selected_units = UNIT_COMMAND.prune(selected_units)
	if selected_units.is_empty():
		_redraw_ground()
		return
	var center: Vector2 = UNIT_COMMAND.clamp_to_bounds(
			_battlefield.get_global_mouse_position(), _bounds)
	if UNIT_COMMAND.issue_move_order(selected_units, center, _bounds) <= 0:
		return
	_attack_lock_target = null
	_order_mark_pos = center
	_order_mark_time = UNIT_COMMAND.ORDER_MARK_DURATION
	_order_mark_is_attack = false
	AudioManager.play_ui_click()
	_flash_hint("已下达移动令：%d 个单位前往指定位置" % selected_units.size())

## 左键点敌人：对选中单位下达攻击锁定令（全体集火）
func _issue_attack_order(enemy: Unit) -> void:
	selected_units = UNIT_COMMAND.prune(selected_units)
	var count: int = UNIT_COMMAND.issue_attack_order(selected_units, enemy)
	if count <= 0:
		return
	_attack_lock_target = enemy
	_order_mark_pos = enemy.global_position
	_order_mark_time = UNIT_COMMAND.ORDER_MARK_DURATION
	_order_mark_is_attack = true
	AudioManager.play_ui_click()
	var enemy_name: String = "敌军单位"
	if enemy.unit_resource != null:
		enemy_name = enemy.unit_resource.get_display_name()
	_flash_hint("集火目标：%s（%d 个单位已锁定）" % [enemy_name, count])

## 往肉鸽 HUD 打一条临时提示（HUD 缺失时静默忽略）
func _flash_hint(text: String) -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("show_hint"):
		_hud.show_hint(text)

# ── 每帧维护与绘制 ────────────────────────────────────────────

func _process(delta: float) -> void:
	## 战斗结束：清掉选中与残留框，避免结算界面上还画着光圈
	if not BattleManager.is_battle_active:
		if not selected_units.is_empty() or _attack_lock_target != null:
			selected_units.clear()
			_attack_lock_target = null
			_redraw_ground()
		return
	## 选中集合与锁定目标每帧剔除失效成员（单位会阵亡并回对象池）
	var before: int = selected_units.size()
	selected_units = UNIT_COMMAND.prune(selected_units)
	var dirty: bool = selected_units.size() != before
	if _attack_lock_target != null and (not is_instance_valid(_attack_lock_target) or _attack_lock_target.is_dead):
		_attack_lock_target = null
		dirty = true
	if _order_mark_time > 0.0:
		_order_mark_time = maxf(0.0, _order_mark_time - delta)
		dirty = true
	## 光圈要跟着单位走，有内容时才每帧重绘（空场不白付重绘调度）
	if dirty or not selected_units.is_empty() or _attack_lock_target != null:
		_redraw_ground()
	if _left_dragged:
		_redraw_selection()

func _redraw_ground() -> void:
	if _ground_layer != null and is_instance_valid(_ground_layer):
		_ground_layer.queue_redraw()

func _redraw_selection() -> void:
	if _selection_layer != null and is_instance_valid(_selection_layer):
		_selection_layer.queue_redraw()

## 单位之上：框选矩形
func _draw_selection() -> void:
	if not _left_dragged or _drag_box.size.length() <= 0.0:
		return
	_selection_layer.draw_rect(_drag_box, BOX_FILL)
	_selection_layer.draw_rect(_drag_box, BOX_LINE, false, 2.0)

## 单位之下：选中光圈 + 集火目标红圈 + 下令反馈
func _draw_ground() -> void:
	for u in selected_units:
		if u == null or not is_instance_valid(u) or u.is_dead:
			continue
		var c: Color = Unit.team_color(u.team)
		UNIT_COMMAND.draw_ellipse_filled(_ground_layer, u.global_position + RING_OFFSET,
				UNIT_COMMAND.SEL_ELLIPSE_HALF_W, UNIT_COMMAND.SEL_ELLIPSE_HALF_H,
				Color(c.r, c.g, c.b, 0.55))
	## 集火目标常驻红圈：只要锁定还有效就一直画，玩家随时能确认在打谁
	if _attack_lock_target != null and is_instance_valid(_attack_lock_target) and not _attack_lock_target.is_dead:
		_ground_layer.draw_polyline(
				UNIT_COMMAND.ellipse_points(_attack_lock_target.global_position + RING_OFFSET,
						UNIT_COMMAND.SEL_ELLIPSE_HALF_W, UNIT_COMMAND.SEL_ELLIPSE_HALF_H),
				ATTACK_MARK_COLOR, 2.0)
	## 下令反馈：1 秒渐隐 + 微扩（移动=阵营色 / 攻击=红）
	if _order_mark_time > 0.0 and _order_mark_pos.is_finite():
		var t: float = _order_mark_time / UNIT_COMMAND.ORDER_MARK_DURATION
		var mc: Color = ATTACK_MARK_COLOR if _order_mark_is_attack else Unit.team_color(OWN_TEAM)
		var grow: float = 1.0 + (1.0 - t) * 0.35
		_ground_layer.draw_polyline(
				UNIT_COMMAND.ellipse_points(_order_mark_pos,
						UNIT_COMMAND.SEL_ELLIPSE_HALF_W * grow,
						UNIT_COMMAND.SEL_ELLIPSE_HALF_H * grow),
				Color(mc.r, mc.g, mc.b, t * 0.95), 2.5)
