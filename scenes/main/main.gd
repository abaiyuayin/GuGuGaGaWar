extends Node  ## 继承 Node，作为场景根节点
## 入口场景脚本
## 游戏启动后的第一个场景：先显示开屏动画（白屏 + 居中 title.png），
## 停留展示后跳转到主菜单

const SPLASH_DURATION := 2.0  ## 开屏停留时长（秒）
const FADE_DURATION := 0.5    ## 开屏淡出时长（秒）
const TITLE_TEXTURE := preload("res://assets/ui/title.png")
## 主菜单场景路径（开屏期间后台预载，结束后直接切换，无需加载框）
const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"

## 开屏期间后台预取的 UI 纹理（2026-10-04 新增）
## 背景：UI 纹理路径在项目里是**字符串常量**（UIButtonHelper.TEX_*），不属于任何场景的
## 资源依赖，因此切到对应场景、`_ready` 里第一次 `load()` 时才会同步读盘 ——
## 例如 `campaign_map` 的 `button_topbar_3.png`（817KB），这是换场景那一帧卡顿的来源之一。
## 开屏 2.5s 是纯等待期，把这份读盘开销全部提前到这里异步完成，之后任何 UI 场景切换都命中缓存。
## 全部异步请求，不阻塞开屏；路径不存在时请求失败即可，无副作用。
const UI_PREFETCH_TEXTURES: Array[String] = [
	"res://assets/ui/battle_ui.png",
	"res://assets/ui/battle_ui_bg.png",
	"res://assets/ui/btn_campaign.png",
	"res://assets/ui/btn_guide.png",
	"res://assets/ui/btn_multi.png",
	"res://assets/ui/btn_quit.png",
	"res://assets/ui/btn_settings.png",
	"res://assets/ui/btn_single.png",
	"res://assets/ui/button_hover.png",
	"res://assets/ui/button_normal.png",
	"res://assets/ui/button_pressed.png",
	"res://assets/ui/button_topbar_2.png",
	"res://assets/ui/button_topbar_3.png",
	"res://assets/ui/economy_gold_icon.png",
	"res://assets/ui/economy_income_upgrade_icon.png",
	"res://assets/ui/economy_pop_upgrade_icon.png",
	"res://assets/ui/info_panel.png",
	"res://assets/ui/panel_parchment.png",
	"res://assets/ui/panel_wood.png",
	"res://assets/ui/unit_button_bg.png",
	## 战役界面美术（2026-10-04）：campaign_map._ready 内 load() 的贴图，预取避免首次切场景同步读盘
	"res://assets/ui/campaign/marker_unlocked.png",
	"res://assets/ui/campaign/marker_locked.png",
	"res://assets/ui/campaign/marker_boss.png",
	"res://assets/ui/campaign/marker_perfect.png",
	"res://assets/ui/campaign/boss_badge.png",
	"res://assets/ui/campaign/star_on.png",
	"res://assets/ui/campaign/star_off.png",
	"res://assets/ui/campaign/sun.png",
	"res://assets/ui/campaign/banner_title.png",
	"res://assets/ui/campaign/ach_window_bg.png",
	"res://assets/ui/campaign/ach_badge_unlocked.png",
	"res://assets/ui/campaign/ach_badge_locked.png",
	"res://assets/ui/campaign/ach_ribbon_done.png",
]
## 开屏期间后台预取的常用弹窗场景（首次打开时 `load()` + instantiate 的卡顿同理）
const UI_PREFETCH_SCENES: Array[String] = [
	"res://scenes/ui/unit_unlock_window.tscn",
	"res://scenes/ui/achievements_window.tscn",
]

var _splash_root: Control = null

func _ready() -> void:
	_show_splash()
	## 开屏展示期间后台异步预载主菜单：2.5s 足够加载完，
	## 结束后可直接切场景而不卡主线程，从而无需加载框
	## （2026-08-19 用户拍板：进入游戏只要开屏动画，不弹加载框）
	ResourceLoader.load_threaded_request(MAIN_MENU_PATH, "PackedScene")
	## Web 按需加载（2026-09-14）：开屏期间后台预取兵种图集资源包（仅 Web 生效，桌面立即返回）
	WebPackLoader.ensure_units()
	## 2026-10-04：开屏等待期顺手把 UI 纹理/弹窗场景预取掉（见上方常量说明）
	_prefetch_ui_resources()
	## 停留展示开屏，然后淡出并进入主菜单
	await get_tree().create_timer(SPLASH_DURATION).timeout
	await _fade_out_splash()
	_enter_main_menu()

## 发起 UI 资源异步预取（不阻塞；未加载完的部分会在后台继续，不影响切场景）
func _prefetch_ui_resources() -> void:
	for tex_path in UI_PREFETCH_TEXTURES:
		ResourceLoader.load_threaded_request(tex_path)
	for scene_path in UI_PREFETCH_SCENES:
		ResourceLoader.load_threaded_request(scene_path, "PackedScene")

## 收尾已完成的预取请求：load_threaded_request 的结果需要调用一次
## load_threaded_get 才算取走；此处只处理已 LOADED 的，未完成的留给后台继续。
func _drain_ui_prefetch() -> void:
	for tex_path in UI_PREFETCH_TEXTURES:
		if ResourceLoader.load_threaded_get_status(tex_path) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(tex_path)
	for scene_path in UI_PREFETCH_SCENES:
		if ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(scene_path)

## 进入主菜单：优先用预载结果直接切换（无加载框）；预载未就绪则走跳过遮罩的常规切换
func _enter_main_menu() -> void:
	_drain_ui_prefetch()
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
