class_name AIStrategy  ## 定义全局类名 AIStrategy
## AI 策略基类
## 所有 AI 难度策略（简单/普通/困难）都继承此类
## 定义了 AI 决策的通用框架和辅助方法

extends RefCounted  ## 继承引用计数类
## 继承 RefCounted，表示这是一个引用计数类，不需要手动释放

## 当前选择的兵种资源，评估完成后会设置此值
## 如果为 null，表示 AI 本回合选择不出兵
var selected_unit: UnitResource = null  ## 当前选中兵种
## 评估计时器，用于控制 AI 决策的频率
var evaluation_timer: float = 0.0  ## 评估计时器
## 评估间隔时间（秒），控制 AI 多久评估一次局势
var evaluation_interval: float = 1.0  ## 默认每秒评估一次
## 玩家最近出兵记录数组，存储玩家最近出的兵种 ID
## 用于分析玩家的出兵偏好，从而选择克制兵种
var player_history: Array[String] = []  ## 玩家出兵历史记录
## 最大历史记录数，超过此数量会移除最旧的记录
var max_history: int = 10  ## 最大历史记录数

## 评估并选择兵种的主方法
## 按照 evaluation_interval 设定的间隔调用 _do_evaluate 进行实际评估
## ai_controller: AI 控制器节点引用
## delta: 上一帧到当前帧的时间间隔（秒）
func evaluate_and_select(ai_controller: Node, delta: float) -> void:  ## 定义评估选择方法
	## 递减评估计时器
	evaluation_timer -= delta  ## 计时器递减
	## 如果计时器未到 0，跳过本次评估
	if evaluation_timer > 0:  ## 如果计时器未到 0
		return  ## 直接返回
	## 重置计时器为评估间隔
	evaluation_timer = evaluation_interval  ## 重置计时器
	## 调用子类实现的实际评估逻辑
	_do_evaluate(ai_controller)  ## 调用子类评估逻辑

## 记录玩家出兵的方法
## 每次玩家出兵时调用，将兵种 ID 添加到历史记录中
## unit_id: 玩家出的兵种 ID
func record_player_unit(unit_id: String) -> void:  ## 定义记录玩家出兵方法
	## 将兵种 ID 添加到历史记录末尾
	player_history.append(unit_id)  ## 添加到历史记录
	## 如果历史记录超过最大限制，移除最旧的一条记录
	if player_history.size() > max_history:  ## 如果超过最大限制
		player_history.pop_front()  ## 移除最旧记录

## 获取玩家最常出的兵种 ID
## 通过统计历史记录中各兵种出现的频率，找出最频繁的兵种
## 返回值: 最常出的兵种 ID，如果历史记录为空则返回空字符串
func get_player_most_frequent() -> String:  ## 定义获取最常出兵方法
	## 如果历史记录为空，返回空字符串
	if player_history.is_empty():  ## 如果历史记录为空
		return ""  ## 返回空字符串
	## 创建频率统计字典
	var freq: Dictionary = {}  ## 频率统计字典
	## 遍历历史记录，统计每个兵种出现的次数
	for id in player_history:  ## 遍历历史记录
		freq[id] = freq.get(id, 0) + 1  ## 统计频率
	## 找出出现频率最高的兵种
	var most_freq_id: String = ""  ## 最频繁兵种 ID
	var most_freq_count: int = 0  ## 最高频率
	for id in freq:  ## 遍历频率字典
		## 如果当前兵种的频率高于已记录的最高频率
		if freq[id] > most_freq_count:  ## 如果频率更高
			most_freq_count = freq[id]  ## 更新最高频率
			most_freq_id = id  ## 更新最频繁兵种 ID
	return most_freq_id  ## 返回最频繁的兵种 ID

## 查找能够克制指定兵种的单位
## target_id: 要克制的目标兵种 ID
## gold: AI 当前拥有的金币数
## 返回值: 能够克制目标且 AI 负担得起的最佳兵种，找不到则返回 null
func find_counter_unit(target_id: String, gold: int) -> UnitResource:  ## 定义查找克制单位方法
	## 如果目标 ID 为空，无法查找克制单位
	if target_id == "":  ## 如果目标 ID 为空
		return null  ## 返回 null
	## 从数据库获取目标兵种的资源
	var target_res = UnitDatabase.get_unit(target_id)  ## 获取目标兵种
	## 如果目标兵种不存在，返回 null
	if target_res == null:  ## 如果目标兵种不存在
		return null  ## 返回 null

	## 获取 AI 当前可负担的所有兵种（战役模式下受敌人兵种数量限制）
	var affordable = UnitDatabase.get_ai_affordable_units(gold)  ## 获取 AI 可负担兵种列表
	## 最佳克制单位
	var best_counter: UnitResource = null  ## 最佳克制单位
	## 最佳克制倍率分数
	var best_score: float = -1.0  ## 最佳分数

	## 遍历所有可负担的兵种
	for unit in affordable:  ## 遍历可负担兵种
		## 检查该兵种是否克制目标兵种（在克制表中）
		if unit.counter_table.has(target_id):  ## 如果能克制目标
			## 获取克制倍率作为评分
			var score = unit.counter_table[target_id]  ## 获取克制倍率
			## 如果评分更高，更新最佳克制单位
			if score > best_score:  ## 如果评分更高
				best_score = score  ## 更新最佳分数
				best_counter = unit  ## 更新最佳克制单位

	return best_counter  ## 返回找到的最佳克制单位

## 子类必须实现的实际评估逻辑
## 由具体难度策略（简单/普通/困难）重写此方法
## _ai_controller: AI 控制器节点引用
func _do_evaluate(_ai_controller: Node) -> void:  ## 定义抽象评估方法
	## 基类中为空实现，子类需要覆盖此方法
	pass  ## 空实现，由子类重写
