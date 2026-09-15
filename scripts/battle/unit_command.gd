extends RefCounted
## 框选指挥的共享逻辑（竞技场 battlefield_mode + 肉鸽 roguelike_command_layer 共用）
##
## 这里只放「两个模式必须表现一致」的纯逻辑：框选命中判定、编队移动令、攻击锁定令、
## 点选敌人、椭圆取点。输入采集、绘制层挂载、镜头平移等场景特有的部分留在各自控制器里。
##
## 刻意不声明 class_name：新增全局类名要等编辑器重扫 global_script_class_cache 才可用，
## 无头编译自检会直接报「未声明」。两个控制器统一用 preload 常量引用本脚本。

## 框选命中所需的最小面积占比（2026-08-20 用户拍板：兵种 1/3 区域被框住即算选中）
const SELECT_AREA_RATIO: float = 1.0 / 3.0
## 编队间距（像素）：必须大于友军分离半径，否则相邻编队位永远互推、抵消前进速度
## （详见 state_move._advance_to_order 的注释：原 GRID_SIZE=30 < 分离半径 40 → 原地狂奔）
const FORMATION_SPACING: float = 44.0
## 选中光圈 / 下令反馈椭圆的半轴（像素）
const SEL_ELLIPSE_HALF_W: float = 28.0
const SEL_ELLIPSE_HALF_H: float = 12.0
## 左键点选敌人下达攻击令的命中半径（世界像素）
const ATTACK_PICK_RADIUS: float = 44.0
## 下令反馈标记的存留时长（秒）
const ORDER_MARK_DURATION: float = 1.0

## 取单位碰撞体的半边长（CircleShape2D 半径；异常时回落到光圈半高，保证判定不失效）
static func unit_half_extent(u: Unit) -> float:
	var col := u.get_node_or_null("CollisionShape2D")
	if col != null and col.shape is CircleShape2D:
		var r: float = (col.shape as CircleShape2D).radius
		if r > 0.0:
			return r
	return SEL_ELLIPSE_HALF_H

## 框选命中判定：单位有 min_ratio 以上面积落在框内即算选中。
## 只测中心点（box.has_point）会漏掉贴边的兵；单位碰撞体是圆，这里取其外接正方形做面积近似
## —— 圆与矩形的精确交集面积要积分，正方形近似精度足够且开销恒定。
static func is_unit_boxed(u: Unit, box: Rect2, min_ratio: float = SELECT_AREA_RATIO) -> bool:
	var half: float = unit_half_extent(u)
	var rect := Rect2(u.global_position - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	var inter: Rect2 = box.intersection(rect)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return false
	var unit_area: float = rect.size.x * rect.size.y
	if unit_area <= 0.0:
		return box.has_point(u.global_position)
	return (inter.size.x * inter.size.y) / unit_area >= min_ratio

## 收集框内属于 [param team] 的存活非基地单位（水晶 / 基地不可被指挥）
static func collect_boxed_units(container: Node, box: Rect2, team: int,
		min_ratio: float = SELECT_AREA_RATIO) -> Array[Unit]:
	var result: Array[Unit] = []
	if container == null or not is_instance_valid(container):
		return result
	for body in container.get_children():
		if not (body is Unit) or not is_instance_valid(body):
			continue
		var u := body as Unit
		if u.is_dead or u.is_base_unit or u.team != team:
			continue
		if is_unit_boxed(u, box, min_ratio):
			result.append(u)
	return result

## 取鼠标落点附近最近的敌方存活单位（左键下达攻击令用）；半径内没有则返回 null
## 基地 / 水晶本体排除在外 —— 攻击锁定只针对可移动的敌军单位
static func pick_enemy_at(container: Node, world_pos: Vector2, own_team: int,
		radius: float = ATTACK_PICK_RADIUS) -> Unit:
	if container == null or not is_instance_valid(container):
		return null
	var nearest: Unit = null
	var nearest_dist: float = radius
	for body in container.get_children():
		if not (body is Unit) or not is_instance_valid(body):
			continue
		var u := body as Unit
		if u.is_dead or u.is_base_unit or u.team == own_team:
			continue
		var d: float = u.global_position.distance_to(world_pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = u
	return nearest

## 剔除已失效 / 已阵亡的成员，返回新数组（选中集合每帧过一遍，免得画到已回池的单位上）
static func prune(units: Array[Unit]) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u != null and is_instance_valid(u) and not u.is_dead:
			result.append(u)
	return result

## 对选中单位下达编队移动令：以 [param center] 为中心按方阵分配落点，全部夹断在 [param bounds] 内。
## 移动令与攻击锁定互斥 —— 下移动令即清掉玩家指定的攻击目标，并强制切回 move 状态执行，
## 否则正在交战的单位会打完当前目标才理会指令（表现为「我的兵不听指挥」）。
## 返回实际接到指令的单位数
static func issue_move_order(units: Array[Unit], center: Vector2, bounds: Rect2,
		spacing: float = FORMATION_SPACING) -> int:
	var alive: Array[Unit] = prune(units)
	if alive.is_empty():
		return 0
	var n: int = alive.size()
	var cols: int = int(ceil(sqrt(float(n))))
	var rows: int = int(ceil(float(n) / float(cols)))
	var anchor: Vector2 = clamp_to_bounds(center, bounds)
	for idx in range(n):
		var u: Unit = alive[idx]
		var gx: int = idx % cols
		var gy: int = idx / cols
		## 纵向居中按实际行数算（用 cols 会让行数≠列数时整个阵列偏心）
		var offset := Vector2(
			(float(gx) - float(cols - 1) * 0.5) * spacing,
			(float(gy) - float(rows - 1) * 0.5) * spacing)
		u.clear_forced_target()
		u.order_pos = clamp_to_bounds(anchor + offset, bounds)
		u.hold_position = true
		u.target = null
		u.change_state("move")
	return n

## 对选中单位下达攻击锁定令：全体改打 [param enemy]，锁定期间不自动换目标、
## 不受肉鸽水晶牵引半径约束，直到该敌人阵亡或玩家改令。返回实际接到指令的单位数
static func issue_attack_order(units: Array[Unit], enemy: Unit) -> int:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead:
		return 0
	var n: int = 0
	for u in prune(units):
		if u.is_base_unit or u.team == enemy.team:
			continue
		u.set_forced_target(enemy)
		n += 1
	return n

## 世界坐标夹断到矩形内（bounds 面积为 0 时原样返回，便于不限制活动范围的场景）
static func clamp_to_bounds(p: Vector2, bounds: Rect2) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return p
	return Vector2(
		clampf(p.x, bounds.position.x, bounds.end.x),
		clampf(p.y, bounds.position.y, bounds.end.y))

## 手动生成椭圆取点（避免 draw_ellipse 在不同 Godot 版本的签名差异）
## segments+1 个点闭合首尾，draw_polyline 不自动闭环
static func ellipse_points(center: Vector2, rx: float, ry: float, segments: int = 24) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in range(segments + 1):
		var a: float = float(i) / float(segments) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## 在指定画布上填充一个椭圆
static func draw_ellipse_filled(layer: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	layer.draw_polygon(ellipse_points(center, rx, ry), [color])
