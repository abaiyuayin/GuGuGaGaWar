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
	## #竞技场（2026-08-24 用户拍板）：未开战（和平 / 停战）站定定格行走动画第一帧，
	## 绝不攻击、绝不移动。此判定必须早于攻击锁定 —— 和平模式下玩家的攻击令也不该生效。
	if GameManager.is_battlefield_mode and not unit.combat_enabled:
		unit.velocity = Vector2.ZERO
		unit.play_arena_stand()
		return
	## #2026-09-22：无攻击能力单位（S5 咕嘎工钢）——不索敌、不切攻击 / 攻基状态。
	## 闸门位置刻意放在「移动令之后、一切索敌/攻击锁定之前」：
	##   - order_pos 移动令仍然生效（玩家可以指挥它走位）；
	##   - 但攻击锁定、竞技场索敌、站定还击、推进攻基全部跳过。
	## 它只照常推进，到敌方基地前按自身射程站定（不造成任何伤害）。
	if not unit.has_attack_ability():
		_advance_without_attack(delta, _forward_direction(), speed_px)
		return

	## #框选攻击锁定（2026-09-04）：玩家指定的目标优先于一切自动索敌 ——
	## 进射程就打，没进射程就全向追（不锁水平方向、不做阵线回归），直到目标阵亡或玩家改令
	var forced: Unit = unit.sync_forced_target()
	if forced != null:
		unit.target = forced
		if unit.is_target_in_attack_range(forced.global_position, 10.0):
			unit.change_state("attack")
			return
		_advance_to_target(delta, forced.global_position, speed_px)
		return
	## #竞技场（2026-08-24 用户拍板）：沙盒索敌与站定统一在此处理。
	## 已开战：全场索敌锁最近敌人 → 进射程打，未进射程全向追击；
	## 场上无敌人则原地站定（沙盒无基地可推，不再沿水平方向平推）。
	if GameManager.is_battlefield_mode:
		var arena_target: Unit = unit.find_nearest_enemy()
		if arena_target == null or not is_instance_valid(arena_target):
			unit.velocity = Vector2.ZERO
			unit.play_arena_stand()
			return
		unit.target = arena_target
		if unit.is_target_in_attack_range(arena_target.global_position, 10.0):
			unit.change_state("attack")
			return
		_advance_to_target(delta, arena_target.global_position, speed_px)
		return
	## 站定待命：hold_position 且无移动令时原地站住，仅敌人进入自身攻击范围才还击
	if unit.hold_position:
		if unit.combat_enabled:
			## #性能（2026-08-27）：索敌半径由 INF 收窄到自身攻击范围（含 10px 滞回容差）。
			## 下一行的闸门就是 is_target_in_attack_range(±10)，攻击范围外的最近敌人一律
			## 通不过 —— 收窄后行为逐条等价。椭圆射程取 h/v 较大者以覆盖整个椭圆。
			## #2026-09-22：改用 get_attack_query_radius_px()，一并带上技能体型/横向范围倍率。
			var reach_px: float = unit.get_attack_query_radius_px() + 10.0
			var near: Unit = unit.find_nearest_enemy_in_range(reach_px)
			if near != null and unit.is_target_in_attack_range(near.global_position, 10.0):
				unit.target = near
				unit.change_state("attack")
				return
		unit.velocity = Vector2.ZERO
		unit.play_anim("idle")
		return

	## 中远程单位的后撤已收拢到攻击状态的「恢复期」（#17），移动状态不再主动后撤，
	## 避免与推进逻辑抢控制权；发现敌人进入射程即转入攻击状态，由攻击后摇触发后撤。

	## 推进方向（红方向右 / 蓝方向左；肉鸽敌军按水晶实时计算，见 _forward_direction）
	var direction: float = _forward_direction()

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
		## ① 锁定保持（#25修复）：已持有有效且在有效射程内的 target 时直接保持，
		##    不再每帧重新平分索敌——其他远程的 target 每帧变化会让自己跟着每帧换锁，
		##    目标在射程边缘反复进出 attack / 超射程防抖 → 原地抽搐（10v3 march 模拟实测）。
		##    target 失效（死亡/释放/超射程）时必须走下方平分换锁，不能锁死不换目标。
		if unit.target != null and is_instance_valid(unit.target) and not unit.target.is_dead:
			if unit.is_target_in_attack_range(unit.target.global_position, 10.0):
				target = unit.target
		## ② 射程内平分索敌（#25）—— 多个敌人在射程内时按被锁数最少分散锁定（2:1 / 各打各），
		##    只有一个敌人则集火。替代旧「射程内最近」，避免多远程无脑集火后排浪费火力。
		if target == null:
			target = unit.find_best_distributed_target_in_attack_range(10.0)
		## ③ 分配器目标在攻击范围内才采用（否则忽略，避免锁后排导致往前送）
		if target == null and unit.target != null and is_instance_valid(unit.target) and not unit.target.is_dead:
			if unit.is_target_in_attack_range(unit.target.global_position, 10.0):
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
			## 注：竞技场沙盒的全向追击已在本函数开头的 is_battlefield_mode 分支统一处理
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
	##
	## #2026-09-22 修复（水晶前原地抽搐 / dorohero 被卡住）：进入阈值必须与
	## state_attack_base 的退出阈值同源。旧实现用 res.attack_range ×32 + 10，
	## 而 attack_base 用 get_attack_query_radius_px() + 30 —— 对「声明 attack_range 远大于
	## 实际横/纵椭圆半轴」的兵种（Hero1 / Hero2 / Hero4 / D2 / F4 / N1 / N5 / S1 / Y1 / Y2），
	## 进入阈值 > 退出阈值（如 Hero2：进入 106px、退出 68.4px），两状态在 (68.4, 106] 区间
	## 每物理帧互相切换：move 判定「已在射程内」直接 return 不推进、attack_base 判定「超出射程」
	## 立刻退回 move → 单位在水晶前原地抽搐、永远走不到能打的位置。
	## 统一取「攻击判定查询半径 + 10」后：进入 48.4px < 退出 68.4px，20px 滞回带稳定。
	## 对没有椭圆配置的兵种（查询半径 = attack_range×32）本式与旧式完全等价。
	var effective_base_range: float = unit.get_attack_query_radius_px() + 10.0  ## 有效攻击水晶范围 = 自身射程 + 滞回容差
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
		unit.request_debug_redraw()  ## 请求重绘
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
	unit.request_debug_redraw()  ## 请求重绘

## 推进方向（唯一计算点）：红方（team=0）向右、蓝方（team=1）向左。
## 肉鸽例外：水晶在地图正中央（x=0），敌军从左右两侧刷新 —— 方向必须朝水晶实时计算，
## 沿用「蓝方一律向左」会让左侧出生的敌人朝反方向走到空气墙前站死，永远打不到水晶。
func _forward_direction() -> float:
	var direction: float = 1.0 if unit.team == 0 else -1.0
	if RoguelikeManager.is_active and unit.team == 1:
		var dx: float = get_enemy_base_position().x - unit.global_position.x
		if absf(dx) > 1.0:
			direction = signf(dx)
	return direction

## #2026-09-22：无攻击能力单位（attack_anim_mode == "none"，S5 咕嘎工钢）的推进分支。
## 与正常推进的唯一差别：不做索敌、不切 attack / attack_base；到敌方基地前按自身射程站定，
## 之后只播待机动画（原地不动，不造成任何伤害）。敌方无基地时（肉鸽蓝方）保持纯推进。
func _advance_without_attack(delta: float, direction: float, speed_px: float) -> void:
	if enemy_has_base():
		var base_pos: Vector2 = get_enemy_base_position()
		if unit.global_position.distance_to(base_pos) <= unit.get_attack_query_radius_px() + 10.0:
			unit.target = null
			unit.velocity = Vector2.ZERO
			unit.move_and_slide()
			unit.play_anim("idle")
			return
	_advance(delta, direction, speed_px)

## 朝玩家下达的 order_pos 移动（框选指挥共用：竞技场 + 肉鸽）
## 复用速度/分离/朝向逻辑；到达目标点（阈值内）后交给 _finish_order 收尾。
## delta: 帧间隔（秒）；speed_px: 像素移速
func _advance_to_order(delta: float, speed_px: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var to_target: Vector2 = unit.order_pos - unit.global_position
	var dist: float = to_target.length()
	## 到达判定：距离小于一步或阈值即视为到达，避免抖动
	## #竞技场（2026-08-24 需求3 修）：原阈值 6px 过严——编队间距 30px 小于友军分离
	## 感知半径 40px，相邻单位永远互推，谁都进不到 6px → 原地狂奔。放宽到 14px。
	if dist <= maxf(14.0, speed_px * delta):
		_finish_order()
		return
	var dir: Vector2 = to_target / dist
	var sep: Vector2 = unit._compute_ally_separation()
	var desired: Vector2 = dir * speed_px + sep * 0.5
	unit.velocity = unit.clamp_move_velocity(desired, speed_px)
	unit.set_facing_hysteresis(unit.velocity.x, maxf(0.25, speed_px * 0.4))
	var prev: Vector2 = unit.global_position
	unit.move_and_slide()
	## #竞技场（2026-08-24 需求3 修）：卡住检测——想去目标点却被友军顶死推不动时，
	## 连续 1.2s 几乎无推进 → 强制视为已到位，停止原地奔跑动画。
	var progress: float = (unit.global_position - prev).dot(dir)
	if progress < maxf(2.0, speed_px * delta * 0.3):
		unit._order_stuck_timer += delta
		if unit._order_stuck_timer >= 1.2:
			_finish_order()
			return
	else:
		unit._order_stuck_timer = 0.0
	unit.play_anim("move")
	unit.request_debug_redraw()

## 移动令执行完毕（到位 / 被友军顶死判定为到位）后的收尾。
##
## 竞技场：保持原语义 —— 原地站定（hold_position），只反击进入自身攻击范围的敌人。
## 肉鸽守卫单位：走「到位后线性判定」（2026-09-05 用户拍板），优先级从上到下：
##   ① 自身攻击范围内有敌人 → 就地打它（近战/远程都不必回防）
##   ② 否则看水晶周围（以水晶为圆心辐射 _crystal_alert_radius）有没有敌人 → 折返迎击
##      近战直接切 attack 冲过去；远程切 guard 走回水晶附近，进射程后由 guard 自行开火
##      （远程若在此硬切 attack，会先在超射程原地空等一个防抖窗口才回防，纯浪费时间）
##   ③ 都没有 → 切 guard 自动返回水晶周围驻守
func _finish_order() -> void:
	unit.order_pos = Vector2.INF
	unit.velocity = Vector2.ZERO
	unit._order_stuck_timer = 0.0
	## 竞技场（含常规战斗）：到位即站定，语义不变
	if not unit.is_guard_mode():
		unit.hold_position = true
		unit.play_anim("idle")
		return
	## 肉鸽：到位后不再永久站定，按三级链决定是打、是折返还是回防
	unit.hold_position = false
	unit.target = null  ## 到位判定重新选目标，避免对象池/内部调用残留旧锁定
	var engage: Unit = _pick_post_order_target()
	if engage == null:
		unit.change_state("guard")  ## ③ 场面干净 → 回水晶周围驻守
		return
	unit.target = engage
	var res: UnitResource = unit.unit_resource
	if res != null and res.is_ranged and not unit.is_target_in_attack_range(engage.global_position, 10.0):
		unit.change_state("guard")  ## ② 远程且未进射程 → 走回防线，靠近后自然开火
		return
	unit.change_state("attack")  ## ① 已进射程 / ② 近战折返冲锋

## 到位后的接敌判定（三级链的 ①②，见 _finish_order）；两级都没有则返回 null
## 返回值: 应该交战的敌方单位，或 null
func _pick_post_order_target() -> Unit:
	## ① 自身攻击范围内（+10px 滞回容差，与进入攻击状态的判定同口径）
	var res: UnitResource = unit.unit_resource
	if res != null:
		## #2026-09-22：统一走 get_attack_query_radius_px()（含椭圆 + 技能体型/横向倍率）
		var reach: float = unit.get_attack_query_radius_px() + 10.0
		var near: Unit = _find_enemy_near(unit.global_position, reach)
		if near != null and unit.is_target_in_attack_range(near.global_position, 10.0):
			return near
	## ② 水晶周围：以水晶自身为圆心向两侧辐射一个兵种的锁定攻击范围
	return _find_enemy_near(get_home_base_position(), _crystal_alert_radius())

## 水晶警戒半径（像素）= 肉鸽统一锁定 / 追击半径 × 警戒倍率。
## 用 chase_range_px 而不是另立一个数：肉鸽下所有兵种共用这一个「锁定攻击范围」（#210），
## 且它能在肉鸽控制台里调，警戒圈会跟着一起变，不会出现两套互相打架的半径。
func _crystal_alert_radius() -> float:
	return maxf(RoguelikeManager.chase_range_px * Constants.ROGUELIKE_CRYSTAL_ALERT_RATIO, 1.0)

## 找出距 [param point] 指定半径内最近的敌方存活单位（排除基地 / 水晶本体与自己）
## 一次移动令只在「到位」这一帧调用一次，故直接线性扫容器，不走 find_nearest_enemy_in_range ——
## 后者是「以自身为圆心」且带索敌节流，圆心换不了，节流窗口内还可能返回 null 造成误判。
## point: 判定圆心（自身位置 / 水晶位置）；radius: 判定半径（像素）
## 返回值: 半径内最近的敌方单位，没有则 null
func _find_enemy_near(point: Vector2, radius: float) -> Unit:
	var container: Node = unit.get_parent()
	if container == null:
		return null
	var nearest: Unit = null
	var nearest_d: float = radius
	for body in container.get_children():
		if body == unit or not (body is Unit) or not is_instance_valid(body):
			continue
		var other: Unit = body as Unit
		if other.is_dead or other.is_base_unit or other.team == unit.team:
			continue
		var d: float = point.distance_to(other.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = other
	return nearest

## 朝指定敌人位置全向接近一帧（竞技场沙盒专属）
## 与 _advance 的区别：不锁固定水平方向、不做阵线回归（lane_y 回拉），
## 因为沙盒是自由摆阵，敌人可能在任意方位，阵线回归会抵消纵向接近的位移。
## 不在此处切 attack 状态：射程判定由调用方（update 开头）每帧统一处理。
## _delta: 帧间隔（秒，本函数用 velocity + move_and_slide 移动故未直接使用）
## target_pos: 目标世界坐标；speed_px: 像素移速
func _advance_to_target(_delta: float, target_pos: Vector2, speed_px: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var to_target: Vector2 = target_pos - unit.global_position
	var dist: float = to_target.length()
	if dist <= 0.01:
		unit.velocity = Vector2.ZERO
		return
	var dir: Vector2 = to_target / dist
	var sep: Vector2 = unit._compute_ally_separation()
	var desired: Vector2 = dir * speed_px + sep * 0.5
	unit.velocity = unit.clamp_move_velocity(desired, speed_px)
	unit.set_facing_hysteresis(unit.velocity.x, maxf(0.25, speed_px * 0.4))
	unit.move_and_slide()
	unit.play_anim("move")
	unit.request_debug_redraw()
