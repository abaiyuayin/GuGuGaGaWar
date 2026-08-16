class_name UnitState  ## 定义全局类名 UnitState
## 单位状态基类
## 所有单位状态（空闲/移动/攻击/死亡）都继承此基类
## 采用状态机模式管理单位的不同行为状态

extends RefCounted  ## 继承引用计数类
## 继承 RefCounted，表示这是一个引用计数类，不需要手动释放

## 引用宿主单位节点，状态通过此引用操作单位
var unit: Node2D  ## 宿主单位节点引用

## 构造函数
## host: 宿主单位节点，状态将操作此单位
func _init(host: Node2D) -> void:  ## 定义构造函数
	unit = host  ## 保存宿主单位引用

## 进入状态时调用
## 子类重写此方法以实现进入状态时的初始化逻辑
func enter() -> void:  ## 定义进入状态方法
	pass  ## 空实现，由子类重写

## 每帧更新方法
## delta: 上一帧到当前帧的时间间隔（秒）
## 子类重写此方法以实现状态的每帧行为
func update(_delta: float) -> void:  ## 定义每帧更新方法
	pass  ## 空实现，由子类重写

## 退出状态时调用
## 子类重写此方法以实现退出状态时的清理逻辑
func exit() -> void:  ## 定义退出状态方法
	pass  ## 空实现，由子类重写

## 获取战场节点（单位挂在 Battlefield/UnitContainer 下，故上溯两级）
## 返回值: Battlefield 节点，取不到时返回 null
func get_battlefield() -> Node:
	if unit == null or not is_instance_valid(unit):
		return null
	var container: Node = unit.get_parent()
	if container == null:
		return null
	return container.get_parent()

## 获取敌方基地/水晶的世界坐标（推进目标）
## #209：肉鸽水晶不在战场最左端（-576）而在放置区正中心，
## 因此不能再硬编码 ±576，必须向战场查询实际位置。
## 返回值: 敌方基地世界坐标
func get_enemy_base_position() -> Vector2:
	var battlefield: Node = get_battlefield()
	var enemy_team: int = 1 - unit.team
	if battlefield != null and battlefield.has_method("get_base_position"):
		return battlefield.get_base_position(enemy_team)
	return Vector2(576.0, 0.0) if unit.team == 0 else Vector2(-576.0, 0.0)

## 获取己方基地/水晶的世界坐标（回防锚点）
## 返回值: 己方基地世界坐标
func get_home_base_position() -> Vector2:
	var battlefield: Node = get_battlefield()
	if battlefield != null and battlefield.has_method("get_base_position"):
		return battlefield.get_base_position(unit.team)
	return Vector2(-576.0, 0.0) if unit.team == 0 else Vector2(576.0, 0.0)

## 敌方是否还有可被攻击的基地/水晶
## 肉鸽水晶模式下敌方无基地，玩家单位不应推进到战场右端攻击空气。
## 返回值: true 表示敌方存在基地
func enemy_has_base() -> bool:
	var battlefield: Node = get_battlefield()
	if battlefield != null and battlefield.has_method("has_base"):
		return battlefield.has_base(1 - unit.team)
	return true

## 查找最近的近战敌方单位（远程单位判断自己是否被贴脸时使用）
## 遍历 UnitContainer 中所有敌方单位，只保留近战类型
## 返回值: 最近的近战敌方单位，没有则返回 null
func find_nearest_melee_enemy() -> Unit:  ## 定义查找最近近战敌人的方法
	if unit == null:  ## 宿主无效
		return null  ## 返回 null
	var container: Node = unit.get_parent()  ## 获取父节点（UnitContainer）
	if container == null:  ## 父节点不存在
		return null  ## 返回 null
	var nearest: Unit = null  ## 最近的近战敌人
	var nearest_dist: float = INF  ## 最近距离
	for body in container.get_children():  ## 遍历同容器下所有节点
		## is_instance_valid 防止访问已 queue_free 的单位
		if body == unit or not (body is Unit) or not is_instance_valid(body):  ## 跳过自身与非单位
			continue
		var other: Unit = body as Unit  ## 转换为单位类型
		if other.is_dead or other.team == unit.team:  ## 跳过已死亡与同阵营
			continue
		if other.unit_resource == null or other.unit_resource.is_ranged:  ## 只找近战
			continue
		var d: float = unit.global_position.distance_to(other.global_position)  ## 计算距离
		if d < nearest_dist:  ## 距离更近
			nearest_dist = d  ## 更新最近距离
			nearest = other  ## 更新最近近战敌人
	return nearest  ## 返回结果

## 计算本单位（中远程）的风筝保持距离（像素）
## #11：保持与敌人距离约等于「最大射程 - 1」，如射程 8 保持 7
## res: 兵种资源
## 返回值: 风筝距离（像素）
func get_kite_distance_px(res: UnitResource) -> float:  ## 定义风筝距离计算方法
	if res == null:  ## 无资源
		return 0.0  ## 返回 0
	## 射程减 1 个标准单位；射程本身小于 1 时兜底为 1，避免出现 0 或负距离
	return maxf(res.attack_range - 1.0, 1.0) * Constants.UNIT_TO_PIXELS  ## 转为像素

## 远程单位的风筝后撤（移动状态与攻击状态共用）
## #4（2026-08-08 用户拍板）：后撤触发距离改为固定「安全距离」= 3 格（RETREAT_SAFE_DISTANCE_PX=96px）。
## 旧逻辑按「射程-1」风筝 + 近战贴脸阈值 55px 触发，远程在射程边缘就开始后退；
## 新逻辑：只有被敌方兵种贴近到 96px（3 格）以内才后撤拉开身位，敌方离得远时站桩输出。
## 后退方向 = 远离威胁 + 朝己方基地的水平分量，走碰撞系统（move_and_slide）
## 越界由 unit_base._clamp_to_field 在物理帧末兜底
## 返回值: true 表示本帧执行了后退，调用方应跳过本帧的攻击/推进逻辑
func try_ranged_retreat(anim: String = "move") -> bool:  ## 定义远程后退方法（anim 默认 "move"，后摇传 "attack" 保持攻击姿态）
	if unit == null or unit.is_dead:  ## 宿主无效或已死亡
		return false  ## 不后退
	var res: UnitResource = unit.unit_resource  ## 获取兵种资源
	if res == null or not res.is_ranged:  ## 无资源或非远程
		return false  ## 不后退
	## 风筝对象是「全场最近的敌人」，不再局限于近战——被敌方远程顶到脸上同样要拉开身位
	var threat: Unit = unit.find_nearest_enemy()  ## 查找最近敌人
	if threat == null or not is_instance_valid(threat):  ## 没有有效敌人
		return false  ## 不后退
	var threat_vec: Vector2 = unit.global_position - threat.global_position  ## 由威胁指向自己的向量
	## #4：固定安全距离触发（3 格 = 96px），不再与射程挂钩
	if threat_vec.length() >= Constants.RETREAT_SAFE_DISTANCE_PX:  ## 敌方离得较远（≥3 格），不后退
		return false  ## 不后退
	## 己方基地方向（红方在左，蓝方在右）
	var home_dir: float = -1.0 if unit.team == 0 else 1.0  ## 回家方向
	var away: Vector2 = threat_vec.normalized() if threat_vec.length() > 0.01 else Vector2(home_dir, 0.0)  ## 远离威胁方向
	var retreat_dir: Vector2 = (away + Vector2(home_dir, 0.0)).normalized()  ## 合成后退方向
	var speed_px: float = res.move_speed * Constants.UNIT_TO_PIXELS * Constants.RETREAT_SPEED_RATIO  ## 后退像素速度
	unit.velocity = retreat_dir * speed_px  ## 设置后退速度
	unit.move_and_slide()  ## 走碰撞系统后退，避免穿模
	## #8：后退时翻转朝向到实际移动方向（面朝撤退方向、背对威胁）。
	## 原实现面朝威胁，角色「脸朝敌人、身体倒退着走」，被用户判定为原地倒退表现；
	## 改为朝向与位移一致（面朝己方基地转身后撤），视觉上就是正常的逃跑/后撤。
	## #5（2026-08-08）：改用带滞回死区的朝向设置——retreat_dir.x 在近垂直后撤时会在 ±阈值间抖动，
	## 旧 set_facing_direction(±1) 每帧硬翻转 → 「疯狂左右抽搐」。传原始方向分量 + 速度相关死区。
	unit.set_facing_hysteresis(retreat_dir.x, maxf(0.25, speed_px * 0.4))  ## 意图方向 + 滞回死区
	unit.play_anim(anim)  ## 播放动画（后摇时传 "attack" 保持攻击姿态）
	return true  ## 本帧已后退
