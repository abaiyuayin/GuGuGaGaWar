extends Node
## 肉鸽模式运行状态管理器 — Autoload 单例
##
## 生命周期：玩家在战役地图点击「肉鸽模式」→ 选英雄 → start_run()，失败或主动退出时 end_run()。
## 职责边界：只维护「一个 run」的牌库 / 手牌 / 层数 / 金币 / 文物 / 军令 / 地图数据与抽牌规则。
## 不包含任何战斗逻辑（刷怪、胜负判定由 RoguelikeDirector 负责），也不直接操作节点。
##
## 卡牌规则（与常规卡牌游戏的差异点）：
##   1. 手牌上限恒为 HAND_LIMIT(3) + 文物 hand_limit_bonus
##   2. 每个战斗节点开局从牌库洗牌后抽满手牌
##   3. 每波敌军刷新时把手牌补到上限 —— 上一波没打出去的牌不会被弃掉
##   4. 牌库只在通关节点后通过三选一奖励 / 商店 / 事件增长
##   5. 每张卡打出后进入独立冷却（Constants.ROGUELIKE_CARD_COOLDOWN_SEC）

## 手牌内容变化时发出。[param hand_ids] 为当前手牌的兵种 ID 列表
signal hand_changed(hand_ids: Array[String])
## 永久牌库变化时发出（获得奖励卡）。[param deck_ids] 为牌库全部兵种ID
signal deck_changed(deck_ids: Array[String])
## 金币变化时发出（地图商店消费 / 通关奖励），[param gold] 为最新余
signal gold_changed(gold: int)
## 持有文物变化时发出。[param artifact_ids] 为当前全部文物ID
signal artifacts_changed(artifact_ids: Array[String])
## 军令卡被打出时发出，供战斗层立即执行一次性指令（补牌 / 治疗 / 跳波 / 延迟刷怪等）
## 持续型军令（伤害倍率、护甲加成等）无需监听，由 RunModifiers 直接读 active_order_effects
signal order_played(order_id: String, effect_type: String, effect_value: float)
## 层数推进时发出。[param floor_index] 为新的层数（第1起）
signal floor_changed(floor_index: int)
## 一个run 正式开始时发出（start_run 末尾），供依赖run 级状态的子系统（如英雄技能CD）清
signal run_started()

## 局内手牌上限
const HAND_LIMIT: int = 3
## 军令卡在牌库 / 手牌里的 ID 前缀：卡 ID = 前缀 + 军令 ID，与兵种 ID 区分
## 军令与兵种同处一个牌库、共用手牌位与抽牌堆（打出只离手，下场重新洗牌仍可抽到）
const ORDER_CARD_PREFIX: String = "ORDER:"
## 起始牌库随机张数（英雄卡另外固定插入）
const STARTING_DECK_SIZE: int = 3
## 起始牌池允许的最高阶层（避免开局白送高阶兵）
const STARTING_MAX_TIER: int = 2
## 通关一个节点后提供的候选奖励卡数量
const REWARD_CHOICE_COUNT: int = 3
## 地图总层数（最后一层为 Boss）
const MAP_FLOORS: int = 10
## 每层节点数量：底部 4 个起始选项、中部 3~4 个、顶部 1 个 Boss，形成分支汇聚地图
const NODES_PER_FLOOR: Array[int] = [4, 4, 4, 3, 3, 3, 3, 3, 2, 1]

## 地图节点类型（战斗/精英/休息/事件/商店/宝箱/Boss）
## 节点数据结构见 scripts/roguelike/roguelike_map_node.gd
enum NodeType { COMBAT, ELITE, REST, EVENT, SHOP, TREASURE, BOSS }

## 入口层（floor_index 0，4 个节点）固定类型：战斗 / 休息 / 商店 / 宝箱（奇遇）
## 每次 start_run 洗牌（见 generate_map），左右位置随机；数量须与 NODES_PER_FLOOR[0] 一致
const ENTRY_FLOOR_TYPES: Array[int] = [NodeType.COMBAT, NodeType.REST, NodeType.SHOP, NodeType.TREASURE]
## Boss 前一层（floor_index MAP_FLOORS-2，2 个节点）固定类型：休息 / 商店
const PRE_BOSS_FLOOR_TYPES: Array[int] = [NodeType.REST, NodeType.SHOP]
## 权重表各列对应的节点类型（与 FLOOR_TYPE_WEIGHTS 的数组下标一一对应）
const WEIGHTED_TYPES: Array[int] = [NodeType.COMBAT, NodeType.ELITE, NodeType.REST, NodeType.EVENT, NodeType.SHOP, NodeType.TREASURE]
## 中间层节点类型权重表，取「floor_idx <= max_floor」中最先匹配的一行
##   早期（≤3 层）：普通战斗为主，精英稀少，让玩家先把牌库攒起来
##   中期（≤6 层）：精英占比翻倍，商店 / 宝箱补给同步增加
##   后期（其余）：精英最多，休息占比提高以应对 Boss 前的损失
const FLOOR_TYPE_WEIGHTS: Array[Dictionary] = [
	{"max_floor": 3, "weights": [55, 8, 4, 5, 2, 2]},
	{"max_floor": 6, "weights": [42, 18, 5, 4, 3, 2]},
	{"max_floor": 99, "weights": [38, 22, 6, 3, 2, 2]},
]
## 连续多少层内必须出现一个休息点（保底规则，防止长段无补给）
const REST_GUARANTEE_SPAN: int = 3

## 当前是否处于肉鸽模式（战场、HUD 依据此标志切换行为）
var is_active: bool = false
## 当前 run 选择的英雄 ID。空 = 尚未选择，由英雄选择界面写入
var selected_hero: String = ""
## 肉鸽可选英雄表：
##   army     军团构成（起始牌库与奖励倾向按 factions 前缀过滤）
##   special  特长文案（战斗开局播报）
##   effects  特长的实际数值，键与文物 / 军令的 effect_type 同名，
##            由 get_hero_effect_total 汇总进 RunModifiers.total
const HERO_DEFS: Array[Dictionary] = [
	{
		"id": "Hero1", "name": "爱弥斯", "locked": false,
		"army": "四兵种随机军队", "special": "全军 +30% 攻击力与攻击速度",
		"factions": ["G", "D", "F", "N"],
		"effects": {"unit_damage_pct": 0.30, "unit_attack_speed_pct": 0.30},
	},
	{
		"id": "Hero2", "name": "Doro勇士", "locked": true,
		"army": "Doro 系随机军队", "special": "全军最大生命 +25%",
		"factions": ["D"],
		"effects": {"unit_hp_pct": 0.25},
	},
	{
		"id": "Hero3", "name": "菲比Hero", "locked": true,
		"army": "菲比系随机军队", "special": "全军魔法伤害 +35%、远程伤害 +20%",
		"factions": ["F"],
		"effects": {"magic_damage_pct": 0.35, "ranged_damage_pct": 0.20},
	},
	{
		"id": "Hero4", "name": "咕咕嘎嘎Hero", "locked": true,
		"army": "咕咕嘎嘎系随机军队", "special": "全军护甲 +8、移动速度 +15%",
		"factions": ["G"],
		"effects": {"unit_armor_flat": 8.0, "unit_move_speed_pct": 0.15},
	},
	{
		"id": "Hero5", "name": "糯糯Hero", "locked": true,
		"army": "糯糯系随机军队", "special": "击杀 +1 金币、节点通关 +2 金币",
		"factions": ["N"],
		"effects": {"death_gold": 1.0, "gold_per_node": 2.0},
	},
]

## 当前所选英雄提供的某项加成总值（与文物 / 军令共用 RunModifiers.total 汇总通道）
func get_hero_effect_total(effect_type: String) -> float:
	if selected_hero.is_empty():
		return 0.0
	for hero in HERO_DEFS:
		if hero["id"] == selected_hero:
			var effects: Dictionary = hero.get("effects", {})
			return float(effects.get(effect_type, 0.0))
	return 0.0

## 当前所选英雄的军团前缀列表（起始牌库与奖励倾向都按此过滤）
func get_hero_factions() -> Array[String]:
	var result: Array[String] = []
	if selected_hero.is_empty():
		return result
	for hero in HERO_DEFS:
		if hero["id"] == selected_hero:
			for f in hero.get("factions", []):
				result.append(String(f))
			return result
	return result

## 当前所选英雄的特长文案（战斗开局播报用）
func get_hero_special_text() -> String:
	for hero in HERO_DEFS:
		if hero["id"] == selected_hero:
			return String(hero.get("special", ""))
	return ""


## 返回英雄选择界面使用的英雄表（HERO_DEFS 的运行时副本）。
## Hero2：开发者模式默认解锁 / 战役隐藏成就「为了欧润橘！」解锁。
## Hero3~Hero5：纯 DevMode 门控（Hero4/5 属 special_units，不在常规关解锁通道内）。
func get_hero_defs() -> Array[Dictionary]:
	var defs: Array[Dictionary] = []
	for hero in HERO_DEFS:
		var def := hero.duplicate()
		var locked: bool = hero["locked"]
		if hero["id"] == "Hero2":
			var unlocked: bool = DevMode.enabled or CampaignProgress.is_unit_unlocked("Hero2")
			locked = not unlocked
		elif hero["id"] in ["Hero3", "Hero4", "Hero5"]:
			locked = not DevMode.enabled
		def["locked"] = locked
		if locked:
			def["name"] = "？？？"
			def["army"] = ""
			def["special"] = ""
		defs.append(def)
	return defs

## ── 局内AI 调参（#210，肉鸽控制台可改）─────────────────────────
## 统一寻敌 / 追击半径（像素）：肉鸽模式下所有兵种共用此值，与各自攻击距离解耦
## 单位在 setup 时据此设置 DetectionArea 半径；改动只对之后生成的单位生效
var chase_range_px: float = Constants.ROGUELIKE_CHASE_RANGE
## 追击牵引半径（像素）。守卫单位离水晶超过此距离即中断追击返回驻守点
var chase_leash_px: float = Constants.ROGUELIKE_CHASE_LEASH
## 当前层数，从 1 开
var current_floor: int = 1
## 永久牌库（跨层保留的兵种 ID 列表
var deck: Array[String] = []
## 每张卡的升级次数（兵种 ID -> 次数）：每次休息升级 +1 级，单卡召唤人数 +2 线性叠加
## 存储的是「次数」，卡牌等级 = 次数 + 1；随 run 重置
var deck_upgrade: Dictionary = {}
## 卡牌等级上限（#211 圆框徽章）：1=初始、=满级。deck_upgrade 存储值= 等级-1，故次数上限为CARD_LEVEL_MAX - 1 = 2
const CARD_LEVEL_MAX: int = 3
## 水晶当前耐久（肉鸽run 级持久资源，跨战斗保留，#213）：每场战斗继承上场剩余，被打掉带回，休息处可回血
var crystal_hp: int = 0
## 水晶耐久上限（肉鸽run 内恒定= Constants.ROGUELIKE_CRYSTAL_HP
var crystal_max_hp: int = 0
## 水晶耐久变化信号（hp, max_hp），供HUD / 休息界面刷新
signal crystal_hp_changed(hp: int, max_hp: int)
## 当前金币余额（肉鸽run 内有效，用于地图商店消费），本run重置
var gold: int = 0
## 已获得的文物 ID 列表（run 内永久被动，本run重置
var owned_artifacts: Array[String] = []
## 本场战斗内已打出军令的累计效果：effect_type -> 累计值
## 生命周期只覆盖「一场战斗」：打出即累加，进入下一个战斗节点（start_floor）时清空。
## 与 owned_artifacts 的永久被动区分开 —— 军令是本场用完就没的临时增益
var active_order_effects: Dictionary = {}
## 本层待抽牌堆（每个战斗节点开局从 deck 洗牌生成）
var draw_pile: Array[String] = []
## 当前手牌（卡 ID 列表：兵种 ID 或 ORDER_CARD_PREFIX + 军令 ID）
var hand: Array[String] = []
## 本 run 实际部署过的兵种 ID 集合（play_card 时记录，start_run / end_run 重置）
## 供肉鸽专属成就「无名小卒还是名扬天下」判定 —— 全程只部署 G1
var run_deployed_ids: Dictionary = {}
## 当前地图（分支DAG），元素为RoguelikeMapNode
var map_nodes: Array[RoguelikeMapNode] = []
## 当前所在节点下标（-1 表示尚未进入任何节点，需从第一层挑一个）
var current_node_index: int = -1
## 本场战斗内各兵种卡的剩余冷却（unit_id -> 剩余秒数），进入新一层清空
var card_cooldowns: Dictionary = {}
## 本 run 已消耗的水晶免死次数（文物「Doro 的破布娃娃」revive_once）
var crystal_revive_used: int = 0
## 某张卡的冷却状态变化时发出（unit_id, 剩余秒数）
signal card_cooldown_changed(unit_id: String, remaining: float)

## ── 本局战绩统计（结算界面展示 + 历史最佳记录）──────────────────
## 键：nodes_cleared / kills / gold_earned / cards_played / orders_played
##     crystal_damage / elapsed_sec / max_floor
var run_stats: Dictionary = {}

## 最近一局结束时的战绩快照（archive_run 写入，start_run 清空）。
## 结算界面读这份而不是 run_stats —— battle_root 在弹失败界面前就调了 end_run()，
## run_stats 那时已被清空，只有快照能保证胜/败两个界面都拿到真实数据。
var last_run_stats: Dictionary = {}

## 结算界面用的统计取值：优先读本局快照，没有快照时回落实时统计
func get_last_stat(key: String) -> int:
	if last_run_stats.has(key):
		return int(last_run_stats[key])
	return get_stat(key)

## 统计项累加（key 不存在时视为 0）
func add_stat(key: String, amount: int = 1) -> void:
	run_stats[key] = int(run_stats.get(key, 0)) + amount

## 统计项取值
func get_stat(key: String) -> int:
	return int(run_stats.get(key, 0))

## 统计项取「更大者」（如已达最深层数）
func track_stat_max(key: String, value: int) -> void:
	if value > int(run_stats.get(key, 0)):
		run_stats[key] = value

## 本局用时（秒）：以 run 开始时的引擎毫秒为基准实时算
func get_elapsed_sec() -> int:
	if _run_start_msec <= 0:
		return get_stat("elapsed_sec")
	return int((Time.get_ticks_msec() - _run_start_msec) / 1000)

var _run_start_msec: int = 0

## ── 进阶难度（通关一次解锁下一级，持久化 user://）─────────────
## 每级：敌方 +ASCENSION_ENEMY_HP_PER_LEVEL 血 / +..._DMG... 伤，
##       起始金币 −ASCENSION_GOLD_PENALTY，水晶上限 ×(1 − ..._CRYSTAL_PENALTY)
const ASCENSION_MAX_LEVEL: int = 5
const ASCENSION_ENEMY_HP_PER_LEVEL: float = 0.10
const ASCENSION_ENEMY_DMG_PER_LEVEL: float = 0.08
const ASCENSION_GOLD_PENALTY: int = 10
const ASCENSION_CRYSTAL_PENALTY: float = 0.05
const PROGRESS_PATH := "user://roguelike_progress.json"

## 本局选定的进阶难度等级（0 = 无加难）
var ascension_level: int = 0
## 已解锁的最高进阶等级（通关后 +1，持久化）
var ascension_unlocked: int = 0
## 历史最佳记录：{ "best_floor", "best_kills", "best_gold", "wins", "runs", "best_ascension" }
var best_records: Dictionary = {}
var _progress_loaded: bool = false

## 载入进阶解锁与历史记录（懒加载）
func load_progress() -> void:
	if _progress_loaded:
		return
	_progress_loaded = true
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed as Dictionary
	ascension_unlocked = clampi(int(data.get("ascension_unlocked", 0)), 0, ASCENSION_MAX_LEVEL)
	var rec: Variant = data.get("best_records", {})
	if rec is Dictionary:
		best_records = rec as Dictionary

## 写盘进阶解锁与历史记录
func save_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("RoguelikeManager: 无法写入肉鸽进度文件")
		return
	f.store_string(JSON.stringify({
		"ascension_unlocked": ascension_unlocked,
		"best_records": best_records,
	}, "\t"))
	f.close()

## 本局结束时归档战绩：刷新历史最佳，通关时解锁下一进阶等级
## [param won] 是否击败 Boss 通关
func archive_run(won: bool) -> void:
	load_progress()
	run_stats["elapsed_sec"] = get_elapsed_sec()
	## 快照必须在此刻做：随后 end_run() 会清空 run_stats，结算界面只认这份快照
	last_run_stats = run_stats.duplicate()
	best_records["runs"] = int(best_records.get("runs", 0)) + 1
	if won:
		best_records["wins"] = int(best_records.get("wins", 0)) + 1
		if ascension_level >= ascension_unlocked and ascension_unlocked < ASCENSION_MAX_LEVEL:
			ascension_unlocked += 1
		best_records["best_ascension"] = maxi(int(best_records.get("best_ascension", 0)), ascension_level)
	best_records["best_floor"] = maxi(int(best_records.get("best_floor", 0)), get_stat("max_floor"))
	best_records["best_kills"] = maxi(int(best_records.get("best_kills", 0)), get_stat("kills"))
	best_records["best_gold"] = maxi(int(best_records.get("best_gold", 0)), get_stat("gold_earned"))
	save_progress()

## 当前进阶难度带来的敌方血量倍率（1.0 = 无加难）
func ascension_enemy_hp_mult() -> float:
	return 1.0 + float(ascension_level) * ASCENSION_ENEMY_HP_PER_LEVEL

## 当前进阶难度带来的敌方伤害倍率
func ascension_enemy_damage_mult() -> float:
	return 1.0 + float(ascension_level) * ASCENSION_ENEMY_DMG_PER_LEVEL

## 某个进阶等级的效果文案（英雄选择界面的难度说明用）
func ascension_desc(level: int) -> String:
	if level <= 0:
		return "标准难度，无额外惩罚"
	return "敌方血量 +%d%% / 伤害 +%d%%，起始金币 −%d，水晶上限 −%d%%" % [
		int(round(float(level) * ASCENSION_ENEMY_HP_PER_LEVEL * 100.0)),
		int(round(float(level) * ASCENSION_ENEMY_DMG_PER_LEVEL * 100.0)),
		level * ASCENSION_GOLD_PENALTY,
		int(round(float(level) * ASCENSION_CRYSTAL_PENALTY * 100.0)),
	]

## ── run 存档（hub 层面）────────────────────────────────────────
## 只存 hub 可恢复的状态：牌库 / 升级 / 文物 / 金币 / 水晶 / 地图 / 当前节点 / 英雄 / 统计。
## 不存局内手牌、抽牌堆与场上单位 —— 战斗中退出会回退到该节点开始前。
const RUN_SAVE_PATH := "user://roguelike_run_save.json"

## 是否存在可继续的存档
func has_save() -> bool:
	return FileAccess.file_exists(RUN_SAVE_PATH)

## 只读窥视存档摘要（供「继续上次征程」按钮显示层数 / 英雄 / 进阶，不改动任何运行态）。
## 无存档或存档损坏时返回空字典。键：hero / floor / gold / ascension / deck_size
func peek_save_summary() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed as Dictionary
	var deck_raw: Variant = data.get("deck", [])
	return {
		"hero": String(data.get("selected_hero", "")),
		"floor": maxi(int(data.get("current_floor", 1)), 1),
		"gold": maxi(int(data.get("gold", 0)), 0),
		"ascension": maxi(int(data.get("ascension_level", 0)), 0),
		"deck_size": (deck_raw as Array).size() if deck_raw is Array else 0,
	}

## 把当前 run 写盘（在 hub 状态调用：进入 hub、非战斗结算完成后）
func save_run() -> void:
	if not is_active or map_nodes.is_empty():
		return
	var nodes: Array = []
	for node in map_nodes:
		nodes.append({
			"floor_index": node.floor_index,
			"slot_index": node.slot_index,
			"x_ratio": node.x_ratio,
			"node_type": node.node_type,
			"next": node.next.duplicate(),
			"visited": node.visited,
			"enemy_tier": node.enemy_tier,
			"wave_count": node.wave_count,
			"is_boss": node.is_boss,
		})
	var f := FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("RoguelikeManager: 无法写入肉鸽存档")
		return
	f.store_string(JSON.stringify({
		"version": 1,
		"selected_hero": selected_hero,
		"current_floor": current_floor,
		"current_node_index": current_node_index,
		"gold": gold,
		"crystal_hp": crystal_hp,
		"crystal_max_hp": crystal_max_hp,
		"crystal_revive_used": crystal_revive_used,
		"ascension_level": ascension_level,
		"deck": deck.duplicate(),
		"deck_upgrade": deck_upgrade.duplicate(),
		"owned_artifacts": owned_artifacts.duplicate(),
		"run_deployed_ids": run_deployed_ids.duplicate(),
		"run_stats": run_stats.duplicate(),
		"map_nodes": nodes,
	}, "\t"))
	f.close()

## 删除存档（run 结束 / 主动放弃）
## DirAccess.remove_absolute 直接吃 res:// / user:// 虚拟路径，无需先 globalize_path
func clear_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)

## 读档恢复一局 run；成功返回 true（随后由调用方切到 hub 场景）
func load_run() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		clear_save()
		return false
	var data: Dictionary = parsed as Dictionary
	var raw_nodes: Variant = data.get("map_nodes", [])
	if not (raw_nodes is Array) or (raw_nodes as Array).is_empty():
		clear_save()
		return false
	is_active = true
	selected_hero = String(data.get("selected_hero", "Hero1"))
	current_floor = maxi(int(data.get("current_floor", 1)), 1)
	current_node_index = int(data.get("current_node_index", -1))
	gold = maxi(int(data.get("gold", 0)), 0)
	crystal_max_hp = maxi(int(data.get("crystal_max_hp", Constants.ROGUELIKE_CRYSTAL_HP)), 1)
	crystal_hp = clampi(int(data.get("crystal_hp", crystal_max_hp)), 1, crystal_max_hp)
	crystal_revive_used = maxi(int(data.get("crystal_revive_used", 0)), 0)
	ascension_level = clampi(int(data.get("ascension_level", 0)), 0, ASCENSION_MAX_LEVEL)
	chase_range_px = Constants.ROGUELIKE_CHASE_RANGE
	chase_leash_px = Constants.ROGUELIKE_CHASE_LEASH
	deck.clear()
	for cid in data.get("deck", []):
		deck.append(String(cid))
	deck_upgrade.clear()
	var raw_up: Variant = data.get("deck_upgrade", {})
	if raw_up is Dictionary:
		for k in (raw_up as Dictionary).keys():
			deck_upgrade[String(k)] = int((raw_up as Dictionary)[k])
	owned_artifacts.clear()
	for aid in data.get("owned_artifacts", []):
		owned_artifacts.append(String(aid))
	run_deployed_ids.clear()
	var raw_dep: Variant = data.get("run_deployed_ids", {})
	if raw_dep is Dictionary:
		for k in (raw_dep as Dictionary).keys():
			run_deployed_ids[String(k)] = true
	run_stats.clear()
	var raw_stats: Variant = data.get("run_stats", {})
	if raw_stats is Dictionary:
		for k in (raw_stats as Dictionary).keys():
			run_stats[String(k)] = int((raw_stats as Dictionary)[k])
	map_nodes.clear()
	for raw in (raw_nodes as Array):
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw as Dictionary
		var node := RoguelikeMapNode.new()
		node.floor_index = int(d.get("floor_index", 0))
		node.slot_index = int(d.get("slot_index", 0))
		node.x_ratio = float(d.get("x_ratio", 0.5))
		node.node_type = int(d.get("node_type", NodeType.COMBAT))
		node.next.clear()
		for n in d.get("next", []):
			node.next.append(int(n))
		node.visited = bool(d.get("visited", false))
		node.enemy_tier = int(d.get("enemy_tier", 1))
		node.wave_count = int(d.get("wave_count", 3))
		node.is_boss = bool(d.get("is_boss", false))
		map_nodes.append(node)
	card_cooldowns.clear()
	active_order_effects.clear()
	draw_pile.clear()
	hand.clear()
	_run_start_msec = Time.get_ticks_msec() - get_stat("elapsed_sec") * 1000
	artifacts_changed.emit(owned_artifacts.duplicate())
	deck_changed.emit(deck.duplicate())
	crystal_hp_changed.emit(crystal_hp, crystal_max_hp)
	gold_changed.emit(gold)
	run_started.emit()
	return true


## #26：肉鸽控制台兵种数值覆盖层（持久化 user://，跨 run 保留，不影响全局 .tres
var _unit_override: Dictionary = {}
var _override_loaded: bool = false
const UNIT_OVERRIDE_PATH := "user://roguelike_unit_override.json"

## 加载持久化覆盖层（懒加载，首次访问时从user://
func _load_unit_override() -> void:
	if _override_loaded:
		return
	_override_loaded = true
	if not FileAccess.file_exists(UNIT_OVERRIDE_PATH):
		return
	var f := FileAccess.open(UNIT_OVERRIDE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_unit_override = parsed as Dictionary

## 保存覆盖层到 user://
func save_unit_override() -> void:
	var f := FileAccess.open(UNIT_OVERRIDE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入肉鸽覆盖层文件")
		return
	f.store_string(JSON.stringify(_unit_override))
	f.close()

## 设置某兵种某属性覆盖值并持久
func set_unit_override(uid: String, prop: String, value: Variant) -> void:
	_load_unit_override()
	if not _unit_override.has(uid):
		_unit_override[uid] = {}
	_unit_override[uid][prop] = value
	save_unit_override()

## 返回覆盖层原始字典（供控制台 UI 初始值SpinBox
func get_unit_override_raw() -> Dictionary:
	_load_unit_override()
	return _unit_override

## 将覆盖层应用到兵种资源（在单次setup 时对 duplicate 副本调用
func apply_unit_override(res: UnitResource) -> void:
	if res == null:
		return
	_load_unit_override()
	var o: Dictionary = _unit_override.get(res.unit_id, {})
	if o.is_empty():
		return
	if o.has("max_hp"): res.max_hp = int(o["max_hp"])
	if o.has("damage"): res.damage = int(o["damage"])
	if o.has("attack_speed"): res.attack_speed = float(o["attack_speed"])
	if o.has("move_speed"): res.move_speed = float(o["move_speed"])
	if o.has("armor_value"): res.armor_value = int(o["armor_value"])
	if o.has("attack_range"): res.attack_range = float(o["attack_range"])
	if o.has("cost"): res.cost = int(o["cost"])

## 开启一次新的run：重置层数，随机生成起始牌库
## [param ascension] 本局进阶难度等级（-1 = 沿用当前值）
func start_run(hero_id: String = "", ascension: int = -1) -> void:
	load_progress()
	is_active = true
	run_deployed_ids.clear()
	run_stats.clear()
	last_run_stats.clear()
	_run_start_msec = Time.get_ticks_msec()
	if ascension >= 0:
		ascension_level = clampi(ascension, 0, ascension_unlocked)
	else:
		ascension_level = clampi(ascension_level, 0, ascension_unlocked)
	if not hero_id.is_empty():
		selected_hero = hero_id
	elif selected_hero.is_empty():
		selected_hero = "Hero1"
	current_floor = 1
	track_stat_max("max_floor", 1)
	chase_range_px = Constants.ROGUELIKE_CHASE_RANGE
	chase_leash_px = Constants.ROGUELIKE_CHASE_LEASH
	deck.clear()
	deck_upgrade.clear()
	card_cooldowns.clear()
	## 进阶难度按等级扣起始金币与水晶上限
	gold = maxi(50 - ascension_level * ASCENSION_GOLD_PENALTY, 0)
	crystal_max_hp = maxi(int(round(float(Constants.ROGUELIKE_CRYSTAL_HP)
			* (1.0 - float(ascension_level) * ASCENSION_CRYSTAL_PENALTY))), 1)
	crystal_hp = crystal_max_hp
	crystal_revive_used = 0
	owned_artifacts.clear()
	artifacts_changed.emit(owned_artifacts.duplicate())
	## 起始随机牌优先取本局英雄的军团（前缀）；该军团池不足时回落到全兵种池
	var pool: Array[String] = _collect_unit_ids(STARTING_MAX_TIER, get_hero_factions())
	if pool.is_empty():
		pool = _collect_unit_ids(STARTING_MAX_TIER)
	if pool.is_empty():
		push_error("RoguelikeManager: 起始牌池为空，检查 UnitDatabase 是否已加载兵种")
		return
	pool.shuffle()
	for i in range(min(STARTING_DECK_SIZE, pool.size())):
		deck.append(pool[i])
	## 本局所选英雄卡固定进起始牌库（抽到顺序仍随机，由 draw_pile 洗牌决定）
	if not deck.has(selected_hero):
		deck.insert(0, selected_hero)
	deck_changed.emit(deck.duplicate())
	generate_map()
	start_floor()
	run_started.emit()
	save_run()

## 开始当前战斗节点：牌库洗牌进抽牌堆，清空手牌并抽满
func start_floor() -> void:
	draw_pile = deck.duplicate()
	draw_pile.shuffle()
	hand.clear()
	## 上一场战斗打出的军令效果不跨场生效
	active_order_effects.clear()
	card_cooldowns.clear()
	refill_hand()
	track_stat_max("max_floor", current_floor)
	floor_changed.emit(current_floor)

## 把手牌补充到上限，返回本次实际补充的张数
## 抽牌堆空了就补不—这是设计上的资源压力来源
func refill_hand() -> int:
	var drawn: int = 0
	var limit: int = get_hand_limit()
	while hand.size() < limit and not draw_pile.is_empty():
		hand.append(draw_pile.pop_back())
		drawn += 1
	if drawn > 0:
		hand_changed.emit(hand.duplicate())
	return drawn

## 当前手牌上限 = 基础上限 + 文物「鎏金怀表」等 hand_limit_bonus 加成
func get_hand_limit() -> int:
	return maxi(HAND_LIMIT + int(get_artifact_effect_total("hand_limit_bonus")), 1)

## 某卡 ID 是否为军令卡（军令与兵种共用牌库，靠前缀区分）
func is_order_card(card_id: String) -> bool:
	return card_id.begins_with(ORDER_CARD_PREFIX)

## 把军令 ID 包装成牌库里的军令卡 ID
func make_order_card(order_id: String) -> String:
	return ORDER_CARD_PREFIX + order_id

## 从军令卡 ID 取回军令 ID；非军令卡返回空串
func order_id_of(card_id: String) -> String:
	if not is_order_card(card_id):
		return ""
	return card_id.substr(ORDER_CARD_PREFIX.length())

## 打出指定手牌位上的兵种卡，返回兵种资源。
## 索引非法 / 是军令卡 / 资源缺失 / 该卡仍在冷却时返回 null。
## 军令卡请走 play_order_card。
func play_card(index: int) -> UnitResource:
	if index < 0 or index >= hand.size():
		return null
	var card_id: String = hand[index]
	if is_order_card(card_id):
		return null
	if get_card_cooldown(card_id) > 0.0:
		return null
	var res := UnitDatabase.get_unit(card_id) as UnitResource
	if res == null:
		push_error("RoguelikeManager: 手牌兵种 %s 在数据库中不存在" % card_id)
		return null
	run_deployed_ids[card_id] = true
	hand.remove_at(index)
	start_card_cooldown(card_id)
	hand_changed.emit(hand.duplicate())
	return res

## 打出指定手牌位上的军令卡：登记本场效果并广播 order_played。
## 打出只离手（不从 deck 移除），下一个战斗节点重新洗牌仍可抽到。
## 索引非法 / 不是军令卡 / 军令数据缺失 / 冷却中时返回 false 且不做任何变更。
func play_order_card(index: int) -> bool:
	if index < 0 or index >= hand.size():
		return false
	var card_id: String = hand[index]
	if not is_order_card(card_id):
		return false
	if get_card_cooldown(card_id) > 0.0:
		return false
	var order_id: String = order_id_of(card_id)
	var od := ItemDatabase.get_order(order_id)
	if od == null:
		push_error("RoguelikeManager: 军令 %s 在数据库中不存在" % order_id)
		return false
	hand.remove_at(index)
	start_card_cooldown(card_id)
	var key: String = od.effect_type
	active_order_effects[key] = float(active_order_effects.get(key, 0.0)) + od.effect_value
	hand_changed.emit(hand.duplicate())
	order_played.emit(order_id, key, od.effect_value)
	return true

## 某张卡当前剩余冷却（秒），未冷却返回 0
func get_card_cooldown(card_id: String) -> float:
	return maxf(float(card_cooldowns.get(card_id, 0.0)), 0.0)

## 给某张卡挂上冷却（打出时调用）；冷却为 0 时不记录
func start_card_cooldown(card_id: String) -> void:
	var cd: float = RunModifiers.card_cooldown_sec()
	if cd <= 0.0:
		return
	card_cooldowns[card_id] = cd
	card_cooldown_changed.emit(card_id, cd)

## 推进所有卡牌冷却（由战斗层每帧调用），归零即移除并广播
func tick_card_cooldowns(delta: float) -> void:
	if card_cooldowns.is_empty():
		return
	for card_id in card_cooldowns.keys():
		var left: float = float(card_cooldowns[card_id]) - delta
		if left <= 0.0:
			card_cooldowns.erase(card_id)
			card_cooldown_changed.emit(card_id, 0.0)
		else:
			card_cooldowns[card_id] = left
			card_cooldown_changed.emit(card_id, left)

## 立即清空所有手牌冷却（军令「疾行军令」）
func clear_card_cooldowns() -> void:
	for card_id in card_cooldowns.keys():
		card_cooldown_changed.emit(card_id, 0.0)
	card_cooldowns.clear()

## 手牌或抽牌堆里是否还有兵种卡（失败判定只看兵种卡：
## 手里剩一堆军令但无兵可出同样算输）
func has_cards_left() -> bool:
	for card_id in hand:
		if not is_order_card(card_id):
			return true
	for card_id in draw_pile:
		if not is_order_card(card_id):
			return true
	return false

## 向永久牌库添加一张卡。传兵种 ID 即兵种卡；
## 传 ORDER_CARD_PREFIX + 军令 ID（通关奖励三选一抽到军令时）则等价于 add_order。
func add_card(unit_id: String) -> void:
	if unit_id.is_empty():
		return
	deck.append(unit_id)
	deck_changed.emit(deck.duplicate())

## 从永久牌库移除一张卡（休息精简 / 事件损失），不存在则忽略
func remove_card(unit_id: String) -> void:
	if unit_id.is_empty():
		return
	var idx: int = deck.find(unit_id)
	if idx >= 0:
		deck.remove_at(idx)
		deck_changed.emit(deck.duplicate())

## 升级一张卡：每次升一级，单卡召唤人数 +2（线性叠加），最高 CARD_LEVEL_MAX 级。
## 升级按兵种 ID 生效，对牌库中所有同名卡同时生效。
## 返回升级后的卡牌等级（从 1 起）；已达上限时返回当前等级，不再增长
func upgrade_card(unit_id: String) -> int:
	if unit_id.is_empty():
		return 0
	var times: int = int(deck_upgrade.get(unit_id, 0)) + 1
	times = mini(times, CARD_LEVEL_MAX - 1)
	deck_upgrade[unit_id] = times
	deck_changed.emit(deck.duplicate())
	return times + 1

## 返回卡牌当前等级（供 HUD 圆框徽章显示）：未升级为 1，满级为 CARD_LEVEL_MAX
## 等级 = 升级次数 + 1，与 upgrade_card 的存储值保持一致
func get_card_level(unit_id: String) -> int:
	var times: int = int(deck_upgrade.get(unit_id, 0))
	return clampi(times + 1, 1, CARD_LEVEL_MAX)

## 恢复水晶耐久 [param pct] 比例（0~1，如 0.3 = 上限的 30%），夹断到 [0, crystal_max_hp] 并广播。
## 用于休息节点等 run 内恢复场景；水晶耐久是 run 级持久资源，跨战斗保留
func heal_crystal(pct: float) -> void:
	crystal_hp = clampi(int(round(float(crystal_hp) + float(crystal_max_hp) * pct)), 0, crystal_max_hp)
	crystal_hp_changed.emit(crystal_hp, crystal_max_hp)

## 抬高水晶耐久上限并同步补满同等当前值（文物 / 事件用），广播给 HUD 与 hub
func boost_crystal_max_hp(amount: int) -> void:
	if amount <= 0:
		return
	crystal_max_hp += amount
	crystal_hp = mini(crystal_hp + amount, crystal_max_hp)
	crystal_hp_changed.emit(crystal_hp, crystal_max_hp)

## 水晶免死（文物「Doro 的破布娃娃」）：还有剩余次数时消耗一次并返回 true
func consume_crystal_revive() -> bool:
	if crystal_revive_used >= RunModifiers.crystal_revive_charges():
		return false
	crystal_revive_used += 1
	return true

## 当前节点类型对应的敌方数值倍率（精英 / Boss 额外加成，普通节点为 1.0）
func node_stat_mult() -> float:
	match current_node_type():
		NodeType.BOSS:
			return Constants.ROGUELIKE_BOSS_STAT_MULT
		NodeType.ELITE:
			return Constants.ROGUELIKE_ELITE_STAT_MULT
		_:
			return 1.0

## 计算某兵种当前单卡实际召唤数。
## 基础值：units_per_card > 0 时直接采用（数据驱动）；否则按阶层自动 —— tier>=2 出 2 个，其余 3 个。
## 训练强化（休息点）：每次强化该卡召唤人数 +2（线性叠加），最高 CARD_LEVEL_MAX 级。
## 最终夹断到 [1, Constants.ROGUELIKE_POPULATION_CAP]
func get_deploy_count(unit_id: String) -> int:
	var res := UnitDatabase.get_unit(unit_id) as UnitResource
	if res == null:
		return 0
	var base: int = res.units_per_card if res.units_per_card > 0 else (3 if res.tier < 2 else 2)
	var level: int = int(deck_upgrade.get(unit_id, 0))
	var upgrade_bonus: int = level * 2  ## 每次训练强化召唤人数 +2
	## 文物「战鼓」与军令「大点兵」提供的额外召唤数，在强化之后加算（加法收益不随强化膨胀
	var bonus: int = int(get_artifact_effect_total("deploy_count_bonus") + get_order_effect_total("deploy_count_bonus"))
	return clampi(base + upgrade_bonus + bonus, 1, Constants.ROGUELIKE_POPULATION_CAP)

## 增加金币（用于商店消费），下限夹断为 0，变化时广播 gold_changed
## 正向变动同时计入本局「累计获得金币」统计
func add_gold(amount: int) -> void:
	if amount > 0:
		add_stat("gold_earned", amount)
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)

## 当前金币余额
func get_gold() -> int:
	return gold

## 金币是否够付 [param amount]
func can_afford(amount: int) -> bool:
	return gold >= amount

## 扣除金币；余额不足时不扣款并返回 false
func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

## 获得一件文物（永久被动，允许重复持有以叠加效果
func add_artifact(artifact_id: String) -> void:
	if artifact_id.is_empty():
		return
	owned_artifacts.append(artifact_id)
	artifacts_changed.emit(owned_artifacts.duplicate())

## 获得一张军令卡：以 ORDER_CARD_PREFIX + 军令 ID 的形式加入永久牌库，
## 之后与兵种卡一起洗进抽牌堆、占手牌位，由 play_order_card 打出。
func add_order(order_id: String) -> void:
	if order_id.is_empty():
		return
	deck.append(make_order_card(order_id))
	deck_changed.emit(deck.duplicate())

## 当前牌库中已持有的军令 ID 列表（去重前的原始顺序，供商店排除已有 / hub 展示）
func get_owned_order_ids() -> Array[String]:
	var result: Array[String] = []
	for card_id in deck:
		if is_order_card(card_id):
			result.append(order_id_of(card_id))
	return result

## 汇总本场已打出军令中指定[param effect_type] 的累计值（未打出过返回 0
func get_order_effect_total(effect_type: String) -> float:
	return float(active_order_effects.get(effect_type, 0.0))

## 汇总所有已持有文物中指定 [param effect_type] 的效果值总和
## 战斗层要用某个加成时统一走这里查，避免各处散落重复判断
func get_artifact_effect_total(effect_type: String) -> float:
	var total: float = 0.0
	for artifact_id in owned_artifacts:
		var art := ItemDatabase.get_artifact(artifact_id)
		if art != null and art.effect_type == effect_type:
			total += art.effect_value
	return total

## 计算商品的实际售价（应用「军需官的账本」等折扣类文物）
func get_shop_price(base_cost: int) -> int:
	var discount: float = clampf(get_artifact_effect_total("shop_discount_pct"), 0.0, 0.8)
	return maxi(int(round(float(base_cost) * (1.0 - discount))), 1)

## 随机抽一张不超过 max_tier 的兵种ID（休息加/ 事件），池空返回 ""
func roll_random_unit_id(max_tier: int) -> String:
	var pool: Array[String] = _collect_unit_ids(max_tier)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

## 按指定阶层上限产出候选奖励卡（宝箱/商店用，与roll_reward_choices 同构
func roll_reward_choices_tier(max_tier: int) -> Array[String]:
	var pool: Array[String] = _collect_unit_ids(max_tier)
	var result: Array[String] = []
	if pool.is_empty():
		return result
	pool.shuffle()
	for i in range(min(REWARD_CHOICE_COUNT, pool.size())):
		result.append(pool[i])
	return result

## 随机产出本层通关的候选奖励卡（可能与牌库已有卡重复，重复即视为该兵种多一张）
## 英雄军团（前缀）优先：候选里至少给一张本军团卡，其余照全池随机
## 军令合并进牌库后，候选里有 ORDER_REWARD_CHANCE 的概率把最后一格换成一张未持有的军令卡
func roll_reward_choices() -> Array[String]:
	var max_tier: int = _max_tier_for_floor()
	var result: Array[String] = []
	var faction_pool: Array[String] = _collect_unit_ids(max_tier, get_hero_factions())
	if not faction_pool.is_empty():
		faction_pool.shuffle()
		result.append(faction_pool[0])
	var pool: Array[String] = _collect_unit_ids(max_tier)
	if pool.is_empty():
		return _inject_order_choice(result)
	pool.shuffle()
	for uid in pool:
		if result.size() >= REWARD_CHOICE_COUNT:
			break
		if uid in result:
			continue
		result.append(uid)
	return _inject_order_choice(result)

## 通关奖励里出现军令卡的概率
const ORDER_REWARD_CHANCE: float = 0.25

## 按概率把候选列表的最后一格替换成一张未持有的军令卡（军令池为空时原样返回）。
## 候选不足一格时改为追加，保证概率命中就一定看得到军令卡。
func _inject_order_choice(choices: Array[String]) -> Array[String]:
	if randf() >= ORDER_REWARD_CHANCE:
		return choices
	var rolled := ItemDatabase.roll_orders(1, get_owned_order_ids())
	if rolled.is_empty():
		return choices
	var card_id: String = make_order_card(rolled[0].order_id)
	if choices.is_empty():
		choices.append(card_id)
	else:
		choices[choices.size() - 1] = card_id
	return choices

## 结束本次 run，清空所有运行态（selected_hero 保留，供结算界面「再来一局」沿用同英雄）
func end_run() -> void:
	is_active = false
	current_floor = 1
	gold = 0
	deck.clear()
	deck_upgrade.clear()
	draw_pile.clear()
	hand.clear()
	card_cooldowns.clear()
	map_nodes.clear()
	owned_artifacts.clear()
	active_order_effects.clear()
	run_deployed_ids.clear()
	crystal_hp = 0
	crystal_max_hp = 0
	crystal_revive_used = 0
	current_node_index = -1
	run_stats.clear()
	clear_save()

## 当前手牌的展示数据列表（UI 建卡用），每项：
##   { "card_id", "hand_index", "is_order", "unit_res"(兵种卡), "order_data"(军令卡) }
## hand_index 是该卡在 hand 里的真实下标 —— 数据缺失的卡会被跳过，
## 列表下标与手牌下标可能错位，UI 打牌必须用 hand_index 而不是列表下标。
func get_hand_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(hand.size()):
		var card_id: String = hand[i]
		if is_order_card(card_id):
			var od := ItemDatabase.get_order(order_id_of(card_id))
			if od != null:
				result.append({"card_id": card_id, "hand_index": i, "is_order": true, "order_data": od})
		else:
			var res := UnitDatabase.get_unit(card_id) as UnitResource
			if res != null:
				result.append({"card_id": card_id, "hand_index": i, "is_order": false, "unit_res": res})
	return result

## 获取当前手牌里的兵种资源列表（兼容旧调用；军令卡会被跳过）
func get_hand_resources() -> Array[UnitResource]:
	var result: Array[UnitResource] = []
	for card_id in hand:
		if is_order_card(card_id):
			continue
		var res := UnitDatabase.get_unit(card_id) as UnitResource
		if res != null:
			result.append(res)
	return result

## 生成分支地图：多层节点，路径可分叉、可汇聚，最终收束到单一 Boss
##
## 关卡结构（floor_index 从 0 起，共 MAP_FLOORS=10 层）：
##   第 0 层（入口层，4 节点）固定为 战斗 / 休息 / 商店 / 宝箱，左右顺序每局洗牌
##   第 1~7 层 按 FLOOR_TYPE_WEIGHTS 的层段权重随机，生成后跑 _enforce_floor_rules 保底修补
##   第 8 层（Boss 前，2 节点）固定为 休息 / 商店 —— 决战前必给回血与补给
##   第 9 层 Boss（唯一节点，全部路径收束于此）
## 每层节点与上下层按横向 proximity 连边，形成自然的分支 / 汇聚结构。
##
## 同层节点最小横向间距（x_ratio 单位）：生成时强制保证同层相邻节点间距 >= 此值，
## 杜绝两个节点渲染到同一像素位置。0.16 在小屏也对应 ~96px，远大于节点直径 54px
const MAP_MIN_X_GAP: float = 0.16

func generate_map() -> void:
	map_nodes.clear()
	current_node_index = -1
	## 固定层的类型序列先洗牌：保证「四种都有」的同时，每局左右摆放顺序不同
	var entry_types: Array[int] = ENTRY_FLOOR_TYPES.duplicate()
	entry_types.shuffle()
	var pre_boss_types: Array[int] = PRE_BOSS_FLOOR_TYPES.duplicate()
	pre_boss_types.shuffle()
	## 1. 创建节点并定类型
	for f in range(MAP_FLOORS):
		var count: int = NODES_PER_FLOOR[f]
		for s in range(count):
			var node := RoguelikeMapNode.new()
			node.floor_index = f
			node.slot_index = s
			## 在层内均匀分布，并加入小幅随机抖动，使路径看起来更自然
			var base_ratio: float = float(s + 1) / float(count + 1)
			var jitter: float = randf_range(-0.12, 0.12)
			## 奇偶层横向错位，避免上下层节点正对形成竖直线
			var stagger: float = 0.09 if (f % 2 == 1) else 0.0
			node.x_ratio = clampf(base_ratio + stagger + jitter, MAP_X_MIN, MAP_X_MAX)
			if f == 0:
				node.node_type = entry_types[s % entry_types.size()]
			elif f == MAP_FLOORS - 1:
				node.node_type = NodeType.BOSS
			elif f == MAP_FLOORS - 2:
				node.node_type = pre_boss_types[s % pre_boss_types.size()]
			else:
				node.node_type = _roll_node_type(f)
			map_nodes.append(node)
	## 1.5 同层节点横向去重叠：保证相邻节点 x_ratio 间距 >= MAP_MIN_X_GAP，杜绝渲染重叠
	_separate_floor_nodes()
	## 2. 保底规则修补（每层至少一场战斗/ 同层类型不单一 / 三层内必有休息）
	_enforce_floor_rules()
	## 3. 类型定稿后才推算难度参数，避免修补后 tier / 波数与类型对不上
	for node in map_nodes:
		node.enemy_tier = _node_enemy_tier(node.floor_index, node.node_type)
		node.wave_count = _node_wave_count(node.floor_index, node.node_type)
		node.is_boss = (node.node_type == NodeType.BOSS)
	## 4. 按proximity 在相邻层之间连边
	for f in range(MAP_FLOORS - 1):
		_connect_floor(f)

## 同层节点横向布局的合法区间（x_ratio）
const MAP_X_MIN: float = 0.08
const MAP_X_MAX: float = 0.92

## 同层节点横向去重叠：每层按 x_ratio 排序后先从左往右推（下界 MAP_X_MIN），
## 再从右往左收（上界 MAP_X_MAX），保证相邻间距 >= MAP_MIN_X_GAP 且整体落在合法区间内。
## 两遍之后仍塞不下（节点数过多）时退化为区间内等距均分。
## 连边（_connect_floor）在此之后执行，因此 x_ratio 同时决定连接关系与显示位置，二者一致。
func _separate_floor_nodes() -> void:
	for f in range(MAP_FLOORS):
		var idx: Array[int] = _floor_node_indices(f)
		if idx.is_empty():
			continue
		if idx.size() == 1:
			map_nodes[idx[0]].x_ratio = clampf(map_nodes[idx[0]].x_ratio, MAP_X_MIN, MAP_X_MAX)
			continue
		idx.sort_custom(func(a: int, b: int) -> bool: return map_nodes[a].x_ratio < map_nodes[b].x_ratio)
		var last: int = idx.size() - 1
		## 从左往右推：首个不低于 MAP_X_MIN，其余不小于「前一个 + 最小间距」
		for i in range(idx.size()):
			var lower: float = MAP_X_MIN if i == 0 else map_nodes[idx[i - 1]].x_ratio + MAP_MIN_X_GAP
			map_nodes[idx[i]].x_ratio = maxf(map_nodes[idx[i]].x_ratio, lower)
		## 从右往左收：末个不超过 MAP_X_MAX，其余不大于「后一个 − 最小间距」
		## 注意不能在此之后再做整体 clampf —— 那会把越界的末节点拉回 MAX 却不同步左邻，重新造成重叠
		for i in range(last, -1, -1):
			var upper: float = MAP_X_MAX if i == last else map_nodes[idx[i + 1]].x_ratio - MAP_MIN_X_GAP
			map_nodes[idx[i]].x_ratio = minf(map_nodes[idx[i]].x_ratio, upper)
		## 兜底：区间宽度不足以容纳全部节点时等距均分（当前 NODES_PER_FLOOR 最多 4，正常不会触发）
		if _floor_has_overlap(idx):
			var step: float = (MAP_X_MAX - MAP_X_MIN) / float(last)
			for i in range(idx.size()):
				map_nodes[idx[i]].x_ratio = MAP_X_MIN + step * float(i)

## 该层（已按 x_ratio 排序的下标数组）是否仍存在小于最小间距的相邻对
func _floor_has_overlap(sorted_idx: Array[int]) -> bool:
	for i in range(1, sorted_idx.size()):
		var gap: float = map_nodes[sorted_idx[i]].x_ratio - map_nodes[sorted_idx[i - 1]].x_ratio
		if gap < MAP_MIN_X_GAP - 0.0001:
			return true
	return false

## 生成后修补中间层类型，保证关卡节奏不失控。三条硬性规则：
##   规则 1：每个中间层至少一个战斗类节点（战斗 / 精英），杜绝整层白嫖
##   规则 2：>=3 节点的层不能全是同一类型，至少两种（避免「四个事件」这类极端地图）
##   规则 3 连续 REST_GUARANTEE_SPAN 层内必须出现休息点，否则强制改写一个非战斗节点
## 只修补中间层：入口层到Boss前层是固定编排，Boss 层不可改
func _enforce_floor_rules() -> void:
	var floors_since_rest: int = 0
	for f in range(1, MAP_FLOORS - 2):
		var indices: Array[int] = _floor_node_indices(f)
		if indices.is_empty():
			continue
		_ensure_combat_on_floor(indices)
		_ensure_type_variety(indices)
		if _floor_has_type(indices, NodeType.REST):
			floors_since_rest = 0
			continue
		floors_since_rest += 1
		if floors_since_rest >= REST_GUARANTEE_SPAN:
			_force_rest_on_floor(indices)
			floors_since_rest = 0

## 该层是否存在指定类型的节
func _floor_has_type(indices: Array[int], type: int) -> bool:
	for i in indices:
		if map_nodes[i].node_type == type:
			return true
	return false

## 规则 1：该层没有任何战斗类节点时，随机挑一个改写为普通战
func _ensure_combat_on_floor(indices: Array[int]) -> void:
	if _floor_has_type(indices, NodeType.COMBAT) or _floor_has_type(indices, NodeType.ELITE):
		return
	map_nodes[indices[randi() % indices.size()]].node_type = NodeType.COMBAT

## 规则 2：≥3 节点的层若类型完全相同，把最后一个改成异类，保证玩家有得
func _ensure_type_variety(indices: Array[int]) -> void:
	if indices.size() < 3:
		return
	var first: int = map_nodes[indices[0]].node_type
	for i in indices:
		if map_nodes[i].node_type != first:
			return
	var last: int = indices[indices.size() - 1]
	map_nodes[last].node_type = NodeType.EVENT if first == NodeType.COMBAT else NodeType.COMBAT

## 规则 3：强制在该层放一个休息点，优先改写非战斗节点；
## 全是战斗时也允许改一个（改后该层仍至少剩一场战斗）
func _force_rest_on_floor(indices: Array[int]) -> void:
	if indices.size() < 2:
		return  ## 单节点层是必经之路，改掉会切断唯一通路
	var candidates: Array[int] = []
	for i in indices:
		var t: int = map_nodes[i].node_type
		if t != NodeType.COMBAT and t != NodeType.ELITE:
			candidates.append(i)
	if candidates.is_empty():
		candidates = indices.duplicate()
	map_nodes[candidates[randi() % candidates.size()]].node_type = NodeType.REST

## 连接第 [floor_idx] 层与下一层的边，保证：
##   - 下一层每个节点至少有一个父节点（不会 unreachable）
##   - 当前层每个节点至少有一个子节点（不会死路）
##   - 连边目标在横向窗口内随机选取（不是固定「最规整等比」），刻意让每条边斜率不同，
##     杜绝平行斜线；配合奇偶层错位，进一步避免竖线
func _connect_floor(floor_idx: int) -> void:
	var current: Array[int] = _floor_node_indices(floor_idx)
	var nxt: Array[int] = _floor_node_indices(floor_idx + 1)
	if current.is_empty() or nxt.is_empty():
		return

	current.sort_custom(func(a: int, b: int) -> bool: return map_nodes[a].x_ratio < map_nodes[b].x_ratio)
	nxt.sort_custom(func(a: int, b: int) -> bool: return map_nodes[a].x_ratio < map_nodes[b].x_ratio)

	var m: int = current.size()
	var n: int = nxt.size()

	## 每个上层节点有1~2个下层节点，目标在横向窗口内随机挑，制造varied 斜率
	for i in range(m):
		var src_x: float = map_nodes[current[i]].x_ratio
		var window: Array[int] = []
		for k in range(n):
			if absf(map_nodes[nxt[k]].x_ratio - src_x) <= 0.35:
				window.append(nxt[k])
		if window.is_empty():
			window = nxt.duplicate()
		var primary: int = window[randi() % window.size()]
		_add_edge(current[i], primary)
		if window.size() > 1 and randf() < 0.7:
			var second: int = window[randi() % window.size()]
			var tries: int = 0
			while second == primary and tries < 5:
				second = window[randi() % window.size()]
				tries += 1
			if second != primary:
				_add_edge(current[i], second)

	## 安全网：确保每个下层节点至少有一个父节点
	for k in range(n):
		if _parent_count(nxt[k], current) == 0:
			var src: int = _closest_node(nxt[k], current)
			if src >= 0:
				_add_edge(src, nxt[k])

	## 安全网：确保每个上层节点至少有一个子节点
	for i in range(m):
		if map_nodes[current[i]].next.is_empty():
			var dst: int = _closest_node(current[i], nxt)
			if dst >= 0:
				_add_edge(current[i], dst)

	for src in current:
		map_nodes[src].next.sort()

## 安全地添加一条有向边（去重）
func _add_edge(src: int, dst: int) -> void:
	if not (dst in map_nodes[src].next):
		map_nodes[src].next.append(dst)

## 统计某下层节点在当前层中有几个父节点
func _parent_count(dst: int, candidates: Array[int]) -> int:
	var count: int = 0
	for src in candidates:
		if dst in map_nodes[src].next:
			count += 1
	return count

## 返回指定层的所有节点下
func _floor_node_indices(floor_idx: int) -> Array[int]:
	var result: Array[int] = []
	for i in range(map_nodes.size()):
		if map_nodes[i].floor_index == floor_idx:
			result.append(i)
	return result

## 在候选节点中找出第[src_idx] 横向最接近的节点下
func _closest_node(src_idx: int, candidates: Array[int]) -> int:
	if candidates.is_empty():
		return -1
	var src: RoguelikeMapNode = map_nodes[src_idx]
	var best: int = -1
	var best_dist: float = 99999.0
	for idx in candidates:
		var dst: RoguelikeMapNode = map_nodes[idx]
		var dist: float = absf(dst.x_ratio - src.x_ratio)
		if dist < best_dist:
			best_dist = dist
			best = idx
	return best

## 当前可前往的节点下标（路径锁定：只能走已连通的下一层节点）
func get_reachable_node_indices() -> Array[int]:
	if current_node_index < 0:
		var result: Array[int] = []
		for i in range(map_nodes.size()):
			if map_nodes[i].floor_index == 0:
				result.append(i)
		return result
	if current_node_index >= map_nodes.size():
		return []
	return map_nodes[current_node_index].next.duplicate()

## 选定一个节点（进入该节点内容前调用），标记为已访问。
## 刻意不在此处存档：存档点只放在「节点内容结算完成」处（战斗 _finish_node /
## 非战斗 _after_noncombat）。否则战斗中途退出后，磁盘上的节点已是 visited，
## 读档会直接跳过这场战斗 —— 与「战斗中退出回退到本节点开始前」的约定相反。
func select_node(index: int) -> void:
	if index < 0 or index >= map_nodes.size():
		return
	current_node_index = index
	map_nodes[index].visited = true
	add_stat("nodes_cleared")

## 获取指定节点数据；下标非法返回null
func get_map_node(index: int) -> RoguelikeMapNode:
	if index < 0 or index >= map_nodes.size():
		return null
	return map_nodes[index]

## 当前所在节点的类型（未选节点返回-1
func current_node_type() -> int:
	if current_node_index < 0 or current_node_index >= map_nodes.size():
		return -1
	return map_nodes[current_node_index].node_type

## 按层段权重表加权随机一个中间层节点类型（层越深，精英越多、纯战斗越少）
## 权重全部来自 FLOOR_TYPE_WEIGHTS，调节节奏不需要动这段逻辑
func _roll_node_type(floor_idx: int) -> int:
	var weights: Array = []
	for row in FLOOR_TYPE_WEIGHTS:
		if floor_idx <= int(row["max_floor"]):
			weights = row["weights"] as Array
			break
	if weights.size() != WEIGHTED_TYPES.size():
		push_error("RoguelikeManager: FLOOR_TYPE_WEIGHTS 权重列数与 WEIGHTED_TYPES 不一致")
		return NodeType.COMBAT
	var total: int = 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return NodeType.COMBAT
	var roll: int = randi() % total
	var acc: int = 0
	for i in range(WEIGHTED_TYPES.size()):
		acc += int(weights[i])
		if roll < acc:
			return WEIGHTED_TYPES[i]
	return NodeType.COMBAT

## 按节点所在层与类型推算敌军阶层上限（越深越高，精英 / Boss 额外加成）
## 入口层精英特例：压到 tier 2，使「开局白嫖文物」的风险落在玩家能承受的范围
func _node_enemy_tier(floor_idx: int, type: int) -> int:
	if type == NodeType.BOSS:
		return 4
	if type == NodeType.ELITE:
		if floor_idx == 0:
			return 2
		return clampi(2 + int(floor_idx / 3.0), 2, 4)
	return clampi(1 + int(floor_idx / 2.0), 1, 4)

## 按节点所在层与类型推算波数（精英/Boss 多于普通战斗）
## 入口层精英同样减波（3 波），避免开局第一场就打4波劝退
func _node_wave_count(floor_idx: int, type: int) -> int:
	if type == NodeType.BOSS:
		return 5
	if type == NodeType.ELITE:
		return 3 if floor_idx == 0 else 4
	return clampi(2 + floor_idx, 2, 5)

## 收集阶层不超过 max_tier 的全部兵种 ID；英雄卡（Hero 前缀）一律排除，
## 英雄只由 start_run 按 selected_hero 显式插入，兼顾「敌方不刷英雄」与「奖励不出英雄」。
## [param factions] 非空时只保留这些前缀的兵种（英雄军团倾向）
func _collect_unit_ids(max_tier: int, factions: Array[String] = []) -> Array[String]:
	var result: Array[String] = []
	for unit in UnitDatabase.unit_list:
		var res := unit as UnitResource
		if res == null:
			continue
		if UnitDatabase.is_hero_unit(res.unit_id):
			continue
		if not factions.is_empty() and not (res.unit_id.left(1) in factions):
			continue
		if res.tier <= max_tier:
			result.append(res.unit_id)
	return result

## 当前层数允许出现的最高兵种阶层（层数越深越可能刷到高阶卡
func _max_tier_for_floor() -> int:
	return clampi(1 + current_floor, 1, 4)
