extends CanvasLayer
## 移动端触屏输入层（安卓/iOS 自动启用；桌面可在设置里手动开以便测试）
##
## 设计原则：复用 battle_root 已有的「右键拖动平移 + 滚轮缩放」相机逻辑，
## 不重写玩法代码、不新增相机分支——只把触摸手势「翻译」成 battle_root 已认识的输入事件。
##
## 手势映射：
##   · 单指轻点        → 不动它。Godot 默认 touch→mouse 模拟会生成鼠标左键，
##                        布兵/选卡/锁单位等左键逻辑照常工作。
##   · 单指拖动        → 合成 MOUSE_BUTTON_RIGHT 按下 + MouseMotion，驱动现有相机平移。
##   · 双指捏合        → 直接改 camera.zoom（复用 battle_root._clamp_camera 钳制边界）。
##   · 单指长按        → 合成一次右键（取消锁定/右键上下文等价）。
##   · 右上角「暂停」键 → 调 hud.toggle_settings_pause()（与 ESC 等价）。
##
## 本层是全屏 CanvasLayer，背景 Control 设 mouse_filter=IGNORE 不拦截点击，
## 只让右上角暂停按钮接收触摸；手势在 Node._input 里处理（与 mouse_filter 无关）。

const DRAG_THRESHOLD: float = 12.0  ## 超过此位移（像素）才判定为拖动，避免轻点误触平移
const LONG_PRESS_TIME: float = 0.5  ## 长按阈值（秒），用于右键（取消/上下文）等价

var _battle_root: Node = null  ## 战斗根（持有 camera / hud / _clamp_camera）
var _camera: Camera2D = null

var _pan_finger: int = -1  ## 正在平移的手指 index（-1 表示无）
var _pan_confirmed: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _long_press_fired: bool = false
var _long_press_timer: float = 0.0

var _finger_pos: Dictionary = {}  ## index -> Vector2（记录所有手指位置，用于捏合）
var _pinch_active: bool = false
var _pinch_start_dist: float = 0.0
var _pinch_start_zoom: float = 0.0

var _pause_button: Button = null

## 由 battle_root._ready 在触屏模式下调用
func setup(p_battle_root: Node, p_camera: Camera2D) -> void:
	_battle_root = p_battle_root
	_camera = p_camera
	layer = 100  ## 盖在 HUD（默认 layer 较低）之上
	process_mode = Node.PROCESS_MODE_ALWAYS  ## 暂停时暂停键仍需可用
	_build_ui()

func _build_ui() -> void:
	## 透明全屏层：不拦截点击，让下方按钮/兵种卡照常接收触摸
	var bg := Control.new()
	bg.name = "TouchPassthrough"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = "暂停"
	_pause_button.custom_minimum_size = Vector2(72, 48)
	var safe_top: int = 16
	var safe_right: int = 16
	## 避开刘海 / 挖孔安全区（如有）
	if DisplayServer.has_method("get_display_safe_area"):
		var sa: Rect2i = DisplayServer.get_display_safe_area()
		safe_top = maxi(safe_top, sa.position.y + 16)
		safe_right = maxi(safe_right, sa.position.x + 16)
	var vp_size: Vector2 = get_viewport().size
	_pause_button.position = Vector2(vp_size.x - _pause_button.custom_minimum_size.x - safe_right, safe_top)
	_pause_button.pressed.connect(_on_pause_pressed)
	add_child(_pause_button)
	## 视口尺寸变化时把暂停键重新贴到右上角
	get_viewport().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized() -> void:
	if _pause_button == null:
		return
	var safe_right: int = 16
	if DisplayServer.has_method("get_display_safe_area"):
		var sa: Rect2i = DisplayServer.get_display_safe_area()
		safe_right = maxi(safe_right, sa.position.x + 16)
	var vp_size: Vector2 = get_viewport().size
	_pause_button.position = Vector2(vp_size.x - _pause_button.custom_minimum_size.x - safe_right, _pause_button.position.y)

func _on_pause_pressed() -> void:
	if _battle_root != null and is_instance_valid(_battle_root) and _battle_root.hud != null:
		if _battle_root.hud.has_method("toggle_settings_pause"):
			_battle_root.hud.toggle_settings_pause()

func _input(event: InputEvent) -> void:
	if _camera == null or _battle_root == null:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)

func _on_touch(ev: InputEventScreenTouch) -> void:
	var idx: int = ev.index
	if ev.pressed:
		_finger_pos[idx] = ev.position
		if _finger_pos.size() == 1:
			## 第一根手指落下：先当作潜在平移，等移动超阈值或长按再定性
			_pan_finger = idx
			_pan_confirmed = false
			_pan_start = ev.position
			_long_press_fired = false
			_long_press_timer = LONG_PRESS_TIME
		elif _finger_pos.size() == 2:
			_start_pinch()
	else:
		## 手指抬起
		_finger_pos.erase(idx)
		if _pinch_active and _finger_pos.size() < 2:
			_pinch_active = false
		if _pan_finger == idx:
			if _pan_confirmed:
				_feed_right(false, ev.position)  ## 结束平移
			## 未确认且未长按 = 普通轻点：交给 Godot 模拟的左键（布兵/选卡）
			_pan_finger = -1
			_pan_confirmed = false

func _on_drag(ev: InputEventScreenDrag) -> void:
	var idx: int = ev.index
	_finger_pos[idx] = ev.position
	if _pinch_active and _finger_pos.size() >= 2:
		_do_pinch()
		return
	if _long_press_fired:
		return  ## 已长按处理，拖动不再触发平移
	if _pan_finger == idx and not _pan_confirmed:
		if ev.position.distance_to(_pan_start) >= DRAG_THRESHOLD:
			_pan_confirmed = true
			_feed_right(true, _pan_start)  ## 开始平移
			_feed_motion(ev.position)
	elif _pan_finger == idx and _pan_confirmed:
		_feed_motion(ev.position)

func _start_pinch() -> void:
	_pinch_active = true
	_pan_finger = -1  ## 捏合期间取消单指平移，避免跳变
	_pan_confirmed = false
	var pts: Array = _finger_pos.values()
	_pinch_start_dist = pts[0].distance_to(pts[1])
	_pinch_start_zoom = _camera.zoom.x

func _do_pinch() -> void:
	if _pinch_start_dist <= 0.0:
		return
	var pts: Array = _finger_pos.values()
	var dist: float = pts[0].distance_to(pts[1])
	if dist <= 0.0:
		return
	var ratio: float = dist / _pinch_start_dist
	var new_zoom: float = clampf(_pinch_start_zoom * ratio, _battle_root.camera_zoom_min, _battle_root.CAMERA_ZOOM_MAX)
	_camera.zoom = Vector2(new_zoom, new_zoom)
	_battle_root._clamp_camera()  ## 复用现有边界钳制

## 合成一次鼠标右键事件喂给 battle_root（其 _input 已处理右键拖动/取消）
func _feed_right(pressed: bool, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)

## 合成一次鼠标移动事件（驱动 battle_root 的拖动位移计算）
func _feed_motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)

func _process(delta: float) -> void:
	if _pan_finger == -1 or _pan_confirmed or _long_press_fired:
		return
	_long_press_timer -= delta
	if _long_press_timer <= 0.0:
		_long_press_fired = true
		## 长按 = 右键（取消锁定 / 上下文），合成一次右键按下+抬起
		_feed_right(true, _pan_start)
		_feed_right(false, _pan_start)
