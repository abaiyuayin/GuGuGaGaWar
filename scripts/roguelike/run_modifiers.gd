class_name RunModifiers
extends RefCounted
## 肉鸽 run 内的数值修正统一查询点（文物永久被动 + 本场已打出军令）
##
## 存在意义：战斗层（unit_base / state_* / director）需要知道「玩家方现在有多少加成」，
## 但绝不该在十几个地方散写 `if RoguelikeManager.is_active and ...`。
## 所有加成查询统一走本类的 static 函数；非肉鸽模式一律返回中性值（倍率 1.0 / 加值 0）。
##
## 生效时机约定：
##   文物 —— 单位 setup() 时快照一次，之后不随手持文物变化（避免每帧查单例）
##   军令 —— 打出后写入 RoguelikeManager.active_order_effects，下一场战斗开始时自动清空
##
## 本类不持有任何状态，也不进场景树，纯函数式，因此 extends RefCounted 而非 Node。

## 伤害类型编号（与 unit_base.take_damage_typed 的约定一致）
const DMG_SLASH: int = 0
const DMG_PIERCE: int = 1
const DMG_BLUNT: int = 2
const DMG_MAGIC: int = 3
## 攻击距离超过该值视为远程单位（用于区分 melee/ranged 系文物）
const RANGED_THRESHOLD: float = 3.0
## 生命百分比低于该值时视为「残血」（军令「死战令」的触发线）
const LOW_HP_RATIO: float = 0.5

## 汇总某效果的总值（文物永久被动 + 本场已打出军令）。非肉鸽模式恒为 0
static func total(effect_type: String) -> float:
	if not RoguelikeManager.is_active:
		return 0.0
	return RoguelikeManager.get_artifact_effect_total(effect_type) + RoguelikeManager.get_order_effect_total(effect_type)

## 当前所选英雄提供的全局攻击 / 攻速加成百分比（0 = 无）。
## 仅肉鸽模式且选了对应英雄时非零；爱弥斯 = 全军 +30% 攻击与攻速（#208）。
## 放在 RunModifiers 这一统一查询点，避免战斗层散写英雄判定。
static func hero_bonus_pct() -> float:
	if not RoguelikeManager.is_active:
		return 0.0
	if RoguelikeManager.selected_hero == "Hero1":
		return 0.30
	return 0.0

## 玩家方单位最大生命倍率（文物「咕咕军旗残片」unit_hp_pct）
static func player_hp_mult() -> float:
	return maxf(1.0 + total("unit_hp_pct"), 0.1)

## 玩家方单位的实际初始护甲：先按 armor_pct 放大基础值，再叠加固定加值
## 固定加值来自文物「锈蚀盾徽」unit_armor_flat 与军令「据守」armor_flat_bonus
static func player_armor(base_armor: int) -> int:
	var scaled: float = float(base_armor) * maxf(1.0 + total("armor_pct"), 0.0)
	var flat: float = total("unit_armor_flat") + total("armor_flat_bonus")
	return maxi(int(round(scaled + flat)), 0)

## 玩家方单位的全局伤害倍率（文物「王座碎石」unit_damage_pct）
## 伤害类型专属加成不在这里，见 damage_type_mult
static func player_damage_mult() -> float:
	return maxf(1.0 + total("unit_damage_pct") + hero_bonus_pct(), 0.1)

## 按伤害类型与远近程取额外倍率
## [param damage_type] 见 DMG_* 常量；[param is_ranged] 由 attack_range 判定
static func damage_type_mult(damage_type: int, is_ranged: bool) -> float:
	var m: float = 1.0
	m += total("ranged_damage_pct") if is_ranged else total("melee_damage_pct")
	if damage_type == DMG_PIERCE:
		m += total("pierce_damage_pct")
	elif damage_type == DMG_MAGIC:
		m += total("magic_damage_pct")
	return maxf(m, 0.1)

## 敌方单位的伤害倍率（军令「缴械」enemy_damage_pct 为负值 → 削弱敌人）
static func enemy_damage_mult() -> float:
	return maxf(1.0 + total("enemy_damage_pct"), 0.1)

## 玩家方单位移动速度倍率
## 文物「青铜号角」unit_move_speed_pct 与军令「全线突击」rally_move_speed 叠加
static func player_move_mult() -> float:
	return maxf(1.0 + total("unit_move_speed_pct") + total("rally_move_speed"), 0.1)

## 玩家方攻击间隔倍率（<1 表示攻击更快）
## attack_speed 字段语义是「一次攻击周期的秒数」，所以攻速加成要取倒数
static func player_attack_interval_mult() -> float:
	return 1.0 / maxf(1.0 + total("unit_attack_speed_pct") + hero_bonus_pct(), 0.1)

## 敌方攻击间隔倍率（文物「无声之铃」enemy_attack_speed_pct 为负 → 间隔变长）
static func enemy_attack_interval_mult() -> float:
	return 1.0 / maxf(1.0 + total("enemy_attack_speed_pct"), 0.1)

## 节点结算金币 = 基础金币 + 文物「糯糯米袋」gold_per_node
static func node_gold(base_gold: int) -> int:
	return maxi(base_gold + int(total("gold_per_node")), 0)

## 每击杀一个敌人额外获得的金币（文物「无名冢砖」+ 军令「劫掠」）
static func kill_gold() -> int:
	return maxi(int(total("death_gold") + total("gold_on_kill")), 0)

## 每波开始时全体获得的护盾（文物「圣殿骑士吊坠」first_wave_shield）
static func wave_shield() -> int:
	return maxi(int(total("first_wave_shield")), 0)

## 每波开始时按最大生命百分比回复（文物「龙涎香炉」regen_per_wave_pct）
static func wave_regen_pct() -> float:
	return maxf(total("regen_per_wave_pct"), 0.0)

## 单位是否算远程（用于选择 melee / ranged 系加成通道）
static func is_ranged_unit(attack_range: float) -> bool:
	return attack_range > RANGED_THRESHOLD

# ---------- 实时（每次结算重新查询）的战场类效果 ----------

## 残血激励倍率（军令「死战令」damage_pct_at_low_hp）
## 只有当前生命低于 LOW_HP_RATIO 时才生效，因此必须实时查询、不能在 setup 时快照。
## [param hp_ratio] 当前生命 / 最大生命，取值 [0,1]
static func low_hp_damage_mult(hp_ratio: float) -> float:
	if hp_ratio > LOW_HP_RATIO:
		return 1.0
	return maxf(1.0 + total("damage_pct_at_low_hp"), 0.1)

## 我方每秒生命回复百分比（军令「战地急救令」regen_per_sec_pct）
static func regen_per_sec_pct() -> float:
	return maxf(total("regen_per_sec_pct"), 0.0)

## 战场持续燃烧每秒对敌方造成的伤害（军令「火攻令」burn_field_damage）
static func burn_field_damage() -> int:
	return maxi(int(total("burn_field_damage")), 0)

## 敌方单位转身撤退的概率（军令「围三阙一令」enemy_retreat_pct）
static func enemy_retreat_pct() -> float:
	return clampf(total("enemy_retreat_pct"), 0.0, 1.0)

## 我方单位阵亡时对周围敌人造成的伤害（军令「断后令」death_explosion_damage）
static func death_explosion_damage() -> int:
	return maxi(int(total("death_explosion_damage")), 0)
