class_name RunModifiers
extends RefCounted

const DMG_SLASH: int = 0
const DMG_PIERCE: int = 1
const DMG_BLUNT: int = 2
const DMG_MAGIC: int = 3
const RANGED_THRESHOLD: float = Constants.RANGED_THRESHOLD
const LOW_HP_RATIO: float = 0.5

static func total(effect_type: String) -> float:
	if not RoguelikeManager.is_active:
		return 0.0
	return RoguelikeManager.get_artifact_effect_total(effect_type) \
		+ RoguelikeManager.get_order_effect_total(effect_type) \
		+ RoguelikeManager.get_hero_effect_total(effect_type)

static func player_hp_mult() -> float:
	return maxf(1.0 + total("unit_hp_pct"), 0.1)

static func player_armor(base_armor: int) -> int:
	var scaled: float = float(base_armor) * maxf(1.0 + total("armor_pct"), 0.0)
	var flat: float = total("unit_armor_flat") + total("armor_flat_bonus")
	return maxi(int(round(scaled + flat)), 0)

static func player_damage_mult() -> float:
	return maxf(1.0 + total("unit_damage_pct"), 0.1)

static func damage_type_mult(damage_type: int, is_ranged: bool) -> float:
	var m: float = 1.0
	m += total("ranged_damage_pct") if is_ranged else total("melee_damage_pct")
	if damage_type == DMG_PIERCE:
		m += total("pierce_damage_pct")
	elif damage_type == DMG_MAGIC:
		m += total("magic_damage_pct")
	return maxf(m, 0.1)

static func enemy_damage_mult() -> float:
	return maxf((1.0 + total("enemy_damage_pct")) * enemy_scale_damage(), 0.1)

static func player_move_mult() -> float:
	return maxf(1.0 + total("unit_move_speed_pct") + total("rally_move_speed"), 0.1)

static func player_attack_interval_mult() -> float:
	return 1.0 / maxf(1.0 + total("unit_attack_speed_pct"), 0.1)

static func enemy_attack_interval_mult() -> float:
	return 1.0 / maxf(1.0 + total("enemy_attack_speed_pct"), 0.1)

static func node_gold(base_gold: int) -> int:
	return maxi(base_gold + int(total("gold_per_node")), 0)

static func kill_gold() -> int:
	return maxi(int(total("death_gold") + total("gold_on_kill")), 0)

static func wave_shield() -> int:
	return maxi(int(total("first_wave_shield")), 0)

static func wave_regen_pct() -> float:
	return maxf(total("regen_per_wave_pct"), 0.0)

static func is_ranged_unit(attack_range: float) -> bool:
	return attack_range > RANGED_THRESHOLD

static func bleed_damage_mult() -> float:
	return maxf(1.0 + total("bleed_damage_pct"), 0.1)

static func card_cooldown_sec() -> float:
	if not RoguelikeManager.is_active:
		return 0.0
	var mult: float = 1.0 + total("deploy_cooldown_pct")
	return maxf(Constants.ROGUELIKE_CARD_COOLDOWN_SEC * clampf(mult, 0.2, 3.0), 0.0)

static func crystal_revive_charges() -> int:
	return maxi(int(total("revive_once")), 0)

static func enemy_scale_hp() -> float:
	if not RoguelikeManager.is_active:
		return 1.0
	return _enemy_scale(Constants.ROGUELIKE_ENEMY_HP_PER_FLOOR) \
		* RoguelikeManager.ascension_enemy_hp_mult()

static func enemy_scale_damage() -> float:
	if not RoguelikeManager.is_active:
		return 1.0
	return _enemy_scale(Constants.ROGUELIKE_ENEMY_DMG_PER_FLOOR) \
		* RoguelikeManager.ascension_enemy_damage_mult()

static func enemy_scale_armor_flat() -> int:
	if not RoguelikeManager.is_active:
		return 0
	var depth: int = maxi(RoguelikeManager.current_floor - 1, 0)
	var flat: float = float(depth * Constants.ROGUELIKE_ENEMY_ARMOR_PER_FLOOR)
	return maxi(int(round(flat * RoguelikeManager.node_stat_mult())), 0)

static func _enemy_scale(per_floor: float) -> float:
	if not RoguelikeManager.is_active:
		return 1.0
	var depth: int = maxi(RoguelikeManager.current_floor - 1, 0)
	return maxf((1.0 + float(depth) * per_floor) * RoguelikeManager.node_stat_mult(), 0.1)

static func low_hp_damage_mult(hp_ratio: float) -> float:
	if hp_ratio > LOW_HP_RATIO:
		return 1.0
	return maxf(1.0 + total("damage_pct_at_low_hp"), 0.1)

static func regen_per_sec_pct() -> float:
	return maxf(total("regen_per_sec_pct"), 0.0)

static func burn_field_damage() -> int:
	return maxi(int(total("burn_field_damage")), 0)

static func enemy_retreat_pct() -> float:
	return clampf(total("enemy_retreat_pct"), 0.0, 1.0)

static func death_explosion_damage() -> int:
	return maxi(int(total("death_explosion_damage")), 0)
