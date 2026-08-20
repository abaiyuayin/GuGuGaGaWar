extends UnitState
## 技能状态（标准模式：战役 / 全面战争 / 双人）
##
## 三阶段流程，全程锁定移动与普攻（与 state_stun 的锁定思路一致）：
##   CAST（前摇）  蓄力 / 吟唱，播放技能动画；结束时结算效果
##   SETTLE        调用 SkillEffects.apply() 造成伤害/击退/减速等
##   RECOVER（后摇）僵直，结束后回到默认状态（move / guard）
##
## 释放许可由 UnitSkillComponent 判定（CD 就绪 + 触发范围内有敌人），
## 本状态只负责「动作流程」，不做任何 CD 或触发条件判断。
##
## 技能落点（光柱等）在 enter() 时一次性锁定，之后目标移动或死亡都不改变落点，
## 避免吟唱期间目标乱跑导致的落点抖动。

## 阶段枚举
enum Phase { CAST, RECOVER }

## 技能效果函数库（显式 preload，不依赖 class_name 全局类缓存）
const SKILL_EFFECTS := preload("res://scripts/skills/skill_effects.gd")

## 当前技能定义（由 unit.pending_skill_def 传入）
var _def: Dictionary = {}
## 当前阶段
var _phase: int = Phase.CAST
## 当前阶段剩余时长（秒）
var _timer: float = 0.0
## 技能落点（enter 时锁定）
var _target_pos: Vector2 = Vector2.ZERO
## 效果是否已结算（防止重复触发）
var _settled: bool = false

## 进入技能状态：锁定落点、播放前摇动画
func enter() -> void:
	_def = unit.pending_skill_def
	if _def.is_empty():
		unit.change_state(unit.get_idle_state_name())
		return

	unit.velocity = Vector2.ZERO
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

## 离开状态：清理待释放技能定义，恢复动画速度
func exit() -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.pending_skill_def = {}
	if unit.unit_sprite != null:
		unit.unit_sprite.speed_scale = 1.0

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
