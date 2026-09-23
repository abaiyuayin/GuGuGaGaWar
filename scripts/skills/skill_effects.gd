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
##
## ⚠️ 有两类效果**不经过本函数**，它们由 state_skill 的专属动作流程直接驱动
##（本函数的 match 里因此没有分支，落到这里就是无声无息，不是 bug）：
##   giant_strike        Hero2 巨化重击：变大/挥击/缩回是动作流程，命中帧才回来取伤害表
##   orb_charge_launch   Hero3 充能光球：四段充能与发射是动作流程，光球本体是 SkillOrb
##
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
		"frame_hold_backburst":
			_frame_hold_backburst(caster, effect)
		"multi_lock_volley":
			_multi_lock_volley(caster, effect)
		"summon_heroes":
			_summon_heroes(caster, effect)

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

## ── 回身七连（Hero4 咕咕嘎嘎，2026-09-20）──────────────────────────
## 由 state_skill 的「帧定格」流程在判定帧位移**结束后**调用（此时施法者已完成 150px 冲刺）。
## 本函数负责「打了什么」——
##   ① 判定走廊 = 沿身后方向 0 ~ back_length、横向 ±back_half_width（150 × 100）
##   ② 视觉：fx_count 道特效沿走廊均匀分布（0 = 位移起点，最后一道 = 位移终点），
##      在 fx_spread_time 内自起点向终点一道道蔓延；攻击动画播完后由调用方统一渐隐
##   ③ 队列出伤：**等红光全部铺完之后**才开始，在 damage_window 内串行打完 hit_count 段
## 位移与动画定格由 state_skill 负责，本函数不改位置。
static func _frame_hold_backburst(caster: Node2D, effect: Dictionary) -> void:
	apply_hold_backburst(caster, effect)

## 帧定格型技能的效果入口，返回本批冲击特效列表（供调用方在攻击动画结束时统一渐隐）
##
## 时序（用户拍板 2026-09-20）：**红光全部铺完之后**才结算伤害。
## 两件事串在**同一条协程**里保证严格先后 —— 若各自挂一个并行定时器，
## 两个 0.6s 的计时器会碰在同一帧上，谁先谁后不确定（伤害可能抢在最后一道红光前面）。
static func apply_hold_backburst(caster: Node2D, effect: Dictionary) -> Array:
	var fx_list := _spawn_back_impact_fx(caster, effect)
	_run_back_burst_sequence(caster, effect, fx_list)  ## 协程：铺红光 → 再出伤害
	return fx_list

## 红光铺开 → 伤害队列，严格串行
static func _run_back_burst_sequence(caster: Node2D, effect: Dictionary, fx_list: Array) -> void:
	await _start_fx_sweep(caster, effect, fx_list)
	await _run_back_burst_queue(caster, effect)

## 队列出伤：在红光全部铺完之后才开始，段间严格串行（await 定时器），前一段结算完才出下一段。
## interval = damage_window / hits（而非 / (hits-1)）：留一点收尾余量，
## 保证最后一段不会正好压在第二次停顿的结束帧上（浮点边界容易溢出到 TAIL）。
## 每段都重新索敌——敌人在这段时长内可能进出矩形带，锁死首帧名单会打空。
static func _run_back_burst_queue(caster: Node2D, effect: Dictionary) -> void:
	var hits: int = maxi(int(effect.get("hit_count", 1)), 1)
	var window: float = maxf(float(effect.get("damage_window", 0.0)), 0.0)
	var interval: float = window / float(hits)
	var dmg: int = int(effect.get("damage", 0))
	var dtype: int = int(effect.get("damage_type", 0))
	## 先取场景树引用：caster 可能在等待期间被回收，之后再取会报错
	var tree: SceneTree = caster.get_tree()
	if tree == null:
		return
	for i in range(hits):
		if caster == null or not is_instance_valid(caster) or caster.is_dead:
			return
		for e in _find_enemies_in_back_rect(caster, effect):
			if e != null and is_instance_valid(e) and not e.is_dead:
				e.take_damage_typed(dmg, dtype, caster)
		if i < hits - 1 and interval > 0.0:
			await tree.create_timer(interval).timeout

## 沿走廊均匀生成 fx_count 道命中特效（先隐藏，等 _start_fx_sweep 一道道点亮）。
##
## 位置不再是矩形带内随机：第 i 道固定落在「距施法者身后 back_length × (1 - t)」处，
## t = i / (count - 1)，于是 i = 0 正好是**位移起点**、最后一道正好是**位移终点**，
## 满足「平均分布 + 从位移开始位置往位移结束位置蔓延」。
## 横向仍取 ±back_half_width 内随机，避免连成一条死板的直线。
## 返回 fx 节点列表（顺序 = 起点 → 终点）。
static func _spawn_back_impact_fx(caster: Node2D, effect: Dictionary) -> Array:
	var parent: Node = caster.get_parent()
	var result: Array = []
	if parent == null:
		return result
	var count: int = maxi(int(effect.get("fx_count", 0)), 0)
	if count <= 0:
		return result
	var frames_path: String = String(effect.get("fx_frames", ""))
	var frames: SpriteFrames = null
	if not frames_path.is_empty() and ResourceLoader.exists(frames_path):
		frames = load(frames_path) as SpriteFrames
	var length: float = float(effect.get("back_length", 150.0))
	var half_w: float = float(effect.get("back_half_width", 50.0))
	var fx_h: float = float(effect.get("fx_height", 0.0))
	var fx_w: float = float(effect.get("fx_width", 0.0))
	var back: float = -float(caster.facing_dir)  ## 身后方向 = 朝向的反向
	var last_idx: int = maxi(count - 1, 1)
	for i in range(count):
		var t: float = float(i) / float(last_idx)
		## 身后距离：位移终点（caster 当前位置）= 0，位移起点 = back_length
		var along: float = length * (1.0 - t)
		var lateral: float = randf_range(-half_w, half_w)
		var fx := ImpactEffect.new()
		fx.frames = frames
		fx.display_height = fx_h
		fx.display_width = fx_w
		fx.team = int(caster.team)
		fx.hold_after_finish = true  ## 播完定格末帧，等攻击动画结束统一渐隐
		fx.start_deferred = true  ## 创建时隐藏，等待蔓延到它
		## 必须先入场景树再设 global_position，否则父节点变换未生效会导致位置偏移
		parent.add_child(fx)
		fx.global_position = caster.global_position + Vector2(back * along, lateral)
		fx.rotation = randf_range(0.0, TAU)
		result.append(fx)
	return result

## 蔓延协程：在 fx_spread_time 内自「位移起点」向「位移终点」一道道点亮特效。
## 间隔 = fx_spread_time / (count - 1)，保证最后一道正好在 fx_spread_time 时刻出现。
static func _start_fx_sweep(caster: Node2D, effect: Dictionary, fx_list: Array) -> void:
	var count: int = fx_list.size()
	if count <= 0:
		return
	var spread: float = maxf(float(effect.get("fx_spread_time", 1.5)), 0.0)
	var interval: float = spread / float(maxi(count - 1, 1))
	var tree: SceneTree = caster.get_tree() if caster != null and is_instance_valid(caster) else null
	for i in range(count):
		if i > 0 and interval > 0.0:
			if tree == null:
				break
			await tree.create_timer(interval).timeout
		var fx = fx_list[i]
		if fx != null and is_instance_valid(fx):
			fx.begin()

## 统一渐隐：对整批特效同时施加 duration 秒的淡出（Hero4 在攻击动画结束时调用）
static func fade_out_fx(fx_list: Array, duration: float) -> void:
	for fx in fx_list:
		if fx != null and is_instance_valid(fx):
			fx.fade_out(duration)

## ── 九箭齐射（Hero5 糯糯，2026-09-20）────────────────────────────
## 本效果**不改变动作流程**：只是给施法者挂上「接下来 charges 次普攻改为多目标齐射」的状态，
## 本次攻击周期照常播放攻击动画，九箭在命中帧由 unit_base._fire_skill_volley 发射。
## 之所以不走 state_skill：技能要求的「持续两次攻击」本质就是两次普通攻击，
## 另起一套定格动作只会打断攻击动画的连贯性。
static func _multi_lock_volley(caster: Node2D, effect: Dictionary) -> void:
	caster.skill_volley_charges = maxi(int(effect.get("charges", 1)), 1)
	caster.skill_volley_params = effect.duplicate(true)
	## 霸体（2026-09-20 用户拍板「英雄们在使用技能的时候都获得霸体效果」）。
	## 九箭是 inline 效果、不切 state_skill，拿不到 state_skill.enter() 里的那次置位，
	## 所以在这里手动开、在 state_attack 把剩余次数打到 0 时关（见 _finish_attack_cycle）。
	caster.skill_super_armor = true

## ── 四方英灵（Hero1 爱弥斯，2026-09-20）────────────────────────────
## 在施法者身边召唤四位英雄（糯糯Hero / 菲比Hero / 咕咕嘎嘎Hero / Doro勇士），
## 全部归入施法者阵营。召唤出来的英雄是**缩水版**（用户拍板）：
##   没有护盾、不能放技能、生命上限与伤害各减半 —— 具体削弱落在 Unit.apply_summoned_penalty()。
static func _summon_heroes(caster: Node2D, effect: Dictionary) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var ids: Array = effect.get("hero_ids", [])
	if ids.is_empty():
		return
	var team: int = int(caster.team)
	## 环形分布在施法者周围：从正上方开始均分一圈，避免四个英雄重叠在一格
	var radius: float = float(effect.get("spawn_radius", 70.0))
	var total: int = ids.size()
	for i in range(total):
		var hero_id: String = String(ids[i])
		var res: UnitResource = UnitDatabase.get_unit(hero_id) as UnitResource
		if res == null:
			continue
		var angle: float = TAU * float(i) / float(total) - PI * 0.5
		var pos: Vector2 = caster.global_position + Vector2(cos(angle), sin(angle)) * radius
		## 出生点钳制在战场内，避免召唤到空气墙外面
		pos.x = clampf(pos.x, Constants.FIELD_X_MIN, Constants.FIELD_X_MAX)
		pos.y = clampf(pos.y, Constants.FIELD_Y_MIN, Constants.FIELD_Y_MAX)
		var unit: Node2D = BattleManager.spawn_unit(res, team, pos)
		if unit == null or not is_instance_valid(unit):
			continue
		## 援军削弱：没有护盾 / 不能放技能 / 生命与伤害减半
		unit.apply_summoned_penalty()
	_spawn_shockwave(caster, caster.global_position, 140.0)

## ── 充能光球（Hero3 菲比，2026-09-20）────────────────────────────
## 生成并挂载光球本体（SkillOrb）。动作流程（四段充能 → 发射）在 state_skill 里，
## 形态推进与发射由 state_skill 在判定帧调用 set_charge_stage() / launch()。
## 必须先入场景树再设 global_position，否则父节点变换未生效会导致位置偏移
##（与 ImpactEffect / 投射物同一惯例）。
static func spawn_charge_orb(caster: Node2D, effect: Dictionary) -> SkillOrb:
	if caster == null or not is_instance_valid(caster):
		return null
	var parent: Node = caster.get_parent()
	if parent == null:
		return null
	var orb := SkillOrb.new()
	orb.setup(caster, effect)
	parent.add_child(orb)
	orb.global_position = caster.global_position + Vector2(0.0, float(effect.get("orb_offset_y", -70.0)))
	return orb

## 把技能定义里的伤害字典（伤害类型 → 数值）转成 take_damage_typed 管线用的伤害列表
## [{"type": int, "value": int}, ...]。
## 键兼容 int（数据表里直接写 0/2）与 String（外部 JSON 来源）两种写法。
static func build_damage_entries(raw: Dictionary) -> Array:
	var entries: Array = []
	for key in raw.keys():
		entries.append({"type": int(key), "value": int(raw[key])})
	return entries

## 施法者身后矩形带内的敌方单位。
## 矩形定义：原点为施法者当前位置，沿身后方向 0 ~ back_length、横向 ±back_half_width。
## 先用外接圆粗筛（复用 Battlefield.get_units_in_radius，纯查询无副作用），再按矩形精筛。
static func _find_enemies_in_back_rect(caster: Node2D, effect: Dictionary) -> Array:
	var length: float = float(effect.get("back_length", 150.0))
	var half_w: float = float(effect.get("back_half_width", 50.0))
	if length <= 0.0 or half_w <= 0.0:
		return []
	var back: float = -float(caster.facing_dir)
	var center: Vector2 = caster.global_position + Vector2(back * length * 0.5, 0.0)
	var outer_r: float = sqrt(length * length * 0.25 + half_w * half_w)
	var result: Array = []
	for e in _find_enemies(caster, center, outer_r):
		if e == null or not is_instance_valid(e):
			continue
		var rel: Vector2 = e.global_position - caster.global_position
		var along: float = rel.x * back
		if along >= 0.0 and along <= length and absf(rel.y) <= half_w:
			result.append(e)
	return result

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
