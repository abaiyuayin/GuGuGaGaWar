class_name SkillOrb
extends Node2D
## 菲比（Hero3）技能「充能光球」的实体（2026-09-20）
##
## 生命周期：
##   CHARGE   跟随施法者头顶悬停，随技能前三段动作依次变大（60 → 90 → 130px 直径）
##   FLY      第四段被发射：沿面朝方向匀速推进，走完 fly_distance 后自爆
##   EXPLODE  对爆炸半径内敌人结算一次大额魔法伤害，播完爆炸视觉后自毁
##
## 视觉全部程序化生成、不新增素材（与 ImpactEffect 同一套做法）：
##   ① 核心：白色径向渐变柔光球（复用 ImpactEffect 的共享贴图）
##   ② 星云：两圈带「透明 → 亮 → 暗 → 透明」渐变的 Line2D 光环，正反反向缓慢旋转，
##      形成「一圈流动的光套住光球」的观感
##
## 判定口径（用户拍板「光球多大，判定范围就多大」）：
##   推进途中每 tick_interval 秒判定一次，半径 = 光球当前半径；吸附强度用**施加瞬间**的半径判断，
##   敌方 → 沿「敌 → 球」方向拉近 pull_px + tick_damage 点魔法伤害；
##   友方 → heal_amount 点治疗（只回血量、不动护盾；满血时 heal() 自然返回 0）。
##
## ⚠️ 刻意不走 body_entered 碰撞：需求是「沿途持续吸附/治疗 + 飞到最远端才爆炸」，
## 碰到第一个敌人就消失会直接废掉整个技能。所有结算都由周期判定与终点爆炸完成，
## 因此本节点也不设任何碰撞层。

enum OrbState { CHARGE, FLY, EXPLODE }

## 硬性寿命兜底（秒）：任何异常导致既没爆也没回收时强制销毁，避免节点永久残留
const MAX_LIFETIME: float = 12.0

## 施法者（充能阶段跟随它、伤害归属也记在它头上）
var caster: Unit = null
## 光球所属阵营
var team: int = 0
## 技能 effect 参数字典（由 SkillEffects.spawn_charge_orb 注入）
var effect: Dictionary = {}

## 当前状态
var _state: int = OrbState.CHARGE
## 当前直径（像素）—— 判定半径恒为它的一半
var _diameter: float = 60.0
## 悬停点相对施法者的偏移
var _offset: Vector2 = Vector2(0.0, -70.0)
## 推进方向 / 速度 / 已走距离 / 行程
var _dir: Vector2 = Vector2.RIGHT
var _speed: float = 200.0
var _traveled: float = 0.0
var _distance: float = 256.0
## 周期判定的间隔与倒计时
var _tick_interval: float = 0.5
var _tick_timer: float = 0.0
## 爆炸半径
var _explode_radius: float = 160.0
## 战场节点（索敌用；单位容器 → 战场）
var _battlefield: Node = null
## 累计寿命
var _life: float = 0.0

## 核心柔光球
var _core: Sprite2D = null
## 推进全程锁定的 Y 坐标（战场垂直居中，launch 时确定）
var _center_y: float = 0.0

## 初始化（必须在 add_child 之前调用：_ready() 依赖这些字段搭视觉）
func setup(caster_unit: Unit, skill_effect: Dictionary) -> void:
	caster = caster_unit
	effect = skill_effect
	team = int(caster_unit.team) if caster_unit != null else 0
	_offset = Vector2(0.0, float(effect.get("orb_offset_y", -70.0)))
	_speed = float(effect.get("fly_speed", 200.0))
	_tick_interval = maxf(float(effect.get("tick_interval", 0.5)), 0.05)
	_explode_radius = float(effect.get("explode_radius", 160.0))
	## 行程 = 显式配的 fly_distance；未配（<=0）则用施法者自身攻击范围 ×32 ——
	## 即用户拍板的「推到自身攻击范围之外时爆炸」（菲比 attack_range 8.0 → 256px）
	var dist: float = float(effect.get("fly_distance", 0.0))
	if dist <= 0.0 and caster_unit != null and caster_unit.unit_resource != null:
		dist = caster_unit.unit_resource.attack_range * Constants.UNIT_TO_PIXELS
	_distance = maxf(dist, 32.0)
	## 战场节点：单位挂在 Battlefield/UnitContainer 下，故上溯两级
	if caster_unit != null and caster_unit.get_parent() != null:
		_battlefield = caster_unit.get_parent().get_parent()

func _ready() -> void:
	z_index = 6  ## 画在单位之上，避免被单位精灵挡住
	_diameter = _diameter_for_stage(0)
	_core = Sprite2D.new()
	_core.name = "OrbCore"
	_core.texture = ImpactEffect._get_glow_texture()
	_core.modulate = Color(1.0, 1.0, 1.0, 1.0)  ## 纯白（用户拍板：就用默认那颗白球）
	add_child(_core)
	_apply_diameter()

## ============================================================
## 对外接口
## ============================================================

## 推进到第 stage 档形态（0 = 出现，1/2 = 两次变大）；越界取最后一档
func set_charge_stage(stage: int) -> void:
	if _state != OrbState.CHARGE:
		return
	_diameter = _diameter_for_stage(stage)
	_apply_diameter()

## 发射：先「归位」到施法者身体中心，再锁在战场垂直居中线上沿面朝方向推进
func launch() -> void:
	if _state != OrbState.CHARGE:
		return
	_state = OrbState.FLY
	var dir: float = 1.0
	var is_caster_alive: bool = caster != null and is_instance_valid(caster)
	if is_caster_alive:
		dir = 1.0 if caster.facing_dir >= 0 else -1.0
	_dir = Vector2(dir, 0.0)
	## 归位：从头顶悬停点回到施法者身体中心（X 取施法者当前 X）。
	## 推进全程 Y 锁在战场垂直居中线上（= 单位活动带 FIELD_Y_MIN~FIELD_Y_MAX 的中线）。
	_center_y = (Constants.FIELD_Y_MIN + Constants.FIELD_Y_MAX) * 0.5
	var origin_x: float = caster.global_position.x if is_caster_alive else global_position.x
	global_position = Vector2(origin_x, _center_y)
	## 发射瞬间立刻判定一次：让贴着光球的那一圈马上吃到吸附/治疗，而不是等 0.5 秒
	_tick_timer = 0.0

## 是否仍在充能阶段（技能状态退出时据此决定「该不该回收」——已发射的光球要留活口）
func is_charging() -> bool:
	return _state == OrbState.CHARGE

## ============================================================
## 逐帧推进
## ============================================================
func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME:
		queue_free()
		return
	if _state == OrbState.CHARGE:
		_process_charge()
	elif _state == OrbState.FLY:
		_process_fly(delta)

## 充能：贴在施法者头顶。施法者阵亡/失效则直接消失，避免光球孤零零挂在场上
func _process_charge() -> void:
	if caster == null or not is_instance_valid(caster) or caster.is_dead:
		queue_free()
		return
	global_position = caster.global_position + _offset

## 推进：沿面朝方向前进（Y 锁在战场垂直居中线上）+ 周期判定；走完行程即爆
func _process_fly(delta: float) -> void:
	var step: float = _speed * delta
	global_position.x += _dir.x * step
	global_position.y = _center_y  ## 全程保持战场垂直居中
	_traveled += step
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = _tick_interval
		_apply_tick()
	if _traveled >= _distance:
		_explode()

## ============================================================
## 判定与结算
## ============================================================

## 一次周期判定：敌方吸附 + 魔法伤害；友方治疗。半径 = 光球当前半径。
func _apply_tick() -> void:
	var radius: float = _diameter * 0.5
	var tick_damage: int = int(effect.get("tick_damage", 0))
	var tick_dtype: int = int(effect.get("tick_damage_type", 3))
	var pull: float = float(effect.get("pull_px", 0.0))
	var heal_amount: int = int(effect.get("heal_amount", 0))

	if tick_damage > 0 or pull > 0.0:
		for e in _units_in_radius(1 - team, radius):
			if e == null or not is_instance_valid(e) or e.is_dead:
				continue
			## 吸附：apply_knockback 的位移方向是「from → 自己」，把 from 取在敌人**背离光球**的
			## 一侧（敌人位置 + 敌人指向外的向量），合成方向就变成「朝光球拉近」。
			## 复用它 = 走既有平滑位移（KNOCKBACK_DURATION 秒内完成），不是瞬移。
			var away: Vector2 = e.global_position - global_position
			if pull > 0.0 and away.length() > 0.01:
				e.apply_knockback(e.global_position + away, pull)
			if tick_damage > 0 and is_instance_valid(e) and not e.is_dead:
				e.take_damage_typed(tick_damage, tick_dtype, caster)

	## 友方：只回血、不吸附。heal() 内部按最大生命封顶，满血自然返回 0，且完全不碰护盾
	##（用户拍板「满血时不恢复护盾」）。
	if heal_amount > 0:
		for a in _units_in_radius(team, radius):
			if a == null or not is_instance_valid(a) or a.is_dead:
				continue
			a.heal(heal_amount)

## 行程终点爆炸：范围内敌人吃一次大额魔法伤害 + 播爆炸视觉
func _explode() -> void:
	if _state == OrbState.EXPLODE:
		return
	_state = OrbState.EXPLODE
	var dmg: int = int(effect.get("explode_damage", 0))
	var dtype: int = int(effect.get("explode_damage_type", 3))
	if dmg > 0:
		for e in _units_in_radius(1 - team, _explode_radius):
			if e == null or not is_instance_valid(e) or e.is_dead:
				continue
			e.take_damage_typed(dmg, dtype, caster)
	_spawn_explosion_fx()
	queue_free()

## 取半径内指定阵营的单位。Battlefield.get_units_in_radius 是纯查询（已排除基地与死亡单位），
## 与 SkillEffects 的索敌同口径，不会偷走单位自身索敌 AI 的节流预算。
func _units_in_radius(team_filter: int, radius: float) -> Array:
	if _battlefield == null or not is_instance_valid(_battlefield):
		return []
	if not _battlefield.has_method("get_units_in_radius"):
		return []
	return _battlefield.get_units_in_radius(global_position, radius, team_filter)

## ============================================================
## 视觉
## ============================================================

## 第 stage 档形态的直径（stage 从 0 开始；越界取最后一档，空表兜底 60）
func _diameter_for_stage(stage: int) -> float:
	var list: Array = effect.get("orb_diameters", [])
	if list.is_empty():
		return 60.0
	return float(list[clampi(stage, 0, list.size() - 1)])

## 造一圈「流动的光」（已按用户要求移除，保留说明以免后人以为漏写）：
## 原实现是两圈带渐变的闭合 Line2D 光环反向旋转。用户实测后要求「把白球周围那一圈删了」，
## 现在光球本体只有一颗纯白柔光核心，不再有环绕光环。
## ⚠️ 若将来要恢复光环：半径必须用**重建点位**而不是缩放节点 ——
## Line2D 的 width 会被 scale 一起放大，光球变大时光环线宽会粗得离谱。

## 按当前直径重建核心缩放。
func _apply_diameter() -> void:
	if _core != null and _core.texture != null:
		var tex_size: float = float(_core.texture.get_width())
		_core.scale = Vector2.ONE * (_diameter / maxf(tex_size, 1.0))

## 爆炸视觉：向外扩张并淡出的光环 + 中心闪光。
## 必须挂到**父节点**而不是光球自己 —— 光球紧接着就 queue_free 了。
func _spawn_explosion_fx() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var ring := Line2D.new()
	ring.width = 6.0
	ring.default_color = Color(1.0, 1.0, 1.0, 0.95)
	ring.z_index = 60
	var pts := PackedVector2Array()
	for i in range(41):
		var a: float = TAU * float(i) / 40.0
		pts.append(Vector2(cos(a), sin(a)) * _explode_radius)
	ring.points = pts
	ring.scale = Vector2.ONE * 0.25
	parent.add_child(ring)
	ring.global_position = global_position

	var flash := Sprite2D.new()
	flash.texture = ImpactEffect._get_glow_texture()
	flash.modulate = Color(1.0, 1.0, 1.0, 0.90)
	flash.z_index = 59
	var flash_end: float = _explode_radius * 2.0 / 32.0
	flash.scale = Vector2.ONE * (flash_end * 0.40)
	parent.add_child(flash)
	flash.global_position = global_position

	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE, 0.28).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.34)
	tw.tween_property(flash, "scale", Vector2.ONE * flash_end, 0.30).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.30)
	tw.finished.connect(ring.queue_free)
	tw.finished.connect(flash.queue_free)
