class_name UIButtonHelper
## 按钮效果辅助类
## 为按钮统一设置中世纪风格按钮底图、悬停和点击效果
## 为容器或弹窗设置木质/羊皮纸底图

## 选中高亮色（旧版使用，保留兼容）
const COLOR_SELECT: Color = Color(1, 0.85, 0, 1)

## 按钮普通状态纹理路径
const TEX_BUTTON_NORMAL := "res://assets/ui/button_normal.png"
## 按钮悬停状态纹理路径
const TEX_BUTTON_HOVER := "res://assets/ui/button_hover.png"
## 按下状态纹理路径
const TEX_BUTTON_PRESSED := "res://assets/ui/button_pressed.png"
## 顶部栏按钮样式「按钮2」纹理路径（局内上方模式/帮助/设置/退出按钮使用）
const TEX_BUTTON_TOPBAR_2 := "res://assets/ui/button_topbar_2.png"
## Top-bar button style 3.5 texture path.
const TEX_BUTTON_TOPBAR_3 := "res://assets/ui/button_topbar_3.png"
## 木质面板纹理路径
const TEX_PANEL_WOOD := "res://assets/ui/panel_wood.png"
## 羊皮纸面板纹理路径
const TEX_PANEL_PARCHMENT := "res://assets/ui/panel_parchment.png"
## 兵种动画资源根目录（解锁弹窗预览奔跑动画用）
const UNIT_ANIM_ROOT_DIR := "res://resources/units"

## 项目全局 UI 字体（毛笔王星缘书法体）的缓存
static var _ui_font_cache: Font = null
static var _font_fallbacks_configured: bool = false

## Web 没有可靠的操作系统字体回退；给主字体挂上随包分发的 CJK/泰文 fallback。
## 主字体仍保留原有书法体，只有缺字时才由 fallback 绘制。
static func configure_global_font_fallbacks() -> void:
	if _font_fallbacks_configured:
		return
	var main_path: String = str(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	var main_font := load(main_path) as FontFile
	if main_font == null:
		return
	var fallback_fonts: Array[Font] = []
	for path in ["res://assets/fonts/NotoSansCJK-Regular.ttc", "res://assets/fonts/NotoSansThai-Regular.ttf"]:
		var fallback := load(path) as FontFile
		if fallback != null:
			fallback_fonts.append(fallback)
	if not fallback_fonts.is_empty():
		main_font.fallbacks = fallback_fonts
	_ui_font_cache = main_font
	_font_fallbacks_configured = true

## 获取项目全局 UI 字体
## draw_string() 这类底层绘制不会自动走主题，必须显式传字体，
## 否则会掉回引擎自带的 fallback 字体，与全局书法体不一致（#11）。
## 读取 ProjectSettings 的 gui/theme/custom_font（Godot 4 的正式键名，
## 注意不是 default_font —— 那是字体渲染选项前缀，写路径进去不会生效）。
static func get_ui_font() -> Font:
	configure_global_font_fallbacks()
	if _ui_font_cache != null:
		return _ui_font_cache
	var path: String = str(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	if path != "" and ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Font:
			_ui_font_cache = res
			return _ui_font_cache
	_ui_font_cache = ThemeDB.fallback_font  ## 兜底：项目未配置字体时用引擎默认
	return _ui_font_cache

## #1：开发者工具专用主题（default_font = 引擎默认字体）
## 全局 gui/theme/custom_font 是书法体（猫啃忘形圆），控制台/开发工具/调整工具用它读长文本、
## 看数值会很难受；给这些调试界面挂一个 default_font 为引擎默认字体的 Theme，
## 子树内所有控件字体解析会优先命中本主题的 default_font，从而避开书法体。
static func make_dev_system_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = ThemeDB.fallback_font
	return theme

## 获取可拉伸的纹理面板样式
static func get_panel_style(texture_path: String, modulate: Color = Color(1, 1, 1, 1)) -> StyleBoxTexture:
	## 创建纹理样式盒
	var style = StyleBoxTexture.new()
	## 加载指定纹理
	style.texture = load(texture_path)
	## 设置四周扩展边距，使内容不被边框遮挡
	style.set_expand_margin_all(8)
	## 设置整体染色
	style.modulate_color = modulate
	return style

## 获取「加载提示框（进度条框）」同款米色描边样式
## 加载框 / 局内设置弹框 / 局外设置弹框共用这一份定义，保证三处外观完全一致；
## 想调风格只改这里即可，不会再出现各处数值漂移。每次返回新实例，避免调用方互相污染。
static func get_loading_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.86, 0.70, 0.98)
	style.border_color = Color(0.35, 0.25, 0.13, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style

## 把「进度条框」同款样式套到 Control / Window（AcceptDialog 等弹窗直接可用）
static func setup_loading_frame_panel(target: Variant) -> void:
	if target is Control or target is Window:
		target.add_theme_stylebox_override("panel", get_loading_frame_style())

## 获取「长按兵种按钮 → 兵种详情框」同款米色描边样式（羊皮纸底 + 深棕边框 + 圆角）
## 数值与 hud.gd 的 _show_unit_detail_popup 逐项一致（含 alpha=1.0 完全不透明）。
## 与 get_loading_frame_style() 的差别：详情框内边距四周统一 14 且不透明，加载框是 20/20/10/10 且 0.98。
## 每次返回新实例，避免调用方互相污染。
static func get_detail_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.86, 0.70, 1.0)
	style.border_color = Color(0.35, 0.25, 0.13, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	return style

## 把 AcceptDialog / ConfirmationDialog 打扮成与兵种详情框（PopupPanel）完全一致的外观
## 背景：详情框是 PopupPanel，只有一个 `panel` 样式，天生没有窗口装饰；
## 而 Dialog 继承自 Window，黑框来自 Window 的 `embedded_border` / `embedded_unfocused_border`
## 两个 StyleBox，外加 `title_height=36` 的标题栏占位与右上角 `close` 图标——
## 这些都不受 `panel` 覆盖影响，只改 panel 是去不掉黑框的（Godot 4.7 实测）。
## 本函数把上述装饰全部压成不可见，使 Dialog 只剩下与详情框同款的米色描边框。
## title 文字请改由调用方在框内加 Label 呈现（标题栏已不可见）。
static func setup_detail_frame_dialog(dialog: Window) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	## ① 主体：与兵种详情框同款米色描边框
	dialog.add_theme_stylebox_override("panel", get_detail_frame_style())
	## ② 窗口装饰边框（黑框本体）：换成完全空的 StyleBoxEmpty
	dialog.add_theme_stylebox_override("embedded_border", StyleBoxEmpty.new())
	dialog.add_theme_stylebox_override("embedded_unfocused_border", StyleBoxEmpty.new())
	## ③ 标题栏高度清零，否则顶部会留 36px 空白
	dialog.add_theme_constant_override("title_height", 0)
	## ④ 标题文字与描边设为全透明（双保险：即便还有绘制也看不见）
	dialog.add_theme_color_override("title_color", Color(0, 0, 0, 0))
	dialog.add_theme_color_override("title_outline_modulate", Color(0, 0, 0, 0))
	## ⑤ 右上角关闭图标换成 1x1 全透明贴图，避免悬空的 X
	var blank := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	dialog.add_theme_icon_override("close", blank)
	dialog.add_theme_icon_override("close_pressed", blank)

## 生成与兵种详情框首行同款的标题 Label（深棕、22 号字）
## 配合 setup_detail_frame_dialog()：窗口标题栏已隐藏，标题改在框内呈现。
static func make_detail_frame_title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.35, 0.12, 0.08, 1.0))
	return lbl

## 显示「获得新兵种！」解锁确认框（#19：通关首通弹窗与战功购买解锁弹窗共用）
## 由 campaign_map（关卡首通）与 unit_unlock_window（战功购买）调用，避免两处重复维护。
## parent: 弹窗父节点（Window 需挂在场景内节点下）；display_name: 兵种显示名；unit_id: 兵种 ID。
static func show_unit_unlock_popup(parent: Node, display_name: String, unit_id: String) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var popup := Window.new()
	popup.title = TranslationServer.translate("UNLOCK_TITLE")
	var popup_size := Vector2i(360, 330)
	popup.size = popup_size
	popup.unresizable = true
	setup_detail_frame_dialog(popup)
	## 弹窗设为始终保持处理（忽略场景暂停）
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 14
	vbox.offset_bottom = -14
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)
	var title_lbl := make_detail_frame_title(TranslationServer.translate("UNLOCK_NEW"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	# 中间展示解锁兵种的奔跑动画；资源缺失时收缩占位，不显示空区域。
	var anim_holder := Control.new()
	anim_holder.custom_minimum_size = Vector2(0, 110)
	vbox.add_child(anim_holder)
	var frames := _load_unit_move_frames(unit_id)
	if frames != null:
		var anim_sprite := AnimatedSprite2D.new()
		anim_sprite.sprite_frames = frames
		anim_sprite.play("move")
		var frame_size := frames.get_frame_texture("move", 0).get_size()
		if frame_size.x > 0.0 and frame_size.y > 0.0:
			var scale_factor := minf(110.0 / frame_size.x, 110.0 / frame_size.y)
			anim_sprite.scale = Vector2.ONE * scale_factor
		anim_sprite.position = anim_holder.custom_minimum_size / 2.0
		anim_holder.add_child(anim_sprite)
	else:
		anim_holder.custom_minimum_size = Vector2(0, 8)

	var name_lbl := Label.new()
	name_lbl.text = "%s（%s）" % [display_name, unit_id]
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.35, 0.12, 0.08, 1.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = TranslationServer.translate("UNLOCK_DESC")
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.45, 0.25, 0.12, 1))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)

	var btn_ok := Button.new()
	btn_ok.text = TranslationServer.translate("UNLOCK_OK")
	btn_ok.custom_minimum_size = Vector2(80, 36)
	setup_parchment_button(btn_ok)
	btn_ok.pressed.connect(popup.queue_free)
	vbox.add_child(btn_ok)
	## 右上角 X 也能关闭（未连接则点击无反应）
	popup.close_requested.connect(popup.queue_free)
	parent.add_child(popup)
	popup.popup_centered(popup_size)
	## 播放 UI 点击音效，提示玩家注意弹窗
	AudioManager.play_ui_click()


## 加载解锁弹窗用的奔跑动画；复制后设为循环，避免改动原始资源。
static func _load_unit_move_frames(unit_id: String) -> SpriteFrames:
	var path := "%s/%s/move_frames.tres" % [UNIT_ANIM_ROOT_DIR, unit_id]
	if not ResourceLoader.exists(path):
		return null
	var frames := load(path) as SpriteFrames
	if frames == null or not frames.has_animation("move"):
		return null
	var dup := frames.duplicate()
	dup.set_animation_loop("move", true)
	return dup

## 为容器或弹窗设置木质底图
static func setup_wood_panel(target: Variant) -> void:
	## Control 类型节点使用 panel 样式覆盖
	if target is Control:
		target.add_theme_stylebox_override("panel", get_panel_style(TEX_PANEL_WOOD))
	## Window 类型节点同样使用 panel 样式覆盖
	elif target is Window:
		target.add_theme_stylebox_override("panel", get_panel_style(TEX_PANEL_WOOD))

## 为按钮设置统一的样式、悬停和点击效果
static func setup_button(btn: Button, bg_normal: Color = Color(0.2, 0.2, 0.2, 0.9),
						 bg_hover: Color = Color(0.35, 0.35, 0.35, 0.95),
						 border_normal: Color = Color(0.5, 0.5, 0.5, 0.7),
						 border_hover: Color = Color(0.8, 0.8, 0.8, 0.9),
						 font_color: Color = Color(1, 1, 1, 1)) -> void:
	## 设置按钮各状态样式
	_setup_style(btn, bg_normal, bg_hover, border_normal, border_hover, font_color)
	## 设置点击闪烁特效
	_setup_click_effect(btn)

## 设置按钮样式（normal / hover / pressed / disabled）
static func _setup_style(btn: Button, bg_normal: Color, bg_hover: Color,
						 _border_normal: Color, _border_hover: Color,
						 font_color: Color) -> void:
	## 普通状态样式
	var normal = StyleBoxTexture.new()
	normal.texture = load(TEX_BUTTON_NORMAL)
	normal.set_expand_margin_all(4)
	normal.modulate_color = bg_normal
	btn.add_theme_stylebox_override("normal", normal)
	## 禁用状态复用普通样式
	btn.add_theme_stylebox_override("disabled", normal)

	## 悬停状态样式
	var hover = StyleBoxTexture.new()
	hover.texture = load(TEX_BUTTON_HOVER)
	hover.set_expand_margin_all(4)
	hover.modulate_color = bg_hover
	btn.add_theme_stylebox_override("hover", hover)

	## 按下状态样式
	var pressed = StyleBoxTexture.new()
	pressed.texture = load(TEX_BUTTON_PRESSED)
	pressed.set_expand_margin_all(4)
	pressed.modulate_color = Color(1, 1, 1, 1)
	btn.add_theme_stylebox_override("pressed", pressed)

	## 设置各状态文字颜色
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_disabled_color", font_color)

## 为按钮设置米色羊皮卷纸风格（与兵种详情框/面板同款羊皮纸纹理）
## normal=原色，hover=提亮，pressed=压暗，disabled=半透明；字体统一深棕。
static func setup_parchment_button(btn: Button, font_color: Color = Color(0.35, 0.12, 0.08, 1.0)) -> void:
	var states := ["normal", "hover", "pressed", "disabled"]
	for state in states:
		var st := StyleBoxTexture.new()
		st.texture = load(TEX_PANEL_PARCHMENT)
		st.set_expand_margin_all(4)
		match state:
			"normal":
				st.modulate_color = Color(1.0, 1.0, 1.0, 1.0)
			"hover":
				st.modulate_color = Color(1.08, 1.02, 0.9, 1.0)
			"pressed":
				st.modulate_color = Color(0.85, 0.8, 0.65, 1.0)
			"disabled":
				st.modulate_color = Color(0.7, 0.65, 0.55, 0.6)
		btn.add_theme_stylebox_override(state, st)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_disabled_color", font_color)
	_setup_click_effect(btn)

## Detail-panel style for campaign-map return buttons.
static func setup_detail_frame_button(btn: Button, font_color: Color = Color(0.35, 0.12, 0.08, 1.0)) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st := get_detail_frame_style()
		match state:
			"hover": st.bg_color = Color(1.0, 0.94, 0.78, 1.0)
			"pressed": st.bg_color = Color(0.82, 0.75, 0.58, 1.0)
			"disabled": st.bg_color = Color(0.7, 0.65, 0.55, 0.6)
		btn.add_theme_stylebox_override(state, st)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_disabled_color", font_color)
	_setup_click_effect(btn)

## 对话框操作按钮统一为紧凑长方形；焦点态沿用普通态，不再出现白色光圈。
static func setup_dialog_action_button(btn: Button) -> void:
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(112, 40)
	setup_detail_frame_button(btn)
	var focus_style := get_detail_frame_style()
	btn.add_theme_stylebox_override("focus", focus_style)

## Top-bar button style; optional texture selects button 2 or button 3.5.
static func setup_topbar_button(btn: Button, font_color: Color = Color(1, 1, 1, 1), texture_path: String = TEX_BUTTON_TOPBAR_2) -> void:
	var tex: Texture2D = load(texture_path)
	var states := ["normal", "hover", "pressed", "disabled"]
	for state in states:
		var st := StyleBoxTexture.new()
		st.texture = tex
		st.set_expand_margin_all(6)
		## 文字垂直位置上移一点（Button 无 vertical_alignment，增大底部内边距使文本视觉重心上移）
		st.content_margin_bottom = 6.0
		match state:
			"normal":
				st.modulate_color = Color(1.0, 1.0, 1.0, 1.0)
			"hover":
				st.modulate_color = Color(1.12, 1.12, 1.12, 1.0)
			"pressed":
				st.modulate_color = Color(0.82, 0.82, 0.82, 1.0)
			"disabled":
				st.modulate_color = Color(1.0, 1.0, 1.0, 0.55)
		btn.add_theme_stylebox_override(state, st)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_disabled_color", font_color)
	## 文字水平居中（Button 文字垂直方向本就居中，不设 vertical_alignment）
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_click_effect(btn)

## 设置点击闪烁特效（仅改变亮度，不改变大小，避免推动 UI）
static func _setup_click_effect(btn: Button) -> void:
	## 监听按钮按下事件
	btn.button_down.connect(func():
		## 检查按钮是否仍然有效
		if not is_instance_valid(btn):
			return
		## 创建线性缓出补间动画
		var tw = btn.create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)
		## 先提亮再恢复，形成闪烁效果
		tw.tween_property(btn, "modulate", Color(1.45, 1.45, 1.45), 0.06)
		tw.tween_property(btn, "modulate", Color(1, 1, 1), 0.1)
	)
