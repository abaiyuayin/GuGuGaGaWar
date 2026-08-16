extends UnitState  ## 继承单位状态基类
## 攻击基地状态
## 当单位到达敌方基地攻击范围时进入此状态
## 遵循攻击周期（前摇 + 命中 + 后摇），只在命中帧对基地造成伤害
## 期间不移动，攻击周期结束后立刻开始下一次攻击

## 本攻击周期是否已执行攻击（命中）
var _attack_performed: bool = false  ## 本周期是否已攻击
## 是否正在攻击周期中
var _attack_started: bool = false  ## 是否在攻击周期中

## 进入攻击基地状态时调用
func enter() -> void:  ## 重写进入状态方法
	## 重置攻击计时器和标志
	unit.attack_timer = 0.0  ## 重置攻击计时器
	_attack_performed = false  ## 重置攻击标志
	_attack_started = false  ## 重置攻击周期标志
	unit.play_anim("attack", true)  ## 强制播放攻击动画

## 退出攻击基地状态时调用
func exit() -> void:  ## 重写退出状态方法
	pass  ## 无需清理

## 攻击基地状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(delta: float) -> void:  ## 重写每帧更新方法
	## 安全校验：单位引用失效时停止处理（防止调数值时单位被移除导致闪退）
	if unit == null or not is_instance_valid(unit):
		return
	## 如果单位已死亡，停止处理
	if unit.is_dead:  ## 如果单位已死亡
		return  ## 直接返回

	## 获取兵种资源
	var res: UnitResource = unit.unit_resource  ## 获取兵种资源
	if res == null:  ## 如果没有兵种资源
		return  ## 直接返回

	## 敌方基地已不存在（被摧毁 / 肉鸽水晶模式的蓝方）时回到移动状态
	if not enemy_has_base():
		unit.change_state("move")
		return
	## 检查基地攻击范围：若单位被推离基地范围，回到移动状态继续推进
	## #209：基地位置向战场查询，肉鸽水晶不在 ±576
	var base_pos: Vector2 = get_enemy_base_position()  ## 敌方基地世界坐标
	var dist_to_base: float = unit.global_position.distance_to(base_pos)  ## 与基地的距离
	## #11（2026-08-08）：有效攻击范围 = 兵种自身射程（不再强制 160px 打空气）。
	## 与 state_move 的进入判定保持一致：近战贴脸、远程进自己射程，视觉与伤害一致。
	## #需求22 修复（滞回带）：进入阈值 = 射程+10（state_move），退出阈值 = 射程+30——
	## 两阈值差 20px 形成滞回带。旧实现进出阈值相同（精确射程），单位被友军分离/碰撞
	## 推挤到射程边缘时 move↔attack_base 高频抖动：一直播奔跑动画、偶尔闪一帧攻击
	## （用户反馈「兵种在水晶周围循环奔跑但水晶在扣血」）。
	var effective_base_range: float = res.attack_range * Constants.UNIT_TO_PIXELS  ## 有效攻击水晶范围 = 自身射程（进入基准）
	## 被推离有效范围，回到移动状态继续推进
	if dist_to_base > effective_base_range + 30.0:  ## 超出「射程+30」才退出（20px 滞回带）
		unit.change_state("move")  ## 切换回移动状态
		return  ## 直接返回

	## 如果正在攻击周期中，继续执行（前后摇硬直，期间不能移动）
	if _attack_started:  ## 如果在攻击周期中
		_attack_cycle(delta, res)  ## 执行攻击周期
		return  ## 直接返回

	## #12：攻击水晶时若射程内出现敌方兵种，优先切换目标打兵。
	## 否则敌人刚刷出来就无视、继续硬敲水晶，水晶会被白嫖到死。
	## 只在自己的攻击射程内切换（近战贴脸、远程进射程），不越级索敌。
	## find_nearest_enemy_in_range 已跳过 is_base_unit，不会误锁敌方水晶。
	var unit_range_px: float = res.attack_range * Constants.UNIT_TO_PIXELS
	var enemy_in_range: Unit = unit.find_nearest_enemy_in_range(unit_range_px)
	if enemy_in_range != null:  ## 射程内有敌兵
		unit.target = enemy_in_range  ## 锁定敌兵
		unit.change_state("attack")  ## 切换到常规攻击状态
		return  ## 直接返回

	## 在基地攻击范围内，开始攻击周期
	_attack_started = true  ## 标记进入攻击周期
	## #14（2026-08-15）：每周期 force 重播攻击动画——周期结束后 current_anim_state 仍为
	## "attack"，下周期 play_anim("attack")（非 force）被同名守卫拦截不重播 → 动画定格在
	## 上一周期末帧，但 attack_base 伤害照常触发（用户反馈「打水晶只播一次动画后定格原地，
	## 水晶却照常扣血」）。force 起播 + 双攻击轮流翻转（凑企鹅等 attack_alt_frames 兵种）。
	if unit.anim_attack_frames_alt != null:
		unit.attack_anim_toggle = not unit.attack_anim_toggle  ## 双攻击轮流（先攻击1再攻击2）
	unit.play_anim("attack", true)  ## force 重播（突破同名守卫），从第一帧起播
	_attack_cycle(delta, res)  ## 执行攻击周期

## 攻击周期（前摇 + 命中 + 后摇，期间不移动）
## 前摇：0 ~ attack_speed * 0.4，播放攻击动画，不移动，不攻击
## 命中：attack_speed * 0.4，对基地造成伤害
## 后摇：attack_speed * 0.4 ~ attack_speed，继续播放攻击动画，不移动
func _attack_cycle(delta: float, res: UnitResource) -> void:  ## 定义攻击周期方法
	unit.attack_timer += delta  ## 计时器累加
	## 命中点在前摇结束处（attack_speed 的 40%）
	var hit_point: float = res.attack_speed * 0.4  ## 命中时间点

	## 设置朝向（面朝基地方向）
	var base_x: float = get_enemy_base_position().x  ## 敌方基地 X 坐标
	var attack_dir: float = signf(base_x - unit.global_position.x)  ## 朝基地方向
	if attack_dir != 0.0:  ## 如果方向非 0
		unit.set_facing_direction(attack_dir)  ## 设置朝向
	unit.velocity = Vector2.ZERO  ## 速度归零（不能移动）
	unit.move_and_slide()  ## 执行移动（实际不移动）

	## 前摇阶段：播放攻击动画，不移动，不攻击
	if unit.attack_timer < hit_point:  ## 如果在前摇阶段
		unit.play_anim("attack")  ## 播放攻击动画
		return  ## 直接返回

	## 命中点：对基地造成伤害（仅执行一次）
	if not _attack_performed:  ## 如果本周期尚未攻击
		unit.attack_base()  ## 对基地造成一次伤害
		_attack_performed = true  ## 标记已攻击
		## #14（2026-08-15）：攻击水晶的命中帧也触发突进（attack_dash_px > 0 的兵种，如凑企鹅），
		## 方向朝敌方基地——与 state_attack 命中突进保持一致的打击感（state_attack 走 target，这里走 base_pos）
		unit.start_attack_dash_toward(get_enemy_base_position())

	## 后摇阶段：继续播放攻击动画，不移动
	if unit.attack_timer < res.attack_speed:  ## 如果在后摇阶段
		unit.play_anim("attack")  ## 继续播放攻击动画
		return  ## 直接返回

	## 攻击周期结束，重置计时器和标志
	unit.attack_timer = 0.0  ## 重置计时器
	_attack_performed = false  ## 重置攻击标志
	## #1（2026-08-09）：周期结束后**不**立即重进攻击周期，而是退回空闲态，
	## 让下一帧 update 走射程内索敌逻辑（L60-69）：若敌方刚刷出兵种且在本单位射程内，
	## 优先切换攻击兵种；无兵可打才重新开始下一次水晶攻击周期。
	## 旧实现 _attack_started=true 直接重进周期、从不重新索敌，敌方出兵时中远程兵
	## 会无视刷出来的敌人继续硬敲水晶，水晶被白嫖到死。
	_attack_started = false
