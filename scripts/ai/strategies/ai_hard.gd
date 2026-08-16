extends AIStrategy  ## 继承 AI 策略基类
## 困难 AI 策略
## 最智能的 AI：具备战场态势感知能力，使用多层决策树
## 会根据局势动态调整策略（防守/推进/经济运营），并进行兵种组合搭配

## 节点就绪时自动调用，设置困难 AI 的评估间隔
func _init() -> void:  ## 重写构造函数
	## 困难 AI 评估间隔最短（1.5秒），反应更快
	evaluation_interval = 0.8  ## 设置评估间隔为 0.8 秒

## #需求5：上一次实际选中的兵种 ID（用于「连续出兵限制」，防止同一兵种被反复死磕）
var _last_pick_id: String = ""

## 执行 AI 评估的核心方法
## 使用多层决策树根据战场态势选择最优兵种
## ai_controller: AI 控制器节点引用
func _do_evaluate(ai_controller: Node) -> void:  ## 重写评估方法
	## 获取 AI 当前拥有的金币数
	var gold: int = EconomyManager.get_gold(1)  ## 获取 AI 金币
	## 获取当前金币可负担的所有兵种列表（战役模式下受敌方 tier 上限限制）
	var affordable = UnitDatabase.get_ai_affordable_units(gold)  ## 获取可负担兵种

	## 如果没有可负担的兵种
	if affordable.is_empty():  ## 如果无可负担兵种
		selected_unit = null  ## 设置选择为 null
		return  ## 直接返回

	## 分析战场态势：获取双方当前单位数量
	var player_unit_count: int = BattleManager.player_units.size()  ## 玩家单位数
	var ai_unit_count: int = BattleManager.enemy_units.size()  ## AI 单位数

	## 决策树第一层：防守判断
	## 如果玩家单位明显多于 AI 单位（差距 > 3），选择防守型单位
	if player_unit_count > ai_unit_count + 3:  ## 如果玩家单位明显多于 AI
		## 调用防守单位选择方法
		var counter = _select_defensive_unit(gold)  ## 选择防守单位
		if counter != null:  ## 如果找到防守单位
			selected_unit = counter  ## 选择防守单位
			return  ## 直接返回

	## 决策树第二层：推进判断
	## 如果 AI 单位明显多于玩家（差距 > 5），选择推进型单位扩大优势
	if ai_unit_count > player_unit_count + 5:  ## 如果 AI 单位明显多于玩家
		## 调用推进单位选择方法
		var pusher = _select_push_unit(gold)  ## 选择推进单位
		if pusher != null:  ## 如果找到推进单位
			selected_unit = pusher  ## 选择推进单位
			return  ## 直接返回

	## 决策树第三层：经济领先判断
	## 如果金币超过 500，说明经济领先，选择高阶强力兵种
	if gold > 500:  ## 如果金币超过 500
		## 调用高阶兵种选择方法
		var high_tier = _select_high_tier_unit(gold)  ## 选择高阶兵种
		if high_tier != null:  ## 如果找到高阶兵种
			selected_unit = high_tier  ## 选择高阶兵种
			return  ## 直接返回

	## 决策树第四层：默认策略
	## 根据克制关系 + 经济性价比选择
	var most_frequent = get_player_most_frequent()  ## 玩家最常用兵种
	if most_frequent != "":  ## 如果玩家有常用兵种
		## 查找克制玩家最常用兵种的单位
		var counter = find_counter_unit(most_frequent, gold)  ## 查找克制单位
		## 80% 概率选择克制单位
		if counter != null and randf() < 0.8:  ## 80% 概率
			selected_unit = counter  ## 选择克制单位
			return  ## 直接返回

	## 如果以上策略都不适用，选择性价比最高的兵种
	var best_unit: UnitResource = null  ## 最佳兵种
	var best_score: float = -1.0  ## 最佳评分
	## 遍历所有可负担的兵种
	for unit in affordable:  ## 遍历可负担兵种
		## 计算综合评分：性价比（伤害/造价）+ 阶层加成
		var avg_damage: float = float(unit.damage)  ## 使用统一伤害值
		var score: float = avg_damage / float(unit.cost) * 10.0  ## 计算性价比（乘 10 放大数值）
		## 高阶兵种额外加分，鼓励 AI 出高阶单位
		score += unit.tier * 0.1  ## 加阶层分
		## #需求5：性价比兜底加「多样性扰动」——±30% 随机波动，避免永远锁死同一个
		## 性价比之王（旧实现 G2 恒定 6.0 分全场最高 → 开局固定出 G2、且特别偏好 G2）。
		## 加扰动后 G2 只是"经常出现"而非"必定出现"，AI 出兵组合更有层次。
		score *= 0.7 + randf() * 0.6  ## 多样性扰动（0.7~1.3 倍）
		## #需求5：连续出兵限制——上次刚出过的兵种本次降权 50%，强制轮换，
		## 彻底杜绝「连续 N 次同一兵种」的机械行为。
		if unit.unit_id == _last_pick_id:  ## 与上次选择相同
			score *= 0.5  ## 降权一半
		## 如果评分更高，更新最佳选择
		if score > best_score:  ## 如果评分更高
			best_score = score  ## 更新最佳评分
			best_unit = unit  ## 更新最佳兵种

	## 战役模式下，40% 概率优先选择玩家尚未解锁的兵种（领先一个 tier 的兵种）
	if GameManager.is_campaign_mode:  ## 如果是战役模式
		var player_unlocked: Array[String] = CampaignProgress.get_player_unlocked_ids()  ## 玩家已解锁兵种
		for unit in affordable:  ## 遍历可负担兵种
			if not (unit.unit_id in player_unlocked) and randf() < 0.4:  ## 玩家未解锁且 40% 概率
				selected_unit = unit  ## 选择玩家没有的兵种
				_last_pick_id = unit.unit_id  ## #需求5：记录本次选择，供下次连续出兵限制
				return  ## 直接返回

	selected_unit = best_unit  ## 选择评分最高的兵种
	if best_unit != null:  ## #需求5：记录本次选择，供下次连续出兵限制
		_last_pick_id = best_unit.unit_id

## 选择防守单位的方法
## 优先选择高 HP 且能克制玩家最常用兵种的单位
## gold: 当前金币数
## 返回值: 选择的防守单位，找不到则返回 null
func _select_defensive_unit(gold: int) -> UnitResource:  ## 定义选择防守单位方法
	## 获取可负担的兵种列表
	var affordable = UnitDatabase.get_ai_affordable_units(gold)  ## 获取可负担兵种
	## 获取玩家最常用兵种
	var most_frequent = get_player_most_frequent()  ## 获取玩家最常用兵种

	var best: UnitResource = null  ## 最佳选择
	var best_hp: int = 0  ## 最佳评分（基于 HP）

	## 遍历可负担的兵种
	for unit in affordable:  ## 遍历可负担兵种
		## 基础评分为单位 HP
		var score = unit.max_hp  ## 基础评分为 HP
		## 如果该单位能克制玩家最常用兵种，评分翻倍
		if most_frequent != "" and unit.counter_table.has(most_frequent):  ## 如果能克制玩家常用兵种
			score *= 2  ## 评分翻倍
		## 如果评分更高，更新最佳选择
		if score > best_hp:  ## 如果评分更高
			best_hp = score  ## 更新最佳评分
			best = unit  ## 更新最佳选择

	return best  ## 返回最佳防守单位

## 选择推进单位的方法
## 优先选择高速度 + 高伤害的单位，用于快速推进
## gold: 当前金币数
## 返回值: 选择的推进单位，找不到则返回 null
func _select_push_unit(gold: int) -> UnitResource:  ## 定义选择推进单位方法
	## 获取可负担的兵种列表
	var affordable = UnitDatabase.get_ai_affordable_units(gold)  ## 获取可负担兵种

	var best: UnitResource = null  ## 最佳选择
	var best_score: float = 0.0  ## 最佳评分

	## 遍历可负担的兵种
	for unit in affordable:  ## 遍历可负担兵种
		## 计算推进评分：移动速度 × 伤害
		var score = unit.move_speed * float(unit.damage)  ## 计算推进评分
		## 如果评分更高，更新最佳选择
		if score > best_score:  ## 如果评分更高
			best_score = score  ## 更新最佳评分
			best = unit  ## 更新最佳选择

	return best  ## 返回最佳推进单位

## 选择高阶兵种的方法
## 优先选择阶层最高的兵种
## gold: 当前金币数
## 返回值: 选择的最高阶兵种，找不到则返回 null
func _select_high_tier_unit(gold: int) -> UnitResource:  ## 定义选择高阶兵种方法
	## 获取可负担的兵种列表
	var affordable = UnitDatabase.get_ai_affordable_units(gold)  ## 获取可负担兵种

	var best: UnitResource = null  ## 最佳选择
	var best_tier: int = 0  ## 最高阶层

	## 遍历可负担的兵种
	for unit in affordable:  ## 遍历可负担兵种
		## 如果阶层更高，更新最佳选择
		if unit.tier > best_tier:  ## 如果阶层更高
			best_tier = unit.tier  ## 更新最高阶层
			best = unit  ## 更新最佳选择

	return best  ## 返回最高阶兵种
