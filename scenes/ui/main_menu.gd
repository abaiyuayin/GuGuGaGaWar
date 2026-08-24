extends Control
## 主菜单脚本
## 管理主菜单界面的按钮交互、本地化、设置弹窗与难度选择

## 开始游戏（战役模式）按钮
@onready var btn_campaign: TextureButton = $MenuPanel/BtnCampaign
## 全面战争（单人模式）按钮
@onready var btn_single: TextureButton = $MenuPanel/BtnSinglePlayer
## 双人游戏按钮
@onready var btn_multi: TextureButton = $MenuPanel/BtnMultiplayer
## 游戏图鉴按钮
@onready var btn_guide: TextureButton = $MenuPanel/BtnGuide
## 游戏设置按钮
@onready var btn_settings: TextureButton = $MenuPanel/BtnSettings
## 退出游戏按钮
@onready var btn_quit: TextureButton = $MenuPanel/BtnQuit
## 调试按钮（兵种尺寸调整）
@onready var btn_debug: Button = $MenuPanel/BtnDebug
## 战场模式按钮（RTS 沙盒）
@onready var btn_battlefield: Button = $MenuPanel/BtnBattlefield
## B站原作者图标按钮（右下角，点击调用系统浏览器打开原作者空间）
@onready var btn_bili: TextureButton = $BiliCredit/BtnBili
## QQ群图标按钮（右下角，B站图标左侧）
@onready var btn_qq: TextureButton = $QQCredit/BtnQQ
@onready var qq_label: Label = $QQCredit/QQLabel
## GitHub 开源图标按钮（右下角，B站与QQ群之间）
@onready var btn_github: TextureButton = $GitHubCredit/BtnGitHub
@onready var github_label: Label = $GitHubCredit/GitHubLabel

## 原作者 B 站空间链接（阿白与阿银）
const BILI_SPACE_URL: String = "https://space.bilibili.com/382838394"
## QQ群信息
const QQ_GROUP_NUMBER: String = "939936934"
const QQ_GROUP_URL: String = "https://qm.qq.com/q/H0BklLFTEK"
## GitHub 开源仓库链接
const GITHUB_URL: String = "https://github.com/abaiyuayin/GuGuGaGaWar"

## 当前打开的设置对话框引用
var _settings_dialog: AcceptDialog = null
## 设置对话框框内标题 Label（窗口标题栏已隐藏，标题改在框内呈现，需随语言刷新）
var _settings_title_label: Label = null
## 设置对话框中需要动态更新的标签数组
var _settings_labels: Array[Label] = []
## 设置对话框中需要动态更新的按钮数组
var _settings_buttons: Array[Button] = []

func _ready() -> void:
	## 首次应用本地化文本
	_apply_localization()
	## 监听设置变化信号以重新应用本地化
	SettingsManager.settings_changed.connect(_apply_localization)
	## 为所有图片按钮添加悬停/按下视觉反馈
	_setup_button_hover()
	## 播放主菜单背景音乐（根据设置选择默认或自定义BGM）
	AudioManager.play_menu_bgm()
	## #新需求：控制台/调试入口仅开发者模式可见——初始化显隐并监听切换
	DevMode.dev_mode_changed.connect(_apply_dev_gating)
	_apply_dev_gating()

## #新需求：开发者专属入口仅 DevMode 可见（主菜单「控制台」「竞技场模式」按钮）
## 非开发者模式隐藏按钮，开启开发者模式后恢复显示。
## #竞技场（2026-08-21 用户拍板）：竞技场是无胜负的 RTS 沙盒，定位为开发/调试用，
## 故与控制台同列为开发者专属入口。入口全项目仅此一处（BtnBattlefield），
## 因此隐藏此按钮即等于普通玩家无法进入竞技场模式。
func _apply_dev_gating(_on: bool = false) -> void:
	btn_debug.visible = DevMode.enabled
	btn_battlefield.visible = DevMode.enabled

## 开发者模式专属快捷键：F12 切换「局内」上方按钮整排（游戏帮助/游戏设置/调整/退出/开发工具）显隐
## 仅开发者模式下生效；切换的是全局标志 DevMode.hide_in_battle_top_buttons，因此主菜单按 F12 也能预隐藏，
## 进入战斗后自动套用——主菜单自身的按钮（战役/单人/多人/攻略/设置/退出/控制台）不受任何影响（F11 已禁用）
func _unhandled_input(event: InputEvent) -> void:
	if not DevMode.enabled:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F12:
		DevMode.hide_in_battle_top_buttons = not DevMode.hide_in_battle_top_buttons
		_show_toast("局内按钮栏：%s" % ("隐藏" if DevMode.hide_in_battle_top_buttons else "显示"))

func _apply_localization() -> void:
	## 标题使用图片，无需设置文本
	## 同步更新设置对话框本地化
	_update_settings_dialog_localization()

## 翻译回退：若翻译键缺失则使用中文兜底文本
func _tr_or_fallback(key: String, fallback: String) -> String:
	## 尝试获取翻译
	var txt := tr(key)
	## 翻译结果与键名相同说明缺失，返回兜底文本
	return txt if txt != key else fallback

## 开始游戏按钮回调：进入战役地图
func _on_btn_campaign_pressed() -> void:
	## 标记为战役模式
	GameManager.is_campaign_mode = true
	## 关闭双人模式
	BattleManager.is_two_player = false
	## 切换到战役地图场景（带加载遮罩）
	GameManager.change_scene_with_loading("res://scenes/ui/campaign_map.tscn")

## 全面战争按钮回调：弹出难度选择
func _on_btn_single_player_pressed() -> void:
	## 关闭战役模式
	GameManager.is_campaign_mode = false
	## 关闭双人模式
	BattleManager.is_two_player = false
	## 显示难度选择弹窗
	_show_difficulty_dialog()

## 双人游戏按钮回调：直接开始双人对战
func _on_btn_multiplayer_pressed() -> void:
	## 关闭战役模式
	GameManager.is_campaign_mode = false
	## 开启双人模式
	BattleManager.is_two_player = true
	## 以普通难度开始游戏
	GameManager.start_game(1)

## 游戏图鉴按钮回调：打开图鉴界面
func _on_btn_guide_pressed() -> void:
	GameManager.change_scene_with_loading("res://scenes/ui/codex_screen.tscn")

## 游戏设置按钮回调：弹出设置对话框
func _on_btn_settings_pressed() -> void:
	_show_settings_dialog()

## 退出游戏按钮回调：弹二次确认框，确认后退出游戏
## 风格统一为兵种详情框同款米色描边框（与局内退出确认框一致），压掉 Godot 默认黑框/标题栏/关闭图标
func _on_btn_quit_pressed() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.title = ""  ## 隐藏 Godot 默认标题栏
	confirm.dialog_text = ""  ## 隐藏 Godot 默认正文区
	confirm.ok_button_text = tr("CONFIRM")
	confirm.get_cancel_button().text = tr("CANCEL")
	confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	UIButtonHelper.setup_detail_frame_dialog(confirm)
	add_child(confirm)
	confirm.popup_centered()
	## 在对话框弹出后，在内部构建上下两级结构（标题在上、正文在下）
	var exit_vbox := VBoxContainer.new()
	exit_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	exit_vbox.add_theme_constant_override("separation", 8)
	exit_vbox.add_theme_constant_override("margin_top", 20)
	exit_vbox.add_theme_constant_override("margin_bottom", 20)
	exit_vbox.add_theme_constant_override("margin_left", 20)
	exit_vbox.add_theme_constant_override("margin_right", 20)
	var exit_title := UIButtonHelper.make_detail_frame_title(tr("TIP_TITLE"))
	exit_vbox.add_child(exit_title)
	var exit_text := Label.new()
	exit_text.text = tr("QUIT_CONFIRM")
	exit_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	exit_text.custom_minimum_size = Vector2(240, 0)
	exit_text.add_theme_font_size_override("font_size", 14)
	exit_text.add_theme_color_override("font_color", Color(0.30, 0.22, 0.12, 1.0))
	exit_vbox.add_child(exit_text)
	confirm.add_child(exit_vbox)
	confirm.confirmed.connect(get_tree().quit)
	confirm.canceled.connect(confirm.queue_free)
	confirm.close_requested.connect(confirm.queue_free)

## 调试按钮回调：进入兵种尺寸调试界面
func _on_btn_debug_pressed() -> void:
	GameManager.change_scene_with_loading("res://scenes/ui/debug_units.tscn")

## 战场模式按钮回调：进入 RTS 沙盒场景
func _on_btn_battlefield_pressed() -> void:
	GameManager.start_battlefield()

## B站原作者图标回调：调用系统浏览器打开原作者空间
func _on_btn_bili_pressed() -> void:
	AudioManager.play_ui_click()
	OS.shell_open(BILI_SPACE_URL)

## QQ群图标按钮回调：复制群号到剪贴板 + 打开加群链接
func _on_btn_qq_pressed() -> void:
	AudioManager.play_ui_click()
	DisplayServer.clipboard_set(QQ_GROUP_NUMBER)
	OS.shell_open(QQ_GROUP_URL)
	_show_toast("已复制QQ群号码")

## GitHub 图标按钮回调：复制仓库链接到剪贴板 + 调用系统浏览器打开
func _on_btn_github_pressed() -> void:
	AudioManager.play_ui_click()
	DisplayServer.clipboard_set(GITHUB_URL)
	OS.shell_open(GITHUB_URL)
	_show_toast("已复制GitHub开源链接")

## GitHub 标签点击回调：点击"游戏已经开源"文本同样触发复制+打开
func _on_github_label_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_btn_github_pressed()

## 显示难度选择弹窗
func _show_difficulty_dialog() -> void:
	## 创建对话框
	var dialog = AcceptDialog.new()
	dialog.title = tr("SELECT_DIFFICULTY")
	dialog.dialog_text = ""
	dialog.ok_button_text = tr("CANCEL")
	add_child(dialog)

	## 创建垂直容器放置难度按钮
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(200, 0)
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)

	## 定义三个难度选项
	var difficulties = [
		{"text": tr("DIFFICULTY_EASY"), "diff": 0},
		{"text": tr("DIFFICULTY_NORMAL"), "diff": 1},
		{"text": tr("DIFFICULTY_HARD"), "diff": 2},
	]

	## 遍历难度列表创建按钮
	for diff in difficulties:
		var btn = Button.new()
		btn.text = diff.text
		btn.custom_minimum_size = Vector2(180, 40)
		UIButtonHelper.setup_button(btn)
		## #5：悬停显示当前难度介绍
		match diff.diff:
			0: btn.tooltip_text = "简单：AI 每 2 秒随机出兵，不分析克制、不运营，新手友好"
			1: btn.tooltip_text = "普通：AI 每 1 秒出兵，70% 克制你的常用兵种、30% 选性价比最优"
			2: btn.tooltip_text = "困难：AI 每 0.8 秒出兵，多层决策树按战场态势动态调兵，硬核挑战"
			_: btn.tooltip_text = ""
		## 点击后关闭弹窗并以对应难度开始游戏
		btn.pressed.connect(func():
			## 先禁用对话框内所有按钮的输入处理，防止 queue_free 延迟窗口内报错
			for b in vbox.get_children():
				if is_instance_valid(b) and b is Button:
					b.set_process_input(false)
					b.set_process_unhandled_input(false)
					b.mouse_filter = Control.MOUSE_FILTER_IGNORE
					b.disabled = true
			dialog.queue_free()
			GameManager.start_game(diff.diff)
		)
		vbox.add_child(btn)

	## 居中弹出对话框
	dialog.popup_centered()

## 显示未实现功能提示弹窗
func _show_not_implemented_dialog(feature: String) -> void:
	var dlg = AcceptDialog.new()
	dlg.title = tr("TIP_TITLE")
	dlg.dialog_text = tr("NOT_IMPLEMENTED") % feature
	dlg.ok_button_text = tr("CONFIRM")
	add_child(dlg)
	dlg.popup_centered()

## 显示设置对话框（窗口/语言/音频/战斗/BGM，单页可滚动）
func _show_settings_dialog() -> void:
	## 若设置对话框已存在则直接弹出
	if _settings_dialog != null and is_instance_valid(_settings_dialog):
		_settings_dialog.popup_centered()
		return

	## 创建新的设置对话框
	_settings_dialog = AcceptDialog.new()
	_settings_dialog.title = tr("SETTINGS_TITLE")
	_settings_dialog.dialog_text = ""
	_settings_dialog.ok_button_text = tr("CLOSE")
	## #19（2026-08-11）：关闭按钮放大 2 倍（标题栏 X 为系统绘制无法缩放，放大底部「关闭」按钮）
	var ok_btn: Button = _settings_dialog.get_ok_button()
	if ok_btn:
		ok_btn.custom_minimum_size = Vector2(180, 56)
	_settings_dialog.confirmed.connect(_on_settings_dialog_closed)
	_settings_dialog.canceled.connect(_on_settings_dialog_closed)
	## 2026-08-22：弹框风格彻底统一为「长按兵种按钮 → 兵种详情框」同款
	## Dialog 继承自 Window，那圈黑框来自 Window 的 embedded_border 而非 panel，
	## 故用 setup_detail_frame_dialog 一并压掉边框/标题栏/关闭图标，标题改在框内以 Label 呈现。
	UIButtonHelper.setup_detail_frame_dialog(_settings_dialog)
	## 对话框最小尺寸 450x600，内容超出可滚动
	_settings_dialog.min_size = Vector2i(450, 600)
	add_child(_settings_dialog)

	## 清空动态控件引用数组（设置项由统一组件内部自管理）
	_settings_labels.clear()
	_settings_buttons.clear()

	## 框内标题（窗口标题栏已隐藏，标题在此呈现；与详情框首行同款深棕大字）
	_settings_title_label = UIButtonHelper.make_detail_frame_title(tr("SETTINGS_TITLE"))
	_settings_dialog.add_child(_settings_title_label)

	## 创建滚动容器包裹唯一设置面板组件（全部设置项统一由 SettingsPanel 提供）
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(430, 520)
	_settings_dialog.add_child(scroll)
	## 弹框本身已是详情框同款米色底，面板内不再叠羊皮纸纹理，否则会盖掉底色
	var panel := SettingsPanel.new()
	panel.show_parchment_bg = false
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)

	## 居中弹出设置对话框
	_settings_dialog.popup_centered()

## 设置对话框关闭回调：释放资源
func _on_settings_dialog_closed() -> void:
	if _settings_dialog != null and is_instance_valid(_settings_dialog):
		_settings_dialog.queue_free()
	_settings_dialog = null
	_settings_title_label = null
	_settings_labels.clear()
	_settings_buttons.clear()

## 更新设置对话框的本地化文本
func _update_settings_dialog_localization() -> void:
	## 对话框不存在则直接返回
	if _settings_dialog == null or not is_instance_valid(_settings_dialog):
		return
	## 更新标题和关闭按钮
	_settings_dialog.title = tr("SETTINGS_TITLE")
	_settings_dialog.ok_button_text = tr("CLOSE")
	## 标题栏已隐藏，框内标题 Label 需同步刷新
	if _settings_title_label != null and is_instance_valid(_settings_title_label):
		_settings_title_label.text = tr("SETTINGS_TITLE")
	## 更新动态标签文本（基于元数据中的翻译键）
	for lbl in _settings_labels:
		if is_instance_valid(lbl) and lbl.has_meta("tr_key"):
			_apply_label_text(lbl)
	## 更新动态按钮文本
	for btn in _settings_buttons:
		if is_instance_valid(btn):
			match btn.text:
				"窗口模式", "Windowed":
					btn.text = tr("WINDOWED")
				"全屏模式", "Fullscreen":
					btn.text = tr("FULLSCREEN")
				"无边框窗口", "Borderless":
					btn.text = tr("BORDERLESS")
				"简体中文", "Simplified Chinese":
					btn.text = tr("SIMPLIFIED_CHINESE")
				"English", "English":
					btn.text = tr("ENGLISH")

## 创建分区标题标签（带本地化元数据，居中金色显示）
func _create_section_label(key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_meta("tr_key", key)
	lbl.set_meta("tr_fallback", fallback)
	lbl.set_meta("is_separator", true)
	_apply_label_text(lbl)
	_settings_labels.append(lbl)
	return lbl

## 创建普通本地化标签（带本地化元数据）
func _create_localized_label(key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.set_meta("tr_key", key)
	lbl.set_meta("tr_fallback", fallback)
	_apply_label_text(lbl)
	_settings_labels.append(lbl)
	return lbl

## 根据元数据应用标签文本（翻译键缺失时使用兜底文本，分隔标签加"—— "前后缀）
func _apply_label_text(lbl: Label) -> void:
	var key: String = lbl.get_meta("tr_key")
	var fallback: String = lbl.get_meta("tr_fallback")
	var txt: String = tr(key)
	## 翻译结果与键名相同说明缺失，使用兜底文本
	if txt == key:
		txt = fallback
	## 分隔标签加上前后缀
	if lbl.has_meta("is_separator") and lbl.get_meta("is_separator"):
		txt = "—— " + txt + " ——"
	lbl.text = txt

## 在 OptionButton 中选中与 value 匹配的项，未匹配则选中 fallback_idx
func _select_option_by_value(opt: OptionButton, value: String, fallback_idx: int = 0) -> void:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == value:
			opt.select(i)
			return
	opt.select(fallback_idx)

## 更新窗口模式按钮的选中状态颜色
func _update_window_button_state(buttons: Array) -> void:
	## 获取当前窗口模式
	var mode = SettingsManager.window_mode
	## 当前模式对应按钮显示绿色，其余正常色
	buttons[0].modulate = Color(1, 1, 1) if mode != SettingsManager.WINDOW_MODE_WINDOWED else Color(0.5, 1, 0.5)
	buttons[1].modulate = Color(1, 1, 1) if mode != SettingsManager.WINDOW_MODE_FULLSCREEN else Color(0.5, 1, 0.5)
	buttons[2].modulate = Color(1, 1, 1) if mode != SettingsManager.WINDOW_MODE_BORDERLESS else Color(0.5, 1, 0.5)

## 更新语言按钮的选中状态颜色
func _update_lang_button_state(buttons: Array) -> void:
	## 获取当前语言
	var lang = SettingsManager.language
	## 当前语言对应按钮显示绿色，其余正常色（按按钮 meta 中的 locale 码匹配）
	for btn in buttons:
		var code: String = String(btn.get_meta("lang", ""))
		btn.modulate = Color(0.5, 1, 0.5) if lang == code else Color(1, 1, 1)

## 语言按钮按下：切换语言并刷新全部本地化与高亮
func _on_lang_button_pressed(btn: Button, lang_buttons: Array) -> void:
	var code: String = String(btn.get_meta("lang", ""))
	SettingsManager.set_language(code)
	_update_lang_button_state(lang_buttons)
	_apply_localization()

## 为所有按钮添加悬停变亮、按下变暗的视觉反馈与点击音效
func _setup_button_hover() -> void:
	var buttons: Array[TextureButton] = [btn_campaign, btn_single, btn_multi, btn_guide, btn_settings, btn_quit]
	for btn in buttons:
		## 悬停变亮
		btn.mouse_entered.connect(func(): btn.modulate = Color(1.25, 1.25, 1.25, 1.0))
		btn.mouse_exited.connect(func(): btn.modulate = Color(1.0, 1.0, 1.0, 1.0))
		## 按下变暗 + 点击音效，松开恢复悬停亮度（鼠标仍在按钮上）
		btn.button_down.connect(func():
			btn.modulate = Color(0.75, 0.75, 0.75, 1.0)
			AudioManager.play_ui_click())
		btn.button_up.connect(func(): btn.modulate = Color(1.25, 1.25, 1.25, 1.0))
	## 调试按钮同样添加悬停/按下反馈与点击音效
	btn_debug.mouse_entered.connect(func(): btn_debug.modulate = Color(1.25, 1.25, 1.25, 1.0))
	btn_debug.mouse_exited.connect(func(): btn_debug.modulate = Color(1.0, 1.0, 1.0, 1.0))
	btn_debug.button_down.connect(func():
		btn_debug.modulate = Color(0.75, 0.75, 0.75, 1.0)
		AudioManager.play_ui_click())
	btn_debug.button_up.connect(func(): btn_debug.modulate = Color(1.25, 1.25, 1.25, 1.0))
	## 战场模式按钮（普通 Button，同 BtnDebug 样式）：悬停/按下反馈 + 点击音效
	btn_battlefield.mouse_entered.connect(func(): btn_battlefield.modulate = Color(1.25, 1.25, 1.25, 1.0))
	btn_battlefield.mouse_exited.connect(func(): btn_battlefield.modulate = Color(1.0, 1.0, 1.0, 1.0))
	btn_battlefield.button_down.connect(func():
		btn_battlefield.modulate = Color(0.75, 0.75, 0.75, 1.0)
		AudioManager.play_ui_click())
	btn_battlefield.button_up.connect(func(): btn_battlefield.modulate = Color(1.25, 1.25, 1.25, 1.0))
	## B站原作者图标：悬停变亮 + 指针变手型（与 QQ/GitHub 一致，仅颜色变化不放大）
	btn_bili.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_bili.mouse_entered.connect(func(): btn_bili.modulate = Color(1.3, 1.3, 1.3, 1.0))
	btn_bili.mouse_exited.connect(func(): btn_bili.modulate = Color(1.0, 1.0, 1.0, 1.0))
	btn_bili.button_down.connect(func(): btn_bili.modulate = Color(0.75, 0.75, 0.75, 1.0))
	btn_bili.button_up.connect(func(): btn_bili.modulate = Color(1.3, 1.3, 1.3, 1.0))
	## QQ群图标：悬停变亮 + 指针变手型（与 B站/GitHub 一致，仅颜色变化不放大），标签显示群号
	btn_qq.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_qq.mouse_entered.connect(func():
		btn_qq.modulate = Color(1.3, 1.3, 1.3, 1.0)
		qq_label.text = QQ_GROUP_NUMBER)
	btn_qq.mouse_exited.connect(func():
		btn_qq.modulate = Color(1.0, 1.0, 1.0, 1.0)
		qq_label.text = "官方QQ群")
	btn_qq.button_down.connect(func(): btn_qq.modulate = Color(0.75, 0.75, 0.75, 1.0))
	btn_qq.button_up.connect(func(): btn_qq.modulate = Color(1.3, 1.3, 1.3, 1.0))
	## GitHub 开源图标：悬停变亮 + 指针变手型（与 B站/QQ群 一致，仅颜色变化不放大）
	btn_github.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_github.mouse_entered.connect(func(): btn_github.modulate = Color(1.3, 1.3, 1.3, 1.0))
	btn_github.mouse_exited.connect(func(): btn_github.modulate = Color(1.0, 1.0, 1.0, 1.0))
	btn_github.button_down.connect(func(): btn_github.modulate = Color(0.75, 0.75, 0.75, 1.0))
	btn_github.button_up.connect(func(): btn_github.modulate = Color(1.3, 1.3, 1.3, 1.0))
	## 点击下方"游戏已经开源"文本同样触发
	github_label.gui_input.connect(_on_github_label_clicked)

## 简单 toast 提示（底部居中，2 秒自动消失）
func _show_toast(msg: String) -> void:
	var label := Label.new()
	label.text = msg
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 1))
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 1.0
	label.offset_left = -200
	label.offset_top = -80
	label.offset_right = 200
	label.offset_bottom = -40
	add_child(label)
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(label, "modulate:a", 0.0, 0.5)
	t.tween_callback(label.queue_free)
