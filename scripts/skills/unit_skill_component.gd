extends Node
## 兵种技能组件（标准模式：战役 / 全面战争 / 双人）
##
## 挂在 Unit 节点下，只负责「何时该放技能」：
##   1. _ready 查表，该兵种无技能则立即自我移除 —— 30+ 个普通兵种零额外开销
##   2. 按 trigger.kind 走对应触发方式（#2026-09-20 抽象，肉鸽 / 标准分别使用不同触发方式）：
##        cooldown      冷却时间触发：每帧递减 CD；CD 就绪且触发半径内有敌人时，请求宿主切入技能状态
##        attack_count  攻击次数触发：累计普通攻击周期次数，打满 count 次后由 state_attack 在
##                      「即将开始新的攻击周期」时调用 try_trigger_on_attack() 抢占本次攻击
##
## 技能绑定兵种而非玩家/AI：红蓝双方部署同一英雄，行为完全一致（用户拍板）。
## 因此本组件不读 team 做任何差异化处理，也不检查是否为玩家控制。
##
## 与肉鸽的隔离：本组件仅在非肉鸽模式激活（肉鸽有自己的 HeroSkillManager 波次技能），
## 避免同一英雄在肉鸽里同时拥有两套技能系统。

## 技能数据表（显式 preload，不依赖 class_name 全局类缓存）
const SKILL_DB := preload("res://scripts/skills/unit_skill_database.gd")
## 技能效果库（这里只用其无副作用的索敌工具 find_nearest_enemy）
const SKILL_EFFECTS := preload("res://scripts/skills/skill_effects.gd")

## 触发方式：冷却时间（CD 就绪 + 触发半径内有敌人）
const TRIGGER_COOLDOWN := "cooldown"
## 触发方式：攻击次数（累计 N 次普通攻击后，第 N+1 次攻击改为释放技能）
const TRIGGER_ATTACK_COUNT := "attack_count"

## #2026-09-20：不改变动作流程、只叠加到当前这次普攻上的效果种类。
## 这类技能不需要独立动作（不用切 state_skill、不打断攻击动画），触发后立即施加效果，
## 本次普攻周期照常进行 —— 糯糯的九箭齐射就属于此类：「持续两次攻击」本质就是两次普通攻击。
const INLINE_EFFECT_KINDS: Array[String] = ["multi_lock_volley"]

## 宿主单位
var _unit: Node2D = null
## 本兵种的技能定义（空 = 无技能）
var _def: Dictionary = {}
## 剩余冷却（秒）—— 仅 cooldown 触发使用
var _cd_left: float = 0.0
## 触发半径（像素，从定义缓存）—— 仅 cooldown 触发使用
var _trigger_range: float = 0.0
## 当前触发方式（trigger.kind）
var _trigger_kind: String = TRIGGER_COOLDOWN
## 攻击次数触发的目标次数（打满该次数后的下一次攻击释放技能）
var _trigger_count: int = 0
## 自上次释放技能以来累计完成的普通攻击周期数 —— 仅 attack_count 触发使用
var _attack_count: int = 0

func _ready() -> void:
	_unit = get_parent() as Node2D
	if _unit == null:
		queue_free()
		return

	## 肉鸽模式不启用本系统（肉鸽走 HeroSkillManager 的波次 CD 技能）
	if RoguelikeManager.is_active:
		queue_free()
		return

	var res: UnitResource = _unit.unit_resource
	if res == null:
		queue_free()
		return

	_def = SKILL_DB.get_skill_for_unit(res.unit_id)
	if _def.is_empty():
		queue_free()  ## 该兵种无技能，组件自我移除
		return

	## 按 trigger.kind 装配对应的触发参数
	var trig: Dictionary = _def.get("trigger", {})
	_trigger_kind = String(trig.get("kind", TRIGGER_COOLDOWN))
	if _trigger_kind == TRIGGER_ATTACK_COUNT:
		_trigger_count = maxi(int(trig.get("count", 1)), 1)
		_attack_count = 0
		## 攻击次数触发的计数源：宿主每次收尾一个普通攻击周期都会通知本组件
		if not _unit.normal_attack_cycle_finished.is_connected(_on_normal_attack_cycle_finished):
			_unit.normal_attack_cycle_finished.connect(_on_normal_attack_cycle_finished)
	else:
		_trigger_kind = TRIGGER_COOLDOWN
		_trigger_range = float(_def.get("trigger_range", 0.0))
		## 进场先进入一次完整冷却，避免一出场就立刻放技能
		_cd_left = float(_def.get("cd", 0.0))

func _physics_process(delta: float) -> void:
	## 攻击次数触发不走逐帧轮询：触发时机由 state_attack 主动询问（见 try_trigger_on_attack）
	if _trigger_kind != TRIGGER_COOLDOWN:
		return
	if _unit == null or not is_instance_valid(_unit) or _unit.is_dead:
		return
	## AI 被禁用（调试暂停）时不推进 CD、不释放
	if _unit.ai_disabled:
		return

	if _cd_left > 0.0:
		_cd_left = maxf(_cd_left - delta, 0.0)
		return

	if not _can_cast():
		return

	## 请求释放：把定义挂到宿主上，由 state_skill 读取并执行
	_unit.pending_skill_def = _def
	_unit.change_state("skill")
	_cd_left = float(_def.get("cd", 0.0))

## 攻击次数触发：每收尾一个普通攻击周期累计一次
func _on_normal_attack_cycle_finished() -> void:
	if _trigger_kind != TRIGGER_ATTACK_COUNT:
		return
	_attack_count += 1

## 攻击次数触发：由 state_attack 在「即将开始新的普通攻击周期」时调用。
## 返回 true  = 本次攻击周期被技能占用（调用方必须立即 return，不要再进普通攻击动画）；
## 返回 false = 触发方式不符 / 计数未满 / 当前不可释放，照常走普通攻击。
func try_trigger_on_attack() -> bool:
	if _trigger_kind != TRIGGER_ATTACK_COUNT:
		return false
	if _unit == null or not is_instance_valid(_unit) or _unit.is_dead or _unit.ai_disabled:
		return false
	if _unit.stun_timer > 0.0:
		return false
	if _unit.is_base_unit:
		return false
	if _attack_count < _trigger_count:
		return false
	## 上一次技能留下的持续状态还没打完（如糯糯九箭的剩余次数），不重复触发
	if _unit.skill_volley_charges > 0:
		return false
	## 计数清零：重新从 0 累计，下次同样打满 _trigger_count 次普攻后再触发
	_attack_count = 0
	## inline 类效果（九箭齐射）：只施加效果、**不切状态**，返回 false 让调用方照常走普通攻击周期。
	## 本次攻击就是技能生效的第一次；返回 true 会让 state_attack 直接 return，
	## 连攻击动画都不会播，九箭无从发射。
	if _is_inline_effect():
		SKILL_EFFECTS.apply(_unit, _def, _unit.global_position)
		## 头顶飘出技能名：inline 技能不切 state_skill，拿不到那边的统一弹名
		_unit.show_skill_name(String(_def.get("name", "")))
		return false
	_unit.pending_skill_def = _def
	_unit.change_state("skill")
	return true

## 本技能是否为「不改动作流程、只叠加普攻行为」的类型
func _is_inline_effect() -> bool:
	var kind: String = String(_def.get("effect", {}).get("kind", ""))
	return INLINE_EFFECT_KINDS.has(kind)

## 能否释放：非技能状态中 且 非晕眩 且 触发半径内有敌人
func _can_cast() -> bool:
	## 已在技能状态中（正在放）则不重复触发
	if _unit.current_state != null and _unit.current_state.get_script() == _unit.state_map.get("skill", null):
		return false
	## 晕眩期间不能释放
	if _unit.stun_timer > 0.0:
		return false
	## 基地单位不释放技能
	if _unit.is_base_unit:
		return false
	return _has_enemy_in_range()

## 触发半径内是否有敌方单位
## 使用 SkillEffects.find_nearest_enemy（纯查询、无副作用），
## 不用 Unit.find_nearest_enemy_in_range —— 后者会消耗单位自身的索敌节流预算。
func _has_enemy_in_range() -> bool:
	if _trigger_range <= 0.0:
		return false
	var enemy: Node2D = SKILL_EFFECTS.find_nearest_enemy(_unit, _trigger_range)
	return enemy != null and is_instance_valid(enemy)

## 当前剩余 CD（秒），供后续 UI / 调试面板查询
func get_cd_left() -> float:
	return _cd_left

## 本兵种技能定义（空 = 无技能）
func get_skill_def() -> Dictionary:
	return _def

## 当前触发方式（"cooldown" / "attack_count"）
func get_trigger_kind() -> String:
	return _trigger_kind

## 攻击次数触发：自上次释放技能以来累计完成的普通攻击周期数（供调试面板查询）
func get_attack_count() -> int:
	return _attack_count
