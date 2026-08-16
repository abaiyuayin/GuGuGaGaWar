class_name AffixResource extends Resource
## 词条资源
## 定义一个词条的静态数据：类型、参数、触发时机、是否可叠加等
## 每种词条对应一个 .tres 文件，存储在 res://resources/affixes/ 下

## 词条类型枚举
## BLEED: 流血 - 每秒扣百分比血量，不可叠加，攻击时重置持续时间
## KNOCKBACK: 击退 - 命中瞬间把目标沿攻击方向推开一小段距离，瞬时生效不进入持续列表
## FROST: 冰霜 - 攻速降低30%持续1秒，不可叠加，刷新计时
## EROSION: 侵蚀 - 受到侵蚀攻击时伤害降低10%/层，最多3层=30%，持续到死亡
enum AffixType {
	BLEED,      ## 流血
	POISON,     ## 中毒（预留）
	STUN,       ## 眩晕（预留）
	SLOW,       ## 减速（预留）
	KNOCKBACK,  ## 击退（瞬时位移）
	FROST,      ## 冰霜（#6：攻速 -30% 持续 1s）
	EROSION,    ## 侵蚀（#6：受击伤害 -10%/层 最多 3 层 持续到死亡）
}

## 词条的唯一标识符
@export var affix_id: String = ""
## 词条显示名称（中文）
@export var display_name: String = ""
## 词条类型
@export var affix_type: int = AffixType.BLEED
## 词条描述
@export var description: String = ""
## 持续时间（秒），0 表示瞬时
@export var duration: float = 5.0
## 数值参数（百分比，0.05 = 5%）
## 对流血：每秒扣血百分比
@export var value_percent: float = 0.05
## 是否可叠加（false=不可叠加，重复施加时刷新持续时间）
@export var stackable: bool = false
## 最大叠加层数（stackable=true 时生效）
@export var max_stacks: int = 1
## 词条触发时机
## ON_ATTACK: 攻击者命中时施加给目标
## ON_HIT: 被命中时施加给攻击者（反伤类）
## ON_DEATH: 死亡时触发
enum TriggerTiming {
	ON_ATTACK,  ## 攻击命中时施加给目标
	ON_HIT,     ## 被命中时施加给攻击者
	ON_DEATH,   ## 死亡时触发
}
@export var trigger_timing: int = TriggerTiming.ON_ATTACK

## 击退距离（标准单位，×Constants.UNIT_TO_PIXELS 换算为像素）
## 仅 affix_type == KNOCKBACK 时生效；0.5 单位 ≈ 16 像素，属于「一小段距离」
@export var knockback_distance: float = 0.5
