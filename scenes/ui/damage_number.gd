class_name DamageNumber extends Label
## 伤害飘字
## 在单位头顶显示伤害数字，向上飘起并淡出后销毁

## 飘动速度（像素/秒）
var float_speed: float = 40.0
## 已存活时间
var elapsed: float = 0.0
## 最大存活时间（秒），超过后销毁
var lifetime: float = 0.8

func _ready() -> void:
	## 文本样式：加粗、黑色描边、居中
	add_theme_font_size_override("font_size", 12)
	## 不在此处设默认颜色：颜色由单位受伤时按伤害类型指定，避免覆盖调用方设置
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	add_theme_constant_override("outline_size", 3)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## 不拦截鼠标事件
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100

func _process(delta: float) -> void:
	elapsed += delta
	## 向上飘动
	position.y -= float_speed * delta
	## 后半段淡出
	if elapsed > lifetime * 0.5:
		var fade_progress: float = (elapsed - lifetime * 0.5) / (lifetime * 0.5)
		modulate.a = clampf(1.0 - fade_progress, 0.0, 1.0)
	## 超过存活时间，销毁
	if elapsed >= lifetime:
		queue_free()

## 设置伤害文本和颜色（根据伤害来源区分）
## damage: 伤害数值
## is_bleed: 是否为流血伤害（红色）
func set_damage(damage: int, is_bleed: bool = false) -> void:
	text = str(damage)
	if is_bleed:
		## 流血伤害用红色
		add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	else:
		## 普通伤害用黄色
		add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))

## 设置伤害文本和自定义颜色（用于中毒等特殊伤害）
## damage: 伤害数值
## color: 自定义颜色
func set_damage_color(damage: int, color: Color) -> void:
	text = str(damage)
	add_theme_color_override("font_color", color)
