extends UnitState  ## 继承单位状态基类
## 攻击状态
## 攻击动画播放中：命中由动画帧或动画进度触发，动画结束立即进入后摇。
## 后摇：攻击动画结束后的固定恢复时间，结束后重新索敌并播放下一轮攻击。
## 后摇动画（2026-09-11）：待机 > 行走 > 奔跑（站定段）；需要位移的追击/后撤仍播奔跑。
## 近战：攻击范围内有敌人→待机停下，没敌人→奔跑追击；远程：正前方有敌人→奔跑后撤，没敌人→攻击动画第一帧定格
## 远程单位在敌人进入射程时立刻停下开始攻击周期
## 近战单位追击时若遇到更近的敌方单位会切换目标

## 本攻击周期已执行的攻击次数（用于连击）
var _attacks_done: int = 0  ## 本周期已攻击次数
## 本攻击周期是否已播放过攻击音效
var _sound_played: bool = false  ## 本周期是否已播放音效
## 是否正在攻击周期中（攻击期间不能移动，必须完整执行完前后摇）
var _attack_started: bool = false  ## 是否在攻击周期中
## 攻击后摇倒计时（秒）：攻击动画结束后开始，>0 时不能开始下一轮攻击。
var _hard_recovery_timer: float = 0.0  ## 后摇倒计时
## #6（2026-08-09）：远程「超射程防抖」累计时间（秒）：目标在射程边缘振荡时原地待命，
## 累计超射程达 Constants.RANGED_ATTACK_LOSE_TIMER 才切回默认状态，杜绝每帧 move↔attack↔idle 循环
var _out_of_range_timer: float = 0.0  ## 超射程累计时间

## 进入攻击状态时调用
func enter() -> void:  ## 重写进入状态方法
	## 重置攻击计时器和标志
	unit.attack_anim_elapsed = 0.0  ## 重置攻击动画计时器
	_attacks_done = 0  ## 重置已攻击次数
	_sound_played = false  ## 重置音效播放标志
	_attack_started = false  ## 重置攻击周期标志
	_hard_recovery_timer = 0.0  ## 重置硬后摇锁定
	_out_of_range_timer = 0.0  ## 重置超射程防抖
	unit._reset_dodge_state()  ## 清空卡住绕步状态，避免上一状态的残留
	## 如果配置了帧触发命中（单帧模式或多段连击模式），连接 attack_animation_hit 信号
	if _uses_frame_hit(unit.unit_resource):
		if not unit.attack_animation_hit.is_connected(_on_frame_hit):
			unit.attack_animation_hit.connect(_on_frame_hit)
	## #双攻击（凑企鹅 Y2 等）2026-08-15 修：进入攻击状态即翻转动画源。
	## 进入攻击状态时切换备用攻击动画，保证双攻击动画轮流使用。
	## 本周期翻转——近战单位「每个目标只打一刀就换目标」（一刀一个的小兵）时，toggle 从不翻转，
	## 永远只播攻击1（用户反馈「没有轮流播放两种攻击动画」）。此处翻转保证每次进入都换一套，
	## 与周期边界翻转互补：换目标交替、连续多周期也交替。
	if unit.anim_attack_frames_alt != null:
		unit.attack_anim_toggle = not unit.attack_anim_toggle
	_play_attack_display_anim(true)  ## 按兵种攻击表现动画模式强制起播

## 按兵种「攻击表现动画模式」播放攻击表现动画（#无攻击动画单位 2026-08-25）
## ""：默认攻击动画；"idle"：无攻击动画坦克播待机（S5 咕嘎工钢）；"charge"：无攻击动画保持奔跑撞击（S4 动力菲比）
func _play_attack_display_anim(force: bool) -> void:
	var mode: String = "" if (unit == null or unit.unit_resource == null) else unit.unit_resource.attack_anim_mode
	if mode == "charge":
		unit.play_anim("move", force)  ## 撞击单位：奔跑冲撞
	elif mode == "idle":
		unit.play_anim("idle", force)  ## 坦克单位：近敌播待机
	else:
		unit.play_anim("attack", force)  ## 默认攻击动画

## 退出攻击状态时调用
func exit() -> void:  ## 重写退出状态方法
	## 断开 attack_animation_hit 信号，避免离开状态后仍触发命中
	## 无条件断开：资源在运行时可被控制台改写，按条件断开会漏掉已连接的信号
	if unit != null and unit.attack_animation_hit.is_connected(_on_frame_hit):
		unit.attack_animation_hit.disconnect(_on_frame_hit)

## 判断兵种是否使用「动画帧驱动命中」
## 三种配置都算帧驱动：
##   - attack_hit_frame_start >= 0        ：主动画单帧命中（一次攻击一段伤害）
##   - attack_hit_frame_start_alt >= 0    ：备用攻击动画（attack_alt_frames）单帧命中
##   - attack_hit_frames 非空             ：多段连击（每个元素是一段伤害的判定帧，如 G6 [10,17]）
## 之前只判断前者，导致 G6/N5 这类只配 attack_hit_frames 的多段兵种信号永不连接，
## 帧命中完全失效，只能退化成时间比例命中（#181）
## #18-4（2026-08-15）：加 alt 命中帧——双攻击兵种（Y2）仅备用动画配独立判定帧时也须连接信号
static func _uses_frame_hit(res: UnitResource) -> bool:
	if res == null:
		return false
	return res.attack_hit_frame_start >= 0 or res.attack_hit_frame_start_alt >= 0 or not res.attack_hit_frames.is_empty()

## 帧触发命中的信号回调：动画播放到配置的判定帧时调用
## 执行 perform_attack（近战伤害或远程投射物）
## hit_index: 当前命中的索引（用于支持二连击不同伤害类型）
func _on_frame_hit(hit_index: int = 0) -> void:
	if unit == null or unit.is_dead:
		return
	_attacks_done += 1  ## 计入本周期已完成的命中数，供周期结束时的兜底补齐使用
	## #18-2（2026-08-15）：突进已由 unit_base._check_attack_hit_frame 在命中帧**前一帧**预触发
	## （frame >= attack_hit_frame_start - 1），这里不再触发——否则命中帧会重复调用
	## start_attack_dash 重置 dash 计时。命中帧只需结算伤害。
	unit.perform_attack(hit_index)

## 攻击状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(delta: float) -> void:  ## 重写每帧更新方法
	if unit == null or not is_instance_valid(unit) or unit.is_dead or unit.ai_disabled:
		return
	var res: UnitResource = unit.unit_resource
	if res == null:
		return

	## 攻击动画结束后立即进入后摇；后摇结束才允许下一次攻击。
	## 这里必须先处理后摇，再检查目标，避免击杀目标后跳过后摇。
	if _hard_recovery_timer > 0.0:
		_hard_recovery_timer = maxf(0.0, _hard_recovery_timer - delta)
		if _is_target_lost():
			## B（2026-09-11 用户拍板）：后摇期间目标被击杀 → 立刻就近换锁并转入追击，
			## 不再沿基地方向推进（Hero/S/Y 秒杀目标后「攻击完继续前冲、回神后转头打」的根因）。
			if _reacquire_recovery_target():
				_backswing_update(delta, res)
				return
			unit.target = null
			_move_during_recovery_without_target(delta, res)
		else:
			_backswing_update(delta, res)
		return

	## 攻击动画播放期间不重新索敌、不移动；命中由动画帧或动画进度触发。
	if _attack_started:
		if res.is_ranged and _is_target_lost():
			if not _reacquire_ranged_target(res) and res.attack_hit_frames.is_empty():
				_abort_attack_cycle()
				unit.change_state(unit.get_idle_state_name())
				return
		_attack_cycle(delta, res, Vector2.ZERO)
		return

	## 后摇结束后才重新检查目标。
	if _is_target_lost():
		unit.target = null
		_attacks_done = 0
		_sound_played = false
		unit.change_state(unit.get_idle_state_name())
		return
	if unit.is_guard_mode() and not unit.is_locked_on_forced_target() and _beyond_guard_leash():
		_abort_attack_cycle()
		unit.change_state("guard")
		return

	var dist_vec: Vector2 = unit.target.global_position - unit.global_position
	var dist: float = dist_vec.length()
	if not res.is_ranged:
		_retarget_for_melee(dist)
		if unit.target == null:
			return
		dist_vec = unit.target.global_position - unit.global_position
		dist = dist_vec.length()

	if unit.is_target_out_of_attack_range(unit.target.global_position, 10.0):
		if res.is_ranged:
			_out_of_range_timer += delta
			if _out_of_range_timer >= Constants.RANGED_ATTACK_LOSE_TIMER:
				_out_of_range_timer = 0.0
				unit.change_state(unit.get_idle_state_name())
			else:
				unit.velocity = Vector2.ZERO
				unit.move_and_slide()
				unit.set_facing_hysteresis(dist_vec.x, Constants.ATTACK_FACING_DEADBAND_PX)
				unit.play_anim("idle")
			return
		_move_towards_target(delta, res, dist_vec)
		return

	## 进入攻击动画状态：动画开始即进入本轮攻击，不等待任何攻击间隔。
	_attack_started = true
	_out_of_range_timer = 0.0
	_attacks_done = 0
	_sound_played = false
	unit.attack_anim_elapsed = 0.0
	unit.reset_attack_frame_flags()
	if unit.anim_attack_frames_alt != null:
		unit.attack_anim_toggle = not unit.attack_anim_toggle
	_play_attack_display_anim(true)
	_attack_cycle(delta, res, dist_vec)

## 攻击动画阶段：动画播完立即结束攻击，随后进入固定后摇。
## attack_anim_speed 只影响 AnimatedSprite2D 播放速度，不参与这里的计时。
func _attack_cycle(delta: float, res: UnitResource, _dist_vec: Vector2) -> void:
	unit.attack_anim_elapsed += delta
	var count: int = max(1, res.attack_count)
	var use_frame_hit: bool = _uses_frame_hit(res)
	var use_frame_sound: bool = res.attack_sound_frame >= 0 or res.attack_sound_frame_alt >= 0
	var has_attack_animation: bool = unit.anim_attack_frames != null or unit.anim_attack_frames_alt != null
	var uses_visual_attack_animation: bool = res.attack_anim_mode == "" and has_attack_animation
	## 普通单位由攻击动画决定时长；无攻击动画的特殊单位才使用旧周期字段兜底。
	var attack_anim_duration: float = _current_attack_anim_duration() if uses_visual_attack_animation else unit.get_legacy_attack_cycle_duration()
	var base_hit_ratio: float = 0.95 if not res.is_ranged else 0.4

	if res.attack_anim_mode == "charge":
		## 无攻击动画的特殊冲撞单位保留旧的碰撞节奏；普通单位不走此分支。
		if unit.target != null and is_instance_valid(unit.target):
			_move_towards_target(delta, res, unit.target.global_position - unit.global_position)
		var charge_duration: float = attack_anim_duration if attack_anim_duration > 0.0 else unit.get_legacy_attack_cycle_duration()
		if unit.attack_anim_elapsed >= charge_duration * base_hit_ratio and _attacks_done == 0:
			unit.perform_attack(0)
			_attacks_done = 1
		if unit.attack_anim_elapsed >= charge_duration:
			_finish_attack_cycle(res)
		return

	if not use_frame_hit:
		var hit_duration: float = attack_anim_duration
		if hit_duration <= 0.0:
			hit_duration = 0.05
		for i in range(count):
			var hit_point: float = hit_duration * (float(i + 1) / count) * base_hit_ratio
			if unit.attack_anim_elapsed >= hit_point and _attacks_done <= i:
				unit.perform_attack(i)
				_attacks_done += 1
				break

	## 非帧触发音效也跟随攻击动画时长。
	if not use_frame_sound and not _sound_played and attack_anim_duration > 0.0 \
			and unit.attack_anim_elapsed >= attack_anim_duration * res.attack_sound_timing:
		AudioManager.play_attack_sound(res.unit_id)
		_sound_played = true

	var attack_anim_done: bool = unit.attack_anim_elapsed >= attack_anim_duration
	if uses_visual_attack_animation:
		attack_anim_done = unit.unit_sprite == null or not unit.unit_sprite.is_playing()
	if not attack_anim_done:
		unit.velocity = Vector2.ZERO
		unit.move_and_slide()
		_play_attack_display_anim(false)
		return

	## 动画结束时补齐掉帧/异常漏掉的多段命中，之后立刻进入后摇。
	if _attacks_done < count:
		for i in range(_attacks_done, count):
			unit.perform_attack(i)
		_attacks_done = count
	_finish_attack_cycle(res)

func _finish_attack_cycle(res: UnitResource) -> void:
	_attack_started = false
	unit.attack_anim_elapsed = 0.0
	_sound_played = false
	unit.reset_attack_frame_flags()
	unit.play_backswing_anim()  ## 后摇动画（#后摇 2026-09-11：待机 > 行走 > 奔跑）
	_hard_recovery_timer = 0.0 if unit.skill_no_recovery_timer > 0.0 else unit.get_attack_recovery_duration()

## #后摇 2026-08-15（用户三连拍板，动画优先级 2026-09-11 修订为 待机 > 行走 > 奔跑）：
## 攻击结束后的后摇段（含攻击周期内后摇 / 硬后摇 / 远程恢复期共用）：
##  - #2 近战：攻击范围内有敌人 → 停下不动（待机 > 行走 > 奔跑）；没敌人 → 奔跑动画追击；
##  - #3 远程：正前方有敌人 → 奔跑动画后撤；正前方没敌人 → 停下不动（待机 > 行走 > 奔跑）。
## 绝不站定摆攻击姿势、绝不凭空漂移（动画与位移必须匹配）。
func _backswing_update(delta: float, res: UnitResource) -> void:
	if unit.target == null or not is_instance_valid(unit.target) or unit.target.is_dead:
		unit.target = null
		_attack_started = false
		unit.change_state(unit.get_idle_state_name())
		return
	var hr_dist_vec: Vector2 = unit.target.global_position - unit.global_position  ## 到目标的向量
	if res.attack_anim_mode == "charge":
		## 动力菲比：后摇主动拉开距离，硬后摇结束后自然回到攻击范围外追击并继续冲撞。
		_move_towards_target(delta, res, -hr_dist_vec)
		return
	if res.is_ranged:
		## 非肉鸽中远程后摇按互斥优先级处理：
		## ① 96px 内有近敌 → 后撤；② 精确圆/椭圆攻击范围内有敌 → 原地站定；
		## ③ 攻击范围内无敌 → 才执行正常推进。每帧只走一个分支，避免前进/后撤抢控制权。
		if not RoguelikeManager.is_active and try_ranged_retreat():
			return
		if not RoguelikeManager.is_active:
			var in_range_enemy: Unit = unit.find_nearest_enemy_in_attack_range(10.0)
			if in_range_enemy != null and is_instance_valid(in_range_enemy) and not in_range_enemy.is_dead:
				unit.target = in_range_enemy
				unit.velocity = Vector2.ZERO
				unit.move_and_slide()
				unit.set_facing_hysteresis(
						in_range_enemy.global_position.x - unit.global_position.x,
						Constants.ATTACK_FACING_DEADBAND_PX)
				unit.play_backswing_stand()
				return
		_move_during_recovery_without_target(delta, res)
		return
	else:
		## #2 近战：攻击范围内有敌人 → 停下不动；没敌人 → 奔跑追击
		if not unit.is_target_out_of_attack_range(unit.target.global_position, 10.0):
			unit.velocity = Vector2.ZERO  ## 停下不动（等冷却结束再挥）
			unit.move_and_slide()
			unit.set_facing_hysteresis(hr_dist_vec.x, Constants.ATTACK_FACING_DEADBAND_PX)  ## 保持面向目标
			unit.play_backswing_stand()  ## 后摇站定：待机动画 > 行走动画 > 奔跑动画
		else:
			_move_towards_target(delta, res, hr_dist_vec)  ## 没敌人（超射程）：奔跑追击

## B（2026-09-11 用户拍板）：后摇无目标时立刻换锁最近敌人并转入追击
##（近战由 _backswing_update 追击；中远程只换锁用于后撤判断，不在后摇中向前追击）。
## 场上已无敌人时返回 false，走 _move_during_recovery_without_target 的模式兜底语义。
## 肉鸽模式不启用——护晶站定与敌方推进语义保持原样，未经授权不改肉鸽路径。
func _reacquire_recovery_target() -> bool:
	if RoguelikeManager.is_active:
		return false
	var next_target: Unit = unit.find_nearest_enemy()
	if next_target == null or not is_instance_valid(next_target) or next_target.is_dead:
		return false
	unit.target = next_target
	return true

## 后摇期间攻击范围内没有敌人时的模式推进，不跳过后摇计时。
## 普通战斗向敌方基地推进；竞技场追击最近敌人；肉鸽保持原语义。
func _move_during_recovery_without_target(delta: float, res: UnitResource) -> void:
	if unit.is_guard_mode():
		unit.velocity = Vector2.ZERO
		unit.move_and_slide()
		unit.play_backswing_stand()
		return
	if GameManager.is_battlefield_mode:
		var next_target: Unit = unit.find_nearest_enemy()
		if next_target != null and is_instance_valid(next_target) and not next_target.is_dead:
			unit.target = next_target
			_move_towards_target(delta, res, next_target.global_position - unit.global_position)
		else:
			unit.velocity = Vector2.ZERO
			unit.move_and_slide()
			unit.play_arena_stand()
		return
	if unit.order_pos.is_finite():
		var order_vec: Vector2 = unit.order_pos - unit.global_position
		if order_vec.length() > 8.0:
			_move_towards_target(delta, res, order_vec)
		else:
			unit.velocity = Vector2.ZERO
			unit.move_and_slide()
			unit.play_backswing_stand()
		return
	if enemy_has_base():
		_move_towards_target(delta, res, get_enemy_base_position() - unit.global_position)
	else:
		unit.velocity = Vector2.ZERO
		unit.move_and_slide()
		unit.play_backswing_stand()

## #3 远程：判断「自身正前方是否有敌人」——按「敌基地方向一侧」（红方朝右、蓝方朝左）判定，
## 不用自身朝向（后撤时朝向会翻向己方基地，用朝向会只退一帧就停）。最近敌人在正前方一侧才算有。
## #性能（2026-08-27）：索敌半径由 INF 收窄到 RETREAT_SAFE_DISTANCE_PX。
## 唯一调用点是 `_enemy_in_front() and try_ranged_retreat()`，而 try_ranged_retreat 的第一道闸门
## 就是「威胁 ≥ 安全距离即不后撤」—— 最近敌人在 96px 外时整个 and 表达式必然为 false，
## 与本函数返回什么无关。故收窄半径后行为逐条等价，但省掉了每帧的全场扫描。
func _enemy_in_front() -> bool:
	var threat: Unit = unit.find_nearest_enemy_in_range(Constants.RETREAT_SAFE_DISTANCE_PX)
	if threat == null or not is_instance_valid(threat) or threat.is_dead:
		return false
	var front_sign: float = 1.0 if unit.team == 0 else -1.0  ## 红方（左）正前方=+x，蓝方（右）正前方=-x
	return (threat.global_position.x - unit.global_position.x) * front_sign > 0.0

## 肉鸽守卫：判断自己是否已被敌人牵引出水晶防区（#210）
## 牵引半径取 Unit.get_chase_leash_px()，超出即应放弃追击回防
## 返回值: true 表示已超出牵引半径
func _beyond_guard_leash() -> bool:  ## 定义牵引半径判定方法
	return unit.global_position.distance_to(get_home_base_position()) > unit.get_chase_leash_px()

## 判断当前目标是否已失效（为空 / 已释放 / 已死亡）
## 返回值: true 表示目标不可用
func _is_target_lost() -> bool:  ## 定义目标失效判定方法
	return unit.target == null or not is_instance_valid(unit.target) or unit.target.is_dead  ## 三种失效情况

## #10 配套：中远程单位在攻击周期中丢失目标时，尝试改锁射程内最近的敌人
## res: 兵种资源（用于取射程）
## 返回值: true 表示成功换锁新目标，本次攻击周期可继续
func _reacquire_ranged_target(res: UnitResource) -> bool:  ## 定义远程重新索敌方法
	## #25修复：口径统一为「有效射程 = 射程×32 + 10」（与 state_move/state_attack 的
	## 进入/退出攻击判定一致）。旧代码用精确射程（无 +10），目标停在 (range, range+10]
	## 区间时：换锁失败 → 中断攻击周期 → 回 move → move 又判目标在有效射程内切回 attack
	## → move↔attack 死循环抖动（中远程兵卡在原地只摆攻击姿势）。
	## #BugC：直接找射程内最近的敌人，而非先全场找最近再验射程
	## 旧实现在「最近敌人不在射程内但射程内有别的敌人」时返回 false → 换锁失败，
	## 现在改为直接锁射程内最近的，不会漏掉能打到的目标。
	## #25：改用射程内平分索敌 —— 换锁时同样按「被锁最少」分散火力，不无脑集火。
	var candidate: Unit = unit.find_best_distributed_target_in_attack_range(10.0)  ## 精确圆/椭圆内平分锁敌
	if candidate == null or not is_instance_valid(candidate) or candidate.is_dead:  ## 没有可用目标
		return false  ## 换锁失败
	unit.target = candidate  ## 换锁到新目标
	return true  ## 换锁成功

## 中断当前攻击周期并清空所有周期内状态
## 用于目标丢失时立刻脱离攻击状态，避免空放后摇
func _abort_attack_cycle() -> void:  ## 定义中断攻击周期方法
	unit.target = null  ## 清空失效目标
	unit.attack_anim_elapsed = 0.0  ## 重置攻击动画计时器
	_attacks_done = 0  ## 重置已攻击次数
	_sound_played = false  ## 重置音效标志
	_attack_started = false  ## 退出攻击周期
	unit.reset_attack_frame_flags()  ## 重置帧命中/帧音效标志，避免残留

## #攻击特效（2026-08-15 / #14 全局启用）：当前实际播放的攻击动画完整时长（秒，含播放倍率）
## 所有兵种用它拉长周期，保证动画不被攻击间隔兜底掐断
func _current_attack_anim_duration() -> float:
	if unit == null:
		return 0.0
	return unit.get_attack_animation_duration()

## #1（2026-08-14）：被击退时打断攻击
## 由 unit_base.apply_knockback 在击退落地前调用。按「本周期是否已出伤害」分两种：
##  - 出伤害前（_attacks_done == 0）：直接中断攻击周期、不进后摇，回正常索敌状态；
##  - 出伤害后（_attacks_done > 0）：进入攻击硬后摇（取消后续攻击动画，原地僵直），
##    与攻击周期自然结束的后摇表现一致。
func on_knockback_interrupt() -> void:
	if _attacks_done <= 0:
		## 情况1：出伤害前被打断 —— 完全中断，不进入攻击后摇
		_abort_attack_cycle()
		unit.change_state(unit.get_idle_state_name())
	else:
		## 情况2：出伤害后打断 —— 进入攻击后摇（硬僵直），取消攻击动画
		_attack_started = false
		unit.reset_attack_frame_flags()
		_sound_played = false
		_hard_recovery_timer = unit.get_attack_recovery_duration()
		unit.play_backswing_anim()  ## 后摇动画（#后摇 2026-09-11：待机 > 行走 > 奔跑）；play_anim 同名守卫不会每帧重置

## 近战单位切换目标逻辑
## 若检测到比当前目标更近的敌方单位（距离差超过 30 像素），则切换目标
## 这样近战单位在追击远程兵时，如果路上碰到其他兵种会改打那个，不继续追远程兵
## current_dist: 当前目标的 2D 距离
## #性能（2026-08-27）：索敌半径由 INF 收窄到 current_dist - 30（换锁的必要条件）。
## 下方闸门要求「最近敌人比当前目标近 30px 以上」才换锁，落在该半径外的敌人一律不可能
## 通过闸门 —— 收窄后行为逐条等价，但混战中半径通常只有几十像素，索敌只查邻近几格。
func _retarget_for_melee(current_dist: float) -> void:  ## 定义近战切换目标的方法
	## #框选攻击锁定（2026-09-04）：玩家已指定目标时不自动换锁 ——
	## 否则近战冲向被点的敌人时，路过任何更近的兵就把玩家的指令甩掉了
	if unit.is_locked_on_forced_target():
		return
	var seek_r: float = current_dist - 30.0  ## 只有比该半径更近的敌人才可能触发换锁
	if seek_r <= 0.0:
		return  ## 当前目标已在 30px 内，不存在能满足换锁条件的更近敌人
	if RoguelikeManager.is_active:
		seek_r = minf(seek_r, unit.get_chase_range_px())  ## 肉鸽仍受统一寻敌半径约束
	var nearer_enemy: Unit = unit.find_nearest_enemy_in_range(seek_r)  ## 该半径内最近的敌人
	if nearer_enemy == null:  ## 如果没有找到敌人
		return  ## 直接返回
	if nearer_enemy == unit.target:  ## 如果最近敌人就是当前目标
		return  ## 直接返回
	## 计算最近敌人的距离
	var nearer_dist: float = unit.global_position.distance_to(nearer_enemy.global_position)  ## 计算最近敌人距离
	## 仅当最近敌人比当前目标近 30 像素以上时才切换，避免频繁抖动
	if current_dist - nearer_dist > 30.0:  ## 如果最近敌人明显更近
		unit.target = nearer_enemy  ## 切换目标到最近敌人

## 朝目标 2D 移动（同时调整 X 和 Y，适用于等视角多线战场）
## 用 velocity + move_and_slide 走碰撞系统，撞到友军会被挡住而不是穿过去；
## 若前进持续受阻，自动向侧方绕步（卡住自动寻路），绕开后继续追击进攻；
## 同时叠加友军分离推力，避免密集人堆互相推挤位移。
func _move_towards_target(delta: float, _res: UnitResource, dist_vec: Vector2, anim: String = "move") -> void:  ## 定义朝目标移动的方法（anim 默认 "move"，后摇传 "attack" 保持攻击姿态）
	var speed_px: float = unit.get_move_speed_px()  ## 计算像素速度（含文物/军令加成）
	var dir: Vector2 = dist_vec.normalized()  ## 归一化方向
	if dir.length() < 0.01:  ## 如果方向几乎为零
		unit.velocity = Vector2.ZERO  ## 速度归零，避免残留速度继续推进
		return  ## 直接返回
	unit.set_facing_hysteresis(dir.x * speed_px, maxf(0.25, speed_px * 0.4))  ## 传像素速度 X，避免归一化方向落入死区

	## 友军分离推力（防止人堆推挤位移）
	var sep: Vector2 = unit._compute_ally_separation()  ## 计算分离推力

	## 绕步（卡住自动侧向寻路）进行中：以侧向（Y 轴）移动为主，保留部分前进
	if unit._dodge_timer > 0.0:  ## 正在绕步
		unit._dodge_timer -= delta  ## 倒计时
		if unit._dodge_timer <= 0.0:  ## 绕步结束
			unit._stuck_timer = 0.0  ## 重置卡住计时，避免立刻再次触发
			unit._dodge_dir = 0.0  ## 清空绕步方向
		var lateral: float = minf(speed_px, 120.0) * unit._dodge_dir  ## 侧向绕步速度（限制上限，避免飞越全场）
		var dodge_vel := Vector2(dir.x * speed_px * Unit.DODGE_FORWARD_FACTOR, lateral) + sep * 0.5  ## 绕步速度
		## 绕步是「前进分量 + 侧向分量 + 分离推力」三者相加，合速度极易超过兵种移速，
		## 这正是「寻路转弯时瞬间加速」的来源。限幅后转弯只改方向、不改速度。
		unit.velocity = unit.clamp_move_velocity(dodge_vel, speed_px)  ## 设置绕步速度（恒定速率）
		unit.move_and_slide()  ## 执行移动并处理碰撞
		unit.play_anim(anim)  ## 播放移动动画（后摇传 "attack"）
		unit._return_to_lane(delta)  ## 拉回出生阵线，抵消 Y 漂移
		return  ## 绕步分支已处理移动，直接返回

	## 正常追击：朝目标前进并叠加分离推力
	var intended: float = speed_px * delta  ## 本帧期望前进量（沿目标方向）
	var prev: Vector2 = unit.global_position  ## 移动前位置
	## 追击速度同样限幅，避免分离推力把合速度顶到移速之上（重新索敌时的窜动感）
	unit.velocity = unit.clamp_move_velocity(dir * speed_px + sep, speed_px)  ## 设置追击速度（含分离，恒定速率）
	unit.move_and_slide()  ## 执行移动并处理碰撞
	unit.play_anim(anim)  ## 播放移动动画（后摇传 "attack"）
	unit._return_to_lane(delta)  ## 拉回出生阵线，抵消 Y 漂移

	## 卡住检测：期望前进却几乎没动 → 累计受阻时间，达阈值触发绕步
	var forward_progress: float = (unit.global_position - prev).dot(dir)  ## 实际沿目标方向位移
	if intended > 0.5 and forward_progress < intended * 0.3:  ## 想前进却受阻
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
	else:  ## 正常前进，清空卡住计时
		unit._stuck_timer = 0.0

## 说明：查找最近近战敌人的逻辑已上移到 UnitState.find_nearest_melee_enemy()，
## 由移动状态与攻击状态共用，避免两处实现不一致。
