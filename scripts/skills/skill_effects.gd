class_name SkillEffects
extends RefCounted
## 技能效果函数库（标准模式）
##
## 职责边界：本文件只负责「技能造成什么结果」，不管「何时释放」（UnitSkillComponent 负责）
## 也不管「动作流程」（state_skill.gd 负责）。三者分离，便于各自独立测试与修改。
##
## 全部效果都复用 unit_base.gd 中已有的战斗原语，不重复实现伤害/击退/减速逻辑：
##   Battlefield.get_units_in_radius()  范围索敌
##   Unit.take_damage_typed()           分类型伤害（护甲/护盾分配规则统一）
##   Unit.apply_knockback()             平滑击退位移（非瞬移）
##   Unit.apply_skill_slow()            技能减速（独立于冰霜词条，见 unit_base.gd）
##
## 新增技能：在 apply() 的 match 里加一个分支 + 写一个 _xxx 静态函数即可。

## 效果总入口：按 effect.kind 分发
## caster    释放技能的单位
## def       技能定义（UnitSkillDatabase.SKILL_DEFS 中的一项）
## target_pos 技能落点（光柱等指定位置技能使用；自身范围技能忽略）
static func apply(caster: Node2D, def: Dictionary, target_pos: Vector2) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var effect: Dictionary = def.get("effect", {})
	match String(effect.get("kind", "")):
		"slam":
			_slam(caster, effect)
		"pillar":
			_pillar(caster, effect, target_pos)
		"dash_strike":
			_dash_strike(caster, effect)
		"no_recovery_buff":
			_no_recovery_buff(caster, effect)

## ── 巨剑下砸（Hero2）────────────────────────────────────────────
## 以自身为圆心的圆形范围：伤害 + 击退 + 减速
static func _slam(caster: Node2D, effect: Dictionary) -> void:
	var radius: float = float(effect.get("radius", 100.0))
	var enemies := _find_enemies(caster, caster.global_position, radius)
	for e in enemies:
		e.take_damage_typed(int(effect.get("damage", 0)), int(effect.get("damage_type", 2)), caster)
		if not is_instance_valid(e) or e.is_dead:
			continue
		var kb: float = float(effect.get("knockback_px", 0.0))
		if kb > 0.0:
			e.apply_knockback(caster.global_position, kb)
		var slow: float = float(effect.get("slow_percent", 0.0))
		if slow > 0.0:
			e.apply_skill_slow(slow, float(effect.get("slow_duration", 0.0)))
	_spawn_shockwave(caster, caster.global_position, radius)

## ── 圣光降临（Hero3）────────────────────────────────────────────
## 在 target_pos 落下光柱，对落点圆形范围造成魔法伤害
static func _pillar(caster: Node2D, effect: Dictionary, target_pos: Vector2) -> void:
	var radius: float = float(effect.get("radius", 60.0))
	var enemies := _find_enemies(caster, target_pos, radius)
	for e in enemies:
		e.take_damage_typed(int(effect.get("damage", 0)), int(effect.get("damage_type", 3)), caster)
	_spawn_pillar_visual(caster, target_pos, radius)

## ── 破阵突袭（Hero4，预留）──────────────────────────────────────
## 向面朝方向位移，位移结束后对身后走廊造成多段伤害
static func _dash_strike(caster: Node2D, effect: Dictionary) -> void:
	var dash_px: float = float(effect.get("dash_px", 0.0))
	if dash_px <= 0.0:
		return
	var dir: Vector2 = Vector2(float(caster.facing_dir), 0.0)
	var start_pos: Vector2 = caster.global_position
	var end_pos: Vector2 = start_pos + dir * dash_px
	end_pos.x = clampf(end_pos.x, Constants.FIELD_X_MIN, Constants.FIELD_X_MAX)
	var tween := caster.create_tween()
	tween.tween_property(caster, "global_position", end_pos, float(effect.get("dash_time", 0.35))) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.finished.connect(_dash_strike_settle.bind(caster, effect, start_pos))

## 位移结束后的多段伤害结算：对起点到终点之间的走廊范围反复命中
static func _dash_strike_settle(caster: Node2D, effect: Dictionary, start_pos: Vector2) -> void:
	if caster == null or not is_instance_valid(caster) or caster.is_dead:
		return
	var mid: Vector2 = (start_pos + caster.global_position) * 0.5
	var half_len: float = start_pos.distance_to(caster.global_position) * 0.5
	var width: float = float(effect.get("trail_width", 90.0))
	var enemies := _find_enemies(caster, mid, maxf(half_len, width))
	var hits: int = int(effect.get("hit_count", 1))
	var dmg: int = int(effect.get("damage", 0))
	var dtype: int = int(effect.get("damage_type", 0))
	for _i in range(hits):
		for e in enemies:
			if is_instance_valid(e) and not e.is_dead:
				e.take_damage_typed(dmg, dtype, caster)

## ── 骑射（Hero5，预留）──────────────────────────────────────────
## 一段时间内取消攻击后摇
static func _no_recovery_buff(caster: Node2D, effect: Dictionary) -> void:
	caster.skill_no_recovery_timer = float(effect.get("duration", 0.0))

## ── 通用工具 ────────────────────────────────────────────────────
## 查找 center 半径内最近的敌方单位（**无副作用**）
##
## 刻意不复用 Unit.find_nearest_enemy_in_range()：那个方法内部调用 _pathfind_ready()，
## 会推进并重置单位的索敌节流累加器 _pathfind_accum。技能组件每物理帧都要判定触发条件，
## 若调用它会「偷走」单位自身移动/攻击 AI 的索敌预算，导致普通行为退化。
## 本函数直接走 Battlefield.get_units_in_radius()（纯查询，已排除基地与死亡单位）。
## 返回 null 表示范围内无敌人。
static func find_nearest_enemy(caster: Node2D, max_range: float) -> Node2D:
	var candidates := _find_enemies(caster, caster.global_position, max_range)
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for e in candidates:
		var d: float = caster.global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

## 查找 center 半径内的敌方单位（敌方 = 与 caster 不同 team）
static func _find_enemies(caster: Node2D, center: Vector2, radius: float) -> Array:
	var battlefield: Node = _get_battlefield(caster)
	if battlefield == null or not battlefield.has_method("get_units_in_radius"):
		return []
	return battlefield.get_units_in_radius(center, radius, 1 - int(caster.team))

## 取战场节点（单位挂在 Battlefield/UnitContainer 下，故上溯两级）
static func _get_battlefield(caster: Node2D) -> Node:
	var container: Node = caster.get_parent()
	if container == null:
		return null
	return container.get_parent()

## 下砸冲击波：由内向外扩张的圆环，淡出后自动销毁
## 用 Line2D（Node2D 派生）而非 Control，保证与单位处于同一 Node2D 坐标空间。
## 注意：Line2D.width 会被 scale 一起缩放，因此点位直接按最终半径生成，
## 只用 scale 做 0.25→1.0 的扩张动画（线宽随之由细变粗，正好符合冲击波观感）。
static func _spawn_shockwave(caster: Node2D, center: Vector2, radius: float) -> void:
	var parent: Node = caster.get_parent()
	if parent == null:
		return
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color(1.0, 0.85, 0.3, 0.9)
	ring.z_index = 60
	## 以 24 段折线近似圆环，点位按最终半径生成
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(25):
		var a: float = TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	ring.scale = Vector2.ONE * 0.25
	## 必须先入场景树再设 global_position，否则父节点变换未生效会导致位置偏移
	parent.add_child(ring)
	ring.global_position = center

	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE, 0.28).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.32)
	tw.finished.connect(ring.queue_free)

## 光柱视觉：自上而下的光束 + 落点光斑，淡出后自动销毁
## 同样使用 Node2D 派生的 Polygon2D，避免 Control 节点在 Node2D 容器中的定位问题。
static func _spawn_pillar_visual(caster: Node2D, center: Vector2, radius: float) -> void:
	var parent: Node = caster.get_parent()
	if parent == null:
		return
	var half_w: float = radius * 0.55
	## 光束：原点在落点（底部中心），向上延伸 420px
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([
		Vector2(-half_w, -420.0), Vector2(half_w, -420.0),
		Vector2(half_w, 0.0), Vector2(-half_w, 0.0),
	])
	beam.color = Color(1.0, 0.97, 0.75, 0.85)
	beam.z_index = 60
	beam.scale = Vector2(0.2, 1.0)
	parent.add_child(beam)
	beam.global_position = center

	## 落点光斑：扁椭圆，表示光柱砸地的范围
	var splash := Polygon2D.new()
	var sp: PackedVector2Array = PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		sp.append(Vector2(cos(a) * radius, sin(a) * radius * 0.35))
	splash.polygon = sp
	splash.color = Color(1.0, 1.0, 0.85, 0.7)
	splash.z_index = 59
	parent.add_child(splash)
	splash.global_position = center

	var tw := beam.create_tween()
	tw.set_parallel(true)
	tw.tween_property(beam, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(beam, "modulate:a", 0.0, 0.45).set_delay(0.12)
	tw.tween_property(splash, "modulate:a", 0.0, 0.45).set_delay(0.12)
	tw.finished.connect(beam.queue_free)
	tw.finished.connect(splash.queue_free)
