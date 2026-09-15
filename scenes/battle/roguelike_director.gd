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
##
## 进入本场战斗一定来自地图节点（roguelike_meta 选点 → GameManager.start_game），
## 因此波数 / 敌军阶层一律读当前节点数据，不存在「线性多层」流程。

## 每波基础敌人数（实际数量 = 本值 + 波次序号，第 1 波=3、第 2 波=4…）
const ENEMY_BASE_COUNT: int = 2
## 战场持续型效果（急救回血 / 火攻灼烧）的结算间隔（秒）
const FIELD_TICK_INTERVAL: float = 1.0
## 单层通关基础金币（实际值 = 本值 + 层数 × FLOOR_GOLD_STEP，再叠加文物加成）
const CLEAR_GOLD_BASE: int = 30
## 每深入一层额外增加的通关金币
const FLOOR_GOLD_STEP: int = 5
## Boss 节点每波敌人数量的额外倍率（决战规模翻倍）
const BOSS_COUNT_MULT: float = 2.0

## 战场节点引用（水晶加血 / 免死等回调需要）
var _battlefield: Node2D = null
## 肉鸽专用 HUD（用于刷新顶部波次文本）
var _hud: CanvasLayer = null
## 本场敌军的阶层上限（每场战斗从节点读取）
var _enemy_tier: int = 1
## 波次刷新倒计时累加器（仅军令「佯攻令」延迟下一波时使用）
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
## 本场节点类型（COMBAT / ELITE / BOSS）
var _node_type: int = RoguelikeManager.NodeType.COMBAT

## 注入依赖并启动本层波次
func setup(battlefield: Node2D, hud: CanvasLayer) -> void:
	_battlefield = battlefield
	_hud = hud
	_node_type = RoguelikeManager.current_node_type()
	BattleManager.unit_removed.connect(_on_unit_removed)
	## 敌军撤退（军令「围三阙一令」）只清波次、不结算赏金，故走独立信号
	BattleManager.unit_retreated.connect(_on_unit_retreated)
	RoguelikeManager.order_played.connect(_on_order_played)
	if _battlefield != null and is_instance_valid(_battlefield) \
			and _battlefield.has_signal("base_revive_requested"):
		_battlefield.base_revive_requested.connect(_on_crystal_revive_requested)
	_start_floor_waves()
	_flash_hero_special()

func _exit_tree() -> void:
	if BattleManager.unit_removed.is_connected(_on_unit_removed):
		BattleManager.unit_removed.disconnect(_on_unit_removed)
	if BattleManager.unit_retreated.is_connected(_on_unit_retreated):
		BattleManager.unit_retreated.disconnect(_on_unit_retreated)
	if RoguelikeManager.order_played.is_connected(_on_order_played):
		RoguelikeManager.order_played.disconnect(_on_order_played)

func _process(delta: float) -> void:
	if not BattleManager.is_battle_active or BattleManager.is_paused or _reward_open or _ended:
		return
	## 手牌冷却推进（部署节奏控制），与波次推进解耦
	RoguelikeManager.tick_card_cooldowns(delta)
	## 战场持续型效果按秒结算（波次刷完后仍需继续回血 / 灼烧）
	_tick_field_effects(delta)
	if _all_waves_spawned:
		return
	## 清波制推进：当前波敌军未全灭前不进入下一波（第一波由 _start_floor_waves 立即刷出）
	if not _current_wave_enemies_cleared():
		return
	if _wave_timer > 0.0:
		_wave_timer -= delta
		return
	_spawn_wave()

## 当前波敌军是否已全部阵亡（清波制推进条件）
func _current_wave_enemies_cleared() -> bool:
	for u in BattleManager.enemy_units:
		var unit := u as Unit
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			return false
	return true

## 重置并启动本节点的波次（每层开局与第一波立即刷新）
func _start_floor_waves() -> void:
	_current_wave = 0
	_all_waves_spawned = false
	var node := RoguelikeManager.get_map_node(RoguelikeManager.current_node_index)
	if node != null:
		_total_waves = node.wave_count
		_enemy_tier = node.enemy_tier
	else:
		## 兜底：节点数据缺失时按层数推波，保证战斗仍可正常结束
		_total_waves = clampi(2 + RoguelikeManager.current_floor, 2, 5)
		_enemy_tier = clampi(1 + int(RoguelikeManager.current_floor / 2.0), 1, 4)
	RoguelikeManager.start_floor()
	_wave_timer = 0.0
	_update_wave_text()
	_spawn_wave()

## 刷出一波敌军，并在每波刷新时给玩家补满手牌
func _spawn_wave() -> void:
	_current_wave += 1
	HeroSkillManager.on_wave_advance()
	var count: int = ENEMY_BASE_COUNT + _current_wave
	if _node_type == RoguelikeManager.NodeType.BOSS:
		count = int(round(float(count) * BOSS_COUNT_MULT))
	for i in range(count):
		var res := _pick_enemy_resource() as UnitResource
		if res == null:
			continue
		## 敌人从屏幕外生成（|x| > FIELD_X_MAX），走入战场后向中央水晶合围
		var side: float = -1.0 if randf() < 0.5 else 1.0
		var spawn_x: float = side * (Constants.FIELD_X_MAX + 40.0)
		var spawn_y: float = Constants.SPAWN_Y_CENTER + randf_range(-Constants.SPAWN_Y_RANGE, Constants.SPAWN_Y_RANGE)
		BattleManager.spawn_unit(res, 1, Vector2(spawn_x, spawn_y))
		_decorate_spawned_enemy()
	if _current_wave >= _total_waves:
		_all_waves_spawned = true
	_apply_wave_start_buffs()
	RoguelikeManager.refill_hand()
	_update_wave_text()
	_check_end_conditions()
	_wave_timer = 0.0

## Boss 节点：把刚生成的敌军体型放大（用户拍板 ×2）
func _decorate_spawned_enemy() -> void:
	if _node_type != RoguelikeManager.NodeType.BOSS:
		return
	if BattleManager.enemy_units.is_empty():
		return
	var unit := BattleManager.enemy_units.back() as Unit
	if unit == null or not is_instance_valid(unit):
		return
	unit.visual_scale_mult = Constants.ROGUELIKE_BOSS_SCALE_MULT

## 从兵种库中随机取一个符合当前阶层上限的敌军资源
## 阶层上限随波次渐进：第 1 波只出低阶兵，每两波提升一档，直到节点阶层上限。
func _pick_enemy_resource() -> UnitResource:
	var max_tier: int = clampi(1 + int((_current_wave - 1) / 2.0), 1, _enemy_tier)
	var pool: Array[UnitResource] = []
	for u in UnitDatabase.unit_list:
		var res := u as UnitResource
		if res == null or res.tier > max_tier:
			continue
		## 英雄卡（Hero 前缀）为玩家专属，一律不进敌方刷怪池
		if UnitDatabase.is_hero_unit(res.unit_id):
			continue
		pool.append(res)
	if pool.is_empty():
		## 兜底：放宽到节点阶层上限内的全部非英雄兵种，避免空波
		for u in UnitDatabase.unit_list:
			var res := u as UnitResource
			if res == null or UnitDatabase.is_hero_unit(res.unit_id):
				continue
			if res.tier <= _enemy_tier:
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

## 任何单位被移除时（敌死 / 己死）都重新评估胜负；敌军阵亡时结算赏金与击杀统计
func _on_unit_removed(player_id: int) -> void:
	if player_id == 1 and not _suppress_kill_gold:
		RoguelikeManager.add_stat("kills")
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
## 只处理「一次性」军令；持续型加成由 RunModifiers 实时读取 active_order_effects。
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
		"deploy_cooldown_pct":
			## 疾行军令：立即清空当前所有手牌冷却，后续冷却按百分比缩短（RunModifiers 实时读取）
			RoguelikeManager.clear_card_cooldowns()
			_flash_hud("疾行军令：出兵冷却缩短 %d%%，当前冷却已清空" % int(round(absf(value) * 100.0)))
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
	var count: int = ENEMY_BASE_COUNT + next_wave
	if _node_type == RoguelikeManager.NodeType.BOSS:
		count = int(round(float(count) * BOSS_COUNT_MULT))
	_flash_hud(tr("ROGUE_INTEL_WAVE") % [next_wave, count, _enemy_tier])

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

## 战斗开始时播报当前英雄特长，停留 5 秒
func _flash_hero_special() -> void:
	var special: String = RoguelikeManager.get_hero_special_text()
	if special.is_empty():
		return
	_flash_hud_duration(tr("ROGUE_HERO_TRAIT") % special, 5.0)

## 与 _flash_hud 类似，但提示停留 [duration] 秒后恢复
func _flash_hud_duration(text: String, duration: float) -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("show_hint_duration"):
		_hud.show_hint_duration(text, duration)

## 水晶被击破时的免死请求（文物「Doro 的破布娃娃」revive_once）
## 返回 true 表示本次免死已生效，战场应把水晶血量拉回而不结算失败。
func _on_crystal_revive_requested() -> void:
	_flash_hud("破布娃娃替你挨了一次！水晶耐久已回复")

## 统一胜负判定入口（多重守卫避免重复触发）
func _check_end_conditions() -> void:
	if _ended or _reward_open or not BattleManager.is_battle_active:
		return
	## 胜利：本层所有波次已刷完 且 场上已无敌军
	if _all_waves_spawned and BattleManager.enemy_units.is_empty():
		_on_floor_cleared()
		return
	## 失败：手牌与抽牌堆里都没有兵种卡（军令卡不算）且场上己方单位全灭
	if not RoguelikeManager.has_cards_left() and BattleManager.player_units.is_empty():
		_on_run_lost()
		return

## 单层通关：暂停并弹出奖励（精英 / Boss 额外给文物）
func _on_floor_cleared() -> void:
	_ended = true
	_reward_open = true
	BattleManager.freeze_units()
	get_tree().paused = true
	RoguelikeManager.add_gold(RunModifiers.node_gold(CLEAR_GOLD_BASE + RoguelikeManager.current_floor * FLOOR_GOLD_STEP))
	_show_reward_screen()

## 整局失败：归档战绩后交给失败结算画面
func _on_run_lost() -> void:
	_ended = true
	RoguelikeManager.archive_run(false)
	BattleManager.end_game(1)

## 弹出通关奖励界面（三选一兵种卡）
func _show_reward_screen() -> void:
	var scene := load("res://scenes/ui/roguelike_reward.tscn") as PackedScene
	var reward := scene.instantiate() as RoguelikeReward
	add_child(reward)
	reward.choices_ready(tr("ROGUE_CHOOSE_REWARD"), RoguelikeManager.roll_reward_choices())
	reward.card_chosen.connect(_on_reward_chosen)

## 精英 / Boss 的额外文物三选一（在兵种卡奖励之后弹出）
func _show_artifact_reward() -> void:
	var scene := load("res://scenes/ui/roguelike_reward.tscn") as PackedScene
	var reward := scene.instantiate() as RoguelikeReward
	reward.artifact_chosen.connect(_on_artifact_reward_chosen)
	add_child(reward)
	var title: String = "决战战利品：三选一获得文物" if _node_type == RoguelikeManager.NodeType.BOSS \
			else "精英战利品：三选一获得文物"
	reward.choices_artifacts_ready(title, ItemDatabase.roll_artifacts(3, RoguelikeManager.owned_artifacts))

## 弹出肉鸽整局通关胜利界面（击败 Boss 后）
## 自建高层 CanvasLayer 承载，避免挂到会被 battle_root 隐藏的肉鸽 HUD，
## 也避免挂到 Node2D 场景根导致界面被摄像机变换缩放/偏移。
func _show_victory_screen() -> void:
	Achievements.unlock_roguelike_g1_legend()
	RoguelikeManager.archive_run(true)
	## 本局已通关：删掉 hub 存档，否则「继续上次征程」会读到一个所有节点都已走完、
	## 无路可走的死局
	RoguelikeManager.clear_save()
	var layer := CanvasLayer.new()
	layer.name = "RoguelikeVictoryLayer"
	layer.layer = 11
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(layer)
	layer.add_child(RoguelikeVictoryScreen.new())

## 玩家选定奖励卡（unit_id 为空表示跳过）
func _on_reward_chosen(unit_id: String) -> void:
	if not unit_id.is_empty():
		RoguelikeManager.add_card(unit_id)
	## 精英 / Boss 额外给一件文物，选完文物才继续
	if _node_type == RoguelikeManager.NodeType.ELITE or _node_type == RoguelikeManager.NodeType.BOSS:
		_show_artifact_reward()
		return
	_finish_node()

## 玩家选定额外文物（artifact_id 为空表示跳过）
func _on_artifact_reward_chosen(artifact_id: String) -> void:
	if not artifact_id.is_empty():
		RoguelikeManager.add_artifact(artifact_id)
	_finish_node()

## 本节点全部奖励结算完毕：Boss → 通关胜利界面；普通节点 → 存档并回地图 hub
func _finish_node() -> void:
	if _node_type == RoguelikeManager.NodeType.BOSS:
		_reward_open = false
		_ended = false
		_show_victory_screen()
		return
	_reward_open = false
	_ended = false
	## 战斗节点通关后立即存档：从此处退出再进入即可从 hub 继续
	RoguelikeManager.save_run()
	get_tree().paused = false
	GameManager.enter_roguelike_map()
