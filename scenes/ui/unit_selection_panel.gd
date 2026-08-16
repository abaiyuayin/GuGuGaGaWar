extends PanelContainer  ## 继承 PanelContainer 面板容器
## 兵种选择面板
## 屏幕底部横向排列所有可选兵种的按钮面板
## 玩家通过点击按钮或快捷键选择要出的兵种

## 节点引用：水平布局容器，存放所有兵种按钮
@onready var grid: GridContainer = $GridContainer

## 当前选中的兵种资源
var selected_unit: UnitResource = null
## 兵种按钮数组，用于批量更新按钮状态
var unit_buttons: Array[Button] = []

## 节点就绪时自动调用，创建兵种按钮
func _ready() -> void:
	## 创建所有兵种的按钮
	_create_unit_buttons()

	## 初始更新按钮的可购买状态
	update_affordability(EconomyManager.get_gold(0))

## 创建兵种按钮的方法（私有）
## 遍历所有兵种，为每个兵种创建一个按钮
func _create_unit_buttons() -> void:
	## 从兵种数据库获取所有兵种列表
	var units = UnitDatabase.unit_list
	## 遍历每个兵种
	for i in range(units.size()):
		var unit_res: UnitResource = units[i]  ## 获取当前兵种资源

		## 创建按钮节点
		var btn = Button.new()
		## 设置按钮最小尺寸
		btn.custom_minimum_size = Vector2(62, 45)
		## 设置按钮文本：兵种名称 + 造价
		btn.text = "%s\n$%d" % [unit_res.display_name, unit_res.cost]
		## 设置按钮工具提示：显示兵种详细属性
		btn.tooltip_text = "%s\nHP:%d 护甲:%d 攻:%d\n速度:%.1f 射程:%.1f\n收入:+%d/回合" % [
			unit_res.description,
			unit_res.max_hp,
			unit_res.armor_value,
			unit_res.damage,
			unit_res.move_speed,
			unit_res.attack_range,
			unit_res.income
		]
		btn.clip_text = true  ## 启用文本裁剪
		btn.autowrap_mode = TextServer.AUTOWRAP_OFF  ## 关闭自动换行
		btn.add_theme_font_size_override("font_size", 11)  ## 设置按钮字体大小为 11
		UIButtonHelper.setup_button(btn)  ## 使用按钮助手统一设置样式

		## 存储兵种引用和索引到按钮的元数据中
		btn.set_meta("unit_resource", unit_res)
		btn.set_meta("index", i)

		## 连接按钮按下信号
		btn.pressed.connect(_on_unit_button_pressed.bind(btn))

		## 为前 16 个兵种设置键盘快捷键
		if i < 9:
			## 1-9 对应前 9 个兵种
			btn.shortcut = create_shortcut(str(i + 1))
		elif i == 9:
			## 0 对应第 10 个兵种
			btn.shortcut = create_shortcut("0")
		elif i < 16:
			## Q/W/E/R/T/Y 对应第 11-16 个兵种
			var key_names = ["q", "w", "e", "r", "t", "y"]
			btn.shortcut = create_shortcut(key_names[i - 10])

		## 将按钮添加到网格容器中
		grid.add_child(btn)
		unit_buttons.append(btn)  ## 将按钮添加到按钮数组中

## 创建键盘快捷键的方法
## key: 按键字符（"1"-"9", "0", "q", "w", "e", "r", "t", "y"）
## 返回值: 创建的 Shortcut 对象
func create_shortcut(key: String) -> Shortcut:
	var shortcut = Shortcut.new()  ## 创建快捷键对象
	var event = InputEventKey.new()  ## 创建键盘事件
	## 根据按键字符设置对应的 keycode
	match key:
		"1": event.keycode = KEY_1  ## 数字键 1
		"2": event.keycode = KEY_2  ## 数字键 2
		"3": event.keycode = KEY_3  ## 数字键 3
		"4": event.keycode = KEY_4  ## 数字键 4
		"5": event.keycode = KEY_5  ## 数字键 5
		"6": event.keycode = KEY_6  ## 数字键 6
		"7": event.keycode = KEY_7  ## 数字键 7
		"8": event.keycode = KEY_8  ## 数字键 8
		"9": event.keycode = KEY_9  ## 数字键 9
		"0": event.keycode = KEY_0  ## 数字键 0
		"q": event.keycode = KEY_Q  ## 字母键 Q
		"w": event.keycode = KEY_W  ## 字母键 W
		"e": event.keycode = KEY_E  ## 字母键 E
		"r": event.keycode = KEY_R  ## 字母键 R
		"t": event.keycode = KEY_T  ## 字母键 T
		"y": event.keycode = KEY_Y  ## 字母键 Y
	## 将键盘事件添加到快捷键中
	shortcut.events.append(event)
	return shortcut  ## 返回创建好的快捷键对象

## 兵种按钮按下回调
## btn: 被按下的按钮
func _on_unit_button_pressed(btn: Button) -> void:
	## 从按钮元数据中获取兵种资源
	var unit_res: UnitResource = btn.get_meta("unit_resource")
	## 选择该兵种
	select_unit(unit_res, btn)

## 选择兵种的方法
## unit_res: 要选择的兵种资源
## btn: 对应的按钮（可选，用于高亮显示）
func select_unit(unit_res: UnitResource, btn: Button = null) -> void:
	selected_unit = unit_res  ## 保存选中的兵种

	## 更新所有按钮的选中状态显示
	for button in unit_buttons:
		## 复制当前样式
		var stylebox = button.get_theme_stylebox("normal").duplicate()
		## 仅改变边框颜色，不改变宽度，避免英文文本换行导致 UI 被推动
		if button == btn:
			stylebox.border_color = Color(1, 1, 0)  ## 选中按钮：黄色边框
		else:
			stylebox.border_color = Color(0.5, 0.5, 0.5, 0.5)  ## 未选中按钮：灰色半透明边框
		button.add_theme_stylebox_override("normal", stylebox)

	## 通知战斗管理器玩家已选择兵种
	BattleManager.set_selected_unit(0, unit_res)

## 更新按钮可购买状态的方法
## gold: 当前金币数
func update_affordability(gold: int) -> void:
	## 遍历所有按钮
	for button in unit_buttons:
		## 从按钮元数据中获取兵种资源
		var unit_res: UnitResource = button.get_meta("unit_resource")
		## 检查金币是否足够
		if gold >= unit_res.cost:
			button.disabled = false  ## 可购买：启用按钮
			button.modulate = Color(1, 1, 1)  ## 正常颜色
		else:
			button.disabled = true  ## 不可购买：禁用按钮
			button.modulate = Color(0.5, 0.5, 0.5)  ## 灰色显示
