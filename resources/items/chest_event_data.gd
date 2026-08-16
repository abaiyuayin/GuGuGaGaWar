class_name ChestEventData extends Resource
## 宝箱奇遇事件数据
##
## 肉鸽模式宝箱节点 = 杀戮尖塔2 式奇遇事件：进入宝箱随机抽取 1 个事件，
## 每个事件提供 3 个选项，选择后按 effect_type 执行对应效果。
## 数据来源：res://data/chest_events.json（由 ItemDatabase 启动时加载并实例化）。
## 数值一律不写死在代码里 —— 想改平衡只动 JSON。

## 唯一标识符（英文小写下划线），用于图鉴展示
@export var event_id: String = ""
## 事件标题（中文）
@export var title: String = ""
## 事件描述（玩家视角的场景叙述）
@export var description: String = ""
## 三个选项：每个为 Dictionary { "label": String, "effect_type": String, "value": float, "result": String }
## effect_type 取值（由 RoguelikeMeta._apply_chest_event 执行）：
##   gain_card / gain_low_card / gain_artifact / gain_order
##   gain_gold / lose_gold / lose_card / upgrade_random / nothing
@export var options: Array[Dictionary] = []

## 从字典（JSON 一条记录）填充本资源字段
func from_dict(data: Dictionary) -> void:
	event_id = String(data.get("event_id", ""))
	title = String(data.get("title", ""))
	description = String(data.get("description", ""))
	options.clear()
	var raw_options: Array = data.get("options", [])
	for raw in raw_options:
		if typeof(raw) == TYPE_DICTIONARY:
			options.append((raw as Dictionary).duplicate())

## 选项数量（通常为 3；数据缺失时返回 0，供调用方做空状态兜底）
func get_option_count() -> int:
	return options.size()
