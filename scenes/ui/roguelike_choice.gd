class_name RoguelikeChoice
extends CanvasLayer
## 肉鸽模式通用选项弹窗（休息 / 事件节点复用）
##
## 全代码结构：根节点 CanvasLayer，UI 在 options_ready() 中构建。
## 选项数组每项为一个 Dictionary：{"label": String, "action": Callable}。
## 玩家点选后执行对应 action，随后本弹窗自行 queue_free()。

## 单张选项按钮字体大小
const OPTION_FONT_SIZE: int = 18
## 标题字体大小
const TITLE_FONT_SIZE: int = 26

## 构建标题与若干选项按钮
## [param title] 弹窗标题；[param options] 为 {label, action} 字典数组
func options_ready(title: String, options: Array[Dictionary]) -> void:
	## 暂停状态下按钮仍应可点击
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui(title, options)

func _build_ui(title: String, options: Array[Dictionary]) -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	## 空状态兜底：没有任何选项时给出提示，避免空白弹窗被误认为卡死
	if options.is_empty():
		var empty_hint := Label.new()
		empty_hint.text = "这里空无一物，没有可做的事。"
		empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_hint.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
		empty_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7, 1.0))
		empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(empty_hint)
		return

	for opt in options:
		var btn := Button.new()
		btn.text = opt["label"]
		btn.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
		var action: Callable = opt["action"] as Callable
		## 防御：action 缺失 / 非法时禁用按钮，避免点击后空调用抛错中断
		if action.is_valid():
			btn.pressed.connect(_on_option_pressed.bind(action))
		else:
			btn.disabled = true
		vbox.add_child(btn)

## 点选后执行选项的 action，随后释放本弹窗（延迟到帧末，避免在执行回调时释放自身）
func _on_option_pressed(action: Callable) -> void:
	if action.is_valid():
		action.call()
	queue_free()
