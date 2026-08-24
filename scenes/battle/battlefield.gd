extends Node2D  ## 继承 Node2D 节点
## 战场场景脚本
## 管理战场上的所有单位
## 负责单位的添加、基地的伤害计算和游戏结束判定
## 基地已从 ColorRect 水晶替换为兵种单位（红方=G5, 蓝方=D3），原地防御

## 节点引用：单位容器（所有战斗单位都添加到此节点下）
@onready var unit_container: Node2D = $UnitContainer  ## 获取场景中的单位容器节点

## 节点引用：红方基地 ColorRect（仅保留作为位置标记，实际不可见）
@onready var red_base: ColorRect = $RedBase  ## 获取场景中的红方基地节点
## 节点引用：蓝方基地 ColorRect（仅保留作为位置标记，实际不可见）
@onready var blue_base: ColorRect = $BlueBase  ## 获取场景中的蓝方基地节点

## 红方基地单位（G5，替代水晶）
var red_base_unit: Unit = null
## 蓝方基地单位（D3，替代水晶）
var blue_base_unit: Unit = null

## 红方基地当前 HP
var red_base_hp: int = Constants.BASE_HP  ## 红方基地初始 HP 为常量定义的最大值
## 蓝方基地当前 HP
var blue_base_hp: int = Constants.BASE_HP  ## 蓝方基地初始 HP 为常量定义的最大值

## 基地/水晶的最大耐久（量程）
## 普通模式 = Constants.BASE_HP；肉鸽模式 = Constants.ROGUELIKE_CRYSTAL_HP。
## 所有血条量程与治疗上限都必须读这里，不要再直接读 Constants.BASE_HP。
var base_max_hp: int = Constants.BASE_HP

## 本局是否为肉鸽水晶模式（#209）：仅玩家侧有一座水晶，敌方无基地
var is_crystal_mode: bool = false

## #需求21：基地水晶是否可主动攻击（开发工具开关，默认开）
## 战役/双人模式的基地水晶默认会攻击射程内敌人；开发工具可一键关闭，测试纯防御水晶
var crystal_can_attack: bool = true

## #开发工具：水晶无敌开关（默认关）——开无敌后红蓝双方水晶都不掉血（标准模式）
## 2026-08-21 用户拍板：仅标准模式（战役/全面战争/双人）生效，肉鸽水晶不受此开关影响。
## 在水晶受伤统一入口 damage_base 处拦截，覆盖所有会打水晶的路径（近战/远程/基地吐息/开发工具扣血）。
var crystal_invincible: bool = false

## 基地攻击配置：战场缩小后范围相应缩小
const BASE_ATTACK_RANGE: float = 160.0  ## 基地攻击范围（像素）
## #8（2026-08-09 用户拍板）：双方水晶单次伤害 100 -> 50
const BASE_ATTACK_DAMAGE: int = 50  ## 基地每次攻击造成的伤害值
const BASE_ATTACK_INTERVAL: float = 1.0  ## 基地攻击间隔时间（秒）

## 获取基地攻击范围（供单位移动状态使用）
func get_base_attack_range() -> float:  ## 定义获取基地攻击范围的方法，返回浮点数
	return BASE_ATTACK_RANGE  ## 返回基地攻击范围常量

## 获取水晶攻击开关（供开发工具菜单读取）
func get_crystal_can_attack() -> bool:
	return crystal_can_attack

## 获取水晶无敌开关（供开发工具菜单读取，无战场时返回 false）
func get_crystal_invincible() -> bool:
	return crystal_invincible

## 获取指定圆心半径内的存活单位（不含基地单位）
## center: 圆心（世界坐标）
## radius: 半径（像素）
## team_filter: 阵营过滤（0/1 只返回该阵营；-1 返回所有阵营）
## 返回: 命中单位数组（类型化，便于调用方遍历）
func get_units_in_radius(center: Vector2, radius: float, team_filter: int = -1) -> Array[Unit]:
	var result: Array[Unit] = []
	if radius <= 0.0:
		return result
	var r2: float = radius * radius
	for child in unit_container.get_children():
		if is_instance_valid(child) and child is Unit and not child.is_base_unit and not child.is_dead:
			if team_filter != -1 and child.team != team_filter:
				continue
			if center.distance_squared_to(child.global_position) <= r2:
				result.append(child)
	return result

## 信号：基地被摧毁时发出
## team: 被摧毁基地的阵营编号（0=红方被摧毁则蓝方胜，1=蓝方被摧毁则红方胜）
signal base_destroyed(team: int)  ## 定义基地被摧毁信号
## 信号：基地生命值变化时发出
## team: 阵营编号, hp: 当前 HP, max_hp: 最大 HP
signal base_hp_changed(team: int, hp: int, max_hp: int)  ## 定义基地 HP 变化信号
## 信号：基地受到攻击造成扣血时发出（用于扣血日志条）
## team: 被攻击方阵营编号, damage: 本次扣血值, attacker: 攻击者（Unit 或 base_unit，可能为 null）
signal base_damaged(team: int, damage: int, attacker: Node)  ## 定义基地扣血信号

## 节点就绪时自动调用
func _ready() -> void:  ## 重写 _ready 生命周期方法
	## 隐藏 ColorRect 基地（仅保留作为位置标记，实际用 G5/D3 单位替代）
	red_base.visible = false
	blue_base.visible = false
	## #209：肉鸽模式改为「玩家侧放置区正中心一座红色方块水晶」，敌方无基地。
	## 水晶被摧毁 = 本局失败；敌方阵营不再拥有可被攻击的基地。
	if RoguelikeManager.is_active:
		is_crystal_mode = true
		base_max_hp = Constants.ROGUELIKE_CRYSTAL_HP
		## #213：水晶耐久跨战斗保留 —— 继承 run 级 RoguelikeManager.crystal_hp（首场=满血）
		red_base_hp = RoguelikeManager.crystal_hp
		blue_base_hp = base_max_hp
		_spawn_roguelike_crystal()
	elif GameManager.is_battlefield_mode:
		## #竞技场（2026-08-24 用户拍板）：沙盒无胜负、无基地 → 完全不生成水晶。
		## has_base() 因 red/blue_base_unit 恒为 null 自然返回 false，单位不会去打空气。
		pass
	else:
		## 生成基地单位（红方=G5, 蓝方=D3）
		_spawn_base_units()
	## 基地攻击计时器已由基地单位自身的攻击逻辑处理，不再需要 ColorRect 时代的计时器
	## 转发 base_damaged 到 BattleManager（便于 HUD 等无直接 battlefield 引用的模块监听）
	## 注意：不能用 emit_signal.bind("base_damaged")，bind 是追加参数会把信号名塞到最后一位
	if not base_damaged.is_connected(_forward_base_damaged):
		base_damaged.connect(_forward_base_damaged)

## 把本场景的 base_damaged 原样转发给 BattleManager 全局信号
func _forward_base_damaged(team: int, damage: int, attacker: Node) -> void:
	BattleManager.base_damaged.emit(team, damage, attacker)

## 生成基地水晶实体（#23：红/蓝方块水晶替代 G5/D3 基地兵种）
## 水晶原地不动、不参与碰撞，可发射小型方块投射物攻击射程内敌人（见 state_base_defense）
func _spawn_base_units() -> void:
	## 红方水晶：红色方块，位于左侧道路尽头
	red_base_unit = _create_crystal_unit(0, Vector2(-576, 0), Color(0.9, 0.16, 0.16, 1.0))
	## 蓝方水晶：蓝色方块，位于右侧道路尽头
	blue_base_unit = _create_crystal_unit(1, Vector2(576, 0), Color(0.16, 0.4, 0.9, 1.0))

## 创建方块水晶实体（#23，战役/双人模式）
## 代码构造 UnitResource：不继承兵种护甲/攻击/动画。
## attack_range = BASE_ATTACK_RANGE(160px)/32 = 5.0 > RANGED_THRESHOLD(2.0) → is_ranged=true，
## perform_attack 走投射物路径，发射默认方块弹道（projectile 默认贴图即方块，按 team 染红/蓝）。
## box_color: 水晶方块颜色（红方红 / 蓝方蓝）
func _create_crystal_unit(team_id: int, pos: Vector2, box_color: Color) -> Unit:
	var res: UnitResource = UnitResource.new()
	res.unit_id = "CRYSTAL"
	res.display_name = tr("BATTLE_CRYSTAL")
	res.max_hp = base_max_hp
	res.armor_value = 0  ## 水晶无护甲，伤害全额进血量
	res.move_speed = 0.0
	res.damage = BASE_ATTACK_DAMAGE
	res.damage_type = 0  ## 挥砍类型（最简单，无克制交互）
	res.damage_types = [0]
	res.damage_by_type = {0: BASE_ATTACK_DAMAGE}
	res.attack_range = BASE_ATTACK_RANGE / Constants.UNIT_TO_PIXELS
	res.attack_speed = BASE_ATTACK_INTERVAL
	## 水晶投射物使用缩小版自身贴图（曲奇饼干/橘子）+ 自旋飞行
	var crystal_tex_path: String = "res://assets/crystal_red.png" if team_id == 0 else "res://assets/crystal_blue.png"
	if ResourceLoader.exists(crystal_tex_path):
		res.projectile_texture = load(crystal_tex_path)
	res.projectile_spin_speed = 720.0  ## 自旋 720°/秒（每秒转两圈）
	return _create_base_unit(res, team_id, pos, true, box_color)

## 生成肉鸽模式的水晶（#209）
## 红色方块，位于玩家侧放置区正中心，不攻击、不移动，被摧毁即本局失败。
## 用代码构造 UnitResource 而非复用兵种，避免继承兵种的护甲/攻击/动画。
func _spawn_roguelike_crystal() -> void:
	var res: UnitResource = UnitResource.new()
	res.unit_id = "CRYSTAL"
	res.display_name = tr("BATTLE_CRYSTAL")
	res.max_hp = Constants.ROGUELIKE_CRYSTAL_HP
	res.armor_value = 0  ## 水晶无护甲，伤害全额进血量，便于数值直观
	res.move_speed = 0.0
	res.damage = 0  ## 水晶不攻击
	res.attack_range = 0.5
	res.attack_speed = 1.0
	red_base_unit = _create_base_unit(res, 0, Constants.ROGUELIKE_CRYSTAL_POS, true)

## 获取指定阵营基地/水晶的世界坐标（供单位 AI 判定推进目标与回防锚点）
## team: 阵营编号（0=红方, 1=蓝方）
## 返回值: 基地世界坐标；该阵营无基地时返回其历史基地位置作为回退
func get_base_position(team: int) -> Vector2:
	var base_unit: Unit = red_base_unit if team == 0 else blue_base_unit
	if base_unit != null and is_instance_valid(base_unit) and not base_unit.is_dead:
		return base_unit.global_position
	if team == 0:
		return Constants.ROGUELIKE_CRYSTAL_POS if is_crystal_mode else Vector2(-576.0, 0.0)
	return Vector2(576.0, 0.0)

## 指定阵营是否拥有可被攻击的基地/水晶
## 肉鸽水晶模式下敌方（team=1）没有基地，玩家单位不应推进去攻击空气。
func has_base(team: int) -> bool:
	if is_crystal_mode and team == 1:
		return false
	var base_unit: Unit = red_base_unit if team == 0 else blue_base_unit
	return base_unit != null and is_instance_valid(base_unit) and not base_unit.is_dead

## 创建基地单位并添加到战场
## res: 兵种资源
## team_id: 阵营编号（0=红方, 1=蓝方）
## pos: 基地位置
## is_crystal: 是否为水晶外观（true 时套用方块外观，跳过兵种放大）
## crystal_color: 水晶方块颜色（默认红色，蓝方水晶传蓝色）
## 返回值: 创建的基地单位
func _create_base_unit(res: UnitResource, team_id: int, pos: Vector2, is_crystal: bool = false, crystal_color: Color = Constants.ROGUELIKE_CRYSTAL_COLOR) -> Unit:
	var unit_scene: PackedScene = load("res://scenes/units/unit_base.tscn")
	var unit: Unit = unit_scene.instantiate()
	## 标记为基地单位（在 setup 之前设置，确保 _finalize_setup 使用 base_defense 状态）
	unit.is_base_unit = true
	## 初始化单位（设置兵种资源和阵营）
	unit.setup(res, team_id)
	## 覆盖耐久为基地/水晶量程：buff_max_hp 必须同步覆盖，
	## 否则 get_max_hp() 仍返回兵种血量，血条量程与实际 HP 对不上。
	unit.buff_max_hp = base_max_hp
	## #213：水晶耐久跨战斗保留 —— 用已同步的 red/blue_base_hp 作为当前血，而非恒等于满血
	unit.current_hp = red_base_hp if team_id == 0 else blue_base_hp
	unit.global_position = pos
	## 添加到单位容器
	unit_container.add_child(unit)
	## 加入基地单位组，供游戏结束时统一冻结
	unit.add_to_group("base_unit")
	if is_crystal:
		## 方块水晶外观（#23：颜色可参数化，红方红 / 蓝方蓝 / 肉鸽默认红）
		## 必须在 _finalize_setup 之后执行，故用 deferred
		unit.call_deferred("apply_crystal_look",
			Constants.ROGUELIKE_CRYSTAL_SIZE, crystal_color)
	else:
		## 基地单位放大 2 倍（替代水晶的视觉存在感）
		## _finalize_setup 中会设置 sprite scale，此处用 call_deferred 在 finalize 后再放大
		unit.call_deferred("_apply_base_unit_scale")
	## 连接死亡信号，基地单位死亡时触发基地摧毁
	unit.unit_died.connect(_on_base_unit_died)
	## 发出初始 HP 变化信号（当前血 = 已同步的 red/blue_base_hp，水晶模式即继承的 run 级耐久）
	base_hp_changed.emit(team_id, red_base_hp if team_id == 0 else blue_base_hp, base_max_hp)
	return unit

## 基地单位死亡回调
## _unit: 死亡的基地单位
## killer_team: 击杀方阵营
## _killer_unit_id: 击杀者兵种 ID（#10 修复：unit_died 信号 2026-08-09 起携带第三参，
##   若签名仍停留在 2 参，信号连接因参数不匹配报错 → base_destroyed 永不发出 → 水晶扣光不结束）
func _on_base_unit_died(_unit: Unit, killer_team: int, _killer_unit_id: String = "") -> void:
	## 防重入：若基地已摧毁（HP 已为 0），不再重复触发胜负判定
	var destroyed_team: int = 1 - killer_team
	if destroyed_team == 0 and red_base_hp <= 0:
		return
	if destroyed_team == 1 and blue_base_hp <= 0:
		return
	## 击杀方获胜，被摧毁方失败
	## killer_team 是击杀方，所以被摧毁的是 1 - killer_team
	if destroyed_team == 0:
		red_base_hp = 0
	else:
		blue_base_hp = 0
	base_hp_changed.emit(destroyed_team, 0, base_max_hp)
	base_destroyed.emit(killer_team)

## 添加单位到战场
## unit: 要添加的单位节点
func add_unit(unit: Node2D) -> void:  ## 定义添加单位的方法
	## 将单位添加为单位容器的子节点
	unit_container.add_child(unit)  ## 将单位添加到单位容器

## 肉鸽水晶模式下，把玩家侧（team 0）基地当前 HP 同步回 RoguelikeManager.crystal_hp，
## 使其在 run 内跨战斗持久（#213）。非水晶模式或敌方基地时为空操作。
func _sync_crystal_persist() -> void:
	if RoguelikeManager.is_active and is_crystal_mode:
		RoguelikeManager.crystal_hp = red_base_hp

## 开发工具：为指定阵营水晶直接加血，溢出部分转为血量上限（#需求3）
## 语义：直接加血 + 溢出转上限 —— 例：
##   1000/1000 加 1000 → 2000/2000（上限同步提升）
##   500/1000  加 1000 → 1500/1500（未溢出，只加血）
##   1000/2000 加 1000 → 2000/2000（未溢出，只加血）
## team: 目标阵营（0=红方/玩家, 1=蓝方/AI）；amount: 加血量（<=0 时忽略）
func boost_base_hp(team: int, amount: int) -> void:
	if amount <= 0:
		return
	var base_unit: Unit = red_base_unit if team == 0 else blue_base_unit
	if base_unit == null or not is_instance_valid(base_unit) or base_unit.is_dead:
		return
	## 直接叠加当前血量
	base_unit.current_hp += amount
	## 溢出部分并入量程：base_max_hp / buff_max_hp / 兵种资源 max_hp 三处同步，
	## 血条量程与实际耐久保持一致（heal_base 的截断上限也随之抬升）
	if base_unit.current_hp > base_max_hp:
		var overflow: int = base_unit.current_hp - base_max_hp
		base_max_hp += overflow
		base_unit.buff_max_hp = base_max_hp
		if base_unit.unit_resource != null:
			base_unit.unit_resource.max_hp = base_max_hp
	if team == 0:
		red_base_hp = base_unit.current_hp
	else:
		blue_base_hp = base_unit.current_hp
	_sync_crystal_persist()
	base_hp_changed.emit(team, base_unit.current_hp, base_max_hp)

## 为指定阵营的基地回复耐久（与 damage_base 对称）
## 供肉鸽军令「筑垒令」base_hp_bonus 调用；上限为 Constants.BASE_HP，不会超出血条量程。
## team: 受到治疗的基地阵营编号；amount: 回复量（<=0 时忽略）
## 返回实际回血量（满血/基地失效时返回 0），供 #4 水晶回血飘字使用
func heal_base(team: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var base_unit: Unit = red_base_unit if team == 0 else blue_base_unit
	if base_unit == null or not is_instance_valid(base_unit) or base_unit.is_dead:
		return 0
	## 基地单位的耐久用 Constants.BASE_HP 计量（远大于兵种自身 max_hp），
	## 因此不能走 Unit.heal()（那会被兵种 max_hp 反向截断），直接改 current_hp。
	var before: int = base_unit.current_hp
	base_unit.current_hp = mini(base_unit.current_hp + amount, base_max_hp)
	if team == 0:
		red_base_hp = base_unit.current_hp
	else:
		blue_base_hp = base_unit.current_hp
	_sync_crystal_persist()
	base_hp_changed.emit(team, base_unit.current_hp, base_max_hp)
	return base_unit.current_hp - before

## 基地受到伤害
## team: 受到伤害的基地阵营编号
## damage: 伤害值
## attacker: 攻击者（Unit 或 base_unit，null 表示直接扣 HP 的回退路径）
func damage_base(team: int, damage: int, attacker: Node = null) -> void:  ## 定义基地受伤的方法
	## #209：肉鸽水晶模式下敌方没有基地，玩家单位打到战场右端不应误判胜利
	if is_crystal_mode and team == 1:
		return
	## #开发工具：水晶无敌（仅标准模式）。开启时不扣血、不发任何伤害信号，
	## 覆盖近战/远程/基地吐息/开发工具手动扣血等所有打水晶路径（2026-08-21 用户拍板）。
	if crystal_invincible and not is_crystal_mode:
		return
	## 找到对应的基地单位，直接对其造成伤害
	var base_unit: Unit = red_base_unit if team == 0 else blue_base_unit
	if base_unit != null and is_instance_valid(base_unit) and not base_unit.is_dead:
		## 直接调用 take_damage，由 unit_base 处理护甲扣减和 HP 扣减
		var prev_hp: int = base_unit.current_hp
		base_unit.take_damage(damage, null)
		var actual_dmg: int = prev_hp - base_unit.current_hp
		## 同步更新 red_base_hp/blue_base_hp 用于 UI 显示
		if team == 0:
			red_base_hp = base_unit.current_hp
		else:
			blue_base_hp = base_unit.current_hp
		_sync_crystal_persist()
		## 发出扣血信号（HUD 扣血日志条监听）
		if actual_dmg > 0:
			## #8（2026-08-15）：基地受实际伤害 → 重置脱战计时，需再等 3s 才恢复回血
			_crystal_out_of_combat_timer = 0.0
			base_damaged.emit(team, actual_dmg, attacker)
		base_hp_changed.emit(team, base_unit.current_hp, base_max_hp)
		return
	## 基地单位不存在或已死亡时的回退逻辑（直接扣 HP）
	if team == 0:
		## 基地已摧毁则不再处理（防止重复触发胜负判定）
		if red_base_hp <= 0:
			return
		red_base_hp -= damage
		if red_base_hp <= 0:
			red_base_hp = 0
			base_destroyed.emit(1)
		_sync_crystal_persist()
		## 回退路径：未分配攻击者，attacker 传 null
		base_damaged.emit(0, damage, attacker)
		base_hp_changed.emit(0, red_base_hp, base_max_hp)
	else:
		## 基地已摧毁则不再处理（防止重复触发胜负判定）
		if blue_base_hp <= 0:
			return
		blue_base_hp -= damage
		if blue_base_hp <= 0:
			blue_base_hp = 0
			base_destroyed.emit(0)
		base_damaged.emit(1, damage, attacker)
		base_hp_changed.emit(1, blue_base_hp, base_max_hp)

## 获取指定阵营基地的当前 HP
## team: 阵营编号（0=红方, 1=蓝方）
## 返回值: 当前 HP
func get_base_hp(team: int) -> int:  ## 定义获取基地 HP 的方法
	## 优先从基地单位获取 HP
	var base_unit: Unit = red_base_unit if team == 0 else blue_base_unit
	if base_unit != null and is_instance_valid(base_unit) and not base_unit.is_dead:
		return base_unit.current_hp
	return red_base_hp if team == 0 else blue_base_hp  ## 回退到缓存值

## 获取基地的最大 HP
## 返回值: 基地最大生命值
func get_base_max_hp() -> int:  ## 定义获取基地最大 HP 的方法
	return base_max_hp  ## 返回本局的基地/水晶量程（普通=BASE_HP，肉鸽=水晶耐久）

## ── 水晶/基地每秒恢复（#23/#13）────────────────────────────────
## #13（2026-08-09 用户拍板）：双方水晶血量不满时每秒恢复 5 点。
## 常规模式（is_crystal_mode=false）双方水晶都回血（BASE_REGEN_PER_SEC）；
## 肉鸽模式仅玩家侧水晶回血（ROGUELIKE_CRYSTAL_REGEN_PER_SEC，敌方无基地）。
## heal_base 内部截断到 base_max_hp，满血不超、走 base_hp_changed 供 UI 同步。
var _crystal_regen_accum: float = 0.0
## #8（2026-08-15）：基地/水晶回血脱战计时——受实际伤害后需等 Constants.BASE_REGEN_OUT_OF_COMBAT_SEC（3s）
## 才重新开始回血；未受伤则正常计时。计时到 0 表示「战斗中」，>= 阈值才允许回血。
var _crystal_out_of_combat_timer: float = 0.0

func _process(delta: float) -> void:
	_crystal_out_of_combat_timer += delta
	_crystal_regen_accum += delta
	if _crystal_regen_accum < 1.0:
		return
	_crystal_regen_accum -= 1.0
	## #8：脱战 3 秒后才开始回血（受击则重置，见 damage_base）
	if _crystal_out_of_combat_timer < Constants.BASE_REGEN_OUT_OF_COMBAT_SEC:
		return
	## #4（2026-08-11）：回血时在基地头顶飘「+N」绿色文本（满血/未实际回血不飘）
	if is_crystal_mode:
		_spawn_base_regen_text(0, heal_base(0, Constants.ROGUELIKE_CRYSTAL_REGEN_PER_SEC))
	else:
		_spawn_base_regen_text(0, heal_base(0, Constants.BASE_REGEN_PER_SEC))
		_spawn_base_regen_text(1, heal_base(1, Constants.BASE_REGEN_PER_SEC))

## #4：水晶/基地回血时在基地上方飘「+N」绿色浮动文本（复用 DamageNumber 飘字）
func _spawn_base_regen_text(team: int, amount: int) -> void:
	if amount <= 0 or not SettingsManager.show_damage_numbers:
		return
	var base_unit: Unit = red_base_unit if team == 0 else blue_base_unit
	if base_unit == null or not is_instance_valid(base_unit) or base_unit.is_dead:
		return
	var regen_label = DamageNumber.new()
	regen_label.text = "+" + str(amount)
	regen_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45, 1.0))  ## 回血绿色
	## 位置：基地头顶血条上方（与受击飘字同基准 -70），随机 X 小幅偏移避免与受击数字重叠
	regen_label.position = Vector2(randf_range(-10.0, 10.0), -70.0)
	base_unit.add_child(regen_label)
