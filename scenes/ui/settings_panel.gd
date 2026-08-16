class_name SettingsPanel
extends Control
## 全局设置面板 —— 游戏内**唯一**的设置 UI 组件。
##
## 开始菜单设置对话框与局内设置对话框都内嵌本组件，保证两处设置项完全一致、
## 不再有两套各自维护的设置代码。数据统一读写 SettingsManager（单一权威数据源），
## 并监听 settings_changed 信号即时刷新所有控件：
## 任意界面（主菜单 / 局内 / 随机BGM 等）修改设置，其余已打开的面板立即同步显示。
##
## 包含全部设置项：窗口模式 / 语言(8) / 主·音乐·音效音量 / 伤害数字开关 / BGM 三路 + 随机。

## 主题/战斗 BGM 可选列表（"默认" 表示跟随配置回退）
const BGM_OPTIONS: Array[String] = ["默认", "Medieval Vol.2", "Falling Apart", "Decisive Battle", "The Calm Before The Storm"]
## 胜利 BGM 可选列表
const VICTORY_OPTIONS: Array[String] = ["无", "Victory!"]
## 语言定义：(locale 码, 显示名)。韩/日/泰/法/意暂无独立翻译文本，
## 由 TranslationServer 的 locale 回退机制兜底（en→源码英文，其余→源码中文）。
## #9（2026-08-09）：删除「美式英语/英式英语」两个条目，统一为「英语」。
const LANG_DEFS: Array[Dictionary] = [
	{"code": "zh", "label": "简体中文"},
	{"code": "en", "label": "英语"},
	{"code": "ko", "label": "한국어 韩语"},
	{"code": "ja", "label": "日本語 日语"},
	{"code": "th", "label": "ไทย 泰语"},
	{"code": "fr", "label": "Français 法语"},
	{"code": "it", "label": "Italiano 意大利语"},
]

## 窗口模式按钮（meta: mode / tr_key）
var _window_buttons: Array[Button] = []
## 语言按钮（meta: lang）
var _lang_buttons: Array[Button] = []
## 三条音量滑条
var _slider_master: HSlider = null
var _slider_music: HSlider = null
var _slider_sfx: HSlider = null
## 伤害数字开关
var _damage_toggle: CheckButton = null
## #16：血条数值显示开关
var _hp_armor_toggle: CheckButton = null
## #4：音频节流开关
var _audio_throttle_toggle: CheckButton = null
## 三个 BGM 下拉框
var _opt_menu_bgm: OptionButton = null
var _opt_battle_bgm: OptionButton = null
var _opt_victory_bgm: OptionButton = null
## 需要按翻译键刷新的文本控件（meta: tr_key / tr_fallback）
var _text_labels: Array[Label] = []

func _ready() -> void:
	## 任何设置修改（无论来自哪个界面）都即时刷新本面板
	SettingsManager.settings_changed.connect(_refresh_all)
	_build_ui()
	_refresh_all()

func _exit_tree() -> void:
	## 断开信号，避免残留连接指向已释放节点
	if SettingsManager.settings_changed.is_connected(_refresh_all):
		SettingsManager.settings_changed.disconnect(_refresh_all)

# ---------- UI 构建 ----------

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	## —— 窗口模式 ——
	vbox.add_child(_make_section("WINDOW_SETTINGS", "窗口设置"))
	var win_grid := GridContainer.new()
	win_grid.columns = 3
	win_grid.add_theme_constant_override("h_separation", 8)
	vbox.add_child(win_grid)
	var win_defs: Array[Dictionary] = [
		{"mode": SettingsManager.WINDOW_MODE_WINDOWED, "key": "WINDOWED", "fallback": "窗口模式"},
		{"mode": SettingsManager.WINDOW_MODE_FULLSCREEN, "key": "FULLSCREEN", "fallback": "全屏模式"},
		{"mode": SettingsManager.WINDOW_MODE_BORDERLESS, "key": "BORDERLESS", "fallback": "无边框窗口"},
	]
	for def in win_defs:
		var btn := _make_button(tr(def["key"]) if tr(def["key"]) != def["key"] else def["fallback"])
		btn.set_meta("mode", int(def["mode"]))
		btn.set_meta("tr_key", def["key"])
		btn.set_meta("tr_fallback", def["fallback"])
		btn.pressed.connect(_on_window_pressed.bind(btn))
		win_grid.add_child(btn)
		_window_buttons.append(btn)

	## —— 语言 ——
	vbox.add_child(_make_section("LANGUAGE_SETTINGS", "语言设置"))
	var lang_grid := GridContainer.new()
	lang_grid.columns = 4  ## #20（2026-08-11）：两行四列（8 格），7 项语言留 1 空位
	lang_grid.add_theme_constant_override("h_separation", 8)
	vbox.add_child(lang_grid)
	for def in LANG_DEFS:
		var lang_btn := Button.new()
		lang_btn.text = def["label"]
		lang_btn.set_meta("lang", def["code"])
		UIButtonHelper.setup_button(lang_btn)
		lang_btn.pressed.connect(_on_lang_pressed.bind(lang_btn))
		lang_grid.add_child(lang_btn)
		_lang_buttons.append(lang_btn)

	## —— 音频 ——
	vbox.add_child(_make_section("AUDIO_SETTINGS", "音频设置"))
	_slider_master = _make_slider(vbox, "MASTER_VOLUME", "主音量", func(v: float) -> void:
		SettingsManager.set_master_volume(v)
	)
	_slider_music = _make_slider(vbox, "MUSIC_VOLUME", "音乐音量", func(v: float) -> void:
		SettingsManager.set_music_volume(v)
	)
	_slider_sfx = _make_slider(vbox, "SFX_VOLUME", "音效音量", func(v: float) -> void:
		SettingsManager.set_sfx_volume(v)
	)
	## #4：音频节流开关（默认开启）。开启=现在的并发限制播放方式；关闭=以前的触发即播、无限制。
	_audio_throttle_toggle = CheckButton.new()
	_audio_throttle_toggle.text = "音频节流（攻击/点击音效并发限制）"
	_audio_throttle_toggle.set_meta("tr_key", "音频节流")
	_audio_throttle_toggle.set_meta("tr_fallback", "音频节流（攻击/点击音效并发限制）")
	_audio_throttle_toggle.toggled.connect(func(pressed: bool) -> void:
		SettingsManager.set_audio_throttle(pressed)
	)
	vbox.add_child(_audio_throttle_toggle)

	## —— 战斗 ——
	vbox.add_child(_make_section("BATTLE_SETTINGS", "战斗设置"))
	_damage_toggle = CheckButton.new()
	_damage_toggle.text = "显示伤害数字"
	_damage_toggle.set_meta("tr_key", "显示伤害数字")
	_damage_toggle.set_meta("tr_fallback", "显示伤害数字")
	_damage_toggle.toggled.connect(func(pressed: bool) -> void:
		SettingsManager.set_show_damage_numbers(pressed)
	)
	vbox.add_child(_damage_toggle)
	## #16：血条居中显示血量/护盾数值（默认开启）
	_hp_armor_toggle = CheckButton.new()
	_hp_armor_toggle.text = "显示血量/护盾数值"
	_hp_armor_toggle.set_meta("tr_key", "显示血量/护盾数值")
	_hp_armor_toggle.set_meta("tr_fallback", "显示血量/护盾数值")
	_hp_armor_toggle.tooltip_text = "开启后兵种与水晶血条中央显示当前血量/护盾数字"
	_hp_armor_toggle.toggled.connect(func(pressed: bool) -> void:
		SettingsManager.set_show_hp_armor_bar(pressed)
	)
	vbox.add_child(_hp_armor_toggle)

	## —— 背景音乐 ——
	vbox.add_child(_make_section("BGM_SETTINGS", "背景音乐设置"))
	_opt_menu_bgm = _make_bgm_row(vbox, "主题BGM", BGM_OPTIONS, func(bgm_name: String) -> void:
		SettingsManager.set_menu_bgm(bgm_name)
	)
	_opt_battle_bgm = _make_bgm_row(vbox, "战斗BGM", BGM_OPTIONS, func(bgm_name: String) -> void:
		SettingsManager.set_battle_bgm(bgm_name)
	)
	_opt_victory_bgm = _make_bgm_row(vbox, "胜利BGM", VICTORY_OPTIONS, func(bgm_name: String) -> void:
		SettingsManager.set_victory_bgm(bgm_name)
	)
	var btn_random := Button.new()
	btn_random.text = "随机播放BGM"
	UIButtonHelper.setup_button(btn_random)
	btn_random.pressed.connect(func() -> void:
		var pool: Array[String] = ["Medieval Vol.2", "Falling Apart", "Decisive Battle", "The Calm Before The Storm"]
		SettingsManager.set_menu_bgm(pool[randi() % pool.size()])
		SettingsManager.set_battle_bgm(pool[randi() % pool.size()])
		## settings_changed 会自动刷新本面板的 BGM 下拉选中态
	)
	vbox.add_child(btn_random)

# ---------- 构建辅助 ----------

func _make_section(key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.text = tr(key) if tr(key) != key else fallback
	lbl.set_meta("tr_key", key)
	lbl.set_meta("tr_fallback", fallback)
	lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_labels.append(lbl)
	return lbl

func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	UIButtonHelper.setup_button(btn)
	return btn

func _make_slider(parent: VBoxContainer, key: String, fallback: String, on_change: Callable) -> HSlider:
	var lbl := Label.new()
	lbl.text = tr(key) if tr(key) != key else fallback
	lbl.set_meta("tr_key", key)
	lbl.set_meta("tr_fallback", fallback)
	parent.add_child(lbl)
	_text_labels.append(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 2.0  ## #1（2026-08-09）：音量上限 1.0 → 2.0（0~200%）
	slider.step = 0.01
	slider.value_changed.connect(on_change)
	parent.add_child(slider)
	return slider

func _make_bgm_row(parent: VBoxContainer, label_text: String, options: Array[String], on_change: Callable) -> OptionButton:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.set_meta("tr_key", label_text)
	lbl.set_meta("tr_fallback", label_text)
	lbl.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(lbl)
	_text_labels.append(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for o in options:
		opt.add_item(o)
	opt.item_selected.connect(func(idx: int) -> void:
		on_change.call(opt.get_item_text(idx))
	)
	hbox.add_child(opt)
	return opt

# ---------- 交互回调（全部经 SettingsManager，统一触发 settings_changed） ----------

func _on_window_pressed(btn: Button) -> void:
	btn.release_focus()
	SettingsManager.set_window_mode(int(btn.get_meta("mode", 0)))
	## 高亮由 settings_changed → _refresh_all 统一刷新

func _on_lang_pressed(btn: Button) -> void:
	SettingsManager.set_language(String(btn.get_meta("lang", "")))
	## 高亮 + 文本翻译由 settings_changed → _refresh_all 统一刷新

# ---------- 全局同步刷新（settings_changed 触发） ----------

func _refresh_all() -> void:
	## 窗口模式按钮高亮
	for btn in _window_buttons:
		btn.modulate = Color(0.5, 1, 0.5) if SettingsManager.window_mode == int(btn.get_meta("mode", 0)) else Color(1, 1, 1)
	## 语言按钮高亮
	for btn in _lang_buttons:
		btn.modulate = Color(0.5, 1, 0.5) if SettingsManager.language == String(btn.get_meta("lang", "")) else Color(1, 1, 1)
	## 音量滑条（set_value_no_signal 不触发 value_changed，避免回写循环）
	if _slider_master != null:
		_slider_master.set_value_no_signal(SettingsManager.master_volume)
	if _slider_music != null:
		_slider_music.set_value_no_signal(SettingsManager.music_volume)
	if _slider_sfx != null:
		_slider_sfx.set_value_no_signal(SettingsManager.sfx_volume)
	## 伤害开关（set_pressed_no_signal 不触发 toggled）
	if _damage_toggle != null:
		_damage_toggle.set_pressed_no_signal(SettingsManager.show_damage_numbers)
	## #16：血条数值开关
	if _hp_armor_toggle != null:
		_hp_armor_toggle.set_pressed_no_signal(SettingsManager.show_hp_armor_bar)
	## #4：音频节流开关
	if _audio_throttle_toggle != null:
		_audio_throttle_toggle.set_pressed_no_signal(SettingsManager.audio_throttle)
	## BGM 下拉选中态（select 不触发 item_selected）
	_select_option(_opt_menu_bgm, SettingsManager.menu_bgm, BGM_OPTIONS)
	_select_option(_opt_battle_bgm, SettingsManager.battle_bgm, BGM_OPTIONS)
	_select_option(_opt_victory_bgm, SettingsManager.victory_bgm, VICTORY_OPTIONS)
	## 翻译文本刷新（语言切换后所有标签/按钮文字即时更新）
	for lbl in _text_labels:
		var key: String = String(lbl.get_meta("tr_key", ""))
		var fallback: String = String(lbl.get_meta("tr_fallback", ""))
		lbl.text = tr(key) if tr(key) != key else fallback
	for btn in _window_buttons:
		var btn_key: String = String(btn.get_meta("tr_key", ""))
		var btn_fallback: String = String(btn.get_meta("tr_fallback", ""))
		btn.text = tr(btn_key) if tr(btn_key) != btn_key else btn_fallback

## 按值选中 OptionButton（value 不在列表时选第一项）
func _select_option(opt: OptionButton, value: String, options: Array[String]) -> void:
	if opt == null:
		return
	var idx: int = options.find(value)
	opt.select(maxi(idx, 0))
