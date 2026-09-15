extends Node

## 技能定义表：id / hero_id / name / type(on_field|off_field) / desc / cd_max
const SKILL_DEFS: Array[Dictionary] = [
	{
		"id": "aimis_1", "hero_id": "Hero1", "name": "万军召来", "type": "on_field",
		"desc": "在爱弥斯身边随机召唤 G / D / F / N 各一名单位（无视解锁，取全兵种池）",
		"cd_max": 3,
	},
	{
		"id": "aimis_2", "hero_id": "Hero1", "name": "全军号令", "type": "off_field",
		"desc": "全体我方单位攻击 +30%、移速 +30%、攻速 +30%，并获得 30 点护盾，持续 10 秒",
		"cd_max": 4,
	},
	{
		"id": "doro_1", "hero_id": "Hero2", "name": "以身为盾", "type": "on_field",
		"desc": "全体我方单位立即获得 60 点护盾",
		"cd_max": 3,
	},
	{
		"id": "doro_2", "hero_id": "Hero2", "name": "破布娃娃", "type": "off_field",
		"desc": "在水晶旁召唤 3 名随机 Doro 系单位",
		"cd_max": 4,
	},
	{
		"id": "phoebe_1", "hero_id": "Hero3", "name": "元素轰击", "type": "on_field",
		"desc": "全场敌军立即受到 40 点魔法伤害",
		"cd_max": 3,
	},
	{
		"id": "phoebe_2", "hero_id": "Hero3", "name": "圣殿庇护", "type": "off_field",
		"desc": "全体我方单位获得 40 点护盾，并清除流血 / 中毒 / 减速等负面状态",
		"cd_max": 4,
	},
	{
		"id": "guga_1", "hero_id": "Hero4", "name": "鹅群冲锋", "type": "on_field",
		"desc": "召唤 5 名随机咕咕嘎嘎系单位，全军移速 +50% 持续 8 秒",
		"cd_max": 3,
	},
	{
		"id": "guga_2", "hero_id": "Hero4", "name": "战旗鼓舞", "type": "off_field",
		"desc": "全体我方单位攻击 +40%，持续 10 秒",
		"cd_max": 4,
	},
	{
		"id": "nuo_1", "hero_id": "Hero5", "name": "糯米补给", "type": "on_field",
		"desc": "全体我方单位回复 35% 最大生命",
		"cd_max": 3,
	},
	{
		"id": "nuo_2", "hero_id": "Hero5", "name": "征召糯兵", "type": "off_field",
		"desc": "立即抽满手牌，并额外获得一张随机糯糯系卡牌",
		"cd_max": 4,
	},
]

const SKILL_BUFF_DURATION: float = 10.0
const SKILL_BUFF_DMG_MULT: float = 1.3
const SKILL_BUFF_SPEED_MULT: float = 1.3
const SKILL_BUFF_SHIELD: int = 30

## Hero2 以身为盾的护盾量
const DORO_SHIELD: int = 60
## Hero2 破布娃娃的召唤数量
const DORO_SUMMON_COUNT: int = 3
## Hero3 元素轰击的全场魔法伤害
const PHOEBE_NOVA_DAMAGE: int = 40
## Hero3 圣殿庇护的护盾量
const PHOEBE_SHIELD: int = 40
## Hero4 鹅群冲锋的召唤数量与移速加成 / 持续
const GUGA_SUMMON_COUNT: int = 5
const GUGA_SPEED_MULT: float = 1.5
const GUGA_SPEED_DURATION: float = 8.0
## Hero4 战旗鼓舞的攻击加成
const GUGA_DAMAGE_MULT: float = 1.4
## Hero5 糯米补给的回复比例
const NUO_HEAL_PCT: float = 0.35
## 召唤落点相对锚点的随机偏移范围
const SUMMON_OFFSET_X: float = 70.0
const SUMMON_OFFSET_Y: float = 40.0

signal skill_used(skill_id: String)
signal skill_cd_changed(skill_id: String, cd: int)

var _cd: Dictionary = {}

var _cd_override: Dictionary = {}
var _cd_override_loaded: bool = false
const CD_OVERRIDE_PATH := "user://roguelike_skill_cd_override.json"

func _ready() -> void:
	RoguelikeManager.run_started.connect(_on_run_started)

func _load_cd_override() -> void:
	if _cd_override_loaded:
		return
	_cd_override_loaded = true
	if not FileAccess.file_exists(CD_OVERRIDE_PATH):
		return
	var f := FileAccess.open(CD_OVERRIDE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_cd_override = parsed as Dictionary

func _save_cd_override() -> void:
	var f := FileAccess.open(CD_OVERRIDE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("HeroSkillManager: 无法写入技能 CD 覆盖层文件")
		return
	f.store_string(JSON.stringify(_cd_override))
	f.close()

func set_skill_cd_override(skill_id: String, val: int) -> void:
	_load_cd_override()
	_cd_override[skill_id] = int(maxi(val, 0))
	_save_cd_override()

func _find_def(skill_id: String) -> Dictionary:
	for d in SKILL_DEFS:
		if d["id"] == skill_id:
			return d
	return {}

func get_skills_for_hero(hero_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for d in SKILL_DEFS:
		if d.get("hero_id", "") == hero_id:
			result.append(d)
	return result

func get_cd_max(skill_id: String) -> int:
	var def := _find_def(skill_id)
	if def.is_empty():
		return 0
	_load_cd_override()
	return int(_cd_override.get(skill_id, def["cd_max"]))

func get_cd(skill_id: String) -> int:
	return int(_cd.get(skill_id, 0))

## 当前所选英雄的单位是否在场（登场技能的前置条件）
func hero_on_field() -> bool:
	return _hero_unit() != null

func can_use(skill_id: String) -> bool:
	var def := _find_def(skill_id)
	if def.is_empty():
		return false
	if def.get("hero_id", "") != RoguelikeManager.selected_hero:
		return false
	if get_cd(skill_id) > 0:
		return false
	if def["type"] == "on_field" and not hero_on_field():
		return false
	return true

func use_skill(skill_id: String) -> bool:
	if not can_use(skill_id):
		return false
	var def := _find_def(skill_id)
	_apply_skill_effect(def)
	_cd[skill_id] = get_cd_max(skill_id)
	skill_used.emit(skill_id)
	skill_cd_changed.emit(skill_id, get_cd(skill_id))
	return true

func on_wave_advance() -> void:
	for sid in _cd.keys():
		var cur: int = int(_cd[sid])
		if cur > 0:
			cur -= 1
			_cd[sid] = cur
			skill_cd_changed.emit(sid, cur)

func _on_run_started() -> void:
	_cd.clear()
	for d in SKILL_DEFS:
		skill_cd_changed.emit(d["id"], 0)

func _apply_skill_effect(def: Dictionary) -> void:
	match def["id"]:
		"aimis_1":
			_summon_around_hero(["G", "D", "F", "N"], 1)
		"aimis_2":
			_buff_all_players(SKILL_BUFF_DMG_MULT, SKILL_BUFF_SPEED_MULT, SKILL_BUFF_SPEED_MULT,
					SKILL_BUFF_SHIELD, SKILL_BUFF_DURATION)
		"doro_1":
			_shield_all_players(DORO_SHIELD)
		"doro_2":
			_summon_at_crystal(["D"], DORO_SUMMON_COUNT)
		"phoebe_1":
			_damage_all_enemies(PHOEBE_NOVA_DAMAGE)
		"phoebe_2":
			_shield_all_players(PHOEBE_SHIELD)
			_cleanse_all_players()
		"guga_1":
			_summon_around_hero(["G"], GUGA_SUMMON_COUNT)
			_buff_all_players(1.0, GUGA_SPEED_MULT, 1.0, 0, GUGA_SPEED_DURATION)
		"guga_2":
			_buff_all_players(GUGA_DAMAGE_MULT, 1.0, 1.0, 0, SKILL_BUFF_DURATION)
		"nuo_1":
			_heal_all_players(NUO_HEAL_PCT)
		"nuo_2":
			RoguelikeManager.refill_hand()
			_gain_faction_card("N")

## 在英雄身边按 factions 各召唤 count 名随机单位（英雄不在场时静默返回）
func _summon_around_hero(factions: Array, count: int) -> void:
	var hero := _hero_unit()
	if hero == null:
		return
	_summon_at(hero.global_position, factions, count)

## 在水晶旁按 factions 召唤随机单位（不要求英雄在场）
func _summon_at_crystal(factions: Array, count: int) -> void:
	_summon_at(Constants.ROGUELIKE_CRYSTAL_POS, factions, count)

## 在 anchor 附近为每个 faction 各召唤 count 名单位；英雄卡不进召唤池
func _summon_at(anchor: Vector2, factions: Array, count: int) -> void:
	for f in factions:
		var pool: Array[UnitResource] = []
		for u in UnitDatabase.unit_list:
			var res := u as UnitResource
			if res == null or UnitDatabase.is_hero_unit(res.unit_id):
				continue
			if res.unit_id.left(1) == String(f):
				pool.append(res)
		if pool.is_empty():
			continue
		for _i in range(count):
			if BattleManager.player_units.size() >= Constants.ROGUELIKE_POPULATION_CAP:
				return
			var res := pool[randi() % pool.size()]
			var off := Vector2(randf_range(-SUMMON_OFFSET_X, SUMMON_OFFSET_X),
					randf_range(-SUMMON_OFFSET_Y, SUMMON_OFFSET_Y))
			var pos := anchor + off
			pos.x = clampf(pos.x, Constants.FIELD_X_MIN, Constants.FIELD_X_MAX)
			pos.y = clampf(pos.y, Constants.FIELD_Y_MIN, Constants.FIELD_Y_MAX)
			BattleManager.spawn_unit(res, 0, pos)

## 全体我方按倍率上 buff 并给护盾，duration 秒后还原倍率（护盾不回收）
func _buff_all_players(dmg_mult: float, move_mult: float, atk_speed_mult: float,
		shield: int, duration: float) -> void:
	for u in BattleManager.player_units.duplicate():
		var unit := u as Unit
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		var orig_dmg: float = unit.buff_damage_mult
		var orig_move: float = unit.buff_move_mult
		var orig_atk: float = unit.buff_attack_interval_mult
		unit.buff_damage_mult = orig_dmg * dmg_mult
		unit.buff_move_mult = orig_move * move_mult
		unit.buff_attack_interval_mult = orig_atk / maxf(atk_speed_mult, 0.1)
		if shield > 0:
			unit.add_shield(shield)
		_restore_buffs_after(unit, orig_dmg, orig_move, orig_atk, duration)

## 全体我方立即获得护盾
func _shield_all_players(shield: int) -> void:
	for u in BattleManager.player_units:
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			unit.add_shield(shield)

## 全体我方按最大生命百分比回复
func _heal_all_players(pct: float) -> void:
	for u in BattleManager.player_units:
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			unit.heal(maxi(int(round(float(unit.get_max_hp()) * pct)), 1))

## 清除全体我方的持续负面状态（流血 / 中毒词条 + 技能减速）
func _cleanse_all_players() -> void:
	for u in BattleManager.player_units:
		var unit := u as Unit
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		if unit.has_method("clear_all_affixes"):
			unit.clear_all_affixes()
		unit.skill_slow_timer = 0.0
		unit.skill_slow_percent = 0.0

## 全场敌军受到固定魔法伤害（duplicate 防止致死时列表在遍历中被改）
func _damage_all_enemies(amount: int) -> void:
	for u in BattleManager.enemy_units.duplicate():
		var unit := u as Unit
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		unit.take_damage_typed(amount, RunModifiers.DMG_MAGIC, null)

## 立即向牌库追加一张指定军团的随机卡（池空时静默忽略）
func _gain_faction_card(faction: String) -> void:
	var pool: Array[String] = []
	for u in UnitDatabase.unit_list:
		var res := u as UnitResource
		if res == null or UnitDatabase.is_hero_unit(res.unit_id):
			continue
		if res.unit_id.left(1) == faction:
			pool.append(res.unit_id)
	if pool.is_empty():
		return
	RoguelikeManager.add_card(pool[randi() % pool.size()])

func _restore_buffs_after(unit: Unit, orig_dmg: float, orig_move: float,
		orig_atk: float, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(unit):
		unit.buff_damage_mult = orig_dmg
		unit.buff_move_mult = orig_move
		unit.buff_attack_interval_mult = orig_atk

## 场上本局所选英雄的单位（存活）
func _hero_unit() -> Unit:
	var hero_id: String = RoguelikeManager.selected_hero
	if hero_id.is_empty():
		return null
	for u in BattleManager.player_units:
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead \
				and unit.unit_resource != null and unit.unit_resource.unit_id == hero_id:
			return unit
	return null
