extends UnitState  ## 继承单位状态基类
## 攻击基地状态
## 当单位到达敌方基地攻击范围时进入此状态
## 遵循攻击周期（前摇 + 命中 + 后摇），只在命中帧对基地造成伤害。
## 普通单位以攻击动画完成为边界，动画结束后直接进入固定后摇。

## 本攻击周期是否已执行攻击（命中）
var _attacks_done: int = 0  ## hits completed in current cycle
## 是否正在攻击周期中
var _attack_started: bool = false  ## 是否在攻击周期中
## hard recovery after every crystal attack
var _recovery_timer: float = 0.0  ## 后摇倒计时

## 进入攻击基地状态时调用
func enter() -> void:  ## 重写进入状态方法
	## 重置攻击计时器和标志
	unit.attack_anim_elapsed = 0.0  ## 重置攻击动画计时器
	_attacks_done = 0  ## 重置命中次数
	_attack_started = false  ## 重置攻击周期标志
	_recovery_timer = 0.0  ## 重置后摇
	if _uses_frame_hit(unit.unit_resource):
		if not unit.attack_animation_hit.is_connected(_on_frame_hit):
			unit.attack_animation_hit.connect(_on_frame_hit)
	_play_attack_display_anim(true)  ## 强制播放攻击表现动画

## 退出攻击基地状态时调用
func exit() -> void:  ## 重写退出状态方法
	if unit != null and unit.attack_animation_hit.is_connected(_on_frame_hit):
		unit.attack_animation_hit.disconnect(_on_frame_hit)
	## 需求（2026-09-21 玩家拍板，从直播版同步）：离开攻击水晶状态时取消未播完的三连红光
	##（与 state_attack 同款）
	if unit != null:
		unit.cancel_tri_volley()

## 判断是否由攻击动画帧驱动命中。
func _uses_frame_hit(res: UnitResource) -> bool:
	return res != null and (res.attack_hit_frame_start >= 0 or res.attack_hit_frame_start_alt >= 0 or not res.attack_hit_frames.is_empty())

## 攻击动画帧命中回调：攻击水晶也必须按 attack_hit_frames 发射完整连击。
func _on_frame_hit(hit_index: int = 0) -> void:
	if unit == null or unit.is_dead or hit_index < _attacks_done:
		return
	unit.attack_base(hit_index)
	_attacks_done = hit_index + 1

## 攻击基地状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(delta: float) -> void:  ## 重写每帧更新方法
	if unit == null or not is_instance_valid(unit) or unit.is_dead:
		return
	var res: UnitResource = unit.unit_resource
	if res == null:
		return
	## #2026-09-22 防御闸门：无攻击能力单位（S5 咕嘎工钢，attack_anim_mode == "none"）
	## 正常路径已由 state_move 拦下不会进到这里；此处兜底，确保它永远不会对水晶造成伤害。
	if not unit.has_attack_ability():
		unit.change_state("move")
		return

	## 攻击动画结束后立即进入后摇；后摇结束后才允许下一轮攻击。
	if _recovery_timer > 0.0:
		_recovery_timer = maxf(0.0, _recovery_timer - delta)
		unit.velocity = Vector2.ZERO
		unit.move_and_slide()
		unit.play_backswing_stand()
		return

	if not enemy_has_base():
		unit.change_state("move")
		return
	var base_pos: Vector2 = get_enemy_base_position()
	var dist_to_base: float = unit.global_position.distance_to(base_pos)
	var effective_base_range: float = unit.get_attack_query_radius_px()
	if dist_to_base > effective_base_range + 30.0:
		unit.change_state("move")
		return

	## 水晶攻击期间不插入额外的攻击间隔。
	if _attack_started:
		_attack_cycle(delta, res)
		return

	## 射程内有兵时优先切换到普通攻击状态。
	var enemy_in_range: Unit = unit.find_nearest_enemy_in_attack_range()
	if enemy_in_range != null:
		unit.target = enemy_in_range
		unit.change_state("attack")
		return

	_attack_started = true
	_attacks_done = 0
	unit.attack_anim_elapsed = 0.0
	unit.reset_attack_frame_flags()
	if unit.anim_attack_frames_alt != null:
		unit.attack_anim_toggle = not unit.attack_anim_toggle
	_play_attack_display_anim(true)
	_attack_cycle(delta, res)

## 攻击水晶：攻击动画播完立即进入后摇，不插入额外等待段。
func _attack_cycle(delta: float, res: UnitResource) -> void:
	unit.attack_anim_elapsed += delta
	var count: int = max(1, res.attack_count)
	var use_frame_hit: bool = _uses_frame_hit(res)
	var has_attack_animation: bool = unit.anim_attack_frames != null or unit.anim_attack_frames_alt != null
	var uses_visual_attack_animation: bool = res.attack_anim_mode == "" and has_attack_animation
	## 普通单位由攻击动画决定时长；无攻击动画的特殊单位才使用旧周期字段兜底。
	var attack_anim_duration: float = unit.get_attack_animation_duration() if uses_visual_attack_animation else unit.get_legacy_attack_cycle_duration()
	var base_hit_ratio: float = 0.4 if res.is_ranged else 0.95

	if not use_frame_hit:
		var hit_duration: float = attack_anim_duration if attack_anim_duration > 0.0 else unit.get_legacy_attack_cycle_duration()
		for i in range(count):
			var hit_point: float = hit_duration * (float(i + 1) / count) * base_hit_ratio
			if unit.attack_anim_elapsed >= hit_point and _attacks_done <= i:
				unit.attack_base(i)
				_attacks_done += 1
				break

	var attack_anim_done: bool = unit.attack_anim_elapsed >= attack_anim_duration
	if uses_visual_attack_animation:
		attack_anim_done = unit.unit_sprite == null or not unit.unit_sprite.is_playing()
	if not attack_anim_done:
		unit.velocity = Vector2.ZERO
		unit.move_and_slide()
		_play_attack_display_anim(false)
		return

	## 需求（2026-09-21 玩家拍板，从直播版同步）：萌黄 S9 打水晶的三连红光未播完 ——
	## 挂起周期收尾（与 state_attack 同款），三道红光全部播完后才进入后摇。
	if unit.is_tri_volley_running():
		unit.velocity = Vector2.ZERO
		unit.move_and_slide()
		_play_attack_display_anim(false)
		return

	## 动画结束时补齐漏掉的连击段，确保 Hero3 打水晶固定发射四枚飞行物。
	if _attacks_done < count:
		for i in range(_attacks_done, count):
			unit.attack_base(i)
		_attacks_done = count

	_attack_started = false
	_attacks_done = 0
	unit.attack_anim_elapsed = 0.0
	unit.reset_attack_frame_flags()
	unit.play_backswing_anim()  ## 后摇动画（#后摇 2026-09-11：待机 > 行走 > 奔跑）
	_recovery_timer = 0.0 if unit.skill_no_recovery_timer > 0.0 else unit.get_attack_recovery_duration()

## Special no-attack-animation units keep their dedicated visual behavior.
func _play_attack_display_anim(force: bool = false) -> void:
	match unit.unit_resource.attack_anim_mode:
		"charge": unit.play_anim("move", force)
		"idle": unit.play_anim("idle", force)
		_: unit.play_anim("attack", force)
