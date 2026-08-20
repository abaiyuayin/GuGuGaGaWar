extends Control
## 游戏结束画面
## 显示游戏结果（胜利/失败）和后续操作按钮
## 作为叠加层显示在战斗场景上方
## 显示时暂停战斗，确保 UI 响应流畅

## 结果显示标签
@onready var result_label: Label = $ResultLabel
## 进入下一关按钮（仅战役模式胜利、且非最后一关时显示）
@onready var btn_next: Button = $VBoxContainer/BtnNext
## 再来一局按钮
@onready var btn_restart: Button = $VBoxContainer/BtnRestart
## 返回地图按钮
@onready var btn_map: Button = $VBoxContainer/BtnMap
## 返回主菜单按钮
@onready var btn_menu: Button = $VBoxContainer/BtnMenu
## 本局是否来自肉鸽模式（决定「再来一局」的重开行为）
var _is_roguelike: bool = false

func _ready() -> void:
	## 设置为始终处理，确保暂停状态下按钮仍可响应
	process_mode = Node.PROCESS_MODE_ALWAYS
	## 暂停战斗，避免后台战斗消耗 CPU 导致 UI 卡顿
	get_tree().paused = true
	## 为按钮应用清晰的自定义样式
	_setup_button_style(btn_next)
	_setup_button_style(btn_restart)
	_setup_button_style(btn_map)
	_setup_button_style(btn_menu)
	## 默认隐藏，由 set_winner 按「战役 + 胜利 + 非末关」条件放开
	btn_next.visible = false
	## 首次应用本地化文本
	_apply_localization()
	## 监听设置变化信号以重新应用本地化
	SettingsManager.settings_changed.connect(_apply_localization)

## 为按钮设置清晰的 StyleBoxFlat 样式（悬停/按下有明显颜色变化）
func _setup_button_style(btn: Button) -> void:
	## 普通状态：深棕底 + 金色边框
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.15, 0.1, 0.95)
	normal.border_color = Color(0.55, 0.45, 0.25, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("disabled", normal)
	## 悬停状态：亮金棕底 + 亮金边框（明显变亮）
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.5, 0.38, 0.2, 1.0)
	hover.border_color = Color(1.0, 0.85, 0.4, 1.0)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover)
	## 按下状态：最亮底色（明显的按压反馈）
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color(0.7, 0.55, 0.3, 1.0)
	pressed.border_color = Color(1.0, 0.9, 0.5, 1.0)
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(4)
	pressed.set_content_margin_all(10)
	btn.add_theme_stylebox_override("pressed", pressed)
	## 文字颜色
	btn.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.9))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 0.85))
	btn.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6))

func _apply_localization() -> void:
	## 更新按钮文本
	btn_next.text = "进入下一关"
	btn_restart.text = tr("RESTART")
	btn_map.text = tr("RETURN_MAP")
	btn_menu.text = tr("MAIN_MENU")

## 设置获胜方的方法
## winner_team: 获胜方的阵营编号（0=红方/玩家, 1=蓝方/AI）
## stats: battle_root 采集的战绩字典（成就系统用，可不传）
## is_roguelike: 本局是否来自肉鸽模式（影响「再来一局」行为）
func set_winner(winner_team: int, stats: Dictionary = {}, is_roguelike: bool = false) -> void:
	_is_roguelike = is_roguelike
	## 仅战役模式且非肉鸽显示「返回地图」；肉鸽/双人/全面战争无地图可返回，隐藏该按钮
	btn_map.visible = GameManager.is_campaign_mode and not _is_roguelike
	## 肉鸽模式的「再来一局」语义是开启全新的一局随机 run，按钮文案改为「再来一局」
	if _is_roguelike:
		btn_restart.text = "再来一局"
	## #8：仅「战役模式 + 玩家胜利 + 当前不是最后一关」时提供「进入下一关」快捷入口，
	## 避免失败界面、肉鸽、全面战争、通关末关时出现无意义按钮
	btn_next.visible = (
		winner_team == 0
		and GameManager.is_campaign_mode
		and not _is_roguelike
		and GameManager.selected_campaign_level < CampaignProgress.MAX_LEVEL
	)
	## 玩家（红方）获胜
	if winner_team == 0:
		## 显示胜利文本
		result_label.text = tr("YOU_WIN")
		## 设置文字颜色为红色（红方主题色）
		result_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		## 战役模式下标记当前关卡的当前难度为已完成（解锁下一难度/下一关）
		## 肉鸽模式不触发战役解锁逻辑（避免误弹兵种解锁/标记完成）
		if GameManager.is_campaign_mode and not _is_roguelike:
			CampaignProgress.mark_difficulty_completed(GameManager.selected_campaign_level, GameManager.current_difficulty)
			## 首通关卡时弹出解锁兵种通知
			_show_unlock_notification(GameManager.selected_campaign_level)
		## 战斗战绩评估成就（独立系统，不发星星）
		Achievements.evaluate_battle(stats)
		## 播放胜利BGM（根据设置选择对应BGM，先停止当前战斗BGM）
		AudioManager.play_victory_bgm()
	else:
		## 蓝方（AI）获胜，显示失败文本
		result_label.text = tr("YOU_LOSE")
		## #18：失败文本改为红色，字号放大到约 10 倍（160 ≈ 16×10），强化败北反馈
		result_label.add_theme_color_override("font_color", Color(1, 0, 0, 1))
		result_label.add_theme_font_size_override("font_size", 160)

## 首通关卡时显示解锁兵种通知（延迟弹出，在结算界面显示后再出现）
func _show_unlock_notification(level: int) -> void:
	var new_unit_id: String = CampaignProgress.get_level_new_unit(level)
	if new_unit_id == "":
		return
	## 查找兵种显示名
	var display_name: String = new_unit_id
	for res in UnitDatabase.unit_list:
		if res.unit_id == new_unit_id:
			display_name = res.get_display_name()
			break
	## 创建解锁通知弹窗（延迟 0.5 秒弹出，确保结算界面先渲染）
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		var popup := Window.new()
		popup.title = "兵种解锁"
		popup.size = Vector2i(300, 180)
		popup.unresizable = true
		## 弹窗设为始终保持处理（忽略场景暂停）
		popup.process_mode = Node.PROCESS_MODE_ALWAYS
		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.add_theme_constant_override("separation", 12)
		popup.add_child(vbox)
		var title_lbl := Label.new()
		title_lbl.text = "获得新兵种！"
		title_lbl.add_theme_font_size_override("font_size", 20)
		title_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title_lbl)
		var spacer1 := Control.new()
		spacer1.custom_minimum_size = Vector2(0, 8)
		vbox.add_child(spacer1)
		var name_lbl := Label.new()
		name_lbl.text = "%s（%s）" % [display_name, new_unit_id]
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_lbl)
		var spacer2 := Control.new()
		spacer2.custom_minimum_size = Vector2(0, 8)
		vbox.add_child(spacer2)
		var desc_lbl := Label.new()
		desc_lbl.text = "已加入编成，可在后续关卡中部署"
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7, 1))
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(desc_lbl)
		var btn_ok := Button.new()
		btn_ok.text = "确定"
		btn_ok.custom_minimum_size = Vector2(80, 36)
		btn_ok.pressed.connect(popup.queue_free)
		vbox.add_child(btn_ok)
		## 居中显示在视口上
		## #2（2026-08-09）：连接 close_requested，右上角 X 才能关闭弹窗（未连接则点击无反应）
		popup.close_requested.connect(popup.queue_free)
		add_child(popup)
		popup.popup_centered(Vector2i(300, 180))
		## 播放 UI 点击音效，提示玩家注意弹窗
		AudioManager.play_ui_click()
	)

## 禁用所有按钮的输入处理，防止场景跳转延迟窗口内触发 !is_inside_tree() 报错
func _disable_all_buttons_input() -> void:
	for btn in [btn_next, btn_restart, btn_map, btn_menu]:
		if btn != null and is_instance_valid(btn):
			btn.set_process_input(false)
			btn.set_process_unhandled_input(false)
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.disabled = true

## 进入下一关按钮回调（#8）
## 直接把战役关卡号 +1 并以「本局相同难度」重新开战，跳过回地图再点一次的流程
func _on_next_level_pressed() -> void:
	_disable_all_buttons_input()  ## 先禁用按钮输入，防止跳转延迟窗口内报错
	AudioManager.play_menu_bgm()  ## 停掉胜利 BGM，战斗场景会自行切战斗 BGM
	get_tree().paused = false  ## 取消暂停，避免新场景被卡住
	## 关卡号 +1（上限保护：理论上按钮在末关已隐藏，这里再兜一次）
	GameManager.selected_campaign_level = mini(
		GameManager.selected_campaign_level + 1, CampaignProgress.MAX_LEVEL)
	## 沿用本局难度直接开打
	GameManager.start_game(GameManager.current_difficulty)

## 再来一局按钮回调
func _on_restart_pressed() -> void:
	_disable_all_buttons_input()  ## 先禁用按钮输入，防止跳转延迟窗口内报错
	## 恢复播放菜单BGM（停止胜利BGM，后续战斗场景会切换为战斗BGM）
	AudioManager.play_menu_bgm()
	## 取消暂停，避免新场景被卡住
	get_tree().paused = false
	## 肉鸽模式：重置模式标志后开启全新的一局随机 run
	if _is_roguelike:
		GameManager.is_campaign_mode = false
		BattleManager.is_two_player = false
		RoguelikeManager.start_run()
		GameManager.start_game(1)
		return
	## 使用当前难度重新开始游戏
	GameManager.start_game(GameManager.current_difficulty)

## 返回地图按钮回调（返回战役地图）
func _on_map_pressed() -> void:
	_disable_all_buttons_input()  ## 先禁用按钮输入，防止跳转延迟窗口内报错
	## 恢复播放菜单BGM（停止胜利BGM）
	AudioManager.play_menu_bgm()
	## 取消暂停
	get_tree().paused = false
	## 返回战役地图（带加载遮罩）
	GameManager.change_scene_with_loading("res://scenes/ui/campaign_map.tscn")

## 返回主菜单按钮回调
func _on_menu_pressed() -> void:
	_disable_all_buttons_input()  ## 先禁用按钮输入，防止跳转延迟窗口内报错
	## 恢复播放菜单BGM（停止胜利BGM，主菜单场景会按设置续播）
	AudioManager.play_menu_bgm()
	## 取消暂停
	get_tree().paused = false
	## 始终返回主菜单
	GameManager.return_to_menu()
