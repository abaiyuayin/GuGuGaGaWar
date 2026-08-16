class_name RoguelikeVictoryScreen
extends Control
## 肉鸽模式整局通关（击败 Boss）后的专属胜利界面（国风羊皮纸风）。
## 由 roguelike_director 在 Boss 节点通关奖励选定后弹出。
## 仅做「通关庆祝 + 再来一局 / 返回主菜单」两枚按钮；战利品三选一已在通关奖励界面发放，不在此重复。

## 场景切换防重入：按钮按下进入跳转后屏蔽再次触发
var _transitioning: bool = false

func _ready() -> void:
	## 始终处理，确保战场暂停状态下按钮仍可响应
	process_mode = Node.PROCESS_MODE_ALWAYS
	## #9（2026-08-11）：胜利 BGM 改为延迟一帧触发（不依赖 UI 构建顺序），
	## 播放后校验状态，未起播则 0.3s 后重播一次 —— 兜底「暂停树时序/UI 异常导致静音」。
	## 树在奖励界面阶段已暂停，_music_player 为 ALWAYS 不受影响；stream_paused 已在播放器层复位。
	call_deferred("_play_victory_bgm_guarded")
	_build_ui()

## #9：播放胜利 BGM 并做播放状态校验（首次失败延迟重试一次）
func _play_victory_bgm_guarded() -> void:
	AudioManager.play_victory_bgm()
	await get_tree().create_timer(0.3).timeout
	if AudioManager.is_music_playing():
		return
	AudioManager.play_victory_bgm()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.86, 0.70, 1.0)
	style.border_color = Color(0.35, 0.25, 0.13, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "通关胜利！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.45, 0.12, 0.08, 1.0))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "你击败了最终 Boss，肉鸽征程圆满收官。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.30, 0.22, 0.12, 1.0))
	vbox.add_child(sub)

	var btn_restart := Button.new()
	btn_restart.text = "再来一局"
	btn_restart.custom_minimum_size = Vector2(200, 48)
	_setup_button_style(btn_restart)
	btn_restart.pressed.connect(_on_restart_pressed)
	vbox.add_child(btn_restart)

	var btn_menu := Button.new()
	btn_menu.text = "返回主菜单"
	btn_menu.custom_minimum_size = Vector2(200, 48)
	_setup_button_style(btn_menu)
	btn_menu.pressed.connect(_on_menu_pressed)
	vbox.add_child(btn_menu)

	## Boss 通关时战场已被奖励界面冻结（paused）；保持暂停，仅本界面按钮可响应
	get_tree().paused = true
	AudioManager.play_victory_bgm()

## 羊皮纸风按钮样式（深棕底 + 金棕边框，悬停/按下明显变亮）
func _setup_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.55, 0.40, 0.20, 1.0)
	normal.border_color = Color(0.30, 0.20, 0.10, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("disabled", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.75, 0.55, 0.25, 1.0)
	hover.border_color = Color(0.95, 0.80, 0.40, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.90, 0.70, 0.35, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9, 1.0))

func _on_restart_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().paused = false
	GameManager.is_campaign_mode = false
	BattleManager.is_two_player = false
	RoguelikeManager.end_run()
	RoguelikeManager.start_run(RoguelikeManager.selected_hero)
	GameManager.enter_roguelike_map()

func _on_menu_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().paused = false
	RoguelikeManager.end_run()
	AudioManager.play_menu_bgm()
	GameManager.return_to_menu()
