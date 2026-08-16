extends UnitState  ## 继承单位状态基类
## 守卫状态（肉鸽模式专用，#210）
##
## 取代 state_move 成为「玩家单位无目标时的默认状态」。核心差异：
## state_move 是无脑向敌方基地推进，本状态是以保护水晶为中心的驻守 + 追击。
##
## 每帧决策优先级：
##   1. 统一寻敌半径（Unit.get_chase_range_px）内出现敌人 → 切攻击状态追击
##   2. 半径内无敌人，但自己是远程且半径内有己方近战已咬住敌人 → 跟随该近战前压（#210-6）
##   3. 其余情况 → 返回水晶旁的驻守锚点
##        近战：水晶正前方一段随机距离（每单位固定不同，避免全挤成一坨）
##        远程：水晶后方一小段距离，按自身射程换算（射程越远站得越靠后）
##
## 仅在 Unit.is_guard_mode() 为真（肉鸽 + 玩家阵营 + 非水晶本体）时会被切入；
## 敌方单位仍走 state_move 推进，否则没人来打水晶。

## 进入守卫状态时调用
func enter() -> void:  ## 重写进入状态方法
	unit._reset_dodge_state()  ## 清空上一状态残留的绕步数据
	unit.play_anim("move")  ## 播放移动动画（下一帧可能立刻切 idle）

## 守卫状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(_delta: float) -> void:  ## 重写每帧更新方法
	if unit == null or not is_instance_valid(unit):  ## 宿主已失效
		return
	if unit.is_dead:  ## 已死亡
		return
	if unit.ai_disabled:  ## AI 禁用（调试模拟）
		return
	var res: UnitResource = unit.unit_resource  ## 获取兵种资源
	if res == null:  ## 无资源
		return

	## 1. 优先索敌：发现敌人后按兵种决定是否切入攻击状态
	## #6（2026-08-09）：远程守卫必须等敌人进入攻击射程才切 attack。
	## 旧逻辑用统一寻敌半径（chase_range，比射程大得多）索敌，敌人在「追击半径内、射程外」时
	## guard 切 attack → attack 判超射程切回 guard → 每帧交替 → 「原地疯狂左右转头不攻击」。
	## 与 state_move 的远程索敌规则一致：射程外不追击；近战仍按寻敌半径立即切入（attack 内自带追击）。
	var found: Unit = unit.find_nearest_enemy()  ## 检测区内最近敌人
	if found != null and is_instance_valid(found) and not found.is_dead:  ## 找到有效敌人
		var can_engage: bool = true  ## 是否可进入攻击状态
		if res.is_ranged:  ## 远程：需敌人在攻击射程内
			var atk_range_px: float = res.attack_range * Constants.UNIT_TO_PIXELS  ## 攻击射程像素值
			can_engage = unit.global_position.distance_to(found.global_position) <= atk_range_px  ## 射程判定
		if can_engage:  ## 可进入攻击状态
			unit.target = found  ## 设置目标
			unit.change_state("attack")  ## 切换到攻击状态
			return

	## 2. 远程跟随：自身没索到敌人，但半径内有己方近战正在交战 → 前压支援
	##    这条规则专门解决「近战冲上去打，远程留在原地发呆」的问题
	if res.is_ranged:  ## 远程兵种
		var escort: Unit = _find_engaged_melee_ally()  ## 查找已交战的近战友军
		if escort != null:  ## 找到护送对象
			_move_towards(_escort_anchor(escort, res))  ## 跟到该近战身后一个身位
			return

	## 3. 回防：走向水晶旁的驻守锚点
	_move_towards(_guard_anchor(res))

## 查找寻敌半径内「已经咬住敌人」的最近己方近战单位
## 检测区的 collision_mask 只覆盖敌方层，友军不会出现在 get_overlapping_bodies 里，
## 因此这里改为遍历同容器兄弟节点并自行做距离筛选。
## 返回值: 最近的已交战近战友军，没有则返回 null
func _find_engaged_melee_ally() -> Unit:  ## 定义查找交战近战友军的方法
	var container: Node = unit.get_parent()  ## 获取 UnitContainer
	if container == null:  ## 容器不存在
		return null
	var range_px: float = unit.get_chase_range_px()  ## 统一寻敌半径
	var nearest: Unit = null  ## 最近的护送对象
	var nearest_dist: float = INF  ## 最近距离
	for body in container.get_children():  ## 遍历同容器节点
		if body == unit or not (body is Unit) or not is_instance_valid(body):  ## 跳过自身与非单位
			continue
		var ally: Unit = body as Unit  ## 转为单位类型
		if ally.is_dead or ally.team != unit.team or ally.is_base_unit:  ## 跳过死亡/敌方/水晶本体
			continue
		if ally.unit_resource == null or ally.unit_resource.is_ranged:  ## 只跟随近战
			continue
		## 只跟随「确实咬住了敌人」的近战，否则会跟着一群同样在回防的近战乱跑
		if ally.target == null or not is_instance_valid(ally.target) or ally.target.is_dead:
			continue
		var d: float = unit.global_position.distance_to(ally.global_position)  ## 与该近战的距离
		if d <= range_px and d < nearest_dist:  ## 在寻敌半径内且更近
			nearest_dist = d  ## 更新最近距离
			nearest = ally  ## 更新护送对象
	return nearest  ## 返回结果

## 计算跟随近战友军时的站位锚点：在该近战身后（靠己方水晶一侧）保持一个身位
## escort: 被跟随的近战友军
## res: 自身兵种资源（用射程换算身位）
## 返回值: 锚点世界坐标
func _escort_anchor(escort: Unit, res: UnitResource) -> Vector2:  ## 定义护送锚点计算方法
	var home_dir: float = -1.0 if unit.team == 0 else 1.0  ## 己方水晶所在方向
	var standoff: float = clampf(
		res.attack_range * Constants.UNIT_TO_PIXELS * 0.8,
		Constants.GUARD_ESCORT_STANDOFF_MIN,
		Constants.GUARD_ESCORT_STANDOFF_MAX)  ## 与近战保持的身位
	return Vector2(escort.global_position.x + home_dir * standoff, unit.lane_y)  ## 身后一个身位，Y 保持自身阵线

## 计算无敌情况下的驻守锚点
## res: 自身兵种资源
## 返回值: 锚点世界坐标
func _guard_anchor(res: UnitResource) -> Vector2:  ## 定义驻守锚点计算方法
	var crystal: Vector2 = get_home_base_position()  ## 己方水晶世界坐标
	var front_dir: float = 1.0 if unit.team == 0 else -1.0  ## 敌人来袭方向（水晶正前方）
	if res.is_ranged:  ## 远程：退到水晶后方一小段
		var back: float = clampf(
			res.attack_range * Constants.UNIT_TO_PIXELS * Constants.GUARD_RANGED_BACK_RATIO,
			Constants.GUARD_RANGED_BACK_MIN,
			Constants.GUARD_RANGED_BACK_MAX)  ## 后撤距离随射程增长
		return Vector2(crystal.x - front_dir * back, unit.lane_y)  ## 水晶后方
	## 近战：水晶正前方一段随机距离（偏移在 setup 时抽定，见 Unit.guard_front_offset）
	return Vector2(crystal.x + front_dir * unit.guard_front_offset, unit.lane_y)

## 朝锚点移动一帧；已在容差内则原地驻守
## anchor: 目标锚点世界坐标
func _move_towards(anchor: Vector2) -> void:  ## 定义朝锚点移动的方法
	var to_anchor: Vector2 = anchor - unit.global_position  ## 到锚点的向量
	if to_anchor.length() <= Constants.GUARD_ARRIVE_TOLERANCE:  ## 已就位
		_hold_position()  ## 原地驻守
		return
	var speed_px: float = unit.get_move_speed_px()  ## 像素移速（含文物/军令加成）
	var dir: Vector2 = to_anchor.normalized()  ## 归一化方向
	## 叠加友军分离推力后统一限幅，避免合速度超过兵种移速（与 state_move 一致）
	unit.velocity = unit.clamp_move_velocity(dir * speed_px + unit._compute_ally_separation(), speed_px)
	## #BugB：朝向改按「意图方向」（朝锚点）+ 滞回死区，不再按实际位移 dx 翻转。
	## 守卫被友军挤住时 dx 会在 ±0.1 间抖动导致原地疯狂转头；意图方向 dir 稳定，死区防抖。
	unit.set_facing_hysteresis(unit.velocity.x, maxf(0.25, speed_px * 0.4))  ## 意图方向 + 滞回
	unit.move_and_slide()  ## 走碰撞系统移动
	unit.play_anim("move")  ## 播放移动动画
	unit.queue_redraw()  ## 请求重绘

## 原地驻守：速度归零、面朝敌方来袭方向、播放待机动画
func _hold_position() -> void:  ## 定义原地驻守的方法
	unit.velocity = Vector2.ZERO  ## 速度归零
	unit.move_and_slide()  ## 仍走一次碰撞系统，保持被推挤时的物理表现
	## #6（2026-08-09）：朝向改滞回设置——意图方向固定（±1 归一化方向，死区 0.25 必然一次翻转到位），
	## 翻转后 facing 锁定来袭方向不再每帧重复翻转；旧 set_facing_direction 在守卫↔攻击交替时反复硬翻转，
	## 配合 guard/attack 状态振荡就是「原地疯狂左右转头」。
	unit.set_facing_hysteresis(1.0 if unit.team == 0 else -1.0, 0.25)  ## 面朝敌人来袭方向（滞回锁定）
	if unit.anim_idle_frames != null:  ## 有待机动画
		unit.play_anim("idle")  ## 播放待机
	else:  ## 无待机动画时保持移动动画，避免动画卡在攻击帧
		unit.play_anim("move")
