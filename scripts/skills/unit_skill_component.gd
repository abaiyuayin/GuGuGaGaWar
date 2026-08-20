extends Node
## 兵种技能组件（标准模式：战役 / 全面战争 / 双人）
##
## 挂在 Unit 节点下，只负责「何时该放技能」：
##   1. _ready 查表，该兵种无技能则立即自我移除 —— 30+ 个普通兵种零额外开销
##   2. 每帧递减 CD；CD 就绪且触发半径内有敌人时，请求宿主切入技能状态
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

## 宿主单位
var _unit: Node2D = null
## 本兵种的技能定义（空 = 无技能）
var _def: Dictionary = {}
## 剩余冷却（秒）
var _cd_left: float = 0.0
## 触发半径（像素，从定义缓存）
var _trigger_range: float = 0.0

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

	_trigger_range = float(_def.get("trigger_range", 0.0))
	## 进场先进入一次完整冷却，避免一出场就立刻放技能
	_cd_left = float(_def.get("cd", 0.0))

func _physics_process(delta: float) -> void:
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
