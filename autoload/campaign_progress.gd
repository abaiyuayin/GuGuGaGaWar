extends Node  ## 继承�?Node 节点�?## 战役进度管理�?��全局单例�?## 负责管理战役模式的关卡解锁��难度完成进度��兵种解锁，以及进度数据的持久化保存与加�?## 战役模式�?10 �?��卡，每个关卡�?3 �?��度（0=�?��? 1=困难, 2=地狱�?
## 朢�大关卡数（战役共 10 关）
const MAX_LEVEL: int = 10
## 默�?已解锁的关卡编号（初始仅解锁�?1 关）
const DEFAULT_UNLOCKED: int = 1
## 难度总数（普�?困难/地狱�?
const DIFFICULTY_COUNT: int = 3

## 已完成关卡的列表（存储关卡编号，旧字段保留兼容）
var completed_levels: Array = []
## 当前已解锁到的关卡编号（玩�?�?��战的朢�高关卡）
var unlocked_level: int = DEFAULT_UNLOCKED
## 关卡难度完成进度字典：key=关卡编号, value=已完成的难度编号数组
var level_difficulty_progress: Dictionary = {}

## 节点就绪时自动调�?��autoload 在游戏启动时加载�?## 霢�求：每�?运�?都清空上丢�次的战役存档状况（关卡解�?战功/星星/已购兵�?/成就），
## 战役模式每�?都从�?1 关重新开始，不保留上次的通过记录�?## 注意：�?重置同时作用于打包后玩�?每�?打开游戏（用户拍板，不持久化战役进度）��?## 例�?：Doro �?��计数（成就��为了�?润�?！��）存独�?meta_stats.cfg，跨�?��持久
func _ready() -> void:
	reset_progress()  ## 清空并保存一份空存档，�?盖上次进�?
	_load_meta_stats()  ## 持久计数不随战役重置，单�?���?
## ============================================================
## 持久计数（独立于战役进度，不�?reset_progress 清零�?## 成就「为了�?润�?！��：�??�?�� 500 �?Doro 兵�?（用户拍板：战役模式统�? + 跨启动持久）
## ============================================================
const META_SAVE_PATH := "user://meta_stats.cfg"

## �??�?�� D 系兵种�?数（战役模式每�?部署 D 前缀兵�? +1，�? Achievements.record_player_deploy�?
var _doro_purchases: int = 0
## ?累计部署 G 系（咕嘎）兵种?数?成就「咕嘎军团」解锁 Hero4 咕咕嘎嘎Hero 用）
var _gugu_purchases: int = 0
## ?累计部署 N 系（糯糯）兵种?数?成就「糯糯大军」解锁 Hero5 糯糯Hero 用）
var _nuo_purchases: int = 0

func _load_meta_stats() -> void:
	var config = ConfigFile.new()
	if config.load(META_SAVE_PATH) == OK:
		_doro_purchases = config.get_value("meta", "doro_purchases", 0)
		_gugu_purchases = config.get_value("meta", "gugu_purchases", 0)
		_nuo_purchases = config.get_value("meta", "nuo_purchases", 0)

func _save_meta_stats() -> void:
	var config = ConfigFile.new()
	config.set_value("meta", "doro_purchases", _doro_purchases)
	config.set_value("meta", "gugu_purchases", _gugu_purchases)
	config.set_value("meta", "nuo_purchases", _nuo_purchases)
	config.save(META_SAVE_PATH)

## ? D 系购买?数并落盘，返回累加后的数（供成就阈判定）
func add_doro_purchases(amount: int) -> int:
	if amount <= 0:
		return _doro_purchases
	_doro_purchases += amount
	_save_meta_stats()
	return _doro_purchases

func get_doro_purchases() -> int:
	return _doro_purchases

## ?累计部署 G 系（咕嘎）兵种次数并落盘，返回累加后的次数（供成就「咕嘎军团」判定）
func add_gugu_purchases(amount: int) -> int:
	if amount <= 0:
		return _gugu_purchases
	_gugu_purchases += amount
	_save_meta_stats()
	return _gugu_purchases

func get_gugu_purchases() -> int:
	return _gugu_purchases

## ?累计部署 N 系（糯糯）兵种次数并落盘，返回累加后的次数（供成就「糯糯大军」判定）
func add_nuo_purchases(amount: int) -> int:
	if amount <= 0:
		return _nuo_purchases
	_nuo_purchases += amount
	_save_meta_stats()
	return _nuo_purchases

func get_nuo_purchases() -> int:
	return _nuo_purchases

## 加载战役进度（�?有方法）
func _load_progress() -> void:
	var config = ConfigFile.new()
	if config.load("user://campaign_progress.cfg") == OK:
		completed_levels = config.get_value("progress", "completed", [])
		unlocked_level = config.get_value("progress", "unlocked", DEFAULT_UNLOCKED)
		level_difficulty_progress = config.get_value("progress", "level_difficulty_progress", {})
		_merit = config.get_value("progress", "merit", 0)
		_stars = config.get_value("progress", "stars", 0)
		_purchased_advanced = config.get_value("progress", "purchased_advanced", {})
		_levels_first_cleared = config.get_value("progress", "levels_first_cleared", {})
		_achievements = config.get_value("progress", "achievements", {})
		_total_kills = config.get_value("progress", "total_kills", 0)
	else:
		completed_levels = []
		unlocked_level = DEFAULT_UNLOCKED
		level_difficulty_progress = {}
	## 迁移旧数�?���?completed_levels 非空�?level_difficulty_progress 为空，将旧��关记录迁移为新格式
	if not completed_levels.is_empty() and level_difficulty_progress.is_empty():
		for level in completed_levels:
			level_difficulty_progress[level] = [0]
	## 迁移旧进度：旧存档无首���?录时，按已��关关卡补发战功与星�?	if not completed_levels.is_empty() and _levels_first_cleared.is_empty():
		for level in completed_levels:
			_award_first_clear(level)

## 保存战役进度（�?有方法）
func _save_progress() -> void:
	var config = ConfigFile.new()
	config.set_value("progress", "completed", completed_levels)
	config.set_value("progress", "unlocked", unlocked_level)
	config.set_value("progress", "level_difficulty_progress", level_difficulty_progress)
	config.set_value("progress", "merit", _merit)
	config.set_value("progress", "stars", _stars)
	config.set_value("progress", "purchased_advanced", _purchased_advanced)
	config.set_value("progress", "levels_first_cleared", _levels_first_cleared)
	config.set_value("progress", "achievements", _achievements)
	config.set_value("progress", "total_kills", _total_kills)
	config.save("user://campaign_progress.cfg")

func get_unlocked_level() -> int:
	return unlocked_level

func is_level_completed(level: int) -> bool:
	return level in completed_levels

## 标�?指定关卡为已完成（旧接口，保留兼容，仅�?录关卡完成状态）
func mark_level_completed(level: int) -> void:
	if level not in completed_levels:
		completed_levels.append(level)
		completed_levels.sort()
		_award_first_clear(level)
	if level >= unlocked_level and level < MAX_LEVEL:
		unlocked_level = level + 1
	_save_progress()

func get_completed_difficulties(level: int) -> Array:
	return level_difficulty_progress.get(level, [])

func get_star_count(level: int) -> int:
	return level_difficulty_progress.get(level, []).size()

func is_difficulty_completed(level: int, difficulty: int) -> bool:
	var completed: Array = level_difficulty_progress.get(level, [])
	return difficulty in completed

## #11：是否已通关全部 10 关的指定难度（战役难度�?义：0=�?��?/ 1=困难 / 2=地狱�?## 用于「全部十关困难��关后自动解锁开发��模式��判�?
func is_all_levels_difficulty_completed(difficulty: int) -> bool:
	for lv in range(1, MAX_LEVEL + 1):
		if not is_difficulty_completed(lv, difficulty):
			return false
	return true

func get_unlocked_difficulty(level: int) -> int:
	if level > unlocked_level:
		return -1
	var completed: Array = level_difficulty_progress.get(level, [])
	var next_diff: int = completed.size()
	return mini(next_diff, DIFFICULTY_COUNT - 1)

## 标�?指定关卡的指定难度为已完�?
func mark_difficulty_completed(level: int, difficulty: int) -> void:
	if not level_difficulty_progress.has(level):
		level_difficulty_progress[level] = []
	var completed: Array = level_difficulty_progress[level]
	if difficulty not in completed:
		completed.append(difficulty)
		completed.sort()
	if level not in completed_levels:
		completed_levels.append(level)
		completed_levels.sort()
		_award_first_clear(level)
		if level >= unlocked_level and level < MAX_LEVEL:
			unlocked_level = level + 1
	## #11：全�?10 关困难（difficulty=1）��关后自动解锁开发��模�?	## 判定放在数据真相源内，任何��关入口（结算界�?/ 获得胜利按钮）都�?��触发
	if difficulty == 1 and is_all_levels_difficulty_completed(1):
		DevMode.set_enabled(true)
	_save_progress()

func reset_progress() -> void:
	completed_levels = []
	unlocked_level = DEFAULT_UNLOCKED
	level_difficulty_progress = {}
	_merit = 0
	_stars = 0
	_purchased_advanced = {}
	_levels_first_cleared = {}
	_achievements = {}
	_total_kills = 0
	_save_progress()

## ============================================================
## 兵�?解锁系统（D 双轨·休闲�?v3�?## 常驻5 + 关卡解锁10 + 战功�?��7；战功���?1100 = 7 高级花费合�?，刚好花�?## 星星每关首��?+1（上�?10），仅作声望�?��

## 全部�?��锁兵�?ID（常�?22 + 星星解锁英雄 Hero1 + 成就门控英雄 Hero2 = 24
const ALL_UNITS: Array[String] = [
	"G1","G2","G3","G4","G5","G6",
	"D1","D2","D3","D4","D5","D6",
	"F1","F2","F3","F4","F5",
	"N1","N2","N3","N4","N5",
	"Hero4",  ## 咕嘎嘎Hero：隐藏成就「咕嘎军团」解锁后进入解锁池，需 20 颗星
	"Hero5",  ## 糯糯Hero：隐藏成就「糯糯大军」解锁后进入解锁池，需 20 颗星
	"Hero1",  ## 爱弥�?��特殊英雄，需�?? 20 颗星解锁（�? STAR_UNLOCK�?
	"Hero2",  ## Doro勇士：隐藏成就��为了�?润�?！��解锁后进入解锁池，霢� 20 颗星（�? STAR_UNLOCK/ACHIEVEMENT_GATED_UNITS�?
]

## 弢�屢�常驻�? �?��
const BASE_UNITS: Array[String] = ["G1","G2","G3","D1","D3"]

## #7�?026-08-09 用户拍板）：困难/地狱专用编成池����D3（2026-08-12 还原）（D2 免购买直接可�?���?## �?��弢�屢�常驻与关卡解锁兵种，不含战功�?��（ADVANCED_COST）与星星英雄（STAR_UNLOCK）��?
const HARD_BASE_UNITS: Array[String] = ["G1","G2","G3","D1","D3"]

## 每关首�?通关解锁的普通兵种（GDFN 顺序，不混搭�?
const LEVEL_NORMAL_UNIT: Dictionary = {
	1:"G4", 2:"D4", 3:"F1", 4:"F2", 5:"F3",
	6:"F5", 7:"N1", 8:"N2", 9:"N3", 10:"N4"}

## #3（2026-08-12）：敌方高级兵种按关卡逐步解锁（与玩家进度同步，避免 N5 级跳）。
## 仅战役模式敌方固定编成使用；从第 3 关起每关追加一个高级兵种，第 9 关集齐全部 7 个。
const ENEMY_ADVANCED_UNITS_BY_LEVEL: Dictionary = {
	3:"D2", 4:"G5", 5:"D5", 6:"F4", 7:"N5", 8:"G6", 9:"D6"}

## 战功�?��的高级兵种及其花�?## #17�?026-08-11 用户拍板）：关刀�?D2 100�?50�? �?��
## #24�?026-08-07 用户拍板）：恢�?分档�?## D2=150�? �?�� / G5·D5·F4·N5=150�? �?�� / G6·D6=200�? �?��
## 150×5 + 200×2 = 1150，��关朢�后一关时�??战功恰为 1150（每关�?�?115，�? MERIT_PER_LEVEL�?
const ADVANCED_COST: Dictionary = {
	"D2":150, "G5":150, "D5":150, "F4":150, "N5":150, "G6":200, "D6":200}

## 每关首��战功（任意难度首�?通关发放丢�次）
## #17�?026-08-11）：D2 上调�?150 后��花�?1150，每关�?�?110�?15�?0×115=1150），
## 通关朢�后一关时�??恰好 1150，买�?7 �?��级兵，不早不晚��?
const MERIT_PER_LEVEL: Dictionary = {
	1:115, 2:115, 3:115, 4:115, 5:115, 6:115, 7:115, 8:115, 9:115, 10:115}
## boss 关编号：突破（�?次��关）可获得额�?战功
const BOSS_LEVELS: Array[int] = [3, 6, 10]

## 星星解锁的特殊兵种（不�?入常�?22 兵�?编成，需�??星星达阈值才解锁�?## 爱弥�?��Hero1）需 20 颗星（用�?2026-08-09 要求�?10 改为 20�?## Doro勇士（Hero2）同样需 20 颗星，且霢�先解锁隐藏成就��为了�?润�?！��（�?ACHIEVEMENT_GATED_UNITS�?
const STAR_UNLOCK: Dictionary = {"Hero1": 20, "Hero2": 20, "Hero4": 20, "Hero5": 20}  ## 2026-08-21 恢复咕嘎/糯糯的 20 星门槛

## 成就门控兵�?：先解锁指定成就，兵种才进入�?��锁池（配�?STAR_UNLOCK 的星星门槛）
## Doro勇士（Hero2）需隐藏成就「为了�?润�?！��（�??�?�� 500 �?Doro）达成后方可�?
const ACHIEVEMENT_GATED_UNITS: Dictionary = {"Hero2": "for_orange", "Hero4": "gugu_legion", "Hero5": "nuo_legion"}

## 运�?态（持久化到 user://campaign_progress.cfg�?
var _levels_first_cleared: Dictionary = {}
var _merit: int = 0
var _stars: int = 0
var _purchased_advanced: Dictionary = {}
var _achievements: Dictionary = {}
## �??运�?�??击杀敌方单位总数（成就��累计击杢�」用�?## �?_achievements 同生命周期：�?reset_progress 丢�起清零（战役存档每�?�?��重置�?
var _total_kills: int = 0

## 关卡首��时发出的信号（用于显示解锁兵�?弹窗�?UI 反�?�?
signal level_first_cleared(level: int, unlocked_unit_id: String)

## 首�?通关某关（任意难度）发放战功与星星（仅一次）
func _award_first_clear(level: int) -> void:
	if _levels_first_cleared.get(level, false):
		return
	_levels_first_cleared[level] = true
	_merit += MERIT_PER_LEVEL.get(level, 100)
	_stars += 1
	## #21：�?通加星后立即棢�查进度类成就（星耢�将星等实时弹出，不等结算�?	Achievements.check_progress()
	## 通知 UI �?��首��并解锁新兵种（首��弹窗）
	var new_unit: String = get_level_new_unit(level)
	level_first_cleared.emit(level, new_unit)

## 判断兵�?�?��已解�?
func is_unit_unlocked(unit_id: String) -> bool:
	## DevMode 全解锁：仅「全面战争（单人沙盒）」与「双人游戏」默认解锁全部兵种（含特殊/异象/英雄）。
	## 战役模式不默认全解锁（回退 #15 2026-08-12 的放开：当时让 DevMode 在战役中也全解锁）；
	## 全面战争=非战役 && 非双人 && 非肉鸽；肉鸽由 RoguelikeManager.is_active 排除。
	if DevMode.enabled and not RoguelikeManager.is_active and not GameManager.is_campaign_mode:
		return true
	if unit_id in BASE_UNITS:
		return true
	if unit_id in LEVEL_NORMAL_UNIT.values():
		for lv in LEVEL_NORMAL_UNIT:
			if LEVEL_NORMAL_UNIT[lv] == unit_id:
				return _levels_first_cleared.get(lv, false)
	if ADVANCED_COST.has(unit_id):
		return _purchased_advanced.get(unit_id, false)
	if STAR_UNLOCK.has(unit_id):
		## 成就门控兵�?：�?应成就未解锁时，即使星星达标也不解锁（Doro勇士等）
		var gate_id: String = ACHIEVEMENT_GATED_UNITS.get(unit_id, "")
		if gate_id != "" and not _achievements.get(gate_id, false):
			return false
		return _stars >= int(STAR_UNLOCK[unit_id])
	return false

## 玩�?当前已解锁的兵�? ID 列表
func get_player_unlocked_ids() -> Array[String]:
	var r: Array[String] = []
	for u in ALL_UNITS:
		if is_unit_unlocked(u):
			r.append(u)
	return r

## 玩�?已解锁兵种中的最�?tier（敌方�?先一�?tier 的判定基准）
func get_player_max_tier() -> int:
	var max_tier: int = 0
	var unlocked: Array[String] = get_player_unlocked_ids()
	for unit in UnitDatabase.unit_list:
		if unit.unit_id in unlocked:
			max_tier = maxi(max_tier, unit.tier)
	return max_tier

## 关卡固定编成：每关敌人编成为「开屢�常驻 + �?1~N 关累�?��锁的新兵种��?## �?��模式：敌方用本关固定编成；我方用全部已解锁
## 困难/地狱模式：敌我双方均用本关固定编成（#21 用户拍板：限制玩家只能用�?��固定兵�?�?## 不能用之后解锁的兵�?和战功购�?星星解锁的英雄）
## �?? N5 泄漏：原 tier 跳跃逻辑在关1 player_max_tier=3 �?next_tier=4�?## �?tier=4 �?N5 �??�?AI 编成。固定编成彻底消除�?�??�?
## 获取指定关卡的固定新兵�? ID（仅返回 LEVEL_NORMAL_UNIT[level]，即该关额�?解锁的新兵�?�?
func get_level_new_unit(level: int) -> String:
	return LEVEL_NORMAL_UNIT.get(level, "")

## 获取指定关卡的固定敌方编成（弢�屢�常驻 5 + �?1~N 关累�?��兵�?�?## 用于�?��模式敌方��困�?地狱模式双方
## #21：不再包�?��家已解锁列表—��剔除战功购买（ADVANCED_COST）与星星英雄（STAR_UNLOCK），
## 编成�?��关卡号变化，不随玩�?�?��/英雄解锁状��变�?
func get_fixed_enemy_unit_ids(level: int) -> Array[String]:
	var r: Array[String] = BASE_UNITS.duplicate()
	## �?���?1 关到�?N 关的新兵种（LEVEL_NORMAL_UNIT �?��关卡号）
	for lv in range(1, level + 1):
		var u: String = LEVEL_NORMAL_UNIT.get(lv, "")
		if u != "" and not r.has(u):
			r.append(u)
	## #3：累加第 1~N 关逐步解锁的敌方高级兵种（ENEMY_ADVANCED_UNITS_BY_LEVEL）
	for lv in ENEMY_ADVANCED_UNITS_BY_LEVEL:
		var adv: String = ENEMY_ADVANCED_UNITS_BY_LEVEL[lv]
		if lv <= level and not r.has(adv):
			r.append(adv)
	return r

## 获取指定难度下指定关卡的己方�?��兵�?列表
## �?��模式：我方用全部已解锁
## 困难/地狱�?7�?026-08-09 用户拍板）我方用专用编成池����?##   HARD_BASE_UNITS（G1/G2/G3/D1/D3，D3（2026-08-12 还原） 且免�?���? �?1~(N-1) 关累�?��兵�?�?##   首关�?5 �?��驻，逐关�?��；敌方编成维持现状（get_enemy_unit_ids_for_level �?D3）��?
func get_player_unit_ids_for_difficulty(level: int, difficulty: int) -> Array[String]:
	if difficulty >= 1:  ## 困难/地狱模式：限制己方用专用编成�?
		return get_hard_player_unit_ids(level)
	return get_player_unlocked_ids()

## #7：获取困�?地狱模式的己方专用编成池（G1/G2/G3/D1/D3 + �?1~(level-1) 关累�?��兵�?�?## 与敌方固定编成的�?��仅在基�?池（D2 vs D3）；�?��逻辑同理逐关追加�?
func get_hard_player_unit_ids(level: int) -> Array[String]:
	var r: Array[String] = HARD_BASE_UNITS.duplicate()
	## �?���?1 关到�?(N-1) 关的新兵种（不含�?��新解锁，用户拍板：玩家只能用「上丢�关敌人��的池）
	for lv in range(1, level):
		var u: String = LEVEL_NORMAL_UNIT.get(lv, "")
		if u != "" and not r.has(u):
			r.append(u)
	return r

## 获取指定难度下指定关卡的敌方�?��兵�?列表
## �?��模式：敌方用本关固定编�?## 困难/地狱：敌方也用本关固定编成（与普通模式相同，但困�?地狱我方也受限）
func get_enemy_unit_ids_for_level(level: int) -> Array[String]:
	return get_fixed_enemy_unit_ids(level)

## 用战功购买高级兵种，成功返回 true
func buy_advanced(unit_id: String) -> bool:
	if not ADVANCED_COST.has(unit_id) or _purchased_advanced.get(unit_id, false):
		return false
	var cost: int = ADVANCED_COST[unit_id]
	if _merit < cost:
		return false
	_merit -= cost
	_purchased_advanced[unit_id] = true
	_save_progress()
	return true

func get_merit() -> int:
	return _merit

func get_total_stars() -> int:
	return _stars

## 成就系统：发放�?外星星（不影响战功经济）
func add_stars(amount: int) -> void:
	_stars += amount
	_save_progress()

## 成就系统：解锁成就（#22：每次新解锁 +1 颗星�?026-08-08 用户拍板，替代旧�?成就不发星星"�?
func unlock_achievement(id: String) -> bool:
	if _achievements.get(id, false):
		return false
	_achievements[id] = true
	_stars += 1  ## #22：解锁成就发�?1 颗星
	_save_progress()
	return true

func is_achievement_unlocked(id: String) -> bool:
	return _achievements.get(id, false)

## 成就系统：累加本屢�击杀数到「累计击杢�」�?数（amount <= 0 时忽略）
## #21：改为由 battle_root 每击杢�丢�次实时调用一次（战役模式），结算不再重�?入账�?## 不���? _save_progress()：战役数�?��次启动即重置，��杀�?cfg �?���?�� I/O�?
func add_kills(amount: int) -> void:
	if amount <= 0:
		return
	_total_kills += amount

## 成就系统：按兵�?�?��击杀数（剑术大师「N2 击杀 500」用�?026-08-09�?## �?unit_base.die 上报击杀者兵�?ID；战役数�?��次启动重�?��不��杀�?cfg�?
var unit_kills: Dictionary = {}
func record_unit_kill(unit_id: String) -> void:
	if unit_id == "":
		return
	unit_kills[unit_id] = int(unit_kills.get(unit_id, 0)) + 1

## 成就系统：�?取指定兵种的�??击杀�?
func get_unit_kills(unit_id: String) -> int:
	return int(unit_kills.get(unit_id, 0))

## 成就系统：�?取累计击杢�总数
func get_total_kills() -> int:
	return _total_kills


## 获取指定关卡可用的兵种数量（供 HUD 显示，hud.gd 仍在调用）
## level: 关卡编号
## 返回值: 该关卡可用的兵种数量
func get_available_units_count(level: int) -> int:
	## 基础 6 个兵种 + 关卡数减 1（最多额外增加 10 个）
	return 6 + min(level - 1, 10)

## 获取指定关卡敌人的可用兵种数量
## 关卡模式下敌人永远比玩家多出一个兵种，玩家只有打败当前关卡后才能解锁该多出的兵种
## level: 关卡编号
## 返回值: 敌人该关卡可用的兵种数量（= 玩家可用数 + 1）
func get_enemy_units_count(level: int) -> int:
	## 敌人比玩家多一个兵种，但不超过兵种数据库总数量
	var total_units: int = 22  ## 兵种数据库总数（G1-G6, D1-D6, F1-F5, N1-N5）
	return min(get_available_units_count(level) + 1, total_units)
