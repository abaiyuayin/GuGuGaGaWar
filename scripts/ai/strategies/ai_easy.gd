extends AIStrategy  ## 继承 AI 策略基类
## 简单 AI 策略
## 最简单的 AI 行为模式：随机选择可负担的兵种
## 不分析玩家行为，不利用克制关系，每次评估必出兵（只要金币够）

## 节点就绪时自动调用，设置简单 AI 的评估间隔
func _init() -> void:  ## 重写构造函数
	## 简单 AI 评估间隔较长（2秒），模拟新手反应慢
	evaluation_interval = 2.0  ## 设置评估间隔为 2 秒

## 执行 AI 评估的核心方法
## 随机选择一个当前金币可负担的兵种（必出兵，不出兵只发生在金币不足时）
## _ai_controller: AI 控制器节点引用（简单 AI 中未使用）
func _do_evaluate(_ai_controller: Node) -> void:  ## 重写评估方法
	## 获取 AI 当前拥有的金币数（AI 是蓝方，player_id=1）
	var gold: int = EconomyManager.get_gold(1)  ## 获取 AI 金币

	## 获取当前金币可负担的所有兵种列表（战役模式下受敌方 tier 上限限制）
	var affordable = UnitDatabase.get_ai_affordable_units(gold)  ## 获取 AI 可负担兵种
	## 如果没有可负担的兵种（金币不足），才不出兵
	if affordable.is_empty():  ## 如果无可负担兵种
		selected_unit = null  ## 设置选择为 null
		return  ## 直接返回

	## 战役模式下，40% 概率优先选择玩家尚未解锁的兵种（敌人领先一个 tier 的那些）
	if GameManager.is_campaign_mode:  ## 如果是战役模式
		var player_unlocked: Array[String] = CampaignProgress.get_player_unlocked_ids()  ## 玩家已解锁兵种
		var exclusive_units: Array = []  ## 玩家没有但 AI 可负担的兵种（即领先一个 tier 的兵种）
		for unit in affordable:  ## 遍历可负担兵种
			if not (unit.unit_id in player_unlocked):  ## 玩家尚未解锁
				exclusive_units.append(unit)  ## 加入列表
		if not exclusive_units.is_empty() and randf() < 0.4:  ## 40% 概率选玩家没有的兵种
			selected_unit = exclusive_units[randi() % exclusive_units.size()]  ## 随机选一个
			return  ## 直接返回

	## 从可负担的兵种中随机选择一个
	## randi() % affordable.size() 生成 0 到 size-1 的随机整数
	selected_unit = affordable[randi() % affordable.size()]  ## 随机选择兵种
