extends UnitState
## 技能状态（标准模式：战役 / 全面战争 / 双人）
##
## 四套动作流程，按技能定义的 effect.kind 四选一：
##
## A. 常规三阶段（默认，slam / pillar 等）
##   CAST（前摇）  蓄力 / 吟唱，播放技能动画；结束时结算效果
##   RECOVER（后摇）僵直，结束后回到默认状态（move / guard）
##
## B. 帧定格流程（effect.kind == "frame_hold_backburst"，Hero4 咕咕嘎嘎）
##   ADVANCE      正常播放攻击动画，逐帧监视 sprite.frame
##   HOLD_PRE     动画定格在 hold_frame（= 判定帧往前两帧），原地停 hold_time 秒（第一次停帧 / 蓄力）
##   HOLD_DASH    跳到判定帧 → 保持定格在 dash_time 秒内平滑冲刺 dash_px
##   HOLD_HIT     原地停 hit_hold_time 秒（第二次停帧）；
##                冲刺结束的瞬间由 SkillEffects 先铺红光（fx_spread_time 内一道道蔓延到终点），
##                **红光全部出现之后**才在 damage_window 内排队打出 hit_count 段伤害
##   TAIL         恢复播放，等剩余攻击动画播完；播完时整批特效统一 1 秒渐隐
##   RECOVER      走兵种常规攻击后摇，再回默认状态
##
## C. 光球流程（effect.kind == "orb_charge_launch"，Hero3 菲比）
##   复用兵种自带的 4 段攻击动画，接 attack_animation_hit 信号按判定帧下标推进：
##     cue 0/1/2 → 光球出现 / 变大 / 变大（直径 60 → 90 → 130）
##     cue 3     → 沿面朝方向发射，之后一切交给 SkillOrb（推进 / 周期判定 / 终点爆炸）
##   本流程**不产生任何普攻伤害**（state_attack 的帧命中回调在进入技能状态时已断开）。
##
## D. 巨化流程（effect.kind == "giant_strike"，Hero2 Doro）
##   GROW    1 秒内平滑膨胀到 grow_mult 倍体型（播后摇动画，不出攻击动作）
##   STRIKE  起播攻击动画，在判定帧用替换后的伤害表打出强化一击
##   SHRINK  1 秒内平滑缩回原体型（同样播后摇动画）
##
## 技能期间霸体（unit.skill_super_armor）：免疫击退位移、不被击退打断，也不累计击退晕眩。
##
## 定格用 speed_scale = 0 实现（不用 pause()）：AnimatedSprite2D.play() 会重置到第 0 帧，
## 恢复播放时无法从定格帧续播；speed_scale 归零则帧号静止、恢复即续播，且 is_playing() 语义不变。
##
## 释放许可由 UnitSkillComponent 判定（CD 就绪 / 攻击次数打满等触发条件），
## 本状态只负责「动作流程」，不做任何 CD 或触发条件判断。
##
## 技能落点（光柱等）在 enter() 时一次性锁定，之后目标移动或死亡都不改变落点，
## 避免吟唱期间目标乱跑导致的落点抖动。

## 常规流程阶段枚举
enum Phase { CAST, RECOVER }

## 帧定格流程阶段枚举
enum HoldPhase { ADVANCE, HOLD_PRE, HOLD_DASH, HOLD_HIT, TAIL, RECOVER }

## 光球流程阶段枚举
enum OrbPhase { CHARGE, RECOVER }

## 巨化流程阶段枚举
enum GiantPhase { GROW, STRIKE, SHRINK }

## 帧定格流程的兜底超时余量（秒）：动画播完后加这段余量仍未结束则强制收尾
const TAIL_TIMEOUT_MARGIN: float = 1.0

## 异常离场时冲击特效的收尾渐隐时长（秒）：比正常 1 秒更短，避免死亡后特效还挂着
const FX_FADE_ON_ABORT: float = 0.25

## 光球流程要消费的判定帧段数（Hero3 的 attack_hit_frames 是 [10,16,27,33] → 4 段）
const ORB_CUE_TOTAL: int = 4

## 技能效果函数库（显式 preload，不依赖 class_name 全局类缓存）
const SKILL_EFFECTS := preload("res://scripts/skills/skill_effects.gd")

## 当前技能定义（由 unit.pending_skill_def 传入）
var _def: Dictionary = {}
## 当前阶段（常规流程）
var _phase: int = Phase.CAST
## 当前阶段剩余时长（秒）
var _timer: float = 0.0
## 技能落点（enter 时锁定）
var _target_pos: Vector2 = Vector2.ZERO
## 效果是否已结算（防止重复触发）
var _settled: bool = false

## 是否走帧定格流程
var _hold_active: bool = false
## 当前帧定格阶段
var _hold_phase: int = HoldPhase.ADVANCE
## 帧定格流程的阶段剩余时长（秒）
var _hold_timer: float = 0.0
## 帧定格流程的技能效果参数（enter 时缓存）
var _hold_effect: Dictionary = {}
## TAIL 阶段的兜底剩余时长（秒）
var _tail_timeout: float = 0.0
## 进入帧定格前精灵的播放倍率（恢复播放时还原）
var _saved_speed_scale: float = 1.0
## 冲刺阶段的起点（进入判定帧时刻的位置）
var _dash_from: Vector2 = Vector2.ZERO
## 冲刺阶段的终点（已按战场 X 边界钳制）
var _dash_to: Vector2 = Vector2.ZERO
## 冲刺阶段的总时长（秒，0 表示直接到位）
var _dash_duration: float = 0.0
## 本批冲击特效（TAIL 结束时统一渐隐）
var _hold_fx_list: Array = []

## ── 光球流程（Hero3 菲比）状态 ────────────────────────────────
## 是否走光球流程
var _orb_active: bool = false
## 光球流程阶段
var _orb_phase: int = OrbPhase.CHARGE
## 光球流程参数（enter 时缓存）
var _orb_effect: Dictionary = {}
## 光球实体（判定帧 0 时生成；发射后由它自己接管生命周期）
var _orb_node: SkillOrb = null
## 光球流程的动画兜底剩余时长（秒）
var _orb_timeout: float = 0.0
## 光球流程 RECOVER 阶段剩余时长（秒）
var _orb_recover_timer: float = 0.0
## 已消费的判定帧段数（0~4）；技能要等 4 段全部走完才能收尾
var _orb_cue_count: int = 0
## 光球流程已推进时长（秒）——用于「至少播满一段攻击动画」的时间判定
var _orb_elapsed: float = 0.0

## ── 巨化流程（Hero2 Doro）状态 ────────────────────────────────
## 是否走巨化流程
var _giant_active: bool = false
## 巨化流程阶段
var _giant_phase: int = GiantPhase.GROW
## 巨化流程参数（enter 时缓存）
var _giant_effect: Dictionary = {}
## 当前阶段的剩余时长（秒）
var _giant_timer: float = 0.0
## 膨胀总时长 / 缩回总时长 / 目标体型倍率（缓存，避免每帧读字典）
var _giant_grow_time: float = 1.0
var _giant_shrink_time: float = 1.0
var _giant_mult: float = 3.0
## 强化一击是否已结算（判定帧只吃一次）
var _giant_hit_done: bool = false
## STRIKE 阶段的兜底剩余时长（秒）
var _giant_strike_timeout: float = 0.0
## STRIKE 阶段已推进时长（秒）——用于「至少播满一段攻击动画」的时间判定
var _giant_strike_elapsed: float = 0.0
## 攻击动画本身的时长（秒），进入 C / D 流程时缓存，作为阶段收尾的时间基准
var _anim_hold_duration: float = 0.0

## 进入技能状态：锁定落点、播放前摇动画
func enter() -> void:
	_def = unit.pending_skill_def
	if _def.is_empty():
		unit.change_state(unit.get_idle_state_name())
		return

	unit.velocity = Vector2.ZERO
	## 技能期间霸体：免疫击退位移与击退打断（由 unit_base.apply_knockback 判定）
	unit.skill_super_armor = true
	## 头顶飘出技能名（渐显 0.5s → 停留 1s → 渐隐 0.5s，整段 2 秒）。
	## 放在这里 = 四套动作流程 A/B/C/D 全部覆盖；inline 技能（Hero5 九箭）不走本状态，
	## 由 UnitSkillComponent 的 inline 分支自己弹。
	unit.show_skill_name(String(_def.get("name", "")))
	_hold_fx_list = []

	## 帧定格型技能走独立流程
	var effect: Dictionary = _def.get("effect", {})
	var kind: String = String(effect.get("kind", ""))
	if kind == "frame_hold_backburst":
		_enter_frame_hold(effect)
		return
	if kind == "orb_charge_launch":
		_enter_orb_charge(effect)
		return
	if kind == "giant_strike":
		_enter_giant_strike(effect)
		return

	_phase = Phase.CAST
	_timer = float(_def.get("cast_time", 0.0))
	_settled = false
	_target_pos = _resolve_target_pos()

	## 面向落点（技能朝向要与落点一致，避免背对着放技能）
	unit.set_facing_direction(1.0 if _target_pos.x >= unit.global_position.x else -1.0)
	_play_cast_anim()

## 每帧推进：前摇 → 结算 → 后摇 → 回默认状态
func update(delta: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit.is_dead:
		return

	unit.velocity = Vector2.ZERO
	unit.move_and_slide()  ## 保持被推挤时的物理表现（与 state_stun 一致）

	if _hold_active:
		_update_frame_hold(delta)
		return
	if _orb_active:
		_update_orb_charge(delta)
		return
	if _giant_active:
		_update_giant_strike(delta)
		return

	_timer -= delta
	if _timer > 0.0:
		return

	match _phase:
		Phase.CAST:
			_settle()
			_phase = Phase.RECOVER
			_timer = float(_def.get("recover_time", 0.0))
		Phase.RECOVER:
			unit.change_state(unit.get_idle_state_name())

## 离开状态：清理待释放技能定义，恢复动画速度，解除霸体并收尾未渐隐的特效
func exit() -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.pending_skill_def = {}
	unit.skill_super_armor = false
	if unit.unit_sprite != null:
		unit.unit_sprite.speed_scale = 1.0
	_hold_active = false
	## 技能自己接管过攻击动画判定帧时，把回调摘掉（否则离开技能后仍在响应）
	if unit.attack_animation_hit.is_connected(_on_skill_hit_frame):
		unit.attack_animation_hit.disconnect(_on_skill_hit_frame)
	## 光球：仍在充能（没发射）的才回收；已发射的光球要留活口飞完并爆炸
	if _orb_node != null and is_instance_valid(_orb_node) and _orb_node.is_charging():
		_orb_node.queue_free()
	_orb_node = null
	_orb_active = false
	## 巨化：无论从哪一阶段离场（含死亡）都恢复原体型，避免对象池复用带着 3 倍体型出场
	_giant_active = false
	unit.set_skill_size_mult(1.0)
	unit.set_skill_range_h_mult(1.0)
	## 异常离场（死亡 / 被外部切换状态）：立即收尾还在场上的冲击特效，
	## 否则要等 ImpactEffect 的 8 秒兜底才消失
	if not _hold_fx_list.is_empty():
		SKILL_EFFECTS.fade_out_fx(_hold_fx_list, FX_FADE_ON_ABORT)
		_hold_fx_list = []

## 结算技能效果（只执行一次）
func _settle() -> void:
	if _settled:
		return
	_settled = true
	SKILL_EFFECTS.apply(unit, _def, _target_pos)

## 解析技能落点：
##   自身范围技能（slam 等）→ 自身位置
##   指定位置技能（pillar 等）→ 最近敌人位置，限制在 cast_range 内
func _resolve_target_pos() -> Vector2:
	var effect: Dictionary = _def.get("effect", {})
	var kind: String = String(effect.get("kind", ""))
	if kind != "pillar":
		return unit.global_position

	var cast_range: float = float(effect.get("cast_range", 0.0))
	## 用无副作用的索敌（不消耗单位自身的 _pathfind_accum 节流预算）
	var enemy: Node2D = SKILL_EFFECTS.find_nearest_enemy(unit, cast_range if cast_range > 0.0 else INF)
	if enemy == null or not is_instance_valid(enemy):
		return unit.global_position

	if cast_range <= 0.0:
		return enemy.global_position
	## 目标超出施法距离时，落点取「自身→目标」方向上距离 cast_range 的位置
	var offset: Vector2 = enemy.global_position - unit.global_position
	if offset.length() <= cast_range:
		return enemy.global_position
	return unit.global_position + offset.normalized() * cast_range

## 播放前摇动画
## anim == "skill" 时使用兵种目录下的 skill_frames.tres（无则回退 attack）；
## anim == "attack" 时复用现有攻击动画并按 anim_speed 降速播放，营造蓄力感。
func _play_cast_anim() -> void:
	var anim_name: String = String(_def.get("anim", "attack"))
	var speed: float = float(_def.get("anim_speed", 1.0))

	if anim_name == "skill" and unit.anim_skill_frames != null:
		unit.play_skill_anim(speed)
		return

	## 回退：复用攻击动画降速播放
	unit.play_anim("attack", true)
	if unit.unit_sprite != null and speed > 0.0:
		unit.unit_sprite.speed_scale = speed

## ── 帧定格流程（effect.kind == "frame_hold_backburst"）────────────────────
## 进入时起播攻击动画，之后由 _update_frame_hold 按阶段推进。
func _enter_frame_hold(effect: Dictionary) -> void:
	_hold_active = true
	_hold_effect = effect
	_hold_phase = HoldPhase.ADVANCE
	_hold_timer = 0.0
	_tail_timeout = 0.0
	## 复用现有攻击动画：current_anim_state 置为 "attack"，单位自身的帧命中检测
	## 会照常运行，但 state_attack 的信号回调未连接，不会重复结算普攻伤害。
	unit.play_anim("attack", true)

## 帧定格流程逐帧推进
func _update_frame_hold(delta: float) -> void:
	var spr: AnimatedSprite2D = unit.unit_sprite
	match _hold_phase:
		HoldPhase.ADVANCE:
			if spr == null:
				_finish_frame_hold()
				return
			var hold_frame: int = int(_hold_effect.get("hold_frame", 0))
			## 用 >= 而非 ==：掉帧时可能从 8 直接跳到 12，精确相等会整段错过定格
			if spr.frame >= hold_frame:
				spr.frame = hold_frame
				_freeze_sprite(spr)
				_hold_phase = HoldPhase.HOLD_PRE
				_hold_timer = float(_hold_effect.get("hold_time", 1.0))
		HoldPhase.HOLD_PRE:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_begin_dash()
		HoldPhase.HOLD_DASH:
			_hold_timer -= delta
			_advance_dash(delta)
			if _hold_timer <= 0.0:
				_finish_dash()
		HoldPhase.HOLD_HIT:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_resume_after_hold()
		HoldPhase.TAIL:
			_tail_timeout -= delta
			var anim_done: bool = spr == null or not spr.is_playing()
			if anim_done or _tail_timeout <= 0.0:
				_finish_frame_hold()
		HoldPhase.RECOVER:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				unit.change_state(unit.get_idle_state_name())

## 定格精灵：记录当前播放倍率并归零（帧号静止，恢复时原倍率续播）
func _freeze_sprite(spr: AnimatedSprite2D) -> void:
	_saved_speed_scale = spr.speed_scale if spr.speed_scale > 0.0 else 1.0
	spr.speed_scale = 0.0

## 第一次停帧结束 → 跳到判定帧，开始冲刺段。
## 冲刺期间保持定格（speed_scale = 0），不播任何新动画。
func _begin_dash() -> void:
	var spr: AnimatedSprite2D = unit.unit_sprite
	if spr != null:
		spr.frame = int(_hold_effect.get("hit_frame", spr.frame))

	var dash: float = float(_hold_effect.get("dash_px", 0.0))
	var dir: float = 1.0 if unit.facing_dir >= 0 else -1.0
	_dash_from = unit.global_position
	## 位移终点按战场 X 边界钳制，避免冲出场地
	_dash_to = Vector2(clampf(_dash_from.x + dir * dash, Constants.FIELD_X_MIN, Constants.FIELD_X_MAX),
			_dash_from.y)
	_dash_duration = float(_hold_effect.get("dash_time", 0.0))
	_hold_phase = HoldPhase.HOLD_DASH
	if dash <= 0.0 or _dash_duration <= 0.0:
		unit.global_position = _dash_to
		_finish_dash()
		return
	_hold_timer = _dash_duration

## 冲刺段的插值位移（EASE_OUT：起步快、收尾慢），用 lerp 而非 Tween ——
## 与 state_skill 每帧的 move_and_slide 并存时 Tween 会与物理位置互相覆盖。
func _advance_dash(_delta: float) -> void:
	var t: float = 1.0
	if _dash_duration > 0.0:
		t = clampf(1.0 - _hold_timer / _dash_duration, 0.0, 1.0)
	unit.global_position = _dash_from.lerp(_dash_to, ease(t, 0.35))

## 冲刺结束 → 进入第二次停帧：此刻才结算判定与特效。
## 判定走廊（身后 0 ~ back_length）此时正好覆盖「位移起点 → 位移终点」整条路径：
## 位移起点落在身后 back_length 处，施法者当前位置即终点。
## ⚠️ 传给 SkillEffects 的必须是 `_hold_effect`（= def["effect"] 子字典），不能传整个 _def：
##    apply_hold_backburst 的入参语义就是 effect，传 _def 会让 damage / fx_count / fx_frames
##    全部落回默认值 → 伤害飘字全 0 且一道特效都不生成。
func _finish_dash() -> void:
	unit.global_position = _dash_to
	_hold_fx_list = SKILL_EFFECTS.apply_hold_backburst(unit, _hold_effect)
	_hold_phase = HoldPhase.HOLD_HIT
	_hold_timer = float(_hold_effect.get("hit_hold_time", 1.0))

## 停留结束：恢复动画播放，进入 TAIL 等剩余帧播完
func _resume_after_hold() -> void:
	var spr: AnimatedSprite2D = unit.unit_sprite
	if spr != null:
		spr.speed_scale = _saved_speed_scale
	_hold_phase = HoldPhase.TAIL
	## 兜底超时：整段攻击动画时长的 2 倍（含定格损耗）与 2 秒取较大值
	_tail_timeout = maxf(unit.get_attack_animation_duration() * 2.0, 2.0)

## 帧定格流程收尾：整批特效同时渐隐 → 进入兵种常规攻击后摇，随后回默认状态
## 「攻击动画结束」= 本函数被调用的时刻（TAIL 段播完剩余帧），
## 后摇不算攻击动画，因此渐隐与后摇并行走。
func _finish_frame_hold() -> void:
	var spr: AnimatedSprite2D = unit.unit_sprite
	if spr != null:
		spr.speed_scale = _saved_speed_scale
	if not _hold_fx_list.is_empty():
		SKILL_EFFECTS.fade_out_fx(_hold_fx_list, float(_hold_effect.get("fx_fade_time", 1.0)))
		_hold_fx_list = []
	_hold_phase = HoldPhase.RECOVER
	_hold_timer = unit.get_attack_recovery_duration()

## ============================================================
## C. 光球流程（effect.kind == "orb_charge_launch"，Hero3 菲比）
## ============================================================

## 进入光球流程：起播兵种自带的 4 段攻击动画，判定帧由 _on_skill_hit_frame 接管。
## ⚠️ 起播前必须 reset_attack_anim_progress()：reset_attack_frame_flags() 不重置连击索引，
## 上一周期残留的索引会让 `_attack_hit_index <= i` 永远不成立 → attack_animation_hit 一次都不发，
## 光球四段动作全部失灵。
func _enter_orb_charge(effect: Dictionary) -> void:
	_orb_active = true
	_orb_effect = effect
	_orb_phase = OrbPhase.CHARGE
	_orb_node = null
	_orb_recover_timer = 0.0
	_orb_cue_count = 0
	_orb_elapsed = 0.0
	## 兜底：先用一个安全默认值，真正的时长在起播攻击动画之后再取（见下方）
	_anim_hold_duration = 1.0
	_orb_timeout = _anim_hold_duration * 2.0 + 1.0
	unit.reset_attack_anim_progress()
	if not unit.attack_animation_hit.is_connected(_on_skill_hit_frame):
		unit.attack_animation_hit.connect(_on_skill_hit_frame)
	unit.play_anim("attack", true)
	if unit.unit_sprite != null:
		unit.unit_sprite.speed_scale = 1.0
	## ⚠️ 时间基准必须**在起播攻击动画之后**取：get_attack_animation_duration() 读的是
	## unit_sprite.sprite_frames，起播前它还是上一个动画（通常没有 attack 通道）→ 恒返回 0。
	## 基准为 0 时 `_orb_elapsed >= 0` 第一帧就成立，三段判定帧被一脚踢完 ——
	## 表现就是「第二次放技能时白球一出现就已经变大并直接发射」。
	_anim_hold_duration = maxf(unit.get_attack_animation_duration(), 0.1)
	_orb_timeout = _anim_hold_duration * 2.0 + 1.0

## 光球判定帧：0/1/2 = 光球出现并变大两次，3 = 发射。
## 光球在第一次判定帧才生成 —— 前三段「出现 → 变大 → 变大」因此天然是同一颗球在长大。
func _on_orb_cue(hit_index: int) -> void:
	if _orb_node == null or not is_instance_valid(_orb_node):
		_orb_node = SKILL_EFFECTS.spawn_charge_orb(unit, _orb_effect)
	_orb_cue_count = maxi(_orb_cue_count, hit_index + 1)
	if _orb_node == null or not is_instance_valid(_orb_node):
		return
	_orb_node.set_charge_stage(hit_index)
	if hit_index >= 3:
		_orb_node.launch()

## 光球流程逐帧推进：等 4 段判定帧 + 一段攻击动画时长都走完，之后走一小段后摇再回默认状态。
## 光球的推进 / 周期判定 / 终点爆炸全部由 SkillOrb 自己负责，本状态不管。
func _update_orb_charge(delta: float) -> void:
	match _orb_phase:
		OrbPhase.CHARGE:
			_orb_elapsed += delta
			_orb_timeout -= delta
			if _orb_elapsed >= _anim_hold_duration:
				## 动画时长已走完仍没走到发射帧（掉帧 / 动画被外部打断）：
				## 把剩下的判定帧一次性补齐，光球照样长大并发射，不让技能白充一场
				for i in range(_orb_cue_count, ORB_CUE_TOTAL):
					_on_orb_cue(i)
			if (_orb_elapsed >= _anim_hold_duration and _orb_cue_count >= ORB_CUE_TOTAL) \
					or _orb_timeout <= 0.0:
				if _orb_node != null and is_instance_valid(_orb_node) and _orb_node.is_charging():
					_orb_node.launch()
				_orb_phase = OrbPhase.RECOVER
				_orb_recover_timer = unit.get_attack_recovery_duration()
		OrbPhase.RECOVER:
			_orb_recover_timer -= delta
			if _orb_recover_timer <= 0.0:
				_orb_active = false
				unit.change_state(unit.get_idle_state_name())

## ============================================================
## D. 巨化流程（effect.kind == "giant_strike"，Hero2 Doro）
## ============================================================

## 进入巨化流程：先播后摇动画并开始膨胀。
## 变大过程**不出攻击动作**（用户拍板「变大变小动画中算后摇动画不能播放攻击动画」）。
func _enter_giant_strike(effect: Dictionary) -> void:
	_giant_active = true
	_giant_effect = effect
	_giant_phase = GiantPhase.GROW
	_giant_grow_time = maxf(float(effect.get("grow_time", 1.0)), 0.0)
	_giant_shrink_time = maxf(float(effect.get("shrink_time", 1.0)), 0.0)
	_giant_mult = maxf(float(effect.get("grow_mult", 3.0)), 1.0)
	_giant_timer = _giant_grow_time
	_giant_hit_done = false
	_giant_strike_timeout = 0.0
	_giant_strike_elapsed = 0.0
	## 时间基准的取法同 C 流程：必须在**起播攻击动画之后**取（见 _begin_giant_strike）。
	## 这里只给安全默认值，避免 GROW 期间被误用。
	_anim_hold_duration = 1.0
	unit.reset_attack_anim_progress()
	if not unit.attack_animation_hit.is_connected(_on_skill_hit_frame):
		unit.attack_animation_hit.connect(_on_skill_hit_frame)
	unit.play_backswing_anim()
	unit.set_skill_size_mult(1.0)
	## 2026-09-22：横向攻击范围额外倍率（用户拍板「变大后横向再宽一点」）。
	## 只在巨化窗口内生效，与体型倍率同步在 exit()/SHRINK 结束时归位。
	unit.set_skill_range_h_mult(maxf(float(effect.get("grow_range_h_mult", 1.0)), 1.0))

## 巨化流程逐帧推进：GROW（膨胀）→ STRIKE（强化一击）→ SHRINK（缩回）
func _update_giant_strike(delta: float) -> void:
	match _giant_phase:
		GiantPhase.GROW:
			_giant_timer -= delta
			var t: float = _giant_progress(_giant_timer, _giant_grow_time)
			unit.set_skill_size_mult(lerpf(1.0, _giant_mult, ease(t, 0.4)))
			if _giant_timer <= 0.0:
				unit.set_skill_size_mult(_giant_mult)
				_begin_giant_strike()
		GiantPhase.STRIKE:
			_giant_strike_elapsed += delta
			_giant_strike_timeout -= delta
			## 动画时长走完仍没结算强化一击（掉帧 / 动画被外部打断）：补结算，
			## 保证「挥出去的那一下」一定打得出来
			if _giant_strike_elapsed >= _anim_hold_duration and not _giant_hit_done:
				_on_giant_hit()
			if (_giant_strike_elapsed >= _anim_hold_duration and _giant_hit_done) \
					or _giant_strike_timeout <= 0.0:
				_begin_giant_shrink()
		GiantPhase.SHRINK:
			_giant_timer -= delta
			var t: float = _giant_progress(_giant_timer, _giant_shrink_time)
			unit.set_skill_size_mult(lerpf(_giant_mult, 1.0, ease(t, 0.4)))
			if _giant_timer <= 0.0:
				unit.set_skill_size_mult(1.0)
				unit.set_skill_range_h_mult(1.0)
				_giant_active = false
				unit.change_state(unit.get_idle_state_name())

## 阶段进度 0 → 1（总时长为 0 时直接给 1：避免除零，同时表示「立刻到位」）
func _giant_progress(timer: float, total: float) -> float:
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - timer / total, 0.0, 1.0)

## 膨胀完成 → 起播攻击动画，等判定帧打出强化一击
func _begin_giant_strike() -> void:
	_giant_phase = GiantPhase.STRIKE
	_giant_strike_elapsed = 0.0
	if unit.unit_sprite != null:
		unit.unit_sprite.speed_scale = 1.0
	unit.play_anim("attack", true)
	## ⚠️ 时间基准在起播之后再取：get_attack_animation_duration() 读的是 unit_sprite.sprite_frames，
	## 起播前它还是上一个动画（没有 attack 通道）→ 恒返回 0 → STRIKE 第一帧就判定「播完」，
	## 强化一击还没挥出去就缩回原大小（用户实测「变大后没有正常播放一次攻击动画」）。
	_anim_hold_duration = maxf(unit.get_attack_animation_duration(), 0.1)
	_giant_strike_timeout = _anim_hold_duration * 2.0 + 1.0

## 收缩：同样播后摇动画，不播攻击动作
func _begin_giant_shrink() -> void:
	_giant_phase = GiantPhase.SHRINK
	_giant_timer = _giant_shrink_time
	unit.play_backswing_anim()

## 强化一击的判定帧：伤害列表整段替换成技能配置（仍走完整近战命中管线：
## 射程复核 / 攻击面 footprint / aoe_radius / 词条），判定帧只吃一次。
func _on_giant_hit() -> void:
	if _giant_hit_done:
		return
	_giant_hit_done = true
	unit.perform_attack(0, SKILL_EFFECTS.build_damage_entries(_giant_effect.get("hit_damage", {})))

## 技能接管攻击动画时的判定帧回调。
## state_attack 会在 state_skill.enter() 之前 exit() 并断掉自己的回调，
## 所以这里收到的一定是「技能自己那一次攻击动画」的判定帧。
func _on_skill_hit_frame(hit_index: int) -> void:
	if _orb_active:
		_on_orb_cue(hit_index)
	elif _giant_active:
		_on_giant_hit()
