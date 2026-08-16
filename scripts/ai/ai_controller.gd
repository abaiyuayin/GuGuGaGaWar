extends Node  ## 继承 Node 节点
## AI 控制器
## 管理 AI 对手的决策和出兵流程
## 根据游戏难度选择不同的 AI 策略，并每帧驱动 AI 评估

## AI 策略实例，根据难度动态创建
var strategy: AIStrategy = null  ## AI 策略实例
## AI 所属玩家 ID（固定为蓝方 = 1）
var player_id: int = 1  ## AI 玩家 ID

## 节点就绪时自动调用，初始化 AI 策略
func _ready() -> void:  ## 重写 _ready 方法
	## 根据当前游戏难度选择对应的 AI 策略。
	## 注意：主菜单自由模式与战役模式的难度语义不同，需分流——
	## 主菜单：0=简单/1=普通/2=困难，直接映射 easy/normal/hard；
	## 战役：  0=普通/1=困难/2=地狱，普通→normal，困难与地狱共用 hard
	##（困难/地狱的强度差由 #24 经济自动升级节奏区分：困难每 10 回合、地狱每 5 回合）
	if GameManager.is_campaign_mode:
		match GameManager.current_difficulty:  ## 战役难度语义
			1:  ## 战役困难
				strategy = load("res://scripts/ai/strategies/ai_hard.gd").new()
			2:  ## 战役地狱
				strategy = load("res://scripts/ai/strategies/ai_hard.gd").new()
			_:  ## 战役普通（0）
				strategy = load("res://scripts/ai/strategies/ai_normal.gd").new()
	else:
		match GameManager.current_difficulty:  ## 主菜单自由模式难度语义
			0:  ## 简单难度
				strategy = load("res://scripts/ai/strategies/ai_easy.gd").new()
			1:  ## 普通难度
				strategy = load("res://scripts/ai/strategies/ai_normal.gd").new()
			2:  ## 困难难度
				strategy = load("res://scripts/ai/strategies/ai_hard.gd").new()
			_:  ## 默认情况（其他难度值）
				strategy = load("res://scripts/ai/strategies/ai_normal.gd").new()

	## 连接战斗管理器的单位生成信号
	## 当玩家出兵时，记录到 AI 的历史记录中
	BattleManager.unit_spawned.connect(_on_unit_spawned)  ## 连接单位生成信号
	## #24：连接回合结束信号，战役困难/地狱按回合自动升级 AI 经济
	BattleManager.round_end.connect(_on_round_end)

## #24：战役模式敌方经济自动升级
## 困难：每 10 回合升一次人口与收入；地狱：每 5 回合升一次。
## 复用玩家同一套 upgrade_population/upgrade_income（同样扣 AI 金币、同样阶梯成本与封顶）；
## #19（2026-08-09 用户拍板）：AI 升级不考虑资金——触发节点前补足本次升级所需金币，
## 保证每 10/5 回合必升，不再因 AI 持续出兵把金币花光而跳过（旧实现「25 回合仅一次」根因）。
func _on_round_end(round_number: int) -> void:
	## 仅 AI 对战模式触发；双人/肉鸽的 AI 控制器已被 battle_root 移除，这里再兜一层
	if BattleManager.is_two_player or RoguelikeManager.is_active:
		return
	## 自动升级门槛：战役=困难及以上(diff>=1)；全面战争仅有「困难」(diff>=2) 才升级（无地狱档）。
	var diff: int = GameManager.current_difficulty
	var earns_auto_upgrade: bool
	if GameManager.is_campaign_mode:
		earns_auto_upgrade = diff >= 1
	else:
		earns_auto_upgrade = diff >= 2
	if not earns_auto_upgrade:
		return
	## round_number 为 0-based 已结束回合号，+1 转 1-based 便于判断「第 N 回合结束」
	var round_num: int = round_number + 1
	## 升级节奏：战役困难每 10 回合 / 地狱每 5 回合；全面战争困难每 5 回合
	var interval: int
	if GameManager.is_campaign_mode:
		interval = 10 if diff == 1 else 5
	else:
		interval = 5
	if round_num % interval != 0:
		return
	## 补足金币：人口 + 收入本次升级成本之和。若 AI 已满级（upgrade 返回 false）则多补的钱不扣，
	## 但满级后无需再升，多出的钱留在 AI 手里也不影响升级节奏（升级函数内部有封顶判断）。
	var need: int = EconomyManager.get_pop_upgrade_cost(player_id) + EconomyManager.get_income_upgrade_cost(player_id)
	if EconomyManager.get_gold(player_id) < need:
		EconomyManager.set_gold(player_id, need)
	EconomyManager.upgrade_population(player_id)
	EconomyManager.upgrade_income(player_id)

## 每帧处理，驱动 AI 评估和出兵
## delta: 上一帧到当前帧的时间间隔（秒）
func _process(delta: float) -> void:  ## 重写 _process 方法
	## 如果战斗未开始或已暂停，跳过 AI 处理
	if not BattleManager.is_battle_active or BattleManager.is_paused:  ## 如果战斗未激活或已暂停
		return  ## 直接返回

	## 调用策略的评估方法，让 AI 根据当前局势选择兵种
	strategy.evaluate_and_select(self, delta)  ## 调用策略评估

	## 如果 AI 已选择兵种，通知战斗管理器
	if strategy.selected_unit != null:  ## 如果已选择兵种
		BattleManager.set_selected_unit(player_id, strategy.selected_unit)  ## 设置选中兵种
	else:  ## 否则没有选择
		## 即使没有选择，也让 BattleManager 持续尝试用当前选择出兵
		var current = BattleManager.selected_units[player_id]  ## 获取当前选中兵种
		if current != null and EconomyManager.get_gold(player_id) < current.cost:  ## 如果金币不足
			BattleManager.set_selected_unit(player_id, null)  ## 清空选中兵种

## 单位生成信号回调
## 当任何单位被生成时调用，用于记录玩家的出兵历史
## unit: 生成的单位节点
## pid: 生成该单位的玩家 ID
func _on_unit_spawned(unit: Node2D, pid: int) -> void:  ## 定义单位生成回调
	## 只记录玩家（红方，pid=0）的出兵
	if pid == 0 and unit is Unit:  ## 如果是玩家出兵
		## 将玩家出的兵种 ID 记录到 AI 策略的历史记录中
		strategy.record_player_unit(unit.unit_resource.unit_id)  ## 记录玩家出兵
