extends Node
## 肉鸽模式运行状态管理器 — Autoload 单例
##
## 生命周期：玩家在战役地图点击「肉鸽模式」时 start_run()，失败或主动退出时 end_run()。## 职责边界：只维护「一个run」的牌库 / 手牌 / 层数数据与抽牌规则。## 不包含任何战斗逻辑（刷怪、胜负判定由 RoguelikeDirector 负责），也不直接操作节点。##
## 卡牌规则（与常规卡牌游戏的差异点）：
##   1. 手牌上限恒为 HAND_LIMIT(3)，与牌库大小无关
##   2. 每层开局从牌库洗牌后抽满手牌
##   3. 每波敌军刷新时把手牌补到上限 — 上一波没打出去的牌不会被弃掉，会一直留在手。##   4. 牌库只在通关一层后通过三选一奖励增长

## 手牌内容变化时发出。[param hand_ids] 为当前手牌的兵种 ID 列表
signal hand_changed(hand_ids: Array[String])
## 永久牌库变化时发出（获得奖励卡）。[param deck_ids] 为牌库全部兵种ID
signal deck_changed(deck_ids: Array[String])
## 金币变化时发出（地图商店消费 / 通关奖励），[param gold] 为最新余
signal gold_changed(gold: int)
## 持有文物变化时发出。[param artifact_ids] 为当前全部文物ID
signal artifacts_changed(artifact_ids: Array[String])
## 持有军令变化时发出。[param order_ids] 为当前全部军令ID
signal orders_changed(order_ids: Array[String])
## 军令被打出时发出，供战斗层立即执行一次性指令（补牌 / 治疗 / 跳波 / 延迟刷怪等。## 持续型军令（伤害倍率、护甲加成等）无需监听，直接由 RunModifiers active_order_effects
signal order_played(order_id: String, effect_type: String, effect_value: float)
## 层数推进时发出。[param floor_index] 为新的层数（第1起）
signal floor_changed(floor_index: int)
## 一个run 正式开始时发出（start_run 末尾），供依赖run 级状态的子系统（如英雄技能CD）清
signal run_started()

## 局内手牌上
const HAND_LIMIT: int = 3
## 起始牌库张数
const STARTING_DECK_SIZE: int = 3
## 起始牌池允许的最高阶层（避免开局白送高阶兵
const STARTING_MAX_TIER: int = 2
## 通关一层后提供的候选奖励卡数量
const REWARD_CHOICE_COUNT: int = 3
## 地图总层数（最后一层为 Boss
const MAP_FLOORS: int = 10
## 每层节点数量：底部4个起始选项、中部 3~4个、顶部 1个Boss，形成分支汇聚地图
const NODES_PER_FLOOR: Array[int] = [4, 4, 4, 3, 3, 3, 3, 3, 2, 1]

## 地图节点类型（与杀戮尖塔一致：战斗/精英/休息/事件/商店/宝箱/Boss。## 节点数据结构见独立的全局的RoguelikeMapNode（scripts/roguelike/roguelike_map_node.gd
enum NodeType { COMBAT, ELITE, REST, EVENT, SHOP, TREASURE, BOSS }

## 入口层（第0层）固定节点类型：战斗/ 休息 / 商店 / 宝箱（奇遇）
## 四种基础体验开局全部给到玩家；每次start_run 洗牌（见 generate_map），所以每次开局
## 哪个位置出现哪种节点都是随机—入口层的"宝箱"节点就是三选一随机奇遇事件。## 自然满足"每次进入初始关卡都从事件池中随机抽一个奇遇的需求。## 数量必须（NODES_PER_FLOOR[0] 一致
const ENTRY_FLOOR_TYPES: Array[int] = [NodeType.COMBAT, NodeType.REST, NodeType.SHOP, NodeType.TREASURE]
## Boss 前一层固定节点类型：休息 / 商店 — 决战前保证能回血与补给。## 数量必须（NODES_PER_FLOOR[MAP_FLOORS - 2] 一致
const PRE_BOSS_FLOOR_TYPES: Array[int] = [NodeType.REST, NodeType.SHOP]
## 权重表各列对应的节点类型（与 FLOOR_TYPE_WEIGHTS 的数组下标一一对应
const WEIGHTED_TYPES: Array[int] = [NodeType.COMBAT, NodeType.ELITE, NodeType.REST, NodeType.EVENT, NodeType.SHOP, NodeType.TREASURE]
## 中间层节点类型权重表（层（按各类型权重），数值驱动：调节关卡节奏只需改这张表
##   早期（~3层）：普通战斗与事件为主，精英稀少，让玩家先把牌库攒起来
##   中期（~6层）：精英占比翻倍，商店 / 宝箱补给同步增加
##   后期（层）：精英最多，休息占比提高以应对Boss 前的损失。## 取「floor_idx <= max_floor」中最先匹配的一个。## #4：REST/EVENT/SHOP/TREASURE（索引2~5）权重统一降到原值约 1/3。## 让肉鸽节奏更偏战斗而非逛街。COMBAT/ELITE（索引0~1）保持不变
const FLOOR_TYPE_WEIGHTS: Array[Dictionary] = [
	{"max_floor": 3, "weights": [55, 8, 4, 5, 2, 2]},
	{"max_floor": 6, "weights": [42, 18, 5, 4, 3, 2]},
	{"max_floor": 99, "weights": [38, 22, 6, 3, 2, 2]},
]
## 连续多少层内必须出现一个休息点（保底规则，防止长段无补给）
const REST_GUARANTEE_SPAN: int = 3

## 当前是否处于肉鸽模式（战场、HUD 依据此标志切换行为）
var is_active: bool = false
## 当前 run 选择的英雄ID208）。空 = 尚未选择，禁止开局；由英雄选择界面写入
var selected_hero: String = ""
## 肉鸽可选英雄表（208）。爱弥斯已实装可选；其余为占位，暂未上线（点击提示「暂未上线」）。## 英雄影响抽牌概率 + 初始卡组 + 局内加成（由start_run / 英雄加成接入点）。## #5：英雄定义拆成「army（军团构成）」与「special（特殊加成）」两栏，
## 供英雄选择界面三栏布局展示；run_modifiers.hero_bonus_pct 已实现30% 加成。## #8（2026-08-11）：Hero2（Doro勇士）的 locked 不再硬编码，由get_hero_defs() 。## 「开发者模式默认解锁/非开发者模式需战役解锁（成就20星）」动态解析
const HERO_DEFS: Array[Dictionary] = [
	{"id": "Hero1", "name": "爱弥斯", "locked": false, "army": "四兵种随机军队", "special": "全军 +30% 攻击与攻速"},
	{"id": "Hero2", "name": "Doro勇士", "locked": true, "army": "Doro 系随机军队", "special": ""},
	{"id": "Hero3", "name": "菲比Hero", "locked": true, "army": "菲比系随机军队", "special": ""},
	{"id": "Hero4", "name": "咕咕嘎嘎Hero", "locked": true, "army": "咕咕嘎嘎系随机军队", "special": ""},
	{"id": "Hero5", "name": "糯糯Hero", "locked": true, "army": "糯糯系随机军队", "special": ""},
]

## 返回英雄选择界面使用的英雄表（HERO_DEFS 的运行时副本）。## #8（2026-08-11）：Hero2的locked 动态计—开发者模式默认解锁；
## 非开发者模式须在战役模式中真正解锁（隐藏成就「为了欧润橘！（20星，
## 由CampaignProgress.is_unit_unlocked）才能选择，未解锁时保持占位显示
func get_hero_defs() -> Array[Dictionary]:
	var defs: Array[Dictionary] = []
	for hero in HERO_DEFS:
		var def := hero.duplicate()
		## #25（2026-08-21 用户拍板）：Hero3 菲比Hero / Hero4 咕咕嘎嘎Hero / Hero5 糯糯Hero
		## 已实装（单位资源齐全），肉鸽中仅开发者模式解锁可选；非开发者模式保持「？？？」锁定占位。
		## 注意：这三个英雄走纯 DevMode 门控，不走战役解锁通道（Hero4/5 属 special_units，不在常规关解锁内）。
		## Hero2 保持既有逻辑：开发者模式默认解锁 / 战役隐藏成就「为了欧润橘！」解锁。
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
## 统一寻敌 / 追击半径（像素）。肉鸽模式下所有兵种共用此值，与各自攻击距离解耦。## 单位在setup 时据此设置DetectionArea 半径；改动只对之后生成的单位生效
var chase_range_px: float = Constants.ROGUELIKE_CHASE_RANGE
## 追击牵引半径（像素）。守卫单位离水晶超过此距离即中断追击返回驻守点
var chase_leash_px: float = Constants.ROGUELIKE_CHASE_LEASH
## 当前层数，从 1 开
var current_floor: int = 1
## 永久牌库（跨层保留的兵种 ID 列表
var deck: Array[String] = []
## 每张卡的升级次数（兵种ID 升级次数，每次休息事件升级 +1 级，单卡召唤人数 +2 线性叠加）。## 注意：存储的是「次数」，卡牌等级 = 次数 + 1（#211圆框徽章），本run重置
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
## 已获得的军令 ID 列表（run 内一次性指令，打出后移除），随 run 重置
var owned_orders: Array[String] = []
## 本场战斗内已打出军令的累计效果：effect_type -> 累计。## 生命周期只覆盖「一场战斗」：打出即累加，进入下一场战斗（start_floor）时清空。## owned_artifacts 的永久被动区分开 —军令是本场用完就没的临时增益
var active_order_effects: Dictionary = {}
## 本层待抽牌堆（每层开局从deck 洗牌生成
var draw_pile: Array[String] = []
## 当前手牌（兵种ID 列表
var hand: Array[String] = []
## #13（2026-08-09）：run 实际部署过的兵种 ID 集合（play_card 时记录，start_run 重置）。## 供肉鸽专属成就「传奇，还是无名小卒？」判定——全程只部署G1
var run_deployed_ids: Dictionary = {}
## 当前地图（分支DAG），元素为RoguelikeMapNode
var map_nodes: Array[RoguelikeMapNode] = []
## 当前所在节点下标（-1 表示尚未进入任何节点，需从第一层挑一个）
var current_node_index: int = -1

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
func start_run(hero_id: String = "") -> void:
	is_active = true
	## #13：肉鸽专属成就「传奇，还是无名小卒？」——重置本 run 部署兵种记录
	run_deployed_ids.clear()
	## 记录本局英雄208）：优先用入参；否则沿用上一局已选；都为空则兜底爱弥斯避免软
	if not hero_id.is_empty():
		selected_hero = hero_id
	elif selected_hero.is_empty():
		selected_hero = "Hero1"
	current_floor = 1
	## AI 调参回到默认值：控制台的临时改动不跨 run 保留
	chase_range_px = Constants.ROGUELIKE_CHASE_RANGE
	chase_leash_px = Constants.ROGUELIKE_CHASE_LEASH
	deck.clear()
	deck_upgrade.clear()
	gold = 50  ## #12：开局金币由0改为50，给玩家首层买补给的余地
	crystal_max_hp = Constants.ROGUELIKE_CRYSTAL_HP
	crystal_hp = crystal_max_hp
	owned_artifacts.clear()
	owned_orders.clear()
	artifacts_changed.emit(owned_artifacts.duplicate())
	orders_changed.emit(owned_orders.duplicate())
	var pool: Array[String] = _collect_unit_ids(STARTING_MAX_TIER)
	if pool.is_empty():
		push_error("RoguelikeManager: 起始牌池为空，检查 UnitDatabase 是否已加载兵种")
		return
	pool.shuffle()
	for i in range(min(STARTING_DECK_SIZE, pool.size())):
		deck.append(pool[i])
	## 保证特殊英雄「爱弥斯」固定在起始牌库内（抽到顺序仍随机，由draw_pile 洗牌决定
	if not deck.has("Hero1"):
		deck.insert(0, "Hero1")
	deck_changed.emit(deck.duplicate())
	generate_map()
	start_floor()
	run_started.emit()

## 开始当前层：牌库洗牌进抽牌堆，清空手牌并抽
func start_floor() -> void:
	draw_pile = deck.duplicate()
	draw_pile.shuffle()
	hand.clear()
	## 上一场战斗打出的军令效果不跨场生效	active_order_effects.clear()
	refill_hand()
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

## 打出指定手牌，返回对应兵种资源；索引非法或资源缺失时返回 null
func play_card(index: int) -> UnitResource:
	if index < 0 or index >= hand.size():
		return null
	var unit_id: String = hand[index]
	var res := UnitDatabase.get_unit(unit_id) as UnitResource
	if res == null:
		push_error("RoguelikeManager: 手牌兵种 %s 在数据库中不存在" % unit_id)
		return null
	## #13：记录本 run 实际部署过的兵种（「传奇，还是无名小卒？」判定只部署G1 通关	run_deployed_ids[unit_id] = true
	hand.remove_at(index)
	hand_changed.emit(hand.duplicate())
	return res

## 手牌与抽牌堆是否还有任何可用卡牌（失败判定的必要条件之一
func has_cards_left() -> bool:
	return not hand.is_empty() or not draw_pile.is_empty()

## 向永久牌库添加一张卡（通关奖励
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

## 升级一张卡：每次升一级，单卡召唤人数 +2（线性叠加，非翻倍），最高CARD_LEVEL_MAX 级（#211）。## 升级按兵种ID 生效，对牌库中所有同名卡同时生效。## 返回升级后的卡牌等级从1起）；已达上限时返回当前等级，不再增长
func upgrade_card(unit_id: String) -> int:
	if unit_id.is_empty():
		return 0
	var times: int = int(deck_upgrade.get(unit_id, 0)) + 1
	times = mini(times, CARD_LEVEL_MAX - 1)
	deck_upgrade[unit_id] = times
	deck_changed.emit(deck.duplicate())
	return times + 1

## 返回卡牌当前等级（供 HUD 圆框徽章显示）：未升级为 1，满级为 CARD_LEVEL_MAX。## 等级 = 升级次数 + 1，与 upgrade_card 的存储值保持一致
func get_card_level(unit_id: String) -> int:
	var times: int = int(deck_upgrade.get(unit_id, 0))
	return clampi(times + 1, 1, CARD_LEVEL_MAX)

## 恢复水晶耐久 [param pct] 比例~1，如 0.3 = 30% 上限），夹断[0, crystal_max_hp] 并广播。## 用于休息处（#213）等 run 内恢复场景；水晶耐久run 级持久资源，跨战斗保留
func heal_crystal(pct: float) -> void:
	crystal_hp = clampi(int(round(float(crystal_hp) + float(crystal_max_hp) * pct)), 0, crystal_max_hp)
	crystal_hp_changed.emit(crystal_hp, crystal_max_hp)

## 计算某兵种当前单卡实际召唤数。## 基础值：units_per_card 若>0 则采用（数据驱动覆盖）；否则按阶层自动：tier>=2 高级为2个，其余 3 。## 训练强化（休息点）：每次强化使该卡牌召唤人数 +2（线性叠加，不翻倍），最高CARD_LEVEL_MAX 级（#211）## 最终受单方人口上限夹断
func get_deploy_count(unit_id: String) -> int:
	var res := UnitDatabase.get_unit(unit_id) as UnitResource
	if res == null:
		return 0
	var base: int = res.units_per_card if res.units_per_card > 0 else (3 if res.tier < 2 else 2)
	var level: int = int(deck_upgrade.get(unit_id, 0))
	var upgrade_bonus: int = level * 2  ## 每次训练强化召唤人数 +2
	## 文物「战鼓」与军令「大点兵」提供的额外召唤数，在强化之后加算（加法收益不随强化膨胀
	var bonus: int = int(get_artifact_effect_total("deploy_count_bonus") + get_order_effect_total("deploy_count_bonus"))
	return clampi(base + upgrade_bonus + bonus, 1, Constants.ROGUELIKE_MAX_UNITS_PER_SIDE)

## 增加金币（用于商店消费），下限夹断为 0，变化时广播 gold_changed
func add_gold(amount: int) -> void:
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

## 获得一张军令（进入军令袋，待战斗中打出
func add_order(order_id: String) -> void:
	if order_id.is_empty():
		return
	owned_orders.append(order_id)
	orders_changed.emit(owned_orders.duplicate())

## 消耗一张军令；未持有返回false
func consume_order(order_id: String) -> bool:
	var idx: int = owned_orders.find(order_id)
	if idx < 0:
		return false
	owned_orders.remove_at(idx)
	orders_changed.emit(owned_orders.duplicate())
	return true

## 打出一张军令：从军令袋移除，并把效果登记进本场临时效果。## 一次性指令（补牌 / 治疗 / 跳波…）由监听order_played 的战斗层执行。## 持续型加成（伤害 / 护甲 / 移速…）直接留在 active_order_effects 里供 RunModifiers 查询## 未持有该军令时返回false 且不做任何变更
func play_order(order_id: String) -> bool:
	var od := ItemDatabase.get_order(order_id)
	if od == null:
		push_error("RoguelikeManager: 军令 %s 在数据库中不存在" % order_id)
		return false
	if not consume_order(order_id):
		return false
	var key: String = od.effect_type
	active_order_effects[key] = float(active_order_effects.get(key, 0.0)) + od.effect_value
	order_played.emit(order_id, key, od.effect_value)
	return true

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
func roll_reward_choices() -> Array[String]:
	var pool: Array[String] = _collect_unit_ids(_max_tier_for_floor())
	var result: Array[String] = []
	if pool.is_empty():
		return result
	pool.shuffle()
	for i in range(min(REWARD_CHOICE_COUNT, pool.size())):
		result.append(pool[i])
	return result

## 推进到下一层并重新发牌
func advance_floor() -> void:
	current_floor += 1
	start_floor()

## 结束本次 run，清空所有运行
func end_run() -> void:
	is_active = false
	current_floor = 1
	deck.clear()
	draw_pile.clear()
	hand.clear()
	map_nodes.clear()
	owned_artifacts.clear()
	owned_orders.clear()
	active_order_effects.clear()
	current_node_index = -1

## 获取当前手牌对应的兵种资源列表（UI 展示用，跳过缺失资源
func get_hand_resources() -> Array[UnitResource]:
	var result: Array[UnitResource] = []
	for unit_id in hand:
		var res := UnitDatabase.get_unit(unit_id) as UnitResource
		if res != null:
			result.append(res)
	return result

## 生成杀戮尖塔式分支地图：多层节点，路径可分叉、可汇聚，最终收束到单一 Boss
##
## 关卡结构（v2 重设计）。##   0 层（入口层 节点）固定为 战斗 / 休息 / 商店 / 精英 —四种基础体验开局全部给到。##       左右顺序每局洗牌。入口精英被压低到tier 2 / 3 波，是「敢打就白嫖一件文物」的选项。##   第1~7 （按FLOOR_TYPE_WEIGHTS 的层段权重随机，生成后跑 _enforce_floor_rules 保底修补##   第8层（Boss 前，2 节点）固定为 休息 / 商店 — 决战前必给回血与补给。##   第9 层Boss（唯一节点，全部路径收束于此）##
## 每层节点与上下层按横向proximity 连边，形成自然的分支/汇聚结构。## 同层节点最小横向间距（x_ratio 单位）。生成时强制保证同层相邻节点间距 >= 此值，
## 杜绝两个节点渲染到同一像素位置（肉鸽大地图节点重叠问题）.16 在小屏（usable_w<100）也
## 对应 ~96px，远大于节点直径 54px
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
			## 奇偶层横向错位，避免上下层节点正对形成竖
			var stagger: float = 0.09 if (f % 2 == 1) else 0.0
			node.x_ratio = clampf(base_ratio + stagger + jitter, 0.08, 0.92)
			if f == 0:
				node.node_type = entry_types[s % entry_types.size()]
			elif f == MAP_FLOORS - 1:
				node.node_type = NodeType.BOSS
			elif f == MAP_FLOORS - 2:
				node.node_type = pre_boss_types[s % pre_boss_types.size()]
			else:
				node.node_type = _roll_node_type(f)
			map_nodes.append(node)
	## 1.5 同层节点横向去重叠：保证相邻节点 x_ratio 间距 >= MAP_MIN_X_GAP，杜绝渲染重叠	_separate_floor_nodes()
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

## 同层节点横向去重叠：对每一层按 x_ratio 排序后，从左往右推保证相邻间距 >= MAP_MIN_X_GAP。## 若右侧溢出再从右往左回收，最后整体夹紧到合法区间。连边（_connect_floor）在之后执行## 因此去重叠后该x_ratio 同时决定了连接关系与显示位置，二者一致，根治节点重叠
func _separate_floor_nodes() -> void:
	for f in range(MAP_FLOORS):
		var idx: Array[int] = _floor_node_indices(f)
		if idx.size() < 2:
			continue
		idx.sort_custom(func(a: int, b: int) -> bool: return map_nodes[a].x_ratio < map_nodes[b].x_ratio)
		## 从左往右推，保证相邻间距达
		for i in range(1, idx.size()):
			var min_x: float = map_nodes[idx[i - 1]].x_ratio + MAP_MIN_X_GAP
			if map_nodes[idx[i]].x_ratio < min_x:
				map_nodes[idx[i]].x_ratio = min_x
		## 右侧溢出时从右往左回收，整体仍处于合法区
		for i in range(idx.size() - 2, -1, -1):
			var max_x: float = map_nodes[idx[i + 1]].x_ratio - MAP_MIN_X_GAP
			if map_nodes[idx[i]].x_ratio > max_x:
				map_nodes[idx[i]].x_ratio = max_x
		for i in idx:
			map_nodes[i].x_ratio = clampf(map_nodes[i].x_ratio, 0.08, 0.92)

## 生成后修补中间层类型，保证关卡节奏不失控。三条硬性规则：
##   规则 1 每个中间层至少一个战斗类节点（战斗/ 精英），杜绝「整层白嫖？##   规则2的节点的层不能全是同一类型，至少两种（避免「四个事件」这类极端地图）
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

## 规则 3：强制在该层放一个休息点。优先改写非战斗节点。## 全是战斗时也允许改一个（该层节点类型，改后仍至少剩一场战斗）
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

## 连接第[floor_idx] 层与下一层的边，保证：##   - 下一层每个节点至少有一个父节点（不会unreachable）##   - 当前层每个节点至少有一个子节点（不会死路）
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

## 选定一个节点（进入该节点内容前调用），标记为已访问
func select_node(index: int) -> void:
	if index < 0 or index >= map_nodes.size():
		return
	current_node_index = index
	map_nodes[index].visited = true

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

## 按层段权重表加权随机一个中间层节点类型（层越深，精英越多、纯战斗越少。## 权重全部来自 FLOOR_TYPE_WEIGHTS，调节节奏不需要动这段逻辑
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

## 按节点所在层与类型推算敌军阶层上限（越深越高，精英Boss 额外加成。## 入口层精英特例：压到 tier 2，使「开局白嫖文物」的风险落在玩家能承受的范围
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

## 收集阶层不超过max_tier 的全部兵种ID
## #3/#14：英雄卡（Hero1 爱弥斯/ Hero2 Doro勇士）由卡组用start_run 显式 insert 保证：## 不进入兵种池 —一并满足「敌方不刷英雄」与「通关奖励不出现英雄」。## #8（2026-08-11）：排除条件由「= Hero1」扩展到全部 Hero 前缀，Hero2 解锁后同样不进随机卡池，
## 避免「选了爱弥斯却随机抽到 Doro勇士卡」破坏英雄决定卡组的设定
func _collect_unit_ids(max_tier: int) -> Array[String]:
	var result: Array[String] = []
	for unit in UnitDatabase.unit_list:
		var res := unit as UnitResource
		if res == null:
			continue
		if res.unit_id.begins_with("Hero"):
			continue
		if res.tier <= max_tier:
			result.append(res.unit_id)
	return result

## 当前层数允许出现的最高兵种阶层（层数越深越可能刷到高阶卡
func _max_tier_for_floor() -> int:
	return clampi(1 + current_floor, 1, 4)
