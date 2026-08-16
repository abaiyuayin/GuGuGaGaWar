class_name MilitaryOrderData extends Resource
## 军令资源
##
## 军令 = 肉鸽 run 内的「一次性指令」道具，购买后进入军令袋，可在战斗中主动打出，
## 打出后按 duration_waves 持续若干波，用完即弃（与文物的永久被动区分开）。
## 数据来源：res://data/military_orders.json（由 ItemDatabase 在启动时加载并实例化）。

## 稀有度枚举：与文物共用同一套语义
enum Rarity { COMMON = 1, FINE = 2, RARE = 3, LEGENDARY = 4 }

## 唯一标识符（英文小写下划线）
@export var order_id: String = ""
## 显示名称（中文）
@export var display_name: String = ""
## 效果说明（玩家视角的一句话功能描述）
@export var description: String = ""
## 外观详细描述（图鉴用，纯文本设定，不影响数值）
@export var appearance: String = ""
## 风味文本（军中俗语 / 出处，可为空）
@export var flavor: String = ""
## 稀有度，见 Rarity
@export var rarity: int = Rarity.COMMON
## 商店售价（金币）
@export var cost: int = 0
## 效果类型标识（供后续战斗层查表生效，例：rally_attack_speed）
@export var effect_type: String = ""
## 效果数值（百分比类为小数，固定值类为整数含义）
@export var effect_value: float = 0.0
## 生效持续波数（0 = 瞬时结算，不占用持续时间）
@export var duration_waves: int = 0

## 从字典（JSON 一条记录）填充本资源字段
func from_dict(data: Dictionary) -> void:
	order_id = String(data.get("order_id", ""))
	display_name = String(data.get("display_name", ""))
	description = String(data.get("description", ""))
	appearance = String(data.get("appearance", ""))
	flavor = String(data.get("flavor", ""))
	rarity = int(data.get("rarity", Rarity.COMMON))
	cost = int(data.get("cost", 0))
	effect_type = String(data.get("effect_type", ""))
	effect_value = float(data.get("effect_value", 0.0))
	duration_waves = int(data.get("duration_waves", 0))

## 导出为字典（开发者模式改写描述后回写 JSON 用）
func to_dict() -> Dictionary:
	return {
		"order_id": order_id,
		"display_name": display_name,
		"description": description,
		"appearance": appearance,
		"flavor": flavor,
		"rarity": rarity,
		"cost": cost,
		"effect_type": effect_type,
		"effect_value": effect_value,
		"duration_waves": duration_waves,
	}

## 稀有度中文名
func get_rarity_name() -> String:
	match rarity:
		Rarity.FINE:
			return "精良"
		Rarity.RARE:
			return "稀有"
		Rarity.LEGENDARY:
			return "传说"
		_:
			return "普通"

## 稀有度对应的描边颜色
func get_rarity_color() -> Color:
	match rarity:
		Rarity.FINE:
			return Color(0.45, 0.85, 0.45, 1.0)
		Rarity.RARE:
			return Color(0.42, 0.66, 1.0, 1.0)
		Rarity.LEGENDARY:
			return Color(0.98, 0.72, 0.30, 1.0)
		_:
			return Color(0.72, 0.72, 0.72, 1.0)

## 持续时间中文描述（图鉴 / 商店卡面用）
func get_duration_text() -> String:
	if duration_waves <= 0:
		return "瞬时"
	return "持续 %d 波" % duration_waves
