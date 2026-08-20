extends UnitState  ## 继承单位状态基类
## 移动状态
## 单位向敌方基地方向前进的状态
## 在移动过程中会检测前方是否有敌人或是否到达敌方基地

## 进入移动状态时调用
func enter() -> void:  ## 重写进入状态方法
	unit._reset_dodge_state()  ## 清空卡住绕步状态，避免上一状态残留
	unit.play_anim("move")  ## 播放移动动画

## 移动状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(delta: float) -> void:  ## 重写每帧更新方法
	## 如果单位已死亡，停止处理
	if unit.is_dead:  ## 如果单位已死亡
		return  ## 直接返回
	## AI 禁用时不自动移动（用于调试模拟）
	if unit.ai_disabled:
		return

	## 获取单位的兵种资源
	var res: UnitResource = unit.unit_resource  ## 获取兵种资源
	if res == null:  ## 如果没有兵种资源
		return  ## 直接返回
	## 将标准单位速度转换为像素速度（走 unit.get_move_speed_px，内含肉鸽文物/军令的移速加成）
	var speed_px: float = unit.get_move_speed_px()  ## 计算像素速度

	## ── 战场模式（RTS 沙盒）专属逻辑 ──────────────────────────────
	## 移动令优先：order_pos 有效则朝其移动，到达后转站定（hold_position）
	if unit.order_pos.is_finite():
		_advance_to_order(delta, speed_px)
		return
	## 站定待命：hold_position 且无移动令时原地站住，仅敌人进入自身攻击范围才还击
	if unit.hold_position:
		if unit.combat_enabled:
			var near: Unit = unit.find_nearest_enemy()
			if near != null and unit.is_target_in_attack_range(near.global_position, 10.0):
				unit.target = near
				unit.change_state("attack")
				return
		unit.velocity = Vector2.ZERO
		unit.play_anim("idle")
		return

	## 中远程单位的后撤已收拢到攻击状态的「恢复期」（#17），移动状态不再主动后撤，
	## 避免与推进逻辑抢控制权；发现敌人进入射程即转入攻击状态，由攻击后摇触发后撤。

	## 设置移动方向：红方（team=0）向右，蓝方（team=1）向左
	var direction: float = 1.0 if unit.team == 0 else -1.0  ## 根据阵营设置方向

	## 安全校验：单位引用失效时停止处理
	if unit == null or not is_instance_valid(unit):
		return
	## 检测前方是否有敌人
	## 远程索敌优先级（#BugC：修复远程兵越过前排锁后排导致送死）：
	## ① 攻击范围内最近的敌人（有就立刻停下打，不会无视眼前敌人往前送）
	## ② 分配器指定的均衡目标（#19 轮转分配，仅当目标在攻击范围内才采用）
	## ③ 全场最近索敌（兜底，敌人在检测范围但不在攻击范围则继续推进）
	var target: Unit = null  ## 最终选定的索敌目标
	if res.is_ranged:  ## 远程单位：优先锁攻击范围内的敌人
		## #5（2026-08-09）：有效射程统一为 attack_range_px + 10.0（与 state_attack 的退出判定一致）。
		## 旧逻辑 move 用精确射程、attack 用 +10 容差，敌人在射程边缘时两状态判定裂缝 →
		## 「进入射程也不攻击、原地抖动」。统一后敌人一进有效射程立即攻击。
		var effective_range_px: float = res.attack_range * Constants.UNIT_TO_PIXELS + 10.0
		## ① 锁定保持（#25修复）：已持有有效且在有效射程内的 target 时直接保持，
		##    不再每帧重新平分索敌——其他远程的 target 每帧变化会让自己跟着每帧换锁，
		##    目标在射程边缘反复进出 attack / 超射程防抖 → 原地抽搐（10v3 march 模拟实测）。
		##    target 失效（死亡/释放/超射程）时必须走下方平分换锁，不能锁死不换目标。
		if unit.target != null and is_instance_valid(unit.target) and not unit.target.is_dead:
			if unit.global_position.distance_to(unit.target.global_position) <= effective_range_px:
				target = unit.target
		## ② 射程内平分索敌（#25）—— 多个敌人在射程内时按被锁数最少分散锁定（2:1 / 各打各），
		##    只有一个敌人则集火。替代旧「射程内最近」，避免多远程无脑集火后排浪费火力。
		if target == null:
			target = unit.find_best_distributed_target(effective_range_px)
		## ③ 分配器目标在攻击范围内才采用（否则忽略，避免锁后排导致往前送）
		if target == null and unit.target != null and is_instance_valid(unit.target) and not unit.target.is_dead:
			var dist_to_assigned: float = unit.global_position.distance_to(unit.target.global_position)
			if dist_to_assigned <= effective_range_px:
				target = unit.target  ## 分配器目标在射程内，采用
		## ④ 兜底：全场最近索敌（敌人在检测范围但不在攻击范围 → 继续推进不追击）
		if target == null:
			target = unit.find_nearest_enemy()
	else:  ## 近战单位：发现敌人立即追击
		target = unit.find_nearest_enemy()
	if target != null and is_instance_valid(target):  ## 如果发现有效敌人
		if res.is_ranged:  ## 远程单位
			## 远程单位：只有敌人进入攻击范围才停下攻击，否则继续向基地方向推进
			## #3：椭圆/圆形统一判定（与 state_attack 一致），不再单写 attack_range_px + 10.0
			if unit.is_target_in_attack_range(target.global_position, 10.0):  ## 敌人在有效攻击范围内
				unit.target = target  ## 设置目标
				unit.change_state("attack")  ## 切换到攻击状态
				return  ## 直接返回
			## 敌人在检测范围但不在攻击范围，远程单位继续推进（不追击）
		else:  ## 近战单位
			## 近战单位：发现敌人立即进入攻击状态追击
			unit.target = target  ## 设置目标
			unit.change_state("attack")  ## 切换到攻击状态
			return  ## 直接返回

	## 检测是否到达敌方基地附近
	## #209/#7：基地位置向战场查询（肉鸽水晶现在地图正中央 x=0，不再是 ±576），逻辑走 get_enemy_base_position()
	if unit == null or not is_instance_valid(unit):
		return
	## 敌方没有基地时（肉鸽水晶模式的蓝方）跳过攻基逻辑，避免推到边界打空气误判胜利
	if not enemy_has_base():
		_advance(delta, direction, speed_px)
		return
	var base_pos: Vector2 = get_enemy_base_position()  ## 敌方基地世界坐标
	var dist_to_base: float = unit.global_position.distance_to(base_pos)  ## 计算与基地的距离
	## #11（2026-08-08）：攻击判定距离 = 兵种自身射程，不再强制 max(基地160px, 射程)。
	## 旧逻辑让兵种在 160px 外就开始挥刀「隔空打水晶」（水晶渲染只有 72×72），表现为打空气；
	## 统一按兵种射程判定：近战贴脸拆水晶，远程进自己射程再射，视觉与伤害判定一致。
	## #需求22 修复：与兵对兵攻击一致，进入判定加 +10.0 滞回容差——
	## 旧逻辑精确射程进、精确射程退，单位被友军分离/碰撞推挤到射程边缘时
	## move↔attack_base 高频抖动 → 一直播奔跑动画、偶尔闪一帧攻击（用户反馈「奔跑不攻击」）。
	var effective_base_range: float = res.attack_range * Constants.UNIT_TO_PIXELS + 10.0  ## 有效攻击水晶范围 = 自身射程 + 滞回容差
	if dist_to_base <= effective_base_range:  ## 如果进入有效攻击范围
		unit.target = null  ## 清空目标（基地不是 Unit 类型）
		unit.change_state("attack_base")  ## 切换到攻击基地状态（遵循攻击周期）
		return  ## 直接返回

	_advance(delta, direction, speed_px)

## 沿指定水平方向推进一帧（含友军分离、朝向翻转、卡住绕步与阵线回归）
## delta: 帧间隔（秒）
## direction: 水平推进方向（+1 向右 / -1 向左）
## speed_px: 像素移速
func _advance(delta: float, direction: float, speed_px: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var sep: Vector2 = unit._compute_ally_separation()  ## 友军分离推力

	## 绕步（卡住自动侧向寻路）进行中：以侧向移动为主，保留部分推进（#12）
	## 与 state_attack._move_towards_target 的绕步保持一致，防止推进路径被堵时原地踏步
	if unit._dodge_timer > 0.0:  ## 正在绕步
		unit._dodge_timer -= delta  ## 倒计时
		if unit._dodge_timer <= 0.0:  ## 绕步结束
			unit._stuck_timer = 0.0  ## 重置卡住计时，避免立刻再次触发
			unit._dodge_dir = 0.0  ## 清空绕步方向
		var lateral: float = minf(speed_px, 120.0) * unit._dodge_dir  ## 侧向绕步速度（限幅防飞越全场）
		var dodge_vel := Vector2(direction * speed_px * Unit.DODGE_FORWARD_FACTOR, lateral) + sep * 0.5  ## 前进 + 侧向 + 分离
		unit.velocity = unit.clamp_move_velocity(dodge_vel, speed_px)  ## 限幅保恒定速率
		unit.move_and_slide()  ## 走碰撞系统移动
		unit.set_facing_hysteresis(unit.velocity.x, maxf(0.25, speed_px * 0.4))  ## 意图方向 + 滞回
		unit.play_anim("move")  ## 播放移动动画
		unit.queue_redraw()  ## 请求重绘
		return  ## 绕步分支已处理移动

	## 正常推进：使用 velocity + move_and_slide() 移动，启用 CharacterBody2D 的碰撞系统
	## 碰撞体会阻止单位互相穿透，实现兵种之间的物理碰撞（最多 1/3 身体重叠）
	## 叠加友军分离推力后统一限幅：分离推力是附加量，直接相加会让合速度超过兵种移速，
	## 表现为「挤出人堆的瞬间窜一下」。clamp 后方向不变、速度恒定（见 Unit.clamp_move_velocity）
	var intended: float = speed_px * delta  ## 本帧期望推进量
	var prev: Vector2 = unit.global_position  ## 移动前位置
	unit.velocity = unit.clamp_move_velocity(Vector2(direction * speed_px, 0.0) + sep, speed_px)
	## #BugB：朝向改按「意图方向」+ 滞回死区，不再按实际位移 dx 翻转。
	## 旧实现（dx > 0.1 翻转）在单位被友军卡死时，物理引擎的挤压滑移让 dx 在 ±0.1 阈值间抖动，
	## 每帧 flip_h 翻转 → 「原地疯狂左右转头」。改按合成 velocity.x 符号，死区 max(0.25, speed*0.4)
	## 保证速度足够且方向明确才翻转，被堵死时保持当前朝向不抖动。
	unit.set_facing_hysteresis(unit.velocity.x, maxf(0.25, speed_px * 0.4))  ## 意图方向 + 滞回
	unit.move_and_slide()  ## 执行移动并处理碰撞
	## Y 坐标不再锁定为 0，保持生成时分配的阵线位置，使单位分散在多条阵线上

	## 阵线回归：move_and_slide 在人堆里的挤压滑移会让单位持续偏离出生阵线，
	## 长期累积就会把单位挤到战场边缘（G5 往右下角漂就是这么来的）。
	## 只在移动状态做回归——此时 velocity 本就是纯水平的，任何 Y 偏移都是被挤出来的。
	var lane_dy: float = unit.lane_y - unit.global_position.y  ## 与出生阵线的 Y 偏差
	if absf(lane_dy) > 2.0:  ## 偏差超过容差才回拉
		var step: float = minf(absf(lane_dy), Constants.LANE_RETURN_SPEED * delta)  ## 本帧回拉步长
		unit.global_position.y += signf(lane_dy) * step  ## 缓慢拉回阵线

	unit.play_anim("move")  ## 播放移动动画

	## 卡住检测（#12）：期望推进却几乎没动 → 累计受阻 → 触发绕步
	## 与 state_attack._move_towards_target 同一套算法，防止「被敌方近战 body 顶住 / 两兵重叠卡位」原地踏步
	var forward_progress: float = (unit.global_position - prev).dot(Vector2(direction, 0.0))  ## 实际沿推进方向位移
	if intended > 0.5 and forward_progress < intended * 0.3:  ## 想推进却被挡住
		unit._stuck_timer += delta  ## 累计受阻时间
		if unit._stuck_timer >= Unit.STUCK_THRESHOLD:  ## 持续受阻达到阈值
			## 触发绕步：优先朝分离推力反方向（即盟友较少的一侧），否则交替上下
			if absf(sep.y) > 0.01:  ## 分离推力有侧向分量
				unit._dodge_dir = signf(sep.y)  ## 朝盟友少的一侧绕
			else:  ## 无明显侧向空间，交替上下
				unit._dodge_dir = unit._dodge_toggle  ## 用交替方向
				unit._dodge_toggle = -unit._dodge_toggle  ## 翻转备用方向
			unit._dodge_timer = Unit.DODGE_DURATION  ## 启动绕步
			unit._stuck_timer = 0.0  ## 清空卡住计时
	else:  ## 正常推进，清空卡住计时
		unit._stuck_timer = 0.0

	## 不翻转整个 CharacterBody2D，避免名字标签镜像/倒立。
	## 若以后需要朝向区分，只翻转专门的 Sprite2D/ColorRect，而不是整体 scale.x。

	## 强制更新 visual 位置（如果 Control 节点滞后）
	unit.queue_redraw()  ## 请求重绘

## 朝玩家下达的 order_pos 移动（战场模式专用）
## 复用速度/分离/朝向逻辑；到达目标点（阈值内）后置 hold_position 转站定。
## delta: 帧间隔（秒）；speed_px: 像素移速
func _advance_to_order(delta: float, speed_px: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var to_target: Vector2 = unit.order_pos - unit.global_position
	var dist: float = to_target.length()
	## 到达判定：距离小于一步或阈值即视为到达，避免抖动
	if dist <= maxf(6.0, speed_px * delta):
		unit.order_pos = Vector2.INF
		unit.hold_position = true
		unit.velocity = Vector2.ZERO
		unit.play_anim("idle")
		return
	var dir: Vector2 = to_target / dist
	var sep: Vector2 = unit._compute_ally_separation()
	var desired: Vector2 = dir * speed_px + sep * 0.5
	unit.velocity = unit.clamp_move_velocity(desired, speed_px)
	unit.set_facing_hysteresis(unit.velocity.x, maxf(0.25, speed_px * 0.4))
	unit.move_and_slide()
	unit.play_anim("move")
	unit.queue_redraw()
