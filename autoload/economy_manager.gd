extends Node  ## 继承自 Node 节点类
## 经济系统管理器（全局单例）
## 管理双方玩家的金币、收入、回合结算等经济相关逻辑

## 信号：金币发生变化时发出
## player_id: 发生变化的玩家 ID（0=红方, 1=蓝方）
## current_gold: 变化后的当前金币数
## income: 当前每回合收入
signal gold_changed(player_id: int, current_gold: int, income: int)
## 信号：回合结算完成时发出
## player_id: 结算的玩家 ID
## gold_gained: 本回合获得的金币数（即收入）
signal round_settled(player_id: int, gold_gained: int)

## 每个玩家的经济数据数组，索引 0=红方，索引 1=蓝方
## 每个元素是一个字典，包含 "gold"（当前金币）和 "income"（每回合收入）
var player_data: Array[Dictionary] = []
## 当前回合数，从 1 开始计数
var current_round: int = 1
## 开发者无限金币（#需求2）：唯一真相源为 DevMode.infinite_gold（autoload 全局单例），
## 开启后购买兵种与升级人口/收入都不扣金币，敌我双方生效；仅本次运行内有效，不持久化。

## 人口升级次数（每玩家），用于阶梯计价与加成累计（#138）
var pop_upgrade_count: Array[int] = [0, 0]
## 收入升级次数（每玩家）
var income_upgrade_count: Array[int] = [0, 0]
## 额外人口上限加成（每玩家），由人口升级累计
var bonus_population: Array[int] = [0, 0]
## 额外每回合收入加成（每玩家），由收入升级累计
var bonus_income: Array[int] = [0, 0]
## #14（2026-08-09）：敌方每回合收入覆盖值（-1=不覆盖）。
## 战役强敌关（3/6/10）由 BattleManager.start_battle 设为 110，使敌方收入固定，
## 不受回合数递增影响；其余关卡/模式保持 -1（随回合正常递增）。
var enemy_income_override: int = -1

## 每回合基础金币收入
## #2（2026-08-08）：初始收入 10 → 50（用户拍板仅改收入，初始金币 200 不变）
const BASE_ROUND_INCOME: int = 50
## 每过一回合，每回合金币收入增加量
const ROUND_INCOME_INCREMENT: int = 10
## 每回合收入上限（达到后不再增加）
## #13（2026-08-08）：900 → 400，且「不包含升级获得的收入提升」——
## 该上限只钳制随回合自然增长的基础收入，收入升级加成（bonus_income）单独封顶见 INCOME_BONUS_CAP
const INCOME_CAP: int = 400
## 收入升级加成封顶：升级累计加成最多 +500（#13 用户拍板：基础上限 400，升级最多增加 500）
const INCOME_BONUS_CAP: int = 500

## 回合倒计时基准时长（秒）（#12）
const ROUND_TIME_BASE: float = 10.0
## 每经过多少回合，倒计时增加一档（#12）
const ROUND_TIME_STEP_ROUNDS: int = 10
## 每档倒计时增量（秒）（#12）
const ROUND_TIME_STEP_BONUS: float = 5.0

## 人口升级：基础花费 200 金 / +1 人口上限；每升 POP_UPGRADE_STEP 次，花费翻倍（#138）
const POP_UPGRADE_BASE_COST: int = 200
const POP_UPGRADE_STEP: int = 5
const POP_UPGRADE_AMOUNT: int = 1
## 收入升级：基础花费 100 金 / +10 收入；每升 INCOME_UPGRADE_STEP 次，花费与加成同时翻倍（#138）
const INCOME_UPGRADE_BASE_COST: int = 100
const INCOME_UPGRADE_STEP: int = 5
const INCOME_UPGRADE_BASE_AMOUNT: int = 10

## 节点就绪时自动调用，初始化经济系统
func _ready() -> void:
	reset()  ## 调用重置方法初始化数据

## 重置经济系统到初始状态
## 将双方金币重置为初始值，收入重置为第一回合收入，回合数重置为 1
## 双方均使用基础值，公平对抗
func reset() -> void:
	current_round = 1  ## 先重置回合数为 1，再计算收入
	var initial_income: int = get_round_income()  ## 计算第一回合的收入
	## #2：调整面板不再持久化经济默认值，重置一律回到常量默认（双方完全平等）
	player_data = [
		{"gold": Constants.INITIAL_GOLD, "income": initial_income},  ## 红方基础值
		{"gold": Constants.INITIAL_GOLD, "income": initial_income}  ## 蓝方基础值
	]
	## 重置经济升级状态，确保「再来一局」后人口/收入加成归零（#138）
	pop_upgrade_count = [0, 0]
	income_upgrade_count = [0, 0]
	bonus_population = [0, 0]
	bonus_income = [0, 0]
	## #14：重置敌方收入覆盖（强敌关的 110 由 start_battle 按局设置，不跨局残留）
	enemy_income_override = -1

## 获取指定玩家的当前金币数
## player_id: 玩家 ID（0=红方, 1=蓝方）
## 返回值: 当前金币数量
func get_gold(player_id: int) -> int:
	return player_data[player_id]["gold"]  ## 从玩家数据字典中获取金币值

## 获取指定玩家的当前每回合收入
## player_id: 玩家 ID（0=红方, 1=蓝方）
## 返回值: 每回合收入数量
func get_income(player_id: int) -> int:
	## 基础每回合收入 + 收入升级加成（#138）
	return player_data[player_id]["income"] + bonus_income[player_id]

## 直接设置指定玩家的当前金币（调整面板实时调节用）
## player_id: 玩家 ID（0=红方, 1=蓝方）
## value: 目标金币数（下限 0）
func set_gold(player_id: int, value: int) -> void:
	player_data[player_id]["gold"] = maxi(value, 0)
	gold_changed.emit(player_id, player_data[player_id]["gold"], get_income(player_id))

## 直接设置指定玩家的人口上限（调整面板实时调节用）
## player_id: 玩家 ID
## value: 目标人口上限（自动折算为相对基础上限的加成值，下限 0）
func set_max_population(player_id: int, value: int) -> void:
	bonus_population[player_id] = maxi(value - Constants.MAX_UNITS_PER_SIDE, 0)
	gold_changed.emit(player_id, get_gold(player_id), get_income(player_id))

## 直接设置指定玩家的每回合收入（调整面板实时调节用）
## player_id: 玩家 ID
## value: 目标每回合收入（自动折算为相对基础回合收入的加成值，下限 0）
func set_income(player_id: int, value: int) -> void:
	bonus_income[player_id] = maxi(value - get_round_income(), 0)
	gold_changed.emit(player_id, get_gold(player_id), get_income(player_id))

## 增加指定玩家的人口上限加成（开发工具「经济控制」用）（#5）
## player_id: 玩家 ID（0=红方, 1=蓝方）
## amount: 增加的人口上限（可正可负，结果不低于 0）
func add_max_population(player_id: int, amount: int) -> void:
	bonus_population[player_id] = maxi(bonus_population[player_id] + amount, 0)
	gold_changed.emit(player_id, get_gold(player_id), get_income(player_id))

## 增加指定玩家的每回合收入加成（开发工具「经济控制」用）（#5）
## player_id: 玩家 ID（0=红方, 1=蓝方）
## amount: 增加的每回合收入（可正可负，结果不低于 0）
func add_income_bonus(player_id: int, amount: int) -> void:
	bonus_income[player_id] = maxi(bonus_income[player_id] + amount, 0)
	gold_changed.emit(player_id, get_gold(player_id), get_income(player_id))

## 获取基础上限人口（不含升级加成），供调整面板折算人口加成
func get_base_max_population() -> int:
	return Constants.MAX_UNITS_PER_SIDE

## 获取基础每回合收入（不含升级加成），供调整面板折算收入加成
func get_base_round_income() -> int:
	return get_round_income()

## 购买兵种的方法
## 扣除金币，如果金币不足则购买失败（收入由回合数统一决定，不再因兵种不同而不同）
## player_id: 购买方的玩家 ID
## unit_res: 要购买的兵种资源对象
## 返回值: true=购买成功, false=金币不足购买失败
func purchase_unit(player_id: int, unit_res: Resource) -> bool:
	## 开发者无限金币：不判余额、不扣钱，直接购买成功（敌我双方生效）
	if DevMode.infinite_gold:
		return true
	## 检查玩家金币是否足够支付兵种造价
	if player_data[player_id]["gold"] >= unit_res.cost:
		player_data[player_id]["gold"] -= unit_res.cost  ## 扣除兵种造价
		## 发出金币变化信号，通知 UI 更新显示（#8：统一用 get_income，含升级加成）
		gold_changed.emit(player_id, player_data[player_id]["gold"], get_income(player_id))
		return true  ## 购买成功
	return false  ## 金币不足，购买失败

## 直接给指定玩家增加金币（开发工具 / 奖励发放用，负数表示扣除但不会扣到 0 以下）
## player_id: 玩家 ID（0=红方, 1=蓝方）
## amount: 增加的金币数（可正可负）
func add_gold(player_id: int, amount: int) -> void:
	player_data[player_id]["gold"] = maxi(player_data[player_id]["gold"] + amount, 0)
	## 发出金币变化信号，通知 UI 更新显示（#8：统一用 get_income，含升级加成）
	gold_changed.emit(player_id, player_data[player_id]["gold"], get_income(player_id))

## 回合结算方法
## 将当前收入累加到金币中，进入下一回合前的结算步骤
## 双方收入均为基础值，公平对抗
## player_id: 要结算的玩家 ID
## 返回值: 本回合获得的金币数（即收入）
func settle_round(player_id: int) -> int:
	## #8：player_data["income"] 只保存「随回合递增的基础收入」，
	## 升级/开发工具累加的 bonus_income 永远单独累积，绝不会被回合结算抹掉。
	player_data[player_id]["income"] = get_player_round_income(player_id)
	## 实际发放 = 基础收入 + 累积加成（此前只发基础值，导致收入升级完全不生效）
	var income_gained: int = get_income(player_id)
	player_data[player_id]["gold"] += income_gained  ## 收入转化为可用金币
	## 发出金币变化信号，通知 UI 更新显示（显示值同样是含加成的累积收入）
	gold_changed.emit(player_id, player_data[player_id]["gold"], income_gained)
	## 发出回合结算信号
	round_settled.emit(player_id, income_gained)
	return income_gained  ## 返回本回合获得的金币数

## 获取当前回合的基础收入（双方相同，并随回合数递增，上限 200）
## 返回值: 当前回合每玩家获得的金币数
func get_round_income() -> int:
	## 基础收入 +（当前回合 - 1）× 每回合递增量，上限 INCOME_CAP
	var income: int = BASE_ROUND_INCOME + (current_round - 1) * ROUND_INCOME_INCREMENT
	return mini(income, INCOME_CAP)  ## 不超过上限

## 获取指定玩家本回合的实际收入
## player_id: 玩家 ID
## 返回值: 该玩家本回合的实际收入
func get_player_round_income(player_id: int) -> int:
	## #14：敌方收入覆盖（强敌关固定 110，不随回合递增）优先
	if player_id == 1 and enemy_income_override > 0:
		return enemy_income_override
	return get_round_income()

## 获取当前回合的倒计时时间（秒）
## 返回值: 当前回合的倒计时秒数
func get_round_time() -> float:
	## #需求（2026-08-14）：开发者模式开启时，回合内倒计时固定为 5 秒，便于快速测试/跳回合
	if DevMode.enabled:
		return 5.0
	## #12：基准 10 秒，每经过 10 回合 +5 秒（1~10 回合=10s，11~20=15s，21~30=20s…）
	var step: int = (current_round - 1) / ROUND_TIME_STEP_ROUNDS
	return ROUND_TIME_BASE + float(step) * ROUND_TIME_STEP_BONUS

## 进入下一回合
## 将当前回合数加 1
func next_round() -> void:
	current_round += 1  ## 回合数递增

## 获取指定玩家的人口上限（基础上限 + 人口升级加成，封顶 MAX_POPULATION_CAP）（#138）
## player_id: 玩家 ID（0=红方, 1=蓝方）
## 返回值: 当前人口上限
func get_max_population(player_id: int) -> int:
	return mini(Constants.MAX_UNITS_PER_SIDE + bonus_population[player_id], Constants.MAX_POPULATION_CAP)

## 获取人口升级的当前花费（阶梯计价：每 POP_UPGRADE_STEP 次翻倍）（#138）
## player_id: 玩家 ID
## 返回值: 本次升级所需金币
func get_pop_upgrade_cost(player_id: int) -> int:
	var step: int = pop_upgrade_count[player_id] / POP_UPGRADE_STEP
	return POP_UPGRADE_BASE_COST * (1 << step)  ## 200 × 2^step

## 获取人口升级的加成数量（固定 +1 人口/次）（#138）
## player_id: 玩家 ID
## 返回值: 本次升级增加的人口上限
func get_pop_upgrade_amount(player_id: int) -> int:
	return POP_UPGRADE_AMOUNT

## 人口升级：消耗金币，增加人口上限（封顶 MAX_POPULATION_CAP）（#138）
## player_id: 玩家 ID
## 返回值: true=升级成功, false=金币不足或已达人口上限
func upgrade_population(player_id: int) -> bool:
	if get_max_population(player_id) >= Constants.MAX_POPULATION_CAP:
		return false  ## 已达人口封顶，不再扣钱
	## 开发者无限金币：跳过余额判定与扣费，升级照常生效
	if not DevMode.infinite_gold:
		var cost: int = get_pop_upgrade_cost(player_id)
		if player_data[player_id]["gold"] < cost:
			return false
		player_data[player_id]["gold"] -= cost
	pop_upgrade_count[player_id] += 1
	bonus_population[player_id] += get_pop_upgrade_amount(player_id)
	gold_changed.emit(player_id, player_data[player_id]["gold"], get_income(player_id))
	return true

## 获取收入升级的当前花费（阶梯计价：每 INCOME_UPGRADE_STEP 次翻倍）（#138）
## player_id: 玩家 ID
## 返回值: 本次升级所需金币
func get_income_upgrade_cost(player_id: int) -> int:
	var step: int = income_upgrade_count[player_id] / INCOME_UPGRADE_STEP
	return INCOME_UPGRADE_BASE_COST * (1 << step)  ## 100 × 2^step

## 获取收入升级的加成数量（阶梯计价：每 INCOME_UPGRADE_STEP 次翻倍）（#138）
## player_id: 玩家 ID
## 返回值: 本次升级增加的每回合收入
func get_income_upgrade_amount(player_id: int) -> int:
	var step: int = income_upgrade_count[player_id] / INCOME_UPGRADE_STEP
	return INCOME_UPGRADE_BASE_AMOUNT * (1 << step)  ## 10 × 2^step

## 收入升级：消耗金币，增加每回合收入（#138）
## 升级加成累计封顶 INCOME_BONUS_CAP（#13：升级最多增加 500，到顶后无法再升）
## player_id: 玩家 ID
## 返回值: true=升级成功, false=金币不足或加成已满级
func upgrade_income(player_id: int) -> bool:
	if bonus_income[player_id] >= INCOME_BONUS_CAP:
		return false  ## 收入升级加成已达封顶（满级）
	## 开发者无限金币：跳过余额判定与扣费，升级照常生效
	if not DevMode.infinite_gold:
		var cost: int = get_income_upgrade_cost(player_id)
		if player_data[player_id]["gold"] < cost:
			return false
		player_data[player_id]["gold"] -= cost
	## 按当前阶梯算本次加成，并钳到封顶内（避免最后一次溢出超过 +500）
	var amount: int = mini(get_income_upgrade_amount(player_id), INCOME_BONUS_CAP - bonus_income[player_id])
	income_upgrade_count[player_id] += 1
	bonus_income[player_id] += amount
	gold_changed.emit(player_id, player_data[player_id]["gold"], get_income(player_id))
	return true
