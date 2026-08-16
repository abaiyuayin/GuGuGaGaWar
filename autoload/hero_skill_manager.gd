extends Node
## 肉鸽英雄技能系统（#8）
##
## 设计原则（来自 grill-me 决策）：
##   1. 通用「技能表」驱动：所有技能都在 SKILL_DEFS 里登记，效果代码按 id 分发，
##      新增英雄/技能只改数据表 + 在 _apply_skill_effect 加一个分支，不散落各处。
##   2. CD 单位为「波次」：释放后进入 cd_max 波冷却，每刷新一波敌军自动 -1（on_wave_advance）。
##   3. CD 上限可由肉鸽控制台覆盖并持久化（set_skill_cd_override），不写死。
##
## 技能两类：
##   on_field  —— 登场技能，需要英雄（Hero1 单位）当前在场才能释放
##   off_field —— 非登场技能，无需英雄在场即可释放
##
## 本管理器是 Autoload 单例，可直接调用 BattleManager / UnitDatabase；
## 不持有任何节点，只维护 CD 状态与效果执行。

## 技能定义表（数据驱动）
##   id      唯一标识
##   hero_id 所属英雄（与 RoguelikeManager.HERO_DEFS 对应）
##   name    显示名
##   type    on_field / off_field
##   desc    描述（HUD 弹窗与 tooltip 复用）
##   cd_max  基础冷却波数（可被控制台覆盖）
const SKILL_DEFS: Array[Dictionary] = [
	{
		"id": "aimis_1",
		"hero_id": "Hero1",
		"name": "万军召来",
		"type": "on_field",
		"desc": "在爱弥斯身边随机召唤 G / D / F / N 各一名单位（无视解锁，取全兵种池）",
		"cd_max": 3,
	},
	{
		"id": "aimis_2",
		"hero_id": "Hero1",
		"name": "全军号令",
		"type": "off_field",
		"desc": "全体我方单位攻击 +30%、移速 +30%、攻速 +30%，并获得 30 点护盾，持续 10 秒",
		"cd_max": 4,
	},
]

## 技能 2 临时增益参数（数据驱动，便于后续调参）
const SKILL_BUFF_DURATION: float = 10.0
const SKILL_BUFF_DMG_MULT: float = 1.3
const SKILL_BUFF_SPEED_MULT: float = 1.3
const SKILL_BUFF_SHIELD: int = 30

## 技能释放时发出（供 HUD 刷新 / 提示）
signal skill_used(skill_id: String)
## 某技能 CD 变化时发出（[param cd] 为剩余波数）
signal skill_cd_changed(skill_id: String, cd: int)

## 当前各技能剩余 CD（波次），key = skill_id，缺省视为 0（就绪）
var _cd: Dictionary = {}

## CD 上限覆盖层（控制台持久化，跨 run 保留）
var _cd_override: Dictionary = {}
var _cd_override_loaded: bool = false
const CD_OVERRIDE_PATH := "user://roguelike_skill_cd_override.json"

func _ready() -> void:
	## 一次 run 开始时清空 CD（挂在 RoguelikeManager.start_run 末尾的 run_started 上）
	RoguelikeManager.run_started.connect(_on_run_started)

## ── 控制台 CD 覆盖层（持久化 user://）──────────────────────────────
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

## 设置某技能 CD 上限覆盖值并持久化
func set_skill_cd_override(skill_id: String, val: int) -> void:
	_load_cd_override()
	_cd_override[skill_id] = int(maxi(val, 0))
	_save_cd_override()

## ── 查询接口 ───────────────────────────────────────────────────────
func _find_def(skill_id: String) -> Dictionary:
	for d in SKILL_DEFS:
		if d["id"] == skill_id:
			return d
	return {}

## 返回某英雄的全部技能定义（HUD 据此建卡）
func get_skills_for_hero(hero_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for d in SKILL_DEFS:
		if d.get("hero_id", "") == hero_id:
			result.append(d)
	return result

## 某技能当前 CD 上限（波数）：覆盖层优先，否则取定义默认值
func get_cd_max(skill_id: String) -> int:
	var def := _find_def(skill_id)
	if def.is_empty():
		return 0
	return int(_cd_override.get(skill_id, def["cd_max"]))

## 某技能剩余 CD（波数）
func get_cd(skill_id: String) -> int:
	return int(_cd.get(skill_id, 0))

## 英雄（爱弥斯）当前是否在场
func hero_on_field() -> bool:
	return _hero_unit() != null

## 能否释放某技能：CD 就绪 且（非登场技能 或 英雄在场）
func can_use(skill_id: String) -> bool:
	var def := _find_def(skill_id)
	if def.is_empty():
		return false
	if get_cd(skill_id) > 0:
		return false
	if def["type"] == "on_field" and not hero_on_field():
		return false
	return true

## ── 释放 / CD 推进 ────────────────────────────────────────────────
## 释放技能；条件不满足返回 false 且不做任何变更
func use_skill(skill_id: String) -> bool:
	if not can_use(skill_id):
		return false
	var def := _find_def(skill_id)
	_apply_skill_effect(def)
	_cd[skill_id] = get_cd_max(skill_id)
	skill_used.emit(skill_id)
	skill_cd_changed.emit(skill_id, get_cd(skill_id))
	return true

## 每刷新一波敌军时调用：所有技能 CD -1（夹断到 0），变化才广播
func on_wave_advance() -> void:
	for sid in _cd.keys():
		var cur: int = int(_cd[sid])
		if cur > 0:
			cur -= 1
			_cd[sid] = cur
			skill_cd_changed.emit(sid, cur)

## run 开始：清空所有 CD（信号来自 RoguelikeManager.run_started）
func _on_run_started() -> void:
	_cd.clear()
	for d in SKILL_DEFS:
		skill_cd_changed.emit(d["id"], 0)

## ── 效果分发 ──────────────────────────────────────────────────────
func _apply_skill_effect(def: Dictionary) -> void:
	match def["id"]:
		"aimis_1":
			_summon_around_hero()
		"aimis_2":
			_buff_all_players()

## 爱弥斯在场时，随机召唤 G/D/F/N 各一名单位于其身边（全兵种池，无视解锁）
func _summon_around_hero() -> void:
	var hero := _hero_unit()
	if hero == null:
		return
	var factions: Array[String] = ["G", "D", "F", "N"]
	for f in factions:
		var pool: Array[UnitResource] = []
		for u in UnitDatabase.unit_list:
			var res := u as UnitResource
			if res == null or res.unit_id == "Hero1":
				continue
			if res.unit_id.left(1) == f:
				pool.append(res)
		if pool.is_empty():
			continue
		var res := pool[randi() % pool.size()]
		var off := Vector2(randf_range(-70.0, 70.0), randf_range(-40.0, 40.0))
		var pos := hero.global_position + off
		pos.x = clampf(pos.x, Constants.FIELD_X_MIN, Constants.FIELD_X_MAX)
		pos.y = clampf(pos.y, Constants.FIELD_Y_MIN, Constants.FIELD_Y_MAX)
		BattleManager.spawn_unit(res, 0, pos)

## 全体我方单位 +30% 攻/速、+30 护盾，持续 10 秒（之后还原倍率，护盾不回落）
func _buff_all_players() -> void:
	for u in BattleManager.player_units.duplicate():
		var unit := u as Unit
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		var orig_dmg: float = unit.buff_damage_mult
		var orig_move: float = unit.buff_move_mult
		var orig_atk: float = unit.buff_attack_interval_mult
		unit.buff_damage_mult = orig_dmg * SKILL_BUFF_DMG_MULT
		unit.buff_move_mult = orig_move * SKILL_BUFF_SPEED_MULT
		unit.buff_attack_interval_mult = orig_atk / SKILL_BUFF_SPEED_MULT
		unit.add_shield(SKILL_BUFF_SHIELD)
		_restore_buffs_after(unit, orig_dmg, orig_move, orig_atk)

## 10 秒后还原倍率（护盾为一次性加成，不回收）
func _restore_buffs_after(unit: Unit, orig_dmg: float, orig_move: float, orig_atk: float) -> void:
	await get_tree().create_timer(SKILL_BUFF_DURATION).timeout
	if is_instance_valid(unit):
		unit.buff_damage_mult = orig_dmg
		unit.buff_move_mult = orig_move
		unit.buff_attack_interval_mult = orig_atk

## 场上英雄单位（unit_resource.unit_id == "Hero1" 且存活）
func _hero_unit() -> Unit:
	for u in BattleManager.player_units:
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead \
				and unit.unit_resource != null and unit.unit_resource.unit_id == "Hero1":
			return unit
	return null
