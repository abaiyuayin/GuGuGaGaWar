class_name ArtifactData extends Resource
## 文物资源
##
## 文物 = 肉鸽 run 内的「永久被动」道具，一旦在商店/宝箱获得，整局生效直到 run 结束。
## 数据来源：res://data/artifacts.json（由 ItemDatabase 在启动时加载并实例化）。
## 数值一律不写死在代码里 —— 想改平衡只动 JSON。

## 稀有度枚举：数值越大越稀有，决定图鉴/商店卡面的描边颜色
enum Rarity { COMMON = 1, FINE = 2, RARE = 3, LEGENDARY = 4 }

## 唯一标识符（英文小写下划线），用于存档与查询
@export var artifact_id: String = ""
## 显示名称（中文）
@export var display_name: String = ""
## 效果说明（玩家视角的一句话功能描述）
@export var description: String = ""
## 外观详细描述（图鉴用，纯文本设定，不影响数值）
@export var appearance: String = ""
## 风味文本（传闻 / 出处，可为空）
@export var flavor: String = ""
## 稀有度，见 Rarity
@export var rarity: int = Rarity.COMMON
## 商店售价（金币）
@export var cost: int = 0
## 效果类型标识（供后续战斗层查表生效，例：unit_damage_pct）
@export var effect_type: String = ""
## 效果数值（百分比类为小数，例 0.10 = +10%；固定值类为整数含义）
@export var effect_value: float = 0.0

## 从字典（JSON 一条记录）填充本资源字段
func from_dict(data: Dictionary) -> void:
	artifact_id = String(data.get("artifact_id", ""))
	display_name = String(data.get("display_name", ""))
	description = String(data.get("description", ""))
	appearance = String(data.get("appearance", ""))
	flavor = String(data.get("flavor", ""))
	rarity = int(data.get("rarity", Rarity.COMMON))
	cost = int(data.get("cost", 0))
	effect_type = String(data.get("effect_type", ""))
	effect_value = float(data.get("effect_value", 0.0))

## 导出为字典（开发者模式改写描述后回写 JSON 用）
func to_dict() -> Dictionary:
	return {
		"artifact_id": artifact_id,
		"display_name": display_name,
		"description": description,
		"appearance": appearance,
		"flavor": flavor,
		"rarity": rarity,
		"cost": cost,
		"effect_type": effect_type,
		"effect_value": effect_value,
	}

## 稀有度中文名（图鉴 / 商店卡面用）
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
