extends Node  ## 继承自 Node 节点类
## 战斗/回合管理器（全局单例）
## 管理战斗流程、倒计时、持续出兵、单位生成等核心战斗逻辑

## 信号：单位被生成时发出
signal unit_spawned(unit: Node2D, player_id: int)
## 信号：单位被移除时发出
signal unit_removed(player_id: int)
## 信号：基地受到攻击造成扣血时转发（由 battlefield.base_damaged 转发，HUD 扣血日志条监听）
## team: 被攻击方阵营, damage: 扣血值, attacker: 攻击者
signal base_damaged(team: int, damage: int, attacker: Node)
## 信号：敌军撤退（军令「围三阙一令」）时发出 —— 与 unit_removed 区隔：
## 撤退的敌军从列表中移除使波次可清空，但不计击杀赏金（由 director 据此跳过金币结算）
signal unit_retreated(player_id: int)
## 信号：倒计时更新时发出
signal countdown_tick(time_left: float)
## 信号：回合结束时发出
signal round_end(round_number: int)
## 信号：游戏结束时发出
signal game_over(winner_team: int)
## 信号：玩家/AI 选择兵种变化时发出
## player_id: 玩家 ID, unit_res: 选择的兵种资源（null 表示取消选择）
signal selection_changed(player_id: int, unit_res: Resource)

## 每个玩家当前选择的兵种数组
var selected_units: Array[Resource] = [null, null]
## 当前回合倒计时计时器
var countdown_timer: float = 0.0
## 战斗是否正在进行中
var is_battle_active: bool = false
## 游戏是否暂停
var is_paused: bool = false
## 是否为双人模式
var is_two_player: bool = false

## #自由事件（2026-08-15）：仓鼠士兵觉醒状态（#18-8：手动触发已改为直接召唤 S2，不再有变身标记）
## _g1_hamster_force：开发工具百分百开关——部署 G1 时 1% 随机觉醒必中（每次部署必变）
## 范围：战役/全面战争仅我方（红方）；双人模式红蓝双方都有效。肉鸽不触发。
## 凑企鹅（Y2）每回合 1% 触发开关（战役/全面战争；双人不触发）
var _penguin_event_enabled: bool = true
## 开发工具：仓鼠士兵觉醒强制百分百触发（部署 G1 时掷点必中）
var _g1_hamster_force: bool = false

## 异象/特殊事件（死亡使者 Y1 / 蓝女巫 S1）一局内各最多触发一次
## 范围：战役 / 全面战争（非双人、非肉鸽）
var _y1_triggered: bool = false  ## 死亡使者（Y1）事件本局是否已触发
var _s1_triggered: bool = false  ## 蓝女巫（S1）事件本局是否已触发

## 开发工具：全面战争（单人沙盒）模式下敌方 AI 可出动的阵营开关
## 键为阵营前缀（G=咕嘎, D=Doro, F=菲比, N=糯糯），值为是否允许敌方部署
## 仅在「全面战争」模式（非战役、非双人）生效；默认四个阵营全部放开
var enemy_faction_enabled: Dictionary = {"G": true, "D": true, "F": true, "N": true}

## 开发工具：请求对指定阵营基地（水晶）造成固定伤害（用于调试）
## 由 battle_root 监听并转发给 battlefield.damage_base
signal dev_base_damage_requested(team: int, amount: int)
## #21：开发工具请求为指定阵营水晶直接加血（可超上限）
signal dev_base_boost_requested(team: int, amount: int)
## #4（2026-08-11）：异象入侵/特殊事件单位生成后请求镜头自动聚焦该单位
## （由 battle_root 监听并临时锁定镜头跟随数秒后恢复）
signal event_unit_focus_requested(unit: Node2D)
## 单位场景缓存
var unit_scene: PackedScene
## 玩家单位列表
var player_units: Array = []
## 敌方单位列表
var enemy_units: Array = []
## 每个玩家独立的持续出兵计时器（控制出兵频率）
## 索引 0=红方, 1=蓝方；按各自剩余金币动态加速
var spawn_timers: Array[float] = [0.0, 0.0]
## 基础出兵间隔（秒），实际间隔 = SPAWN_INTERVAL / 速度倍率
const SPAWN_INTERVAL: float = 1.0
## 出兵速度加速阈值：剩余金币每达到此值的倍数，出兵速度 +0.25
const SPAWN_SPEED_GOLD_STEP: int = 500
## 每达到一个加速阈值增加的出兵速度倍率
const SPAWN_SPEED_BONUS: float = 0.25
## #2：回合制批量出兵阈值——20 回合后每次出 2 个，30 回合后每次出 3 个
const BATCH_SPAWN_ROUND_TIER2: int = 20  ## 20 回合起每次出 2 个
const BATCH_SPAWN_ROUND_TIER3: int = 30  ## 30 回合起每次出 3 个

## 节点就绪时自动调用，重置战斗状态
func _ready() -> void:
	reset()  ## 调用重置方法初始化战斗数据

## 每帧调用的处理函数，处理战斗主循环逻辑
## delta: 上一帧到当前帧的时间间隔（秒）
func _process(delta: float) -> void:
	## 战斗未激活或已暂停时，跳过本帧处理
	if not is_battle_active or is_paused:
		return

	## 持续出兵逻辑：每个玩家独立的出兵计时器，按剩余金币动态加速
	## 速度倍率 = 1.0 + floor(gold / 500) * 0.25（剩余金币越多出兵越快）
	for player_id in range(2):
		## #11 单发出兵：开启后禁用持续自动出兵，仅在“选中/点击”事件时出 1 个（见 set_selected_unit / deploy_selected_once）
		if DevMode.single_spawn:
			continue
		## 仅当该玩家已选择兵种时才尝试出兵
		if selected_units[player_id] == null:
			continue
		## 按剩余金币计算该玩家的出兵速度倍率
		var speed_mult: float = get_spawn_speed_multiplier(player_id)
		## 计时器按倍率加速递减
		spawn_timers[player_id] -= delta * speed_mult
		if spawn_timers[player_id] > 0.0:
			continue
		## 重置该玩家的出兵计时器
		spawn_timers[player_id] = SPAWN_INTERVAL
		## #2：回合制批量出兵——20 回合后每次出 2 个，30 回合后每次出 3 个
		var batch_count: int = 1
		## #11：开发工具「出兵限制」——开启后每次出兵严格只出 1 个
		## #1（2026-08-11 用户拍板）：原先仅玩家方生效（AI 不受影响），导致全面战争蓝方 AI
		## 仍批量出兵、用户认为开关没实现。现改为对双方一律生效（双人双方 / 全面战争 AI 同限）。
		if not DevMode.single_spawn:
			var round_num: int = EconomyManager.current_round
			if round_num >= BATCH_SPAWN_ROUND_TIER3:
				batch_count = 3
			elif round_num >= BATCH_SPAWN_ROUND_TIER2:
				batch_count = 2
		## 批量出兵：每次尝试购买+生成一个单位，金币不足或人口到顶则停止本批
		for _i in range(batch_count):
			## 根据玩家 ID 获取当前己方单位数量
			var current_count: int = player_units.size() if player_id == 0 else enemy_units.size()
			## 检查是否已达单方单位上限（含人口升级加成，#138）
			if current_count >= EconomyManager.get_max_population(player_id):
				break  ## 人口到顶，本批停止
			## 尝试购买兵种，购买成功则生成单位；金币不足则停止本批
			if not EconomyManager.purchase_unit(player_id, selected_units[player_id]):
				break  ## 金币不足，本批停止
			spawn_unit(selected_units[player_id], player_id)

	## #19：远程火力均衡分配（仅常规模式：战役/双人/全面战争）
	## 肉鸽模式守卫 AI 有独立的索敌/牵引体系（chase_range/leash），不干预。
	_distribute_ranged_targets()

	## 倒计时递减
	countdown_timer -= delta
	countdown_timer = maxf(countdown_timer, 0.0)  ## 限制倒计时最小值为 0
	countdown_tick.emit(countdown_timer)  ## 发出倒计时更新信号，通知 UI 显示

	## 回合结算：倒计时归零时执行回合结算
	if countdown_timer <= 0.0:
		execute_round()

## 获取指定玩家的出兵速度倍率
## 剩余金币每有 500 则出兵速度增加 0.25（即倍率 +0.25）
## 回合数越高出兵越快：每回合额外 +5% 速度（第10回合约1.45倍，第20回合约1.95倍）
## player_id: 玩家 ID（0=红方, 1=蓝方）
## 返回值: 出兵速度倍率（>= 1.0）
func get_spawn_speed_multiplier(player_id: int) -> float:
	var gold: int = EconomyManager.get_gold(player_id)
	var bonus_steps: int = int(gold) / SPAWN_SPEED_GOLD_STEP
	var gold_mult: float = 1.0 + bonus_steps * SPAWN_SPEED_BONUS
	## 回合数加成：每回合 +5% 出兵速度，让后期战斗节奏加快
	var round_mult: float = 1.0 + float(EconomyManager.current_round - 1) * 0.05
	return gold_mult * round_mult

## 重置战斗系统到初始状态
## 清空所有单位列表、选择状态、计时器，并将战斗状态设为未激活
func reset() -> void:
	selected_units = [null, null]  ## 清空双方兵种选择
	countdown_timer = EconomyManager.get_round_time()  ## 从经济管理器获取本回合倒计时时长
	is_battle_active = false  ## 战斗状态置为未激活
	is_paused = false  ## 暂停状态置为否
	spawn_timers = [0.0, 0.0]  ## 双方出兵计时器归零（下次帧立即出兵）
	player_units.clear()  ## 清空玩家方单位列表
	enemy_units.clear()  ## 清空敌方单位列表
	## #自由事件（2026-08-15）：仓鼠士兵觉醒状态按局清空（#18-8：仅剩百分百开关，无需按局清理字典）
	## （_g1_hamster_force 为开关，跨局保留由 DevMode 控制台管理）
	_y1_triggered = false  ## 死亡使者事件按局清空
	_s1_triggered = false  ## 蓝女巫事件按局清空

## 开始战斗的方法
## 重置经济与战斗数据，激活战斗状态并启动倒计时
func start_battle() -> void:
	EconomyManager.reset()  ## 重置经济系统到初始状态
	## #14（2026-08-09 用户拍板）：战役强敌关（3/6/10）敌方开局金币 300（总值）、
	## 每回合收入固定 110、开局人口 11；其余关卡双方同基准（旧分档加成 100/200/300 已废弃）
	var is_strong_level: bool = GameManager.is_campaign_mode \
			and CampaignProgress.BOSS_LEVELS.has(GameManager.selected_campaign_level)
	if is_strong_level:
		EconomyManager.set_gold(1, 300)  ## 开局金币 300（总值）
		EconomyManager.enemy_income_override = 110  ## 每回合收入固定 110
		EconomyManager.bonus_population[1] = 1  ## 开局人口 11（基础上限 10 + 1）
	reset()  ## 重置战斗系统到初始状态
	is_battle_active = true  ## 激活战斗状态
	countdown_timer = EconomyManager.get_round_time()  ## 设置初始回合倒计时

## 执行回合结算
## 对双方玩家进行经济结算、发出回合结束信号、进入下一回合并重置倒计时
func execute_round() -> void:
	## 回合结算（收入转化为金币）
	for player_id in range(2):
		EconomyManager.settle_round(player_id)  ## 对每个玩家执行回合结算
	
	## 发出回合结束信号（注意：此时 current_round 尚未递增，所以是当前回合号）
	round_end.emit(EconomyManager.current_round - 1)
	
	## 进入下一回合
	EconomyManager.next_round()  ## 回合数 +1
	countdown_timer = EconomyManager.get_round_time()  ## 重置新回合的倒计时
	
	## 死亡使者（Y1）/ 蓝女巫（S1）异象事件判定
	## 范围：战役 / 全面战争（非双人、非肉鸽）；双人不触发、肉鸽不触发
	## 一局内各自最多触发一次（_y1_triggered / _s1_triggered 封顶）
	if not RoguelikeManager.is_active and not is_two_player:
		_check_death_reaper_event()
	
	## 凑企鹅事件（2026-08-15）：每回合倒计时结束掷 1%，命中敌方刷一只凑企鹅（Y2）
	## 范围：战役/全面战争；双人不触发；肉鸽不触发
	if _penguin_event_enabled and not RoguelikeManager.is_active and not is_two_player:
		if randf() < 0.01:
			_try_spawn_penguin_event()

## 凑企鹅事件：敌方刷一只凑企鹅（Y2），并开启「存活期间每秒 5% 召 S1 蓝女巫入我方」追踪
func _try_spawn_penguin_event() -> void:
	var res: Resource = UnitDatabase.get_unit("Y2")
	if res == null:
		return
	print("[自由事件] 凑企鹅入侵！敌方增加凑企鹅")
	spawn_unit(res, 1)  ## 敌方（蓝方）
	if not enemy_units.is_empty():
		event_unit_focus_requested.emit(enemy_units.back())
	## 解锁隐藏成就「异象入侵」（Y 前缀异象单位登场，与异象入侵事件同源）
	Achievements.unlock_by_id("anomaly_invasion")
	## 追踪凑企鹅存活：每秒 5% 召 S1 蓝女巫入我方（#自由事件：专召 S1）
	_start_penguin_tracker()

## 凑企鹅存活追踪器：每秒 5% 概率召 S1 蓝女巫（特殊阵营）加入我方红方
## 场上无存活凑企鹅（Y2）时自动销毁
func _start_penguin_tracker() -> void:
	var tracker := Timer.new()
	tracker.wait_time = 1.0
	tracker.one_shot = false
	tracker.name = "_penguin_tracker_%d" % Time.get_ticks_msec()
	var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() else null
	if root == null:
		return
	root.add_child(tracker)
	tracker.timeout.connect(func() -> void:
		## 场上是否仍有存活凑企鹅（Y2）
		var alive: bool = false
		for u in enemy_units:
			if is_instance_valid(u) and not u.is_dead and u.unit_resource != null and u.unit_resource.unit_id == "Y2":
				alive = true
				break
		if not alive:
			tracker.queue_free()
			return
		if randf() > 0.05:
			return
		## 专召 S1 蓝女巫入我方（红方）
		var s1: Resource = UnitDatabase.get_unit("S1")
		if s1 == null:
			return
		spawn_unit(s1, 0)
		if not player_units.is_empty():
			event_unit_focus_requested.emit(player_units.back())
		print("[自由事件] 蓝女巫降临！凑企鹅引来特殊援军")
		_show_special_event_text("S1")
		Achievements.unlock_by_id("parallel_heroes")
	)

## 死亡使者（Y1）异象事件：概率判定 + 触发（事件触发制，固定刷 Y1）
## 难度映射：普通5% / 困难10% / 地狱15%；一局内最多触发一次
func _check_death_reaper_event() -> void:
	## 一局内最多触发一次（封顶）
	if _y1_triggered:
		return
	## 难度映射：普通5% / 困难10% / 地狱15%
	var diff: int = GameManager.current_difficulty
	var chances: Array[float] = [0.05, 0.10, 0.15]
	var chance: float = chances[clampi(diff, 0, 2)]
	if randf() > chance:
		return

	var res: Resource = UnitDatabase.get_unit("Y1")
	if res == null:
		return
	_y1_triggered = true  ## 封顶：本局不再自然触发

	## 触发文本动画后延迟生成异象敌兵（敌方 / 蓝方）
	print("[异象入侵] 死亡使者降临！概率 %.0f%%" % [chance * 100])
	_show_anomaly_texts("Y1", res)

## 异象入侵文本动画（#5 2026-08-11 调整 / 2026-08-14 简化）：
## 仅保留「异象入侵！！！」红色大字（72号、3s，固定居中只淡入淡出）。
## （原「诡异！」「无序！」小字已删除：需求删除无序/诡异文本，只保留异象入侵）
## #3（2026-08-11）：文本原直接挂 root（canvas layer 0），会被战场 Camera2D 的画布变换
## 带离屏幕（实际渲染在世界坐标附近、可视区外），故提示从未出现。现挂到专用 CanvasLayer(10)。
func _get_event_text_layer() -> CanvasLayer:
	var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() else null
	if root == null:
		return null
	var layer: CanvasLayer = root.get_node_or_null("_EventTextLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "_EventTextLayer"
		layer.layer = 10
		root.add_child(layer)
	return layer

func _show_anomaly_texts(unit_id: String, unit_res: Resource) -> void:
	var texts: Array[String] = ["异象入侵！！！"]
	var layer: CanvasLayer = _get_event_text_layer()
	if layer == null:
		_spawn_anomaly_unit(unit_id, unit_res)
		return
	
	var delay: float = 0.0
	for i in range(texts.size()):
		var label := Label.new()
		label.text = texts[i]
		label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1, 1.0))
		var font_size: int = 72 if i == 0 else 48
		label.add_theme_font_size_override("font_size", font_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.anchor_left = 0.5
		label.anchor_top = 0.5
		label.offset_left = -300 if i == 0 else -160
		label.offset_top = -45
		label.offset_right = 300 if i == 0 else 160
		label.offset_bottom = 45
		label.modulate.a = 0.0  ## 从透明开始
		layer.add_child(label)
		
		var dur: float = 3.0 if i == 0 else 1.0  ## 大字 3s，小字各 1s
		var tween := layer.create_tween()
		if i == 0:
			## 红色大字：固定居中，只淡入淡出（与特殊事件大字规格一致）
			tween.tween_interval(delay)
			tween.tween_property(label, "modulate:a", 1.0, 0.5)  ## 淡入
			tween.tween_interval(dur - 1.0)  ## 停留
			tween.tween_property(label, "modulate:a", 0.0, 1.0)  ## 淡出
		else:
			## 小字：从上往下平移 + 缩小 + 淡出
			tween.tween_interval(delay)
			tween.tween_property(label, "modulate:a", 1.0, 0.3)  ## 淡入
			tween.parallel().tween_property(label, "position:y", -100, dur).as_relative()  ## 下移
			tween.parallel().tween_property(label, "scale", Vector2(0.5, 0.5), dur)  ## 缩小
			tween.tween_property(label, "modulate:a", 0.0, 0.5)  ## 淡出
		tween.tween_callback(label.queue_free)
		delay += dur  ## 下一个文本延迟
	
	## 延迟（3+1+1+0.5）后实际生成异象敌兵
	## 修复（2026-08-11）：原写 `root.get_tree()`，但本函数无 root 局部变量（root 只在
	## _get_event_text_layer 内部），编译报 Identifier "root" not declared → 改用自身 get_tree()
	await get_tree().create_timer(delay + 0.5).timeout
	_spawn_anomaly_unit(unit_id, unit_res)

## 生成异象敌兵并开启特殊事件定时检测
func _spawn_anomaly_unit(unit_id: String, unit_res: Resource) -> void:
	spawn_unit(unit_res, 1)  ## 敌方（蓝方，team 1）
	## #4：镜头自动聚焦刚生成的异象敌兵
	event_unit_focus_requested.emit(enemy_units.back())
	
	## 解锁隐藏成就「异象入侵」
	Achievements.unlock_by_id("anomaly_invasion")  ## 经成就系统解锁，确保右下角弹框 + 提示音
	
	## 追踪异象单位存活状态：每秒 5% 概率触发特殊事件
	var anomaly_tracker := Timer.new()
	anomaly_tracker.wait_time = 1.0
	anomaly_tracker.one_shot = false
	anomaly_tracker.name = "_anomaly_tracker_%d" % Time.get_ticks_msec()
	var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() else null
	if root == null:
		return
	root.add_child(anomaly_tracker)
	
	## 仅当死亡使者（Y1）仍存活时，蓝女巫（S1）才有概率降临（联动）
	anomaly_tracker.timeout.connect(func() -> void:
		var y1_alive: bool = false
		for u in enemy_units:
			if is_instance_valid(u) and not u.is_dead and u.unit_resource != null and u.unit_resource.unit_id == "Y1":
				y1_alive = true
				break
		if not y1_alive:
			anomaly_tracker.queue_free()
			return
		## 蓝女巫（S1）一局内最多触发一次（封顶）
		if _s1_triggered:
			return
		## 10% 概率触发蓝女巫特殊事件
		if randf() > 0.10:
			return
		var s_res: Resource = UnitDatabase.get_unit("S1")
		if s_res == null:
			return
		_s1_triggered = true  ## 封顶：本局不再自然触发
		spawn_unit(s_res, 0)  ## 加入我方（红方）
		## #4：镜头自动聚焦刚生成的特殊事件援军
		event_unit_focus_requested.emit(player_units.back())
		print("[特殊事件] 蓝女巫降临！加入我方")
		_show_special_event_text("S1")
		## 经成就系统解锁，确保右下角弹框 + 提示音
		Achievements.unlock_by_id("parallel_heroes")
	)

## 开发工具：触发蓝色女巫事件（#自由事件 2026-08-15）
## 专召 S1 蓝女巫加入我方（红方）+ 金色大字 + 成就
func dev_trigger_blue_witch_event() -> void:
	var res: Resource = UnitDatabase.get_unit("S1")
	if res == null:
		push_warning("DevTool: 蓝女巫（S1）资源缺失。")
		return
	_s1_triggered = true  ## 封顶：本局不再自然触发
	spawn_unit(res, 0)  ## 加入我方（红方）
	if not player_units.is_empty():
		event_unit_focus_requested.emit(player_units.back())
	print("[蓝色女巫事件] 开发工具触发！召唤蓝女巫加入我方")
	_show_special_event_text("S1")
	Achievements.unlock_by_id("parallel_heroes")

## 开发工具：仓鼠士兵事件（#自由事件 2026-08-15 / #18-8 改：手动触发=直接召唤 S2）
## 用户拍板：手动触发 = 战役/全面战争红方召唤一只；双人模式红蓝双方各召唤一只。
## 不设置任何 G1 变身状态——G1 变身仅由部署时的 1% 随机觉醒（dev_set_hamster_100pct 强制必中）触发。
func dev_trigger_hamster_event() -> void:
	var s2: Resource = UnitDatabase.get_unit("S2")
	if s2 == null:
		push_warning("DevTool: 仓鼠士兵（S2）资源缺失。")
		return
	spawn_unit(s2, 0)  ## 战役/全面战争：红方召唤一只
	if is_two_player:
		spawn_unit(s2, 1)  ## 双人：蓝方也召唤一只
	_show_special_event_text("S2")  ## 金色大字反馈
	## 解锁隐藏成就「平行时空的英雄们」（S 前缀特殊单位登场）
	Achievements.unlock_by_id("parallel_heroes")
	print("[仓鼠士兵事件] 开发工具触发！召唤仓鼠士兵加入%s" % ("红蓝双方" if is_two_player else "我方"))

## 开发工具：将仓鼠士兵触发概率改为百分百（#自由事件 2026-08-15 / #18-7 合一）
## 开启 _g1_hamster_force 后，每次部署 G1 掷点必中 → 每次部署都变仓鼠（100% 概率）
func dev_set_hamster_100pct() -> void:
	_g1_hamster_force = true
	print("[仓鼠士兵事件] 触发概率已改为百分百（每次部署 G1 必变仓鼠士兵）")

## 开发工具：触发死亡使者异象（#自由事件 2026-08-15）
## 专召 Y1 死亡使者加入敌方（蓝方）+ 异象文本 + 成就 + 存活追踪（5% 召 S1）
func dev_trigger_death_reaper_event() -> void:
	var res: Resource = UnitDatabase.get_unit("Y1")
	if res == null:
		push_warning("DevTool: 死亡使者（Y1）资源缺失。")
		return
	_y1_triggered = true  ## 封顶：本局不再自然触发
	print("[死亡使者异象] 开发工具触发！召唤死亡使者")
	_show_anomaly_texts("Y1", res)

## 开发工具：触发凑企鹅异象（#自由事件 2026-08-15）
## 专召 Y2 凑企鹅加入敌方（蓝方）+ 存活追踪（每秒 5% 召 S1 蓝女巫）
func dev_trigger_penguin_event() -> void:
	var res: Resource = UnitDatabase.get_unit("Y2")
	if res == null:
		push_warning("DevTool: 凑企鹅（Y2）资源缺失。")
		return
	_try_spawn_penguin_event()

## 特殊事件触发：屏幕中央金色大字「平行时空的英雄到来！」（#5 2026-08-11）
## 规格：固定居中、5 秒后自动消失、渐入渐出、不缩放不位移。
## #3（2026-08-11）：同异象文本，改挂专用 CanvasLayer(10)，避免被 Camera2D 画布变换带离屏幕。
func _show_special_event_text(unit_id: String) -> void:
	var layer: CanvasLayer = _get_event_text_layer()
	if layer == null:
		return
	var label := Label.new()
	label.text = "平行时空的英雄到来！"
	## 金色：R=1, G=0.84, B=0（金黄）
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0, 1.0))
	label.add_theme_font_size_override("font_size", 72)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -350
	label.offset_top = -45
	label.offset_right = 350
	label.offset_bottom = 45
	label.modulate.a = 0.0
	layer.add_child(label)
	## 动画：淡入 0.5s → 停留 3.4s → 淡出 1.1s（总 5s），固定居中不缩放不位移
	var tween := layer.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.5)  ## 淡入
	tween.tween_interval(3.4)  ## 停留展示
	tween.tween_property(label, "modulate:a", 0.0, 1.1)  ## 淡出
	tween.tween_callback(label.queue_free)

## 生成单位的方法
## unit_res: 兵种资源对象（包含属性数据）
## player_id: 所属玩家 ID（0=红方, 1=蓝方）
## at_position: 指定出生世界坐标；默认 Vector2.INF 表示沿用基地前方的默认出生逻辑
##              肉鸽模式拖放部署时传入鼠标落点，实现「拖到哪出到哪」
func spawn_unit(unit_res: Resource, player_id: int, at_position: Vector2 = Vector2.INF) -> void:
	## 首次调用时缓存单位场景资源
	if unit_scene == null:
		unit_scene = load("res://scenes/units/unit_base.tscn")  ## 加载单位基础场景
	
	## #自由事件：仓鼠士兵 G1 替换（部署 G1 时 1% 触发，本局该方 G1 全部变仓鼠士兵）
	unit_res = _maybe_apply_hamster_replacement(unit_res, player_id)
	
	var unit = unit_scene.instantiate()  ## 实例化单位节点
	unit.setup(unit_res, player_id)  ## 调用单位的初始化方法，传入兵种资源与玩家 ID
	
	## 设置出生位置（基地前方，使用实际 battlefield 坐标）
	var spawn_x: float
	if player_id == 0:
		## 红方单位出生在红方基地右侧（基地 -592~-560，出生点 -544）
		spawn_x = -544.0
	elif RoguelikeManager.is_active:
		## #7：肉鸽模式敌人从地图两侧随机刷新，向中央水晶合围（左右各半概率）
		spawn_x = -544.0 if randf() < 0.5 else 544.0
	else:
		## 蓝方单位出生在蓝方基地左侧（基地 560~592，出生点 544）
		spawn_x = 544.0

	## 随机分配 Y 坐标，限定在战场灰色土路区域内（y∈-280~-120）
	var spawn_y: float = Constants.SPAWN_Y_CENTER + randf_range(-Constants.SPAWN_Y_RANGE, Constants.SPAWN_Y_RANGE)  ## 灰色区域内随机 Y

	## 指定了合法落点则优先使用（肉鸽拖放部署），否则用基地前方默认出生点
	if at_position.is_finite():
		unit.global_position = at_position
	else:
		unit.global_position = Vector2(spawn_x, spawn_y)  ## 设置单位的全局出生坐标
	
	## 根据玩家 ID 将单位加入对应的单位列表
	if player_id == 0:
		player_units.append(unit)  ## 加入玩家方单位列表
	else:
		enemy_units.append(unit)  ## 加入敌方单位列表
	
	unit_spawned.emit(unit, player_id)  ## 发出单位生成信号，通知场景树挂载该单位

## #自由事件：仓鼠士兵觉醒（2026-08-15 / #18-8 简化）
## 部署 G1 时掷 1%（dev_set_hamster_100pct 开启则必中），命中即**当前这只 G1 变仓鼠士兵（S2）**，
## 仅当次、不设本局替换状态——后续 G1 保持普通。
## 手动触发（dev_trigger_hamster_event）已改为直接召唤 S2，不经过本判定（#18-8 用户拍板）。
## 范围：战役/全面战争仅我方（player_id=0）有效；双人模式双方（player_id 0/1）都有效；肉鸽不触发。
## 返回值: 替换后的兵种资源（未触发时原样返回）
func _maybe_apply_hamster_replacement(unit_res: Resource, player_id: int) -> Resource:
	if unit_res == null or unit_res.unit_id != "G1":
		return unit_res
	if RoguelikeManager.is_active:  ## 肉鸽不触发
		return unit_res
	## 蓝方仅在双人模式有效（#18-7：双人红蓝双方都能触发；战役/全面战争敌方 AI 不触发）
	if player_id == 1 and not is_two_player:
		return unit_res
	## 1% 随机觉醒（每次部署掷点，百分百开关必中）——命中即当前这只变 S2，仅当次
	if _g1_hamster_force or randf() < 0.01:
		var s2: Resource = UnitDatabase.get_unit("S2")
		if s2:
			print("[自由事件] 仓鼠士兵觉醒！%s 方 G1 变为仓鼠士兵" % ("红" if player_id == 0 else "蓝"))
			## 解锁隐藏成就「平行时空的英雄们」（S 前缀特殊单位登场）
			Achievements.unlock_by_id("parallel_heroes")
			return s2
		return unit_res  ## S2 资源缺失时保持普通 G1
	return unit_res

## 设置玩家当前选择的兵种
## player_id: 玩家 ID（0=红方, 1=蓝方）
## unit_res: 选择的兵种资源（null 表示取消选择）
func set_selected_unit(player_id: int, unit_res: Resource) -> void:
	## #11 单发出兵（事件触发）：仅当“选中发生变化”时出 1 个；
	## 重复点击同一兵种不在此触发（由 HUD 调 deploy_selected_once 显式再出一个），
	## 以免 AI 每帧重设同一兵种导致每帧狂出。
	if DevMode.single_spawn:
		if unit_res == null:
			selected_units[player_id] = null  ## 取消选择
			selection_changed.emit(player_id, null)
			return
		if selected_units[player_id] != unit_res:
			selected_units[player_id] = unit_res  ## 更新对应玩家的兵种选择
			selection_changed.emit(player_id, unit_res)  ## 发出选择变化信号，通知 UI 更新
			_deploy_single(player_id, unit_res)  ## 新选兵种 → 立即出 1 个
		return  ## 单发模式下不进入后续“每帧重设”逻辑
	## 原逻辑（非单发）：只有选择真正发生变化时才更新并发信号，避免每帧重复重建 UI 节点
	if selected_units[player_id] == unit_res:
		return  ## 选择未变化，直接返回
	selected_units[player_id] = unit_res  ## 更新对应玩家的兵种选择
	selection_changed.emit(player_id, unit_res)  ## 发出选择变化信号，通知 UI 更新

## #11 单发出兵：立即出且仅出 1 个指定兵种，受人口上限与金币约束
## player_id: 玩家 ID（0=红方, 1=蓝方）；unit_res: 要出的兵种
func _deploy_single(player_id: int, unit_res: Resource) -> void:
	var current_count: int = player_units.size() if player_id == 0 else enemy_units.size()
	if current_count >= EconomyManager.get_max_population(player_id):
		return  ## 人口到顶，不出
	if not EconomyManager.purchase_unit(player_id, unit_res):
		return  ## 金币不足，不出
	spawn_unit(unit_res, player_id)

## #11 单发出兵：由 HUD 在“重复点击已选中兵种”时调用，额外再出 1 个（不改变选择状态）
## player_id: 玩家 ID
func deploy_selected_once(player_id: int) -> void:
	if not DevMode.single_spawn:
		return
	var res: Resource = selected_units[player_id]
	if res == null:
		return
	_deploy_single(player_id, res)

## 移除单位的方法
## unit: 要移除的单位节点
## player_id: 单位所属的玩家 ID
func remove_unit(unit: Node2D, player_id: int) -> void:
	## 根据玩家 ID 从对应列表中删除该单位
	if player_id == 0:
		player_units.erase(unit)  ## 从玩家方单位列表中移除
	else:
		enemy_units.erase(unit)  ## 从敌方单位列表中移除
	unit_removed.emit(player_id)  ## 发出单位移除信号

## 敌军撤退：从对应列表中移除单位并发出 unit_retreated（不计击杀赏金，但波次仍可清空）
## 与 remove_unit 的区别仅在于发出的信号不同，供 director 区分「击杀」与「撤退」。
func retreat_unit(unit: Node2D, player_id: int) -> void:
	if player_id == 0:
		player_units.erase(unit)
	else:
		enemy_units.erase(unit)
	unit_retreated.emit(player_id)

## 开发工具：清空场上所有普通兵种（双方）
## 只清 player_units / enemy_units 列表中的单位；基地单位（is_base_unit）不在列表中，自动保留，
## 因此水晶/基地不受影响，肉鸽波次逻辑（依赖 enemy_units 判空）也会自然进入下一波。
func clear_all_units() -> void:
	var doomed: Array[Node] = []
	for u in player_units:
		if is_instance_valid(u):
			doomed.append(u as Node)
	for u in enemy_units:
		if is_instance_valid(u):
			doomed.append(u as Node)
	player_units.clear()
	enemy_units.clear()
	for u in doomed:
		u.queue_free()
	## 通知双方 UI 刷新人口计数
	unit_removed.emit(0)
	unit_removed.emit(1)

## 获取指定 team 的敌方单位列表
## team: 己方 team（0=红方/玩家, 1=蓝方/AI）
## 返回: 敌方单位数组
func get_enemy_units(team: int) -> Array:
	if team == 0:
		return enemy_units
	return player_units

## 开发工具：对指定阵营基地（水晶）造成固定伤害（默认用于「扣除敌方水晶 100 血」）
## team: 目标阵营（0=红方/玩家, 1=蓝方/AI）
## amount: 伤害量（正数表示扣血）
func dev_damage_base(team: int, amount: int) -> void:
	dev_base_damage_requested.emit(team, amount)

## 开发工具：对指定阵营基地（水晶）直接加血，可超过上限（#21）
## team: 目标阵营（0=红方/玩家, 1=蓝方/AI）
## amount: 加血量
func dev_boost_base_hp(team: int, amount: int) -> void:
	dev_base_boost_requested.emit(team, amount)

## 开发工具：只清空对面（敌方，team 1）的普通兵种
## 与 clear_all_units 相同的安全边界：基地单位（is_base_unit）不在 enemy_units 列表中，水晶不受影响。
## 肉鸽模式下敌军清空后波次逻辑（依赖 enemy_units 判空）会自然推进到下一波。
func clear_enemy_units() -> void:
	var doomed: Array[Node] = []
	for u in enemy_units:
		if is_instance_valid(u):
			doomed.append(u as Node)
	enemy_units.clear()
	for u in doomed:
		u.queue_free()
	## 只刷新敌方人口计数
	unit_removed.emit(1)

## #19：远程火力均衡分配
## 常规模式（战役/双人/全面战争）每物理帧执行：将双方远程单位各自轮转分配到对方现存敌人上，
## 避免所有远程独立「找最近敌人」导致集火同一个敌人、浪费火力。
## 分配规则：n 个远程轮转锁定 m 个敌人，第 i 个远程锁 enemies[i % m]：
##   n=6,m=2 → 3/3；n=6,m=3 → 2/2/2；n=6,m=4 → 2/2/1/1；n=6,m=6 → 各 1；n=6,m=7 → 余 1 敌无锁。
## 敌人死亡后列表变短，轮转结果自然变化 = 目标死亡后重新分配。
## 仅在单位非攻击周期时写入 target（攻击周期中的目标不动，避免打断动画）；
## 单位实际是否攻击/推进由状态机决定（state_move 优先消费本分配结果）。
func _distribute_ranged_targets() -> void:
	## 肉鸽模式守卫 AI 有独立索敌/牵引体系，不干预
	if RoguelikeManager.is_active:
		return
	## 收集双方远程单位（存活、非基地）
	var red_ranged: Array[Unit] = []
	var blue_ranged: Array[Unit] = []
	_collect_ranged_units(player_units, red_ranged)
	_collect_ranged_units(enemy_units, blue_ranged)
	## 收集对方现存普通单位（存活、非基地；基地/水晶不是可锁定目标）
	var red_enemies: Array[Unit] = []
	var blue_enemies: Array[Unit] = []
	for u in enemy_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead and not (u as Unit).is_base_unit:
			red_enemies.append(u as Unit)
	for u in player_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead and not (u as Unit).is_base_unit:
			blue_enemies.append(u as Unit)
	_apply_round_robin(red_ranged, red_enemies)
	_apply_round_robin(blue_ranged, blue_enemies)

## 从单位列表中收集存活且非基地的远程单位
## units: 来源列表（player_units / enemy_units）
## out: 收集结果（远程单位数组）
func _collect_ranged_units(units: Array, out: Array) -> void:
	for u in units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead and not (u as Unit).is_base_unit:
			var unit: Unit = u as Unit
			if unit.unit_resource != null and unit.unit_resource.is_ranged:
				out.append(unit)

## 对一组远程单位执行轮转分配
## ranged_units: 待分配的远程单位列表
## enemies: 可锁定的敌人列表（按列表顺序轮转）
func _apply_round_robin(ranged_units: Array, enemies: Array) -> void:
	if ranged_units.is_empty() or enemies.is_empty():
		return
	var count: int = enemies.size()
	for i in range(ranged_units.size()):
		var unit: Unit = ranged_units[i]
		## 攻击周期中不改目标（当前周期打完，避免打断攻击动画）
		if unit.current_state != null and unit.current_state.get("_attack_started") == true:
			continue
		## 锁定保持（#25修复）：已持有有效且在本单位有效射程内的目标时不覆盖。
		## 旧逻辑每帧无脑改写 target，会把「攻击后摇/恢复期内的单位」换锁到射程外敌人 →
		## 下一攻击周期判超射程 → 超射程防抖 0.3s 原地待命 → 切回 move → 再切 attack，
		## 10v3「7 个远程原地抽搐、状态高频交替」的根因之一（march 模拟实测：分配器开
		## 4/10 红方切换 28~48 次；关 0 个）。持有有效目标时保持，等它失效再重新分配。
		if _has_valid_in_range_target(unit):
			continue
		var target: Unit = enemies[i % count]
		if target == null or not is_instance_valid(target) or target.is_dead:
			continue
		## 射程检查：只把本单位有效射程（射程×32 + 10）内的敌人写进 target。
		## 旧逻辑无射程检查，把「够不着」的敌人写进 target →
		## ① 该单位在 move 状态锁着射程外目标，无法开火（只在推进）；
		## ② 该 target 会污染 find_best_distributed_target 的锁定数统计（幻影锁定），
		##    让射程内的其他远程平分失真 → 只有部分远程开火。
		if unit.global_position.distance_to(target.global_position) > _unit_effective_range(unit):
			continue
		unit.target = target  ## 写入均衡分配的目标

## 本单位有效射程（像素）：默认圆形 = 射程 × 32 + 10；#3 h/v 任一非零时改用椭圆判定
## unit: 远程单位
## 返回值: 有效射程（像素），无资源时返回 0；h/v 模式下用「近似圆半径 = max(h, v)」保守覆盖
static func _unit_effective_range(unit: Unit) -> float:
	if unit == null or unit.unit_resource == null:
		return 0.0
	var res: UnitResource = unit.unit_resource
	if res.use_elliptical_range:
		return maxf(res.get_attack_range_h_px(), res.get_attack_range_v_px()) + 10.0
	return res.attack_range * Constants.UNIT_TO_PIXELS + 10.0

## #3：精确判定单位能否攻击到目标位置（椭圆/圆形），分配器与平分索敌统一用此方法
## unit: 远程单位
## target_pos: 目标世界坐标
## 返回值: true=有效射程内
static func _unit_can_reach(unit: Unit, target_pos: Vector2) -> bool:
	if unit == null or unit.unit_resource == null:
		return false
	return unit.is_target_in_attack_range(target_pos, 10.0)

## 是否已持有「有效且在有效射程内」的目标（锁定保持判定，#25修复）
## unit: 远程单位
## 返回值: true 表示已有可继续攻击的目标，不应被分配器覆盖
static func _has_valid_in_range_target(unit: Unit) -> bool:
	if unit == null or unit.target == null or not is_instance_valid(unit.target) or unit.target.is_dead:
		return false
	return unit.global_position.distance_to(unit.target.global_position) <= _unit_effective_range(unit)

## 切换暂停状态的方法
## 在暂停与继续之间切换，同时同步整个场景树的暂停状态
func toggle_pause() -> void:
	set_paused(not is_paused)

## 显式设置暂停状态（幂等）
## 供「长按 ESC 暂停 / 松开恢复」这类需要按住状态而非切换语义的输入使用，
## 重复设置同一状态不会产生副作用。
func set_paused(paused: bool) -> void:
	if is_paused == paused:
		return
	is_paused = paused
	get_tree().paused = is_paused

## 强制冻结所有战斗单位（存活的玩家/敌方单位 + 双方基地）
## 将 target 清空、速度归零、切换到 idle 状态，停止一切移动与攻击动作。
## 供 end_game 与肉鸽单层通关（_on_floor_cleared）复用，
## 确保「胜负已分 / 本层通关」后单位不再继续战斗，且不依赖 get_tree().paused 这一道。
func freeze_units() -> void:
	## 存活单位快照（避免遍历中列表被修改）
	var frozen_units: Array[Unit] = []
	for u in player_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead:
			frozen_units.append(u as Unit)
	for u in enemy_units:
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead:
			frozen_units.append(u as Unit)
	## 强制所有单位进入 idle 状态，停止攻击动画与移动
	for unit in frozen_units:
		unit.target = null
		unit.velocity = Vector2.ZERO
		unit.change_state("idle")
	## 同时冻结双方基地单位（替代水晶），避免胜负已分后基地仍在攻击
	for base in get_tree().get_nodes_in_group("base_unit"):
		if is_instance_valid(base) and base is Unit and not (base as Unit).is_dead:
			var base_unit: Unit = base as Unit
			base_unit.target = null
			base_unit.velocity = Vector2.ZERO
			base_unit.change_state("idle")

## 结束游戏的方法
## winner_team: 获胜方阵营编号（0=红方, 1=蓝方）
func end_game(winner_team: int) -> void:
	## 防重入：游戏已结束时不再重复触发（防止双方基地同时摧毁导致结算画面叠加）
	if not is_battle_active:
		return
	is_battle_active = false  ## 停止战斗主循环
	## 强制所有存活单位与基地进入 idle 状态，停止移动与攻击（详见 freeze_units）
	freeze_units()
	## 停止所有正在进行中的攻击音效（防止胜利后仍在播放攻击音效）
	AudioManager.stop_all_sfx()
	## 立即暂停战斗，防止游戏结束画面加载前单位继续战斗
	get_tree().paused = true
	game_over.emit(winner_team)  ## 发出游戏结束信号，通知 UI 显示结算画面
