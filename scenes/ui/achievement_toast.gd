extends CanvasLayer
## 成就解锁提示框：屏幕右下角由下往上滑入，停留数秒后滑出并自毁
## 由 Achievements 单例在成就首次解锁时实例化并加入场景树
## 根节点使用 CanvasLayer 且 layer 较高，确保盖在 HUD / 结算界面之上

const TOAST_SIZE: Vector2 = Vector2(360.0, 84.0)
const SCREEN_MARGIN: float = 16.0
const SLIDE_TIME: float = 0.35
## #13（2026-08-09）：停留时长 3.2 → 3.0 秒（用户拍板「每弹窗保持 3 秒」）
const HOLD_TIME: float = 3.0

var _root: Control
var _icon_label: Label
var _name_label: Label
var _desc_label: Label
## 待展示的成就条目，由 configure() 在入树前写入
var _entry: Dictionary = {}

## 入树前配置成就内容（不访问任何子节点，可在 add_child 之前安全调用）
func configure(entry: Dictionary) -> void:
	_entry = entry

func _ready() -> void:
	layer = 200
	## #14 修复：失败/结算界面弹出时 get_tree().paused=true，默认 PAUSABLE 会让滑入
	## Tween 冻结，toast 永远停在屏幕外（hidden_y）→「语音响了但成就没弹出来」。
	## 改 ALWAYS 保证任何暂停状态下滑入/停留/滑出动画照常播放。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_play()

## 纯代码构建提示框内容（自包含，不依赖场景内子节点）
func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = TOAST_SIZE
	add_child(_root)

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 0.96)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.95, 0.78, 0.28, 1.0)
	sb.set_corner_radius_all(8)
	bg.add_theme_stylebox_override("panel", sb)
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	bg.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	## 左侧图标
	_icon_label = Label.new()
	_icon_label.text = "★"
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 40)
	_icon_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.28, 1.0))
	_icon_label.custom_minimum_size = Vector2(56.0, 56.0)
	hbox.add_child(_icon_label)

	## 右侧文本区（成就名 + 描述）
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.28, 1.0))
	vbox.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 13)
	_desc_label.add_theme_color_override("font_color", Color(0.90, 0.90, 0.90, 1.0))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(250.0, 0.0)
	vbox.add_child(_desc_label)

## 填充文本并播放入场 → 停留 → 退场动画
func _play() -> void:
	_name_label.text = tr("ACH_NAME_" + str(_entry.get("id", "")))
	_desc_label.text = tr("ACH_DESC_" + str(_entry.get("id", "")))

	var vp: Vector2 = _root.get_viewport_rect().size
	var target_x: float = vp.x - TOAST_SIZE.x - SCREEN_MARGIN
	var target_y: float = vp.y - TOAST_SIZE.y - SCREEN_MARGIN
	var hidden_y: float = vp.y + 8.0
	_root.position = Vector2(target_x, hidden_y)

	var tween_in := create_tween()
	tween_in.tween_property(_root, "position:y", target_y, SLIDE_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	await get_tree().create_timer(SLIDE_TIME + HOLD_TIME).timeout
	if not is_instance_valid(self) or not is_instance_valid(_root):
		return

	var tween_out := create_tween()
	tween_out.tween_property(_root, "position:y", hidden_y, SLIDE_TIME) \
		.set_ease(Tween.EASE_IN)
	tween_out.tween_callback(queue_free)
