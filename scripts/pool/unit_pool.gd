class_name UnitPool  ## 声明类名为 UnitPool
## ⚠️ 已废弃（2026-08-20）：本类是**未启用的遗留实现**，全仓零引用、未注册为 autoload。
## 项目真正生效的对象池是 BattleManager 内嵌的 `_unit_pool: Array`（见 battle_manager.gd:74），
## 那是一个**无类型扁平池**——任何实例都可被 setup() 重塑为任意兵种；
## 而本类是按 unit_id 分桶的设计，两者不兼容。
## 请勿在新代码中使用本类，也不要照它的思路改动池逻辑；一切修改请落到 BattleManager。
## 保留物理文件仅因删除操作被占用阻塞，功能上等同于不存在。
## 单位对象池类
## 用于优化大量单位的创建和销毁性能，避免频繁的内存分配和垃圾回收

extends Node  ## 继承 Node，作为场景树中的一个节点存在
## 继承 Node，作为场景树中的一个节点存在

## 对象池字典：键为兵种 ID（字符串），值为该兵种的对象数组
## 每个数组中存放已被回收、可重复使用的单位实例
var pools: Dictionary = {}
## 单位基础场景的 PackedScene 缓存，用于首次创建单位时实例化
var unit_scene: PackedScene

## 节点就绪时自动调用，预加载单位场景
func _ready() -> void:
	## 加载单位基础场景文件，缓存到 unit_scene 变量中
	unit_scene = load("res://scenes/units/unit_base.tscn")

## 从对象池中获取一个单位实例
## 如果池中有可用的回收单位，则复用；否则创建新实例
## unit_res: 要获取的兵种资源
## team: 单位所属阵营（0=红方, 1=蓝方）
## 返回值: 初始化好的单位节点
func get_unit(unit_res: UnitResource, team: int) -> Node2D:
	var key: String = unit_res.unit_id  ## 使用兵种 ID 作为池的键
	## 如果该兵种还没有对应的池，创建一个空数组
	if not pools.has(key):
		pools[key] = []

	var unit: Node2D
	## 检查池中是否有可复用的单位
	if pools[key].size() > 0:
		## 从池中取出一个已回收的单位
		unit = pools[key].pop_back()
	else:
		## 池为空，创建新的单位实例
		unit = unit_scene.instantiate()

	## 初始化单位（设置兵种资源和阵营）
	unit.setup(unit_res, team)
	return unit  ## 返回初始化好的单位

## 将单位归还到对象池中，以便后续复用
## unit: 要回收的单位节点
func return_unit(unit: Node2D) -> void:
	## 检查单位实例是否仍然有效（未被销毁）
	if not is_instance_valid(unit):
		return
	var key: String = unit.unit_resource.unit_id  ## 获取该单位的兵种 ID
	## 如果该兵种还没有对应的池，创建一个空数组
	if not pools.has(key):
		pools[key] = []

	## 如果单位仍在场景树中，从父节点移除
	if unit.get_parent():
		unit.get_parent().remove_child(unit)
	## 将单位添加到对应兵种的对象池中
	pools[key].append(unit)

## 清空所有对象池，销毁池中所有单位实例
## 通常在战斗结束或场景切换时调用
func clear_all() -> void:
	## 遍历所有兵种的对象池
	for key in pools:
		## 遍历池中的每个单位实例
		for unit in pools[key]:
			## 检查实例是否有效，有效则销毁
			if is_instance_valid(unit):
				unit.queue_free()
	## 清空池字典
	pools.clear()
