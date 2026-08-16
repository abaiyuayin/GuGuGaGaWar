extends Area2D  ## 继承 Area2D 区域节点
## 基地建筑脚本
## 代表红方或蓝方的基地（水晶）
## 基地有生命值，被摧毁则游戏结束

## 所属阵营编号（0=红方, 1=蓝方）
var team: int = 0  ## 阵营编号，默认红方
## 当前生命值（HP）
var hp: int = Constants.BASE_HP  ## 当前 HP
## 最大生命值
var max_hp: int = Constants.BASE_HP  ## 最大 HP
## 预加载水晶贴图（红方=曲奇饼干，蓝方=橘子）
const TEX_RED: String = "res://assets/crystal_red.png"
const TEX_BLUE: String = "res://assets/crystal_blue.png"

## 节点引用：血条显示
@onready var health_bar: TextureProgressBar = $HealthBar  ## 获取血条节点

## 初始化基地
## team_id: 阵营编号（0=红方, 1=蓝方）
func setup(team_id: int) -> void:  ## 定义初始化基地的方法
	team = team_id  ## 保存阵营
	hp = max_hp  ## 重置 HP 为最大值
	## 设置血条的最大值和当前值
	health_bar.max_value = max_hp  ## 设置血条最大值
	health_bar.value = hp  ## 设置血条当前值
	## 根据阵营设置纹理
	var sprite = get_node_or_null("Sprite2D")  ## 获取精灵节点
	if sprite:  ## 如果精灵节点存在
		var tex_path: String = TEX_RED if team == 0 else TEX_BLUE
		sprite.texture = load(tex_path)
		sprite.modulate = Color(1, 1, 1, 1)  ## 原图不染色
		## 动画效果：红方(曲奇饼干)上下来回浮动，蓝方(橘子)缓慢旋转
		var tween := create_tween().set_loops()
		if team == 0:
			## 曲奇饼干：垂直浮动，幅度 8px，周期 2 秒（正弦来回）
			tween.tween_property(sprite, "position:y", -8.0, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tween.tween_property(sprite, "position:y", 8.0, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		else:
			## 橘子：缓慢旋转，360 度 / 12 秒
			tween.tween_property(sprite, "rotation", TAU, 12.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

## 基地受到伤害
## damage: 受到的伤害值
func take_damage(damage: int) -> void:  ## 定义基地受伤方法
	## 扣除生命值
	hp -= damage  ## 扣除 HP
	## 确保生命值不会小于 0
	hp = maxi(hp, 0)  ## 确保 HP 不小于 0
	## 更新血条显示
	health_bar.value = hp  ## 更新血条

	## 如果生命值归零，基地被摧毁
	if hp <= 0:  ## 如果 HP 归零
		_on_destroyed()  ## 调用被摧毁方法

## 基地被摧毁的处理方法（私有）
func _on_destroyed() -> void:  ## 定义被摧毁处理方法
	## 获取战场场景引用
	var battlefield = get_parent()  ## 获取父节点（战场）
	## 如果战场有 damage_base 方法，通知战场基地被摧毁
	if battlefield and battlefield.has_method("damage_base"):  ## 如果战场有 damage_base 方法
		## 发出基地被摧毁信号，参数为获胜方（敌方阵营）
		battlefield.base_destroyed.emit(1 - team)  ## 发出被摧毁信号，敌方获胜
