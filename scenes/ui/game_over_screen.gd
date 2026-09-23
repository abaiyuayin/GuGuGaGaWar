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

## 标题外壳（普通 Control，**不是容器**）：容器会强制子节点铺满并居中，
## 只有非容器父级才能让标题靠 anchors + offset 做「墨迹居中」补偿，
## 见 _apply_title_ink_centering()
var _title_holder: Control = null

## 全角「！」(U+FF01) 在项目主字体（猫啃忘形圆）里占满 1em 字宽（font_size 72 时 = 58px），
## 但墨迹只有约 0.14em 且紧贴字框左侧，右侧残留约 0.51em 空白
## （font_size 72 实测：左留白 4px、右留白 37px）。
## Label 的 CENTER 对齐只保证「字串字宽 advance 居中」，于是整块墨迹视觉左偏半格。
## 本常量 = (右留白 - 左留白) / 2 / 字号 = 16.5 / 72，用于把标题右移回正中。
## 换主字体后需按同法重测：渲染「你赢了！」后量墨迹左右边距。
const FULLWIDTH_BANG: String = "！"
const TITLE_INK_SHIFT_RATIO: float = 0.2292

func _ready() -> void:
	## 设置为始终处理，确保暂停状态下按钮仍可响应
	process_mode = Node.PROCESS_MODE_ALWAYS
	## 暂停战斗，避免后台战斗消耗 CPU 导致 UI 卡顿
	get_tree().paused = true
	_setup_parchment_frame()
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

## 为中央结算区域铺设与图二同款的米色描边面板，并将按钮样式统一为棕金风
func _setup_parchment_frame() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.86, 0.70, 1.0)
	style.border_color = Color(0.35, 0.25, 0.13, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := $VBoxContainer
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	## ⚠️ Godot 4 的 add_child() 不会自动从旧父级摘除节点（会报 "already has a parent" 且后续语句照跑），
	## 把 .tscn 里已有的节点收进面板必须用 reparent()。此前用 add_child 导致面板一个子节点都挂不上，
	## 只剩「最小宽 560 + 内边距 56」的空壳渲染在屏幕正中。
	## 标题先装进一个普通 Control 外壳（非容器）：容器会把子节点强制铺满 / 居中，
	## 只有非容器父级才能靠 anchors + offset 做墨迹居中补偿（_apply_title_ink_centering）。
	_title_holder = Control.new()
	_title_holder.name = "TitleHolder"
	_title_holder.custom_minimum_size = Vector2(0, 96)
	_title_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.reparent(_title_holder)
	result_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_title_holder)
	vbox.move_child(_title_holder, 0)
	vbox.reparent(panel)
	center.add_child(panel)
	add_child(center)
	move_child(center, 1)


## 让标题按「墨迹」而不是「字宽」居中
## 中文标题（你赢了！/ 你输了！）以全角「！」结尾，该字形右侧自带约半格空白，
## 只靠 Label 的 CENTER 对齐会让整块字视觉左偏；这里把标题框右移半个空白差补偿。
## 其它语言（You Win! / You Lose! 等）用半角「!」，左右留白本来就对称，不做补偿。
## 注：必须在字号确定之后调用 —— _setup_parchment_frame() 执行时字号还是主题默认值。
func _apply_title_ink_centering() -> void:
	if _title_holder == null or not is_instance_valid(_title_holder):
		return
	var shift: float = 0.0
	if result_label.text.ends_with(FULLWIDTH_BANG):
		shift = TITLE_INK_SHIFT_RATIO * float(result_label.get_theme_font_size("font_size"))
	## anchors 为 FULL_RECT 时，左右 offset 同量平移即可把整块字右移 shift
	result_label.offset_left = shift
	result_label.offset_right = shift


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
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 0.85, 1.0))

func _apply_localization() -> void:
	## 更新按钮文本
	btn_next.text = "进入下一关"
	btn_restart.text = tr("RESTART")
	btn_map.text = tr("RETURN_MAP")
	btn_menu.text = tr("MAIN_MENU")

## 设置获胜方的方法
## winner_team: 获胜方的阵营编号（0=红方/玩家, 1=蓝方/AI）
## stats: battle_root 采集的战绩字典（成就系统用，可不传）
## 注：肉鸽模式有专属胜利 / 失败界面（RoguelikeVictoryScreen / RoguelikeDefeatScreen），
##     不会走到本界面，故此处不再保留肉鸽分支。
func set_winner(winner_team: int, stats: Dictionary = {}) -> void:
	## 仅战役模式显示「返回地图」；双人/全面战争无地图可返回，隐藏该按钮
	btn_map.visible = GameManager.is_campaign_mode
	## #8：仅「战役模式 + 玩家胜利 + 当前不是最后一关」时提供「进入下一关」快捷入口
	btn_next.visible = (
		winner_team == 0
		and GameManager.is_campaign_mode
		and GameManager.selected_campaign_level < CampaignProgress.MAX_LEVEL
	)
	## 玩家（红方）获胜
	if winner_team == 0:
		## 显示胜利文本
		result_label.text = tr("YOU_WIN")
		result_label.add_theme_font_size_override("font_size", 72)
		## 羊皮卷纸风格标题色（深红棕）
		result_label.add_theme_color_override("font_color", Color(0.45, 0.12, 0.08))
		## 战役模式下标记当前关卡的当前难度为已完成（解锁下一难度/下一关）
		if GameManager.is_campaign_mode:
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
		## #18：失败文本保持大字号；标题色与羊皮卷纸风格统一
		result_label.add_theme_color_override("font_color", Color(0.45, 0.12, 0.08))
		result_label.add_theme_font_size_override("font_size", 72)

	## 文本与字号都定下来之后再补偿墨迹居中（见 _apply_title_ink_centering）
	_apply_title_ink_centering()

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
	## 延迟 0.5 秒弹共享解锁框，确保结算界面先渲染；样式与奔跑动画由共享实现维护
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		UIButtonHelper.show_unit_unlock_popup(self, display_name, new_unit_id)
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
