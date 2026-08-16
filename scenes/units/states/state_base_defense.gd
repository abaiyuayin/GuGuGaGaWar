extends UnitState  ## 继承单位状态基类
## 基地防御状态
## 水晶（基地单位）原地防御：
## - 战役/双人（#23）：方块水晶可发射小型方块投射物攻击射程内敌人，
##   修复「兵种抵达对方水晶后攻击空气」——水晶现在是实体且有反击能力。
## - 肉鸽水晶模式：保持静态展示不攻击（#154「水晶不会攻击」语义仅对肉鸽保留，
##   用户 #23 只要求战役/双人水晶攻击，肉鸽数值不动）。

## 本攻击周期是否已执行攻击（命中）
var _attack_performed: bool = false  ## 本周期是否已攻击
## 是否正在攻击周期中
var _attack_started: bool = false  ## 是否在攻击周期中

## 进入基地防御状态时调用
func enter() -> void:  ## 重写进入状态方法
	_attack_performed = false  ## 重置攻击标志
	_attack_started = false  ## 重置攻击周期标志
	## 基地单位保持静止：播放 idle 动画（若有），否则保持当前动画不动
	## 不回退到 move 动画，避免基地单位一直处于移动动画
	if unit.anim_idle_frames != null:
		unit.play_anim("idle", true)
	## 若无 idle 动画，则停止当前动画（保持最后一帧静止）
	## 不调用 play_anim("move")，因为基地单位不应移动

## 退出基地防御状态时调用
func exit() -> void:  ## 重写退出状态方法
	pass  ## 无需清理

## 基地防御状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(delta: float) -> void:  ## 重写每帧更新方法
	## 如果单位已死亡，停止处理
	if unit.is_dead:  ## 如果单位已死亡
		return  ## 直接返回

	## 肉鸽水晶模式：纯静态展示，不查找目标、不进入攻击周期（#154）
	if RoguelikeManager.is_active:  ## 肉鸽模式
		if unit.anim_idle_frames != null:  ## 有 idle 动画
			unit.play_anim("idle")  ## 播放待机
		return  ## 直接返回

	## 攻击周期中：走完前后摇（期间不索敌、不移动）
	if _attack_started:  ## 如果在攻击周期中
		_attack_cycle(delta)  ## 执行攻击周期
		return  ## 直接返回

	## #需求21：水晶攻击开关——关闭时水晶不索敌、不进入攻击周期（纯防御展示）
	var battlefield_node: Node = get_battlefield()  ## 获取战场节点
	if battlefield_node != null and battlefield_node.has_method("get_crystal_can_attack") \
			and not battlefield_node.crystal_can_attack:  ## 水晶攻击已关闭
		if unit.anim_idle_frames != null:  ## 有 idle 动画
			unit.play_anim("idle")  ## 播放待机
		return  ## 直接返回

	## 索敌：射程内最近的敌人（BASE_ATTACK_RANGE，向 battlefield 查询）
	var attack_range_px: float = 160.0  ## 默认攻击范围
	if battlefield_node != null and battlefield_node.has_method("get_base_attack_range"):  ## 战场有获取方法
		attack_range_px = battlefield_node.get_base_attack_range()  ## 从战场获取
	var enemy: Unit = unit.find_nearest_enemy_in_range(attack_range_px)  ## 射程内最近敌人
	if enemy == null:  ## 无敌人
		if unit.anim_idle_frames != null:  ## 有 idle 动画
			unit.play_anim("idle")  ## 播放待机
		return  ## 直接返回
	## 有敌人：锁定并开始攻击周期
	unit.target = enemy  ## 锁定目标
	unit.attack_timer = 0.0  ## 重置计时器
	_attack_started = true  ## 标记进入攻击周期
	_attack_performed = false  ## 重置攻击标志
	_attack_cycle(delta)  ## 执行攻击周期

## 攻击周期（前摇 + 命中 + 后摇，期间不移动）
## 命中点在前摇结束处（attack_speed 的 40%），命中时发射小型方块投射物
func _attack_cycle(delta: float) -> void:  ## 定义攻击周期方法
	unit.attack_timer += delta  ## 计时器累加
	var res: UnitResource = unit.unit_resource  ## 获取兵种资源
	if res == null:  ## 无资源兜底
		return  ## 直接返回
	var hit_point: float = res.attack_speed * 0.4  ## 命中时间点

	## 设置朝向（面朝目标）
	if unit.target != null and is_instance_valid(unit.target):  ## 目标有效
		var face: float = signf(unit.target.global_position.x - unit.global_position.x)  ## 朝目标方向
		if face != 0.0:  ## 方向有效
			unit.set_facing_direction(face)  ## 设置朝向
	unit.velocity = Vector2.ZERO  ## 速度归零（不能移动）
	unit.move_and_slide()  ## 执行移动（实际不移动）

	## 前摇阶段：播放攻击动画，不攻击
	if unit.attack_timer < hit_point:  ## 如果在前摇阶段
		return  ## 直接返回

	## 命中点：发射方块投射物（仅执行一次）
	if not _attack_performed:  ## 如果本周期尚未攻击
		_attack_performed = true  ## 标记已攻击
		## 目标仍有效才攻击；投射物直线飞行不追踪，目标中途死亡会自然落空
		if unit.target != null and is_instance_valid(unit.target) and not unit.target.is_dead:  ## 目标有效
			unit.perform_attack(0)  ## 执行攻击（is_ranged=true → 发射小型方块投射物）

	## 后摇阶段：继续等待
	if unit.attack_timer < res.attack_speed:  ## 如果在后摇阶段
		return  ## 直接返回

	## 攻击周期结束，重置计时器和标志（下一帧重新索敌，目标死亡/脱射程会自动换锁）
	unit.attack_timer = 0.0  ## 重置计时器
	_attack_performed = false  ## 重置攻击标志
	_attack_started = false  ## 退出攻击周期
