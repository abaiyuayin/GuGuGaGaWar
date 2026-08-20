extends Node  ## 继承 Node，作为全局单例节点存在
## 兵种数据库（全局单例）
## 负责在游戏启动时加载所有兵种数据资源，并提供查询接口

## 兵种解锁顺序（共 22 个）
## 咕咕嘎嘎阵营 6 个：G1, G6, G2, G4, G5, G3
## Doro 阵营 6 个：D1, D4, D5, D3, D2, D6
## 菲比丘比阵营 5 个：F1, F2, F3, F4, F5（F4=圣殿骑士长）
## 糯糯阵营 5 个：N1, N2, N3, N4, N5
const UNLOCK_ORDER: Array = [
	"G1", "G6", "G2", "G4", "G5", "G3",  ## 咕咕嘎嘎阵营 6 个兵种
	"D1", "D4", "D5", "D3", "D2", "D6",  ## Doro 阵营 6 个兵种
	"F1", "F2", "F3", "F4", "F5",  ## 菲比丘比阵营 5 个兵种
	"N1", "N2", "N3", "N4", "N5",  ## 糯糯阵营 5 个兵种
	"Hero1",  ## 爱弥斯：特殊英雄，需累计 20 颗星解锁（见 CampaignProgress.STAR_UNLOCK）
	"Hero2",  ## Doro勇士：隐藏成就「为了欧润橘！」解锁后入池，需 20 颗星（见 CampaignProgress）
	"Hero3",  ## 菲比Hero：菲比阵营英雄，需累计 20 颗星解锁（见 CampaignProgress.STAR_UNLOCK）
	"S1",  ## 蓝女巫：特殊阵营英雄
	"Y1",  ## 死亡使者：异象阵营
]

## 仅后台注册兵种（不进 unit_list → 不进图鉴/控制台/常规编成/异象池/特殊事件池）
## 由独立触发规则召唤或替换（仓鼠士兵 G1 替换 / 凑企鹅回合触发），纯事件兵种。
## S2 仓鼠士兵 / S3 天命人（原天明人）/ Y2 我的刀盾 / Y3 香蕉猫 / Y4 凑企鹅
const HIDDEN_UNITS: Array[String] = ["S2", "S3", "Y2", "Y3", "Y4"]

## 特殊英雄单位（不计入常规编成，仅用于肉鸽固定首发卡 + 图鉴/控制台特殊行展示）
## 爱弥斯（Hero1）已并入常规 UNLOCK_ORDER 使其可在战役/全面战争中作为兵种解锁与部署，
## 故此处留空；之后若新增其他不参与常规战争的纯展示英雄，再追加到此数组。
const SPECIAL_UNITS: Array[String] = []

var units: Dictionary = {}  ## 兵种资源字典：键为兵种 ID，值为对应的兵种资源
var unit_list: Array = []  ## 兵种列表：按解锁顺序排序的所有常规兵种资源数组（不含特殊英雄）
var special_units: Array = []  ## 特殊英雄单位列表（仅展示/肉鸽首发用，不进入常规战争逻辑）
var hidden_units: Array = []  ## 仅后台注册兵种资源列表（事件召唤/替换用，图鉴按隐藏兵种展示）

func _ready() -> void:  ## 节点就绪时自动调用
	load_all_units()  ## 加载所有兵种资源到内存

func load_all_units() -> void:  ## 加载所有兵种资源的方法
	units.clear()  ## 清空兵种字典
	unit_list.clear()  ## 清空兵种列表
	## 按解锁顺序加载常规兵种资源
	for id in UNLOCK_ORDER:  ## 遍历解锁顺序数组
		var res = load("res://resources/units/%s.tres" % id)  ## 加载对应的 .tres 资源文件
		if res:  ## 如果资源加载成功
			units[id] = res  ## 将资源存入字典
			unit_list.append(res)  ## 将资源添加到列表（按解锁顺序）
	## 加载特殊英雄单位（仅入 units 字典与 special_units，不进 unit_list）
	for id in SPECIAL_UNITS:
		var res = load("res://resources/units/%s.tres" % id)
		if res:
			units[id] = res
			special_units.append(res)
	## 加载仅后台注册兵种（只入 units 字典，供事件触发/替换用；不进 unit_list / special_units）
	for id in HIDDEN_UNITS:
		var res = load("res://resources/units/%s.tres" % id)
		if res:
			units[id] = res
			hidden_units.append(res)

func get_unit(id: String) -> Resource:  ## 根据兵种 ID 获取兵种资源
	return units.get(id, null)  ## 返回字典中对应的资源，未找到则返回 null

## 是否为英雄兵种（ID 以 "Hero" 开头，如爱弥斯 Hero1）
## 英雄仅允许玩家在战役/肉鸽中按解锁条件使用，敌方 AI 一律不得编成
func is_hero_unit(id: String) -> bool:
	return id.begins_with("Hero")

func get_affordable_units(gold: int, max_tier: int = 4) -> Array:  ## 获取当前金币可购买且阶层不超限的兵种列表
	var result: Array = []  ## 结果数组
	for unit in unit_list:  ## 遍历所有兵种
		if unit.tier <= max_tier and unit.cost <= gold:  ## 阶层不超限且金币足够
			result.append(unit)  ## 添加到结果列表
	return result  ## 返回可购买的兵种列表

func get_units_by_tier(tier: int) -> Array:  ## 获取指定阶层的所有兵种
	var result: Array = []  ## 结果数组
	for unit in unit_list:  ## 遍历所有兵种
		if unit.tier == tier:  ## 阶层匹配
			result.append(unit)  ## 添加到结果列表
	return result  ## 返回该阶层的兵种列表

## 获取 AI（敌人）当前可负担的兵种列表（考虑战役模式限制）
## 战役模式：敌方编成固定为「玩家已解锁兵种 + 本关新兵种」（固定编成，不随 tier 跳跃）
## 非战役模式：敌人可使用全部兵种
## gold: 当前金币数
## level: 当前关卡号（用于固定编成；未传时自动取 GameManager.selected_campaign_level）
## 返回值: AI 可负担且在可用编成内的兵种列表
func get_ai_affordable_units(gold: int, level: int = -1) -> Array:
	## 非战役模式直接返回全部可负担兵种
	if not GameManager.is_campaign_mode:
		## 全面战争：敌方 AI 一律禁用英雄/特殊/异象兵种。
		## Hero 前缀=英雄；S 前缀=特殊（仅异象事件召唤）；Y 前缀=异象（仅战役入侵）。
		## 这些兵种不在常规 AI 编成中，避免全面战争凭空刷出特殊/异象。
		var all_units: Array = []
		for unit in get_affordable_units(gold):
			var uid: String = (unit as UnitResource).unit_id
			if is_hero_unit(uid) or uid.begins_with("S") or uid.begins_with("Y"):
				continue
			all_units.append(unit)
		## 全面战争（单人沙盒，非双人）：按开发工具设置的敌方阵营开关过滤
		## 双人模式由人类控制敌方，不应用此过滤；战役模式走下方固定编成
		if not BattleManager.is_two_player:
			var filtered: Array = []
			for unit in all_units:
				var prefix: String = (unit as UnitResource).unit_id.left(1)
				if BattleManager.enemy_faction_enabled.get(prefix, true):
					filtered.append(unit)
			return filtered
		return all_units
	## 战役模式：确定关卡号（默认取全局已选关卡）
	if level < 1:
		level = GameManager.selected_campaign_level
	## 敌方可用兵种 = 玩家已解锁 + 本关固定新兵种
	var enemy_ids: Array[String] = CampaignProgress.get_fixed_enemy_unit_ids(level)
	var result: Array = []
	for unit in unit_list:
		if unit.unit_id in enemy_ids and unit.cost <= gold:
			result.append(unit)
	return result
