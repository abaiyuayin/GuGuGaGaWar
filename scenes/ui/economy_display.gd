extends PanelContainer  ## 继承 PanelContainer 面板容器
## 经济信息显示面板
## 显示玩家当前的金币数量和每回合收入
## 位于屏幕左下角

## 节点引用：金币数量标签
@onready var gold_label: Label = $VBox/GoldLabel
## 节点引用：收入标签
@onready var income_label: Label = $VBox/IncomeLabel

## 节点就绪时自动调用，设置字体大小
func _ready() -> void:
	## 设置金币标签字体大小为 20
	gold_label.add_theme_font_size_override("font_size", 20)
	## 设置收入标签字体大小为 16
	income_label.add_theme_font_size_override("font_size", 16)

## 更新经济显示的方法
## gold: 当前金币数
## income: 每回合收入
func update_display(gold: int, income: int) -> void:
	## 更新金币显示文本
	gold_label.text = tr("ECON_GOLD") % gold
	## 更新收入显示文本
	income_label.text = tr("ECON_INCOME") % income

	## 金币不足时变红提示
	if gold < 20:
		## 金币少于 20 时显示红色（警告色）
		gold_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:  ## 金币充足
		## 金币充足时显示金色
		gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0))
