extends Node  ## 继承 Node，作为场景根节点
## 入口场景脚本
## 游戏启动后的第一个场景：先显示开屏动画（白屏 + 居中 title.png），
## 停留展示后跳转到主菜单

const SPLASH_DURATION := 2.0  ## 开屏停留时长（秒）
const FADE_DURATION := 0.5    ## 开屏淡出时长（秒）
const TITLE_TEXTURE := preload("res://assets/ui/title.png")
## 主菜单场景路径（开屏期间后台预载，结束后直接切换，无需加载框）
const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"

var _splash_root: Control = null

func _ready() -> void:
	_show_splash()
	## 开屏展示期间后台异步预载主菜单：2.5s 足够加载完，
	## 结束后可直接切场景而不卡主线程，从而无需加载框
	## （2026-08-19 用户拍板：进入游戏只要开屏动画，不弹加载框）
	ResourceLoader.load_threaded_request(MAIN_MENU_PATH, "PackedScene")
	## 停留展示开屏，然后淡出并进入主菜单
	await get_tree().create_timer(SPLASH_DURATION).timeout
	await _fade_out_splash()
	_enter_main_menu()

## 进入主菜单：优先用预载结果直接切换（无加载框）；预载未就绪则走跳过遮罩的常规切换
func _enter_main_menu() -> void:
	var st: int = ResourceLoader.load_threaded_get_status(MAIN_MENU_PATH)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		var packed: PackedScene = ResourceLoader.load_threaded_get(MAIN_MENU_PATH)
		if packed != null:
			GameManager.current_state = GameManager.GameState.MAIN_MENU
			get_tree().change_scene_to_packed(packed)
			return
	## 兜底：预载失败或未完成，仍跳过加载框直接切（skip_loading = true）
	GameManager.change_state.call_deferred(GameManager.GameState.MAIN_MENU, true)

## 构建开屏：全屏白底 + 中间水平垂直居中的 title.png
func _show_splash() -> void:
	_splash_root = Control.new()
	_splash_root.name = "SplashScreen"
	_splash_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_splash_root)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(1, 1, 1, 1)  ## 白屏
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash_root.add_child(bg)

	var title := TextureRect.new()
	title.name = "Title"
	title.texture = TITLE_TEXTURE
	## 等比完整显示（title 2848x1600 约 16:9，1280x720 下接近铺满），水平垂直居中
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash_root.add_child(title)

## 淡出开屏
func _fade_out_splash() -> void:
	if _splash_root == null or not is_instance_valid(_splash_root):
		return
	var tw := create_tween()
	tw.tween_property(_splash_root, "modulate:a", 0.0, FADE_DURATION)
	await tw.finished
	_splash_root.queue_free()
	_splash_root = null
