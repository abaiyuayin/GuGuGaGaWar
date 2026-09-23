class_name ImpactEffect  ## 定义全局类名 ImpactEffect
extends Node2D  ## 继承 Node2D 节点
## 命中特效（2026-09-18，萌黄 S9）
## 供 attack_instant_hit 兵种使用：伤害在目标身上结算后，于命中位置播放一段独立特效。
## 两种外观二选一：
##   ① 配置了 frames（SpriteFrames）→ 播放该动画，播完自动销毁；
##   ② 未配置 → 内置圆形光点（白色径向渐变，按阵营红/蓝着色），放大淡出后销毁。
## 纯视觉节点，不参与物理、碰撞与伤害结算。

## 未配置显示尺寸时的默认高度（像素）
const DEFAULT_DISPLAY_HEIGHT: float = 32.0
## 圆形光点的放大淡出时长（秒）
const GLOW_FADE_TIME: float = 0.3
## 圆形光点起始缩放倍率（相对基准缩放）
const GLOW_SCALE_FROM: float = 0.55
## 圆形光点结束缩放倍率
const GLOW_SCALE_TO: float = 1.35

## 命中特效帧动画（null = 用内置圆形光点）
var frames: SpriteFrames = null
## 显示高度（像素），<=0 时用 DEFAULT_DISPLAY_HEIGHT
var display_height: float = 0.0
## 显示宽度（像素），<=0 时与高度相同
var display_width: float = 0.0
## 所属阵营（0=红方, 1=蓝方），仅用于圆形光点着色
var team: int = 0
## 视觉命中时刻（秒）：帧动画「中间帧」的播放时间（22 帧 @30fps → 第 11 帧 ≈ 0.367s）。
## 攻击方（unit_base 的瞬发命中分支）把伤害结算对齐到该时刻，避免「血先掉、特效后到」。
## 未配置帧动画（走圆形光点回退）时恒为 0，调用方据此退回立即结算。
var impact_moment: float = 0.0

## 定格模式（2026-09-20，Hero4 回身七连专用）：
## 帧动画播完后不自毁，而是停在最后一帧等待调用方统一渐隐（不再是「播完即消失」）。
## 此时保留动画不循环，且兜底回收延长到 8 秒防止调用方漏掉渐隐导致节点永久残留。
var hold_after_finish: bool = false
## 延迟起播（2026-09-20，Hero4 回身七连专用）：
## 为 true 时创建后保持隐藏且不起播，由调用方在「蔓延到它」的时刻调用 begin()。
## 用于「一道道特效自位移起点向终点蔓延」的时序表现。
var start_deferred: bool = false

## 定格模式的兜底余量（秒）：远大于正常播放时长，只在调用方漏掉渐隐时兜底
const HOLD_GUARD_MARGIN: float = 8.0

## 延迟起播模式下记录动画名，供 begin() 使用
var _deferred_anim: String = ""
## 帧动画精灵引用（begin() / fade_out() 使用）
var _sprite: AnimatedSprite2D = null

## 共享的白色径向渐变贴图（与投射物光球同款，静态复用）
static var _glow_texture: Texture2D = null

## 创建/复用白色径向渐变贴图（中心亮白、边缘透明）
static func _get_glow_texture() -> Texture2D:
	if _glow_texture != null:
		return _glow_texture
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := float(size) * 0.5
	var radius := center
	for y in range(size):
		for x in range(size):
			var dx := float(x) - center
			var dy := float(y) - center
			var d := sqrt(dx * dx + dy * dy) / radius
			if d <= 1.0:
				## (1-d)^1.5 让光晕集中在中心
				img.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - d, 1.5)))
	_glow_texture = ImageTexture.create_from_image(img)
	return _glow_texture

## 计算缩放系数：与 Unit._compute_anim_scale 同口径（整帧纹理尺寸 + 宽高双向约束取较小值）
func _compute_scale(tex: Texture2D) -> float:
	var target_h: float = display_height if display_height > 0.0 else DEFAULT_DISPLAY_HEIGHT
	var target_w: float = display_width if display_width > 0.0 else target_h
	if tex == null:
		return 1.0
	var fw: float = float(tex.get_width())
	var fh: float = float(tex.get_height())
	if fw <= 0.0 or fh <= 0.0:
		return 1.0
	return minf(target_w / fw, target_h / fh)

func _ready() -> void:
	z_index = 5  ## 画在单位之上，避免被单位精灵挡住
	if frames != null and frames.get_animation_names().size() > 0:
		_setup_animation()
	else:
		_setup_glow()

## 外观①：播放配置的帧动画，播完自毁
func _setup_animation() -> void:
	var anim_name: String = frames.get_animation_names()[0]
	var first_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "EffectSprite"
	sprite.centered = true
	sprite.sprite_frames = frames
	var s: float = _compute_scale(first_tex)
	sprite.scale = Vector2(s, s)
	add_child(sprite)
	_sprite = sprite
	_deferred_anim = anim_name
	## 视觉命中时刻 = 中间帧（帧数取半）：该时刻特效刚完成展开、冲击感最强，
	## 攻击方据此把伤害结算对齐到这里。
	var frame_count: int = frames.get_frame_count(anim_name)
	var anim_fps: float = frames.get_animation_speed(anim_name)
	var duration: float = float(frame_count) / maxf(anim_fps, 0.001)
	impact_moment = (float(frame_count) * 0.5) / maxf(anim_fps, 0.001)

	if start_deferred:
		## 延迟起播：先隐藏，等调用方 begin()（用于一道道蔓延）
		visible = false
	else:
		sprite.play(anim_name)

	if hold_after_finish:
		## 定格模式：播完停在最后一帧，等调用方统一渐隐（不自毁）
		sprite.animation_finished.connect(_on_anim_finished_hold)
	else:
		sprite.animation_finished.connect(queue_free)
	## 兜底回收：帧动画若被配成 loop = true，animation_finished 永不触发，
	## 特效会永久留在场上（每个命中点残留一个）。按「总帧数 / 帧率 + 0.3s」强制销毁。
	## 定格模式延长到 8 秒 —— 生命周期由调用方掌管，这里只做防漏兜底。
	var guard: float = duration + (HOLD_GUARD_MARGIN if hold_after_finish else 0.3)
	get_tree().create_timer(guard).timeout.connect(_on_guard_timeout)

## 定格模式的动画结束回调：冻结在最后一帧，不自毁
func _on_anim_finished_hold() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.pause()

## 延迟起播模式下开始播放（蔓延到它时由技能调用方调用）
func begin() -> void:
	visible = true
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.play(_deferred_anim)

## 统一渐隐后自毁（技能调用方在「攻击动画结束」时刻对整批特效同时调用）
func fade_out(duration: float = 1.0) -> void:
	if not is_instance_valid(self):
		return
	## 已播放中的特效不再冻结，直接整体淡出
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, maxf(duration, 0.0))
	tw.tween_callback(queue_free)

## 兜底定时器回调（方法引用，不捕获节点，避免节点先释放时 lambda 报错）
func _on_guard_timeout() -> void:
	if is_instance_valid(self):
		queue_free()

## 外观②：内置圆形光点，放大淡出后自毁
func _setup_glow() -> void:
	var tex: Texture2D = _get_glow_texture()
	var sprite := Sprite2D.new()
	sprite.name = "EffectSprite"
	sprite.centered = true
	sprite.texture = tex
	var base: float = _compute_scale(tex)
	sprite.scale = Vector2(base * GLOW_SCALE_FROM, base * GLOW_SCALE_FROM)
	sprite.modulate = Color(1.0, 0.35, 0.35, 1.0) if team == 0 else Color(0.4, 0.6, 1.0, 1.0)
	add_child(sprite)
	var end_scale := Vector2(base * GLOW_SCALE_TO, base * GLOW_SCALE_TO)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", end_scale, GLOW_FADE_TIME)
	tween.tween_property(sprite, "modulate:a", 0.0, GLOW_FADE_TIME)
	tween.chain().tween_callback(queue_free)
