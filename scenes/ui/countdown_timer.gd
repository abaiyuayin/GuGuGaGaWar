extends PanelContainer  ## 继承 PanelContainer 面板容器
## 倒计时显示面板
## 显示当前回合数和剩余倒计时时间
## 位于屏幕顶部中央

## 节点引用：回合数标签
@onready var round_label: Label = $HBox/RoundLabel
## 节点引用：倒计时标签
@onready var timer_label: Label = $HBox/TimerLabel

## 节点就绪时自动调用，设置字体大小
func _ready() -> void:
	## 设置倒计时数字字体大小为 36（大号显示）
	timer_label.add_theme_font_size_override("font_size", 36)
	## 设置回合标签字体大小为 20
	round_label.add_theme_font_size_override("font_size", 20)

## 更新倒计时显示的方法
## time_left: 剩余时间（秒）
## round_number: 当前回合数
func update_timer(time_left: float, round_number: int) -> void:
	## 更新回合数显示
	round_label.text = tr("COUNTDOWN_ROUND") % round_number
	## 更新倒计时显示（向上取整显示整数秒）
	timer_label.text = "%d" % ceili(time_left)

	## 最后 5 秒变红警告
	if time_left <= 5.0:
		## 剩余时间少于 5 秒，显示红色警告
		timer_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:  ## 剩余时间充足
		## 正常状态下显示白色
		timer_label.add_theme_color_override("font_color", Color(1, 1, 1))

## 闪烁效果方法
## 回合切换时调用，产生闪烁动画
func flash() -> void:
	## 创建 Tween 动画
	var tween = create_tween()
	## 在 0.1 秒内将透明度降到 0.3
	tween.tween_property(self, "modulate:a", 0.3, 0.1)
	## 在 0.2 秒内恢复透明度到 1.0
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
