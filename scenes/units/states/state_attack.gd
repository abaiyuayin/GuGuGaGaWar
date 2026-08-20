extends UnitState  ## 继承单位状态基类
## 攻击状态
## 前摇/挥击中（命中未出）：站定播放攻击动画，不移动（命中已出即锁真进后摇，见 _swing_done）
## 命中（40% attack_speed）：执行攻击（近战直接伤害，远程发射投射物）
## 后摇（命中已出→本周期结束前）：#2/#3 行为（近战停下或追击 / 远程定格或后撤），见 _backswing_update
## #后摇 2026-08-15（#12 最终拍板）：命中已出立刻进入后摇；后摇 = 攻击冷却
## 近战：攻击范围内有敌人→待机停下，没敌人→奔跑追击；远程：正前方有敌人→奔跑后撤，没敌人→攻击动画第一帧定格
## 远程单位在敌人进入射程时立刻停下开始攻击周期
## 近战单位追击时若遇到更近的敌方单位会切换目标

## 本攻击周期已执行的攻击次数（用于连击）
var _attacks_done: int = 0  ## 本周期已攻击次数
## 本攻击周期是否已播放过攻击音效
var _sound_played: bool = false  ## 本周期是否已播放音效
## 是否正在攻击周期中（攻击期间不能移动，必须完整执行完前后摇）
var _attack_started: bool = false  ## 是否在攻击周期中
## 攻击后摇/冷却恢复倒计时（秒）：>0 时中远程兵进入「恢复期后撤」，归零即转回攻击（#17，杜绝无限后退）
var _recovery_countdown: float = 0.0  ## 恢复期倒计时
## #5（2026-08-09 起）/ #回归修复 2026-08-15：攻击硬后摇倒计时（秒）：>0 时仍处攻击冷却、不可发起新攻击，
## 但照常移动（近战追击 / 远程风筝后撤）——反转 2026-08-09「完全锁定」拍板。倒计时结束才进入 _recovery_countdown 恢复期。
var _hard_recovery_timer: float = 0.0  ## 硬后摇（攻击冷却）倒计时
## #6（2026-08-09）：远程「超射程防抖」累计时间（秒）：目标在射程边缘振荡时原地待命，
## 累计超射程达 Constants.RANGED_ATTACK_LOSE_TIMER 才切回默认状态，杜绝每帧 move↔attack↔idle 循环
var _out_of_range_timer: float = 0.0  ## 超射程累计时间
var _swing_played: bool = false  ## 本攻击周期是否已强制起播攻击动画（避免只播一次后冻在末帧，导致「攻击姿势永久卡住」）
var _swing_done: bool = false  ## 本周期「挥击结束」锁存：攻击动画播完或命中已出即锁真，后摇切奔跑后 is_playing() 恒真也不回退到挥击段

## 进入攻击状态时调用
func enter() -> void:  ## 重写进入状态方法
	## 重置攻击计时器和标志
	unit.attack_timer = 0.0  ## 重置攻击计时器
	_attacks_done = 0  ## 重置已攻击次数
	_sound_played = false  ## 重置音效播放标志
	_attack_started = false  ## 重置攻击周期标志
	_recovery_countdown = 0.0  ## 重置恢复期倒计时
	_hard_recovery_timer = 0.0  ## 重置硬后摇锁定
	_out_of_range_timer = 0.0  ## 重置超射程防抖
	unit._reset_dodge_state()  ## 清空卡住绕步状态，避免上一状态的残留
	## 如果配置了帧触发命中（单帧模式或多段连击模式），连接 attack_animation_hit 信号
	if _uses_frame_hit(unit.unit_resource):
		if not unit.attack_animation_hit.is_connected(_on_frame_hit):
			unit.attack_animation_hit.connect(_on_frame_hit)
	## #双攻击（凑企鹅 Y2 等）2026-08-15 修：进入攻击状态即翻转动画源。
	## 原实现只在周期边界的 _swing_played 处翻转，而 enter() 先把 _swing_played 置 true 拦掉
	## 本周期翻转——近战单位「每个目标只打一刀就换目标」（一刀一个的小兵）时，toggle 从不翻转，
	## 永远只播攻击1（用户反馈「没有轮流播放两种攻击动画」）。此处翻转保证每次进入都换一套，
	## 与周期边界翻转互补：换目标交替、连续多周期也交替。
	if unit.anim_attack_frames_alt != null:
		unit.attack_anim_toggle = not unit.attack_anim_toggle
	unit.play_anim("attack", true)  ## 强制播放攻击动画
	_swing_played = true  ## 首次进入已强播，本周期不再重复强播（避免每帧 force 重播抖动）
	_swing_done = false  ## 重置挥击结束锁存

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
	## 安全校验：单位引用失效时停止处理（防止调数值时单位被移除导致闪退）
	if unit == null or not is_instance_valid(unit):
		return
	## 如果单位已死亡，停止处理
	if unit.is_dead:  ## 如果单位已死亡
		return  ## 直接返回
	## AI 禁用时不执行攻击逻辑（用于调试模拟，停止按钮立即生效）
	if unit.ai_disabled:
		return

	## 获取兵种资源
	var res: UnitResource = unit.unit_resource  ## 获取兵种资源
	if res == null:
		return

	## 如果正在攻击周期中，必须完整执行完前后摇（攻击动画必须播完才能切换状态）
	## 即使目标死亡或超出范围，也要等当前攻击周期结束才切换状态
	if _attack_started:  ## 如果在攻击周期中
		## #10：中远程单位在攻击周期内目标阵亡时，原逻辑会把整段后摇空放完却不发射飞行物，
		##      表现为「挥了个空刀」。这里改为立即改打射程内的下一个目标；
		##      射程内确实没人了就中断周期回移动状态，不再空转动画。
		if res.is_ranged and _is_target_lost():  ## 远程且目标已失效
			if not _reacquire_ranged_target(res):  ## 射程内没有可换的目标
				_abort_attack_cycle()  ## 中断当前攻击周期
				unit.change_state(unit.get_idle_state_name())  ## 回到默认状态重新索敌
				return  ## 直接返回
		_attack_cycle(delta, res, Vector2.ZERO)  ## 执行攻击周期（不依赖目标距离）
		return  ## 直接返回

	## 以下逻辑仅在非攻击周期中执行（攻击周期已结束，可以切换状态）
	## 检查目标是否仍然有效
	if unit.target == null or unit.target.is_dead or not is_instance_valid(unit.target):  ## 如果目标无效
		unit.target = null  ## 清空无效目标
		_attacks_done = 0  ## 重置已攻击次数
		_sound_played = false  ## 重置音效标志
		_attack_started = false  ## 重置攻击周期标志
		unit.attack_timer = 0.0  ## 重置计时器
		unit.change_state(unit.get_idle_state_name())  ## 切回默认状态寻找新的目标
		return  ## 直接返回

	## 肉鸽守卫：追出水晶牵引半径就放弃追击回防（#210「以保护水晶为主」）
	## 只在非攻击周期中判定，不会打断已经开始的前后摇动画
	if unit.is_guard_mode() and _beyond_guard_leash():  ## 已被敌人牵引出防区
		_abort_attack_cycle()  ## 清空目标与周期状态
		unit.change_state("guard")  ## 返回驻守点
		return  ## 直接返回

	## 计算 2D 距离向量（等视角战场需要考虑 Y 轴）
	var dist_vec: Vector2 = unit.target.global_position - unit.global_position  ## 到目标的向量
	var dist: float = dist_vec.length()  ## 2D 距离

	## 近战单位：不在攻击周期中时，若发现更近的敌方单位则切换目标
	if not res.is_ranged:  ## 近战单位
		_retarget_for_melee(dist)  ## 尝试切换到更近的目标
		## 目标可能已切换，重新计算距离
		if unit.target == null:  ## 如果目标丢失
			return  ## 直接返回
		dist_vec = unit.target.global_position - unit.global_position  ## 重新计算距离向量
		dist = dist_vec.length()  ## 重新计算距离

	## #回归修复 2026-08-15：攻击硬后摇 = 攻击冷却（近战 0.5s / 中远程 1s），期间仅锁定不能发起新攻击。
	## #5 最终拍板：后摇期间行为按 #2/#3——近战：攻击范围内有敌人就停下不动、没敌人就奔跑追击；
	## 远程：正前方有敌人就奔跑后撤、没敌人就停下不动。绝不站定摆攻击姿势、绝不凭空漂移。
	## 硬后摇结束才进入 #17 恢复期（远程后撤窗口，近战直接重新索敌）。
	## #需求21：近战兵种同样进入硬后摇（0.5s），故目标可能已在本帧死亡/释放，转身前必须判空。
	if _hard_recovery_timer > 0.0:
		_hard_recovery_timer -= delta
		_backswing_update(delta, res)  ## #2/#3 后摇行为（目标失效内部已切换状态）
		if _hard_recovery_timer <= 0.0:  ## 硬后摇结束 → 直接转回攻击判定（不再叠加恢复期后撤窗口，避免总后摇 2-3s）
			unit.stop_recovery_tail()  ## 停止末段循环
		return  ## 硬后摇期间不执行任何攻击判定

	## #8（2026-08-15）：取消恢复期后撤窗口（_recovery_countdown 风筝），总后摇 = 硬后摇（攻击冷却）≈ 1s，
	## 远程 #3 行为已在硬后摇期间由 _backswing_update 兜底；恢复期再叠加会拉长到 2-3s，严重拖慢远程 DPS。
	## 近战 fall-through 到下方攻击范围判定。

	## 不在攻击周期中，判断是否在攻击范围内
	## #3：攻击范围改用椭圆判定（h/v 任一非零即启用），否则圆形与旧逻辑等价
	if unit.is_target_out_of_attack_range(unit.target.global_position, 10.0):  ## 如果超出攻击范围（10px 滞回容差）
		if res.is_ranged:  ## 远程单位
			## #6（2026-08-09）：超射程防抖——守卫索敌半径（chase_range）比射程大得多，
			## 敌人在「追击半径内、射程外」时旧逻辑立刻切回默认状态 → guard/attack 每帧交替，
			## 表现为「原地疯狂左右转头不攻击」。改为累计超射程时长：
			## 短时间超射程原地待命面向目标（目标马上进射程就不切状态），
			## 连续超射程达 RANGED_ATTACK_LOSE_TIMER 才放弃回默认状态。
			_out_of_range_timer += delta  ## 累计超射程时长
			if _out_of_range_timer >= Constants.RANGED_ATTACK_LOSE_TIMER:  ## 连续超射程超阈值
				_out_of_range_timer = 0.0  ## 重置防抖计时
				unit.change_state(unit.get_idle_state_name())  ## 切换回默认状态
			else:  ## 短时间超射程：原地待命，面向目标等它进射程
				unit.velocity = Vector2.ZERO  ## 原地待命不追击
				unit.move_and_slide()  ## 保持碰撞表现
				unit.set_facing_hysteresis(dist_vec.x, Constants.ATTACK_FACING_DEADBAND_PX)  ## 面向目标（滞回）
				unit.play_anim("idle")  ## 待命姿态
			return  ## 直接返回
		## 近战单位：朝目标 2D 移动追击
		_move_towards_target(delta, res, dist_vec)  ## 朝目标移动
		return  ## 直接返回

	## 在攻击范围内，开始攻击周期（进入前后摇，不能移动）
	_attack_started = true  ## 标记进入攻击周期
	_recovery_countdown = 0.0  ## 重置恢复期，避免上一周期残留
	_out_of_range_timer = 0.0  ## #6：目标已入射程，重置超射程防抖
	_attack_cycle(delta, res, dist_vec)  ## 执行攻击周期

## 攻击周期（前摇 + 命中 + 后摇，期间不能移动）
## 单次攻击：近战命中在 95%，远程命中在 40%
## 多次连击（attack_count>1）：在一个周期内均匀分布多次命中点
## 例如 attack_count=2 近战：命中点在 47.5% 和 95%
## 音效优先级：attack_sound_frame（帧触发）> attack_sound_timing 比例
## 命中优先级：attack_hit_frame_start/end（帧触发）> 时间比例（base_hit_ratio）
func _attack_cycle(delta: float, res: UnitResource, dist_vec: Vector2) -> void:  ## 定义攻击周期方法
	unit.attack_timer += delta  ## 计时器累加
	## 计算连击次数（至少1次）
	var count: int = max(1, res.attack_count)  ## 连击次数
	## 基础命中比例：近战 0.95（动画结束前一帧），远程 0.4
	var base_hit_ratio: float = 0.95 if not res.is_ranged else 0.4  ## 基础命中比例
	## 是否启用帧触发机制（单帧命中 或 多段连击判定帧，两者都由动画帧驱动）
	var use_frame_hit: bool = _uses_frame_hit(res)  ## 是否用帧触发命中
	var use_frame_sound: bool = res.attack_sound_frame >= 0  ## 是否用帧触发音效

	## 设置朝向（面朝目标）
	## #5（2026-08-08）：改用带滞回死区的朝向设置。旧实现按 signf(dist_vec.x) 每帧翻转，
	## 目标与自身几乎同 Y 时 dist_vec.x 在 ±阈值间抖动 → 「攻击循环 + 后撤」期间疯狂左右抽搐。
	## 传原始 X 分量（像素距离）+ 24px 死区：目标在自身水平 24px 内保持当前朝向不翻转。
	var attack_dir: float = signf(dist_vec.x)  ## 攻击方向
	if attack_dir != 0.0:  ## 如果方向非 0
		unit.set_facing_hysteresis(dist_vec.x, Constants.ATTACK_FACING_DEADBAND_PX)  ## 意图方向 + 滞回死区

	## 播放攻击音效
	## 帧触发模式：由 unit_base._check_attack_hit_frame 在动画帧到达 attack_sound_frame 时播放
	## 时间比例模式：在 attack_sound_timing 比例处播放，每周期仅一次
	if not use_frame_sound and not _sound_played:  ## 未用帧触发且本周期尚未播放
		var sound_point: float = unit.get_attack_interval() * res.attack_sound_timing  ## 音效播放时间点
		if unit.attack_timer >= sound_point:  ## 到达音效播放时机
			AudioManager.play_attack_sound(res.unit_id)  ## 播放攻击音效（最多同时 10 个）
			_sound_played = true  ## 标记已播放

	## 命中判定
	## 帧触发模式：由 unit_base._check_attack_hit_frame 在动画帧进入 [start, end] 范围时
	##            emit attack_animation_hit 信号，本状态通过信号回调执行 perform_attack
	## 时间比例模式：连击命中点均匀分布，第 i 次命中在 (i+1)/count * base_hit_ratio * attack_speed
	if not use_frame_hit:  ## 未用帧触发命中，使用时间比例
		for i in range(count):  ## 遍历每次连击
			var hit_point: float = unit.get_attack_interval() * (float(i + 1) / count) * base_hit_ratio  ## 第 i 次命中时间点
			if unit.attack_timer >= hit_point and _attacks_done <= i:  ## 如果到达命中点且尚未执行该次攻击
				unit.perform_attack(i)  ## 执行攻击，传入命中索引 i（支持二连击不同伤害类型）
				_attacks_done += 1  ## 已攻击次数+1
				break  ## 每帧最多执行一次攻击

	## 每个攻击周期强制起播一次攻击动画：enter() 仅在首次进入攻击状态时强播，
	## 之后周期不重进 enter()（攻击状态不切换），若只靠 is_playing() 判定，
	## 上一周期 loop=false 已定格末帧 → is_playing()=false → 跳过起播 → 攻击动画永远冻在上一周期末帧
	## （表现即「攻击后停在攻击姿势永久不动」）。故每周期显式 force 起播一次。
	if not _swing_played:
		## #双攻击（凑企鹅 Y4 等）：每攻击周期翻转一次动画源，先攻击1（默认）再攻击2（备用）
		if unit.anim_attack_frames_alt != null:
			unit.attack_anim_toggle = not unit.attack_anim_toggle
		unit.play_anim("attack", true)  ## 强制从第一帧起播
		_swing_played = true
	## 攻击动画是否已完整播完（loop=false 定格末帧）
	var attack_anim_done: bool = (unit.unit_sprite == null) or (not unit.unit_sprite.is_playing())
	var hit_done: bool = _attacks_done >= count
	var has_attack_anim: bool = unit.anim_attack_frames != null or unit.anim_attack_frames_alt != null
	## #14（2026-08-15 用户拍板）：默认所有兵种攻击动画完整播放——命中已出后仍继续播放动画，
	## 等到动画播完（或攻击间隔兜底）才锁真进后摇。推翻 #12「命中已出即锁真进后摇」
	## （该行为把普通兵种攻击动画后半段全掐断）。
	## #14 补丁：H2 例外（attack_wait_anim_end=false）——其攻击动画 frame 14 后帧内容尺寸
	## 暴涨，完整播放会视觉膨胀偏移，故 H2 保持「命中即后摇」。
	## 周期长度需覆盖动画时长，否则「攻击间隔兜底」会在动画播完前锁后摇，把动画/特效掐断。
	var cycle_len: float = unit.get_attack_interval()
	if res.attack_wait_anim_end and has_attack_anim:
		cycle_len = maxf(cycle_len, _current_attack_anim_duration())
	if not _swing_done:
		if hit_done and not (res.attack_wait_anim_end and has_attack_anim and not attack_anim_done):
			_swing_done = true  ## 命中已出（且动画播完 / 非完整播放兵种）→ 进后摇
		elif unit.attack_timer >= cycle_len:
			_swing_done = true  ## 周期兜底：命中/动画异常时确保周期能结束，绝不无限挥
	if not _swing_done:
		## 前摇/挥击中（动画没播完 或 伤害没出齐）：站定播放攻击动画，不移动
		unit.velocity = Vector2.ZERO  ## 速度归零（不能移动）
		unit.move_and_slide()  ## 执行移动（实际不移动）
		if attack_anim_done and has_attack_anim:
			## 动画停了但伤害没出齐（远程命中在动画后 / 多段最后一击）→ 强制重播保持挥击视觉
			unit.play_anim("attack", true)  ## force 重播（突破同名守卫），避免冻在攻击末帧
		else:
			unit.play_anim("attack")  ## 正常播放（同名守卫下若已在播则不重置）
		return  ## 直接返回
	## 后摇（挥击结束：动画播完且伤害出齐 → 周期结束前）：#2/#3 行为（近战停下或追击 / 远程停下或后撤），画面奔跑或待机
	## #后摇 2026-08-15（#12 拍板）：命中已出即进后摇；后摇 = 攻击冷却，行为见 _backswing_update
	if unit.attack_timer < cycle_len:  ## 仍在本攻击周期内（后摇段）
		_backswing_update(delta, res)  ## #2/#3 后摇行为
		return  ## 直接返回

	## 帧触发模式兜底：动画帧数不足 / 动画被打断导致判定帧没走到时，
	## 在周期结束前补齐剩余命中，保证多段兵种（G6/N5）不会因为掉帧而少打伤害
	if use_frame_hit and _attacks_done < count:
		for i in range(_attacks_done, count):
			unit.perform_attack(i)  ## 补齐第 i 段命中（伤害类型仍按 attack_hit_types[i]）

	## 攻击周期结束：切奔跑动画进入硬后摇（后摇全程奔跑，不冻攻击姿势）
	unit.play_anim("move")

	## 攻击周期结束，重置计时器和标志
	unit.attack_timer = 0.0  ## 重置计时器
	_attacks_done = 0  ## 重置已攻击次数
	_swing_played = false  ## 重置，下一周期重新强播攻击动画
	_swing_done = false  ## 重置挥击结束锁存
	_sound_played = false  ## 重置音效标志
	## 同时重置 unit_base 的帧判定与帧音效标志，确保下一周期可重新触发
	if use_frame_hit or use_frame_sound:
		unit.reset_attack_frame_flags()

	## 远程单位：后摇结束后如果攻击范围内仍有敌人，立刻开始下一次攻击周期（不移动）
	## 若目标超出射程，回到移动状态继续向基地方向推进（不追击）
	## 近战单位：后摇结束后允许移动追击
	if res.is_ranged:  ## 如果是远程单位
		## 攻击周期中目标可能已死亡并被释放，需重新检查有效性
		if unit.target == null or not is_instance_valid(unit.target) or unit.target.is_dead:
			unit.target = null
			_attack_started = false
			unit.change_state(unit.get_idle_state_name())
			return
		## #修复：周期结束判定加 +10 容差，与「进入攻击」的阈值（state_move/state_guard 的
		## attack_range_px + 10.0）完全一致。旧代码用无容差的精确射程判定退出：
		## 目标停在 (range, range+10] 区间时，进攻击 → 周期结束判超距 → 切回 move →
		## move 又因目标在有效射程内立即切回 attack → move↔attack 死循环，
		## 中远程兵「卡在原地不攻击/只摆攻击姿势就被打断」（战役/双人/全面战争复现）。
		## #3：椭圆/圆形统一判定（与进入一致），不再单写 attack_range_px
		var cur_in_range: bool = unit.is_target_in_attack_range(unit.target.global_position, 10.0)
		if cur_in_range:  ## 如果目标仍在有效攻击范围内
			## #5（2026-08-09）：攻击周期结束后先进入硬后摇（完全锁定：不可移动/不可后撤/可转身）。
			## 旧逻辑周期一结束就进恢复期后撤窗口，中远程「打完一枪立刻风筝」，缺少攻击后摇的僵直感；
			## 新逻辑硬后摇期间 update() 锁定移动与后撤，结束后才进入 #17 恢复期后撤窗口（风筝）。
			## #需求2：时长改读兵种资源 attack_recovery_time（默认：近战 0.5s / 中远程 1s，可控制台调校）
			_attack_started = false  ## 退出攻击周期
			## #技能系统：骑射类技能（Hero5）生效期间取消攻击后摇
			_hard_recovery_timer = 0.0 if unit.skill_no_recovery_timer > 0.0 else res.get_attack_recovery_time()  ## 启动硬后摇（按兵种配置）
		else:  ## 目标超出范围
			_attack_started = false  ## 重置攻击周期标志
			unit.change_state(unit.get_idle_state_name())  ## 回到默认状态（推进 / 回防），不追击
	else:  ## 近战单位
		_attack_started = false  ## 允许下一帧重新判断移动或攻击
		## #需求21：近战兵种同样进入攻击硬后摇（默认 0.5s）——攻击周期结束后短暂锁定，
		## 与中远程保持一致的攻击节奏感；时长同样读兵种资源，可在控制台数值调整中调校
		## #技能系统：骑射类技能（Hero5）生效期间取消攻击后摇
		_hard_recovery_timer = 0.0 if unit.skill_no_recovery_timer > 0.0 else res.get_attack_recovery_time()

## #后摇 2026-08-15（用户三连拍板）：攻击结束后的后摇段（含攻击周期内后摇 / 硬后摇 / 远程恢复期共用）：
##  - #2 近战：攻击范围内有敌人 → 停下不动（待机）；没敌人 → 奔跑动画追击；
##  - #3 远程：正前方有敌人 → 奔跑动画后撤；正前方没敌人 → 停下不动（待机）。
## 绝不站定摆攻击姿势、绝不凭空漂移（动画与位移必须匹配）。
func _backswing_update(delta: float, res: UnitResource) -> void:
	if unit.target == null or not is_instance_valid(unit.target) or unit.target.is_dead:
		unit.target = null
		_attack_started = false
		unit.change_state(unit.get_idle_state_name())
		return
	var hr_dist_vec: Vector2 = unit.target.global_position - unit.global_position  ## 到目标的向量
	if res.is_ranged:
		## #3 远程：正前方有敌人（且威胁近）→ 奔跑后撤；否则停下不动
		if _enemy_in_front() and try_ranged_retreat():  ## 后撤（内部 play_anim("move") + move_and_slide）
			return
		unit.velocity = Vector2.ZERO  ## 停下不动
		unit.move_and_slide()
		## 后摇站定优先级链（2026-08-17）：待机动画 > 后摇乒乓循环帧 > 冻结当前帧
		## （原 #14「定格保持攻击末帧」行为保留为链的兜底分支）
		unit.play_backswing_stand()
	else:
		## #2 近战：攻击范围内有敌人 → 停下不动；没敌人 → 奔跑追击
		if not unit.is_target_out_of_attack_range(unit.target.global_position, 10.0):
			unit.velocity = Vector2.ZERO  ## 停下不动（等冷却结束再挥）
			unit.move_and_slide()
			unit.set_facing_hysteresis(hr_dist_vec.x, Constants.ATTACK_FACING_DEADBAND_PX)  ## 保持面向目标
			unit.play_backswing_stand()  ## 后摇站定优先级链（原 play_anim("idle")）
		else:
			_move_towards_target(delta, res, hr_dist_vec)  ## 没敌人（超射程）：奔跑追击

## #3 远程：判断「自身正前方是否有敌人」——按「敌基地方向一侧」（红方朝右、蓝方朝左）判定，
## 不用自身朝向（后撤时朝向会翻向己方基地，用朝向会只退一帧就停）。最近敌人在正前方一侧才算有。
func _enemy_in_front() -> bool:
	var threat: Unit = unit.find_nearest_enemy()
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
	var range_px: float = res.attack_range * Constants.UNIT_TO_PIXELS + 10.0  ## 有效射程像素值（+10 容差）
	## #BugC：直接找射程内最近的敌人，而非先全场找最近再验射程
	## 旧实现在「最近敌人不在射程内但射程内有别的敌人」时返回 false → 换锁失败，
	## 现在改为直接锁射程内最近的，不会漏掉能打到的目标。
	## #25：改用射程内平分索敌 —— 换锁时同样按「被锁最少」分散火力，不无脑集火。
	var candidate: Unit = unit.find_best_distributed_target(range_px)  ## 射程内平分锁敌
	if candidate == null or not is_instance_valid(candidate) or candidate.is_dead:  ## 没有可用目标
		return false  ## 换锁失败
	unit.target = candidate  ## 换锁到新目标
	return true  ## 换锁成功

## 中断当前攻击周期并清空所有周期内状态
## 用于目标丢失时立刻脱离攻击状态，避免空放后摇
func _abort_attack_cycle() -> void:  ## 定义中断攻击周期方法
	unit.target = null  ## 清空失效目标
	unit.attack_timer = 0.0  ## 重置计时器
	_attacks_done = 0  ## 重置已攻击次数
	_sound_played = false  ## 重置音效标志
	_attack_started = false  ## 退出攻击周期
	_swing_played = false  ## 重置起播标志，避免下次周期不重播
	_swing_done = false  ## 重置挥击结束锁存
	unit.reset_attack_frame_flags()  ## 重置帧命中/帧音效标志，避免残留

## #攻击特效（2026-08-15 / #14 全局启用）：当前实际播放的攻击动画完整时长（秒，含播放倍率）
## 所有兵种用它拉长周期，保证动画不被攻击间隔兜底掐断
func _current_attack_anim_duration() -> float:
	if unit == null or unit.unit_sprite == null:
		return 0.0
	var sf: SpriteFrames = unit.unit_sprite.sprite_frames
	if sf == null or not sf.has_animation("attack"):
		## #14 修复：后摇段 _backswing_update 已把动画切到 move/idle 帧集（无 "attack" 动画），
		## 此时 get_frame_count/get_animation_speed("attack") 会报错刷屏且 cycle_len 计算异常。
		## 没有攻击动画帧集 → 周期长度回退到攻击间隔，不再依赖动画时长。
		return 0.0
	var fc: int = sf.get_frame_count("attack")
	var fps: float = sf.get_animation_speed("attack")
	if fc <= 0 or fps <= 0.0:
		return 0.0
	var scale: float = unit.unit_sprite.speed_scale
	if scale <= 0.0:
		scale = 1.0
	return float(fc) / (fps * scale)

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
		_hard_recovery_timer = unit.unit_resource.get_attack_recovery_time()
		unit.play_anim("move")  ## 后摇：奔跑动画（#后摇 2026-08-15 最终拍板：后摇全程奔跑）；play_anim 同名守卫不会每帧重置

## 近战单位切换目标逻辑
## 若检测到比当前目标更近的敌方单位（距离差超过 30 像素），则切换目标
## 这样近战单位在追击远程兵时，如果路上碰到其他兵种会改打那个，不继续追远程兵
## current_dist: 当前目标的 2D 距离
func _retarget_for_melee(current_dist: float) -> void:  ## 定义近战切换目标的方法
	var nearer_enemy: Unit = unit.find_nearest_enemy()  ## 查找检测区域内最近的敌人
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
	unit.set_facing_hysteresis(dir.x, maxf(0.25, speed_px * 0.4))  ## 意图方向 + 滞回（与 state_move 一致，#5）

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
