extends Node
class_name RoguelikeDirector
## 肉鸽（随机）模式波次导演
##
## 由 battle_root 在 RoguelikeManager.is_active 时实例化并调用 setup()。
## 职责边界：只负责「刷怪节奏 + 单局胜负判定 + 通关奖励衔接」。
##   - 抽牌 / 牌库 / 层数数据：RoguelikeManager
##   - 单位生成 / 死亡统计 / 战斗主循环：BattleManager
##   - 手牌 UI / 拖放部署：roguelike_hud
## 本节点不直接操作任何单位节点，只通过 BattleManager.spawn_unit 与 RoguelikeManager 协作。

## 相邻两波敌军的刷新间隔（秒）
const WAVE_INTERVAL: float = 10.0
## 单层基础波数（实际波数 = 本值 + 当前层数，受 WAVES_CAP 限制）
const WAVES_BASE: int = 2
## 单层波数上限（防止后期层数过深时波数爆炸）
const WAVES_CAP: int = 5
## 每波基础敌人数（实际数量 = 本值 + 波次序号，第 1 波=3、第 2 波=4…）
const ENEMY_BASE_COUNT: int = 2
## 战场持续型效果（急救回血 / 火攻灼烧）的结算间隔（秒）
const FIELD_TICK_INTERVAL: float = 1.0
## 单层通关基础金币（实际值 = 本值 + 层数 × FLOOR_GOLD_STEP，再叠加文物加成）
const CLEAR_GOLD_BASE: int = 30
## 每深入一层额外增加的通关金币
const FLOOR_GOLD_STEP: int = 5
## 线性（非地图）模式的最终层：清掉该层即视为击败最终 Boss，整局通关 → 弹胜利界面 + 播 BGM（#204）
## 地图模式的终点由地图 Boss 节点决定，不依赖此常量
const LINEAR_FINAL_FLOOR: int = 10

## 战场节点引用（用于潜在的关卡衔接，当前主要作为存在性校验）
var _battlefield: Node2D = null
## 肉鸽专用 HUD（用于刷新顶部波次文本）
var _hud: CanvasLayer = null
## 是否由地图节点进入本场战斗（true=从 roguelike_meta 选节点进来；false=旧线性多层流程）
## 由当前已选节点下标判定：地图模式下 current_node_index >= 0
var is_map_mode: bool = false
## 地图模式下本场敌军的阶层上限（每场战斗从节点读取）
var _enemy_tier: int = 1
## 波次刷新倒计时累加器
var _wave_timer: float = 0.0
## 当前已刷出的波次序号（从 1 起）
var _current_wave: int = 0
## 本层总波数
var _total_waves: int = 0
## 本层所有波次是否已全部刷出
var _all_waves_spawned: bool = false
## 本层结算（胜/负）是否已触发，防止重复结算
var _ended: bool = false
## 通关奖励界面是否打开（打开期间冻结波次与胜负判定）
var _reward_open: bool = false
## 战场每秒效果的计时累加器
var _field_tick: float = 0.0
## 「白旗休战令」清场期间抑制击杀金币，避免敌军撤退也算战功
var _suppress_kill_gold: bool = false

## 注入依赖并启动本层波次
func setup(battlefield: Node2D, hud: CanvasLayer) -> void:
	_battlefield = battlefield
	_hud = hud
	## 地图模式下玩家已通过 select_node 选定了具体节点（current_node_index >= 0）
	is_map_mode = RoguelikeManager.current_node_index >= 0
	BattleManager.unit_removed.connect(_on_unit_removed)
	## 敌军撤退（军令「围三阙一令」）只清波次、不结算赏金，故走独立信号
	BattleManager.unit_retreated.connect(_on_unit_retreated)
	## 军令的即时结算（补牌 / 治疗 / 跳波…）在本节点执行；
	## 持续型加成不用监听，打出后已写进 active_order_effects，由 RunModifiers 实时查询
	RoguelikeManager.order_played.connect(_on_order_played)
	_start_floor_waves()
	## #6：战斗开始时播报当前英雄特长（顶部提示停留 5 秒）
	_flash_hero_special()

func _exit_tree() -> void:
	## 场景卸载时断开单例信号，避免残留连接指向已释放节点
	if BattleManager.unit_removed.is_connected(_on_unit_removed):
		BattleManager.unit_removed.disconnect(_on_unit_removed)
	if BattleManager.unit_retreated.is_connected(_on_unit_retreated):
		BattleManager.unit_retreated.disconnect(_on_unit_retreated)
	if RoguelikeManager.order_played.is_connected(_on_order_played):
		RoguelikeManager.order_played.disconnect(_on_order_played)

func _process(delta: float) -> void:
	## 战斗未激活 / 已暂停 / 奖励界面打开 / 已结算 时均跳过波次推进
	if not BattleManager.is_battle_active or BattleManager.is_paused or _reward_open or _ended:
		return
	## 战场持续型效果按秒结算，与波次推进解耦（波次刷完后仍需继续回血 / 灼烧）
	_tick_field_effects(delta)
	## 所有波次已刷完，胜负交由 _check_end_conditions 在敌军清空时判定
	if _all_waves_spawned:
		return
	## 清波制推进：当前波敌军未全灭前不进入下一波（第一波由 _start_floor_waves 立即刷出）
	if not _current_wave_enemies_cleared():
		return
	## #13：全灭即刷新——正常情况下 _wave_timer 为 0，直接进下一波，不再空等 10 秒。
	## _wave_timer 保留给军令「佯攻令」(enemy_wave_delay) 临时压后下一波使用。
	if _wave_timer > 0.0:
		_wave_timer -= delta
		return
	_spawn_wave()

## 当前波敌军是否已全部阵亡（清波制推进条件：第一波敌人全部死亡后才进入第二波）
func _current_wave_enemies_cleared() -> bool:
	for u in BattleManager.enemy_units:
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			return false
	return true

## 重置并启动某一层的波次（每层开局与第一波立即刷新）
func _start_floor_waves() -> void:
	_current_wave = 0
	_all_waves_spawned = false
	if is_map_mode:
		## 地图模式：难度取当前节点的 wave_count / enemy_tier，且每场战斗重新洗牌抽满手牌
		var node := RoguelikeManager.get_map_node(RoguelikeManager.current_node_index)
		if node != null:
			_total_waves = node.wave_count
			_enemy_tier = node.enemy_tier
		else:
			_total_waves = mini(WAVES_BASE + RoguelikeManager.current_floor, WAVES_CAP)
		RoguelikeManager.start_floor()
	else:
		_total_waves = mini(WAVES_BASE + RoguelikeManager.current_floor, WAVES_CAP)
		RoguelikeManager.refill_hand()
	_wave_timer = 0.0  ## 立即刷新第一波
	_update_wave_text()
	_spawn_wave()

## 刷出一波敌军，并在每波刷新时给玩家补满手牌
func _spawn_wave() -> void:
	_current_wave += 1
	## #8：每刷新一波敌军，英雄技能 CD 自动恢复 1 点（波次制冷却）
	HeroSkillManager.on_wave_advance()
	var count: int = ENEMY_BASE_COUNT + _current_wave
	for i in range(count):
		var res := _pick_enemy_resource() as UnitResource
		if res == null:
			continue
		## #24：肉鸽敌人从屏幕外生成——出生点放到地图左右边缘之外（|x| > FIELD_X_MAX），
		## 敌人从视野边缘走入战场，不再凭空出现在基地前方（默认出生点 ±544 在视野内）。
		## y 仍限定在出兵区域内（SPAWN_Y_CENTER ± SPAWN_Y_RANGE）。
		var side: float = -1.0 if randf() < 0.5 else 1.0
		var spawn_x: float = side * (Constants.FIELD_X_MAX + 40.0)
		var spawn_y: float = Constants.SPAWN_Y_CENTER + randf_range(-Constants.SPAWN_Y_RANGE, Constants.SPAWN_Y_RANGE)
		BattleManager.spawn_unit(res, 1, Vector2(spawn_x, spawn_y))
	if _current_wave >= _total_waves:
		_all_waves_spawned = true
	## 每波开局给场上我方单位结算文物类的护盾 / 回复
	_apply_wave_start_buffs()
	## 每波刷新把玩家手牌补到上限 —— 上一波没打出的牌保留，不弃置
	RoguelikeManager.refill_hand()
	_update_wave_text()
	_check_end_conditions()
	## #13：波次间隔归零 —— 下一波的触发条件只剩「当前波全灭」
	_wave_timer = 0.0

## 从兵种库中随机取一个符合当前阶层上限的敌军资源
## 阶层上限随波次渐进：第 1 波只出 T1 低级兵，每两波提升一档，直到节点/层数上限。
## 地图模式取本场节点的 enemy_tier 为上限；旧线性模式取 clamp(层数,1,4)。
func _pick_enemy_resource() -> UnitResource:
	var tier_cap: int = _enemy_tier if is_map_mode else clampi(RoguelikeManager.current_floor, 1, 4)
	## 随战斗深入逐渐出现高级兵：前期清一色低级，后期出现高阶兵种
	var max_tier: int = clampi(1 + int((_current_wave - 1) / 2.0), 1, tier_cap)
	var pool: Array[UnitResource] = []
	for u in UnitDatabase.unit_list:
		var res := u as UnitResource
		if res == null or res.tier > max_tier:
			continue
		if res.unit_id == "Hero1" or res.unit_id == "Hero2":
			continue  ## #3/#14/#Bug9：英雄卡不进入敌方刷怪池（爱弥斯/Doro勇士为玩家专属，禁止敌方刷出）
		pool.append(res)
	if pool.is_empty():
		## 兜底：退回全部兵种，避免空波
		for u in UnitDatabase.unit_list:
			var res := u as UnitResource
			if res != null:
				pool.append(res)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

## 刷新 HUD 顶部的「第 N 层 · 第 x/y 波」文本
func _update_wave_text() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	var text: String = tr("ROGUE_FLOOR_WAVE") % [RoguelikeManager.current_floor, _current_wave, _total_waves]
	_hud.set_wave_text(text)

## 任何单位被移除时（敌死 / 己死）都重新评估胜负；敌军阵亡时结算赏金
func _on_unit_removed(player_id: int) -> void:
	## player_id == 1 表示被移除的是敌方单位 —— 文物「无名冢砖」/ 军令「掠夺令」在此兑现
	if player_id == 1 and not _suppress_kill_gold:
		var bounty: int = RunModifiers.kill_gold()
		if bounty > 0:
			RoguelikeManager.add_gold(bounty)
	if _ended:
		return
	_check_end_conditions()

## 敌军撤退（军令「围三阙一令」）时回调：只清波次判定，不结算击杀赏金
func _on_unit_retreated(_player_id: int) -> void:
	if _ended:
		return
	_check_end_conditions()

# ---------- 文物 / 军令的战场结算 ----------

## 每波开局的文物结算：首波护盾（圣殿骑士吊坠）+ 每波回复（龙涎香炉）
func _apply_wave_start_buffs() -> void:
	## first_wave_shield 顾名思义只在本层第一波兑现，后续波次不再叠加
	var shield: int = RunModifiers.wave_shield() if _current_wave <= 1 else 0
	var regen_pct: float = RunModifiers.wave_regen_pct()
	if shield <= 0 and regen_pct <= 0.0:
		return
	for u in BattleManager.player_units:
		var unit := u as Unit
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		if shield > 0:
			unit.add_shield(shield)
		if regen_pct > 0.0:
			unit.heal(_pct_of_max_hp(unit, regen_pct))

## 每秒结算一次的战场效果：我方持续回血（战地急救令）+ 敌方战场灼烧（火攻令）
func _tick_field_effects(delta: float) -> void:
	var regen_pct: float = RunModifiers.regen_per_sec_pct()
	var burn: int = RunModifiers.burn_field_damage()
	if regen_pct <= 0.0 and burn <= 0:
		_field_tick = 0.0
		return
	_field_tick += delta
	if _field_tick < FIELD_TICK_INTERVAL:
		return
	_field_tick -= FIELD_TICK_INTERVAL
	if regen_pct > 0.0:
		for u in BattleManager.player_units:
			var unit := u as Unit
			if unit != null and is_instance_valid(unit) and not unit.is_dead:
				unit.heal(_pct_of_max_hp(unit, regen_pct))
	if burn > 0:
		## duplicate() 防止灼烧致死时 enemy_units 在遍历中被 remove_unit 修改
		for u in BattleManager.enemy_units.duplicate():
			var unit := u as Unit
			if unit != null and is_instance_valid(unit) and not unit.is_dead:
				unit.take_damage(burn)

## 取某单位最大生命的百分比（至少 1 点，避免低血量单位回复被取整成 0）
func _pct_of_max_hp(unit: Unit, pct: float) -> int:
	return maxi(int(round(float(unit.get_max_hp()) * pct)), 1)

## 军令被打出时的即时结算
## 只处理「一次性」军令；持续型加成（移速 / 护甲 / 敌方减伤…）已由 play_order 写入
## RoguelikeManager.active_order_effects，战斗层通过 RunModifiers 自动读到，无需在此处理。
func _on_order_played(_order_id: String, effect_type: String, value: float) -> void:
	match effect_type:
		"refill_hand":
			RoguelikeManager.refill_hand()
			_flash_hud(tr("ROGUE_REINFORCE"))
		"gain_random_card":
			RoguelikeManager.add_card(RoguelikeManager.roll_random_unit_id(3))
			_flash_hud(tr("ROGUE_DRAFT"))
		"remove_card_and_draw":
			_reorganize_deck()
			_flash_hud(tr("ROGUE_REORG"))
		"heal_all_pct":
			_heal_all_players(value)
			_flash_hud(tr("ROGUE_FEAST") % int(round(value * 100.0)))
		"enemy_wave_delay":
			_wave_timer += value
			_flash_hud(tr("ROGUE_FEINT") % int(round(value)))
		"base_hp_bonus":
			_fortify_base(int(value))
			_flash_hud(tr("ROGUE_FORTIFY") % int(value))
		"reveal_next_wave":
			_reveal_next_wave()
		"skip_wave":
			_skip_current_wave()
		_:
			## 持续型加成：无需即时动作，交给 RunModifiers 实时查询
			pass

## 全军按最大生命百分比回复（犒军令）
func _heal_all_players(pct: float) -> void:
	for u in BattleManager.player_units:
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			unit.heal(_pct_of_max_hp(unit, pct))

## 整编令：从永久牌库随机移除一张，再把手牌补满
func _reorganize_deck() -> void:
	if not RoguelikeManager.deck.is_empty():
		RoguelikeManager.remove_card(RoguelikeManager.deck[randi() % RoguelikeManager.deck.size()])
	RoguelikeManager.refill_hand()

## 筑垒令：为我方据点（team 0）补耐久
func _fortify_base(amount: int) -> void:
	if _battlefield == null or not is_instance_valid(_battlefield):
		return
	if _battlefield.has_method("heal_base"):
		_battlefield.heal_base(0, amount)

## 谍报令：把下一波的规模写到 HUD 提示条上
func _reveal_next_wave() -> void:
	if _all_waves_spawned:
		_flash_hud(tr("ROGUE_INTEL"))
		return
	var next_wave: int = _current_wave + 1
	_flash_hud(tr("ROGUE_INTEL_WAVE") % [next_wave, ENEMY_BASE_COUNT + next_wave, _enemy_tier])

## 白旗休战令：当前这一波已登场的敌军全部撤退（不给击杀赏金）
func _skip_current_wave() -> void:
	_suppress_kill_gold = true
	for u in BattleManager.enemy_units.duplicate():
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			unit.die()
	_suppress_kill_gold = false
	_flash_hud(tr("ROGUE_WHITEFLAG"))
	_check_end_conditions()

## 往 HUD 提示条打一条临时文本（HUD 缺失时静默忽略）
func _flash_hud(text: String) -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("show_hint"):
		_hud.show_hint(text)

## #6：战斗开始时播报当前英雄特长（如「全军 +30% 攻击与攻速」），停留 5 秒
func _flash_hero_special() -> void:
	var hero_id: String = RoguelikeManager.selected_hero
	for hero in RoguelikeManager.HERO_DEFS:
		if hero["id"] == hero_id:
			var special: String = hero.get("special", "")
			if not special.is_empty():
				_flash_hud_duration(tr("ROGUE_HERO_TRAIT") % special, 5.0)
			return

## 与 _flash_hud 类似，但提示停留 [duration] 秒后恢复（用于英雄特长等长提示，#6）
func _flash_hud_duration(text: String, duration: float) -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("show_hint_duration"):
		_hud.show_hint_duration(text, duration)

## 统一胜负判定入口（多重守卫避免重复触发）
func _check_end_conditions() -> void:
	if _ended or _reward_open or not BattleManager.is_battle_active:
		return
	## 胜利：本层所有波次已刷完 且 场上已无敌军
	if _all_waves_spawned and BattleManager.enemy_units.is_empty():
		_on_floor_cleared()
		return
	## 失败：手牌与抽牌堆皆空 且 场上己方单位全灭
	if not RoguelikeManager.has_cards_left() and BattleManager.player_units.is_empty():
		_on_run_lost()
		return

## 单层通关：暂停并弹出三选一奖励
func _on_floor_cleared() -> void:
	_ended = true
	_reward_open = true
	## 显式冻结场上所有单位（强制 idle），不单纯依赖 get_tree().paused，
	## 避免本层通关后单位仍在攻击/移动（游戏结束后仍在战斗）
	BattleManager.freeze_units()
	get_tree().paused = true
	## 通关发金币（几十金币，随层数递增，并叠加文物「糯糯米袋」gold_per_node），用于路途商店消费
	RoguelikeManager.add_gold(RunModifiers.node_gold(CLEAR_GOLD_BASE + RoguelikeManager.current_floor * FLOOR_GOLD_STEP))
	_show_reward_screen()

## 整局失败：交给既有失败结算画面
func _on_run_lost() -> void:
	_ended = true
	BattleManager.end_game(1)

## 弹出通关奖励界面（三选一）
func _show_reward_screen() -> void:
	var scene := load("res://scenes/ui/roguelike_reward.tscn") as PackedScene
	var reward := scene.instantiate() as RoguelikeReward
	add_child(reward)
	reward.choices_ready(tr("ROGUE_CHOOSE_REWARD"), RoguelikeManager.roll_reward_choices())
	reward.card_chosen.connect(_on_reward_chosen)

## 弹出肉鸽整局通关胜利界面（击败 Boss 后）。战场仍处暂停态，由胜利界面接管并管理按钮响应。
func _show_victory_screen() -> void:
	## #13：肉鸽专属成就「传奇，还是无名小卒？」——通关时判定本 run 是否全程只用 G1
	Achievements.unlock_roguelike_g1_legend()
	var screen := RoguelikeVictoryScreen.new()
	if _hud != null and is_instance_valid(_hud):
		_hud.add_child(screen)
	else:
		get_tree().current_scene.add_child(screen)

## 玩家选定奖励卡（unit_id 为空表示跳过）
func _on_reward_chosen(unit_id: String) -> void:
	if not unit_id.is_empty():
		RoguelikeManager.add_card(unit_id)
	if is_map_mode:
		## 地图模式：若刚通关的是 Boss 节点，整局完成 → 弹专属胜利界面（不回地图 hub）
		var node := RoguelikeManager.get_map_node(RoguelikeManager.current_node_index)
		if node != null and node.node_type == RoguelikeManager.NodeType.BOSS:
			_reward_open = false
			_ended = false
			_show_victory_screen()
			return
		## 普通节点：获得卡牌后返回地图 hub，由玩家选择下一节点（不自动进层）
		_reward_open = false
		_ended = false
		get_tree().paused = false
		GameManager.enter_roguelike_map()
	else:
		## 旧线性模式：已抵达最终层 → 清场即视为击败最终 Boss，整局通关胜利（#204，与地图模式 Boss 通关对齐）
		if RoguelikeManager.current_floor >= LINEAR_FINAL_FLOOR:
			_reward_open = false
			_ended = false
			_show_victory_screen()
			return
		## 普通层：推进到下一层并重新发牌
		RoguelikeManager.advance_floor()
		_reward_open = false
		_ended = false
		get_tree().paused = false
		_start_floor_waves()
