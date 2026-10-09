class_name UIButtonHelper
## 按钮效果辅助类
## 为按钮统一设置中世纪风格按钮底图、悬停和点击效果
## 为容器或弹窗设置木质/羊皮纸底图

## 选中高亮色（旧版使用，保留兼容）
const COLOR_SELECT: Color = Color(1, 0.85, 0, 1)

## 按钮普通状态纹理路径（用户口中的「按钮1」——最早接入的默认按钮底图）
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
## 战役风弹窗羊皮纸九宫格底（与 ach_window_bg 同风格手绘绘本，2026-10-04）
const TEX_POPUP_BG := "res://assets/ui/campaign/popup_bg.png"
## 卷轴标题横幅贴图（2026-10-04 晚起三处弹窗标题统一改雕花金边牌匾，本贴图暂未使用，留作备用）
const TEX_BANNER_TITLE := "res://assets/ui/campaign/banner_title.png"

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
	## ①b 关键：嵌入窗口的视口底色必须透明。
	## 项目 default_clear_color=纯白，嵌入 Window 的视口按该色清屏——
	## 圆角 StyleBoxFlat 四角「画不到」的小方块就露出白底（弹框四角白角 BUG 的根因）。
	## transparent_bg=true 后视口按透明清屏，四角直接透出弹窗后面的游戏画面。
	dialog.transparent_bg = true
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

## 生成与兵种详情框首行同款的标题 Label（深棕、22 号字，默认水平居中）
## 配合 setup_detail_frame_dialog()：窗口标题栏已隐藏，标题改在框内呈现。
## 2026-10-04（晚）：默认居中——难度弹窗/退出确认框标题此前全顶在左侧。
static func make_detail_frame_title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.35, 0.12, 0.08, 1.0))
	return lbl

## 贴图内「羊皮纸内区」的垂直中心比例（原图 1466×399，内区约 y 35..305 → 中心 0.426）。
## 画布下方有底部纹章+阴影，画布几何中心（0.5）比视觉中心低 → 文字按 0.5 居中会看着偏下。
const BANNER_TEXT_CENTER_RATIO: float = 0.44

## 生成标题横幅：局内顶栏「按钮」同款金边雕花素材（button_topbar_2）等比整图居中
## 2026-10-04（晚·二次订正）：用户对照截图拍板——要的是顶栏按钮那张雕花金边图，
## 不是素面金胶囊（blank_button_gold 已废弃删除）。整图等比绘制，不九宫格，
## 避免雕花角饰/底部纹章被拉伸变形；标题 Label 按 BANNER_TEXT_CENTER_RATIO 对齐视觉中心。
static func make_button_banner_title(text: String, height: float = 72.0, font_size: int = 24) -> Control:
	var banner := TextureRect.new()
	banner.name = "TitleBanner"
	banner.texture = load(TEX_BUTTON_TOPBAR_2)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.custom_minimum_size = Vector2(0, height)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := make_detail_frame_title(text)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_child(lbl)
	lbl.anchor_left = 0.0
	lbl.anchor_top = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	## 锚点铺满整条横幅，再整体上移，使文字落在羊皮纸内区中心（默认 0.5 会偏低）
	var dy: float = (BANNER_TEXT_CENTER_RATIO - 0.5) * height
	lbl.offset_left = 0.0
	lbl.offset_top = dy
	lbl.offset_right = 0.0
	lbl.offset_bottom = dy
	return banner

## 把 Dialog 内建按钮行改为「等宽长方形 + 整排水平居中」
## 2026-10-04（晚·查引擎源码后重写）：Godot 4.7 的 AcceptDialog 按钮行不用 alignment 排布——
##   · 构造函数/ add_button 会塞进若干「弹性 spacer」，行内 spacer 吃掉全部余量 → alignment 不生效；
##   · 布局函数 _update_child_rects() 每次都会用主题常量 buttons_min_width/height 覆盖每个按钮的
##     custom_minimum_size → 只设 custom_minimum_size 会被引擎冲掉，按钮变成内容自适应宽度。
## 因此：① 用对话框主题常量统一尺寸；② 删掉全部 spacer，首尾各插一个等权弹性 spacer → 精确居中。
static func center_dialog_buttons(dialog: Window, btn_width: int = 150, btn_height: int = 42) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	var ok_btn: Button = dialog.get_ok_button()
	if ok_btn == null or not is_instance_valid(ok_btn):
		return
	var row_node: Node = ok_btn.get_parent()
	if not (row_node is HBoxContainer):
		return
	var row := row_node as HBoxContainer
	## ① 统一尺寸（引擎布局时以这两个主题常量为准）
	dialog.add_theme_constant_override("buttons_min_width", btn_width)
	dialog.add_theme_constant_override("buttons_min_height", btn_height)
	## ② 收集按钮（保持既有顺序），清掉所有 spacer
	var buttons: Array[Button] = []
	for c in row.get_children():
		if c is Button:
			buttons.append(c)
	for c in row.get_children():
		if not (c is Button):
			row.remove_child(c)
			c.queue_free()
	for b in buttons:
		if b.has_meta("__bound_spacer"):
			## 绑定 spacer 已删，去掉悬空引用（引擎读不到 meta 时是安全的空转）
			b.remove_meta("__bound_spacer")
	## ③ 首尾等权弹性 spacer → 按钮组精确居中（隐藏按钮不占位，仍居中）
	var spacer_l := Control.new()
	spacer_l.name = "CenterSpacerL"
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer_l)
	row.move_child(spacer_l, 0)
	var spacer_r := Control.new()
	spacer_r.name = "CenterSpacerR"
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer_r)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

## 战役风美术弹窗（2026-10-04）：羊皮纸九宫格底 + 标题横幅。
## 用于难度选择弹窗 / 兵种解锁弹窗，与成就窗口（achievements_window）同一套美术语言。
## 结构：Window(panel 清空) → 九宫格 bg Panel + MarginContainer → VBox(标题横幅 + 调用方内容)。
## 2026-10-04（晚·反馈轮 15）：标题横幅由卷轴贴图统一改为「成就/兵种解锁同款」雕花金边牌匾
## （make_button_banner_title，button_topbar_2），三处弹窗标题风格一致。
## 返回 VBox 供调用方继续填充内容；失败返回 null。
static func setup_campaign_popup(dialog: Window, title_text: String, banner_height: float = 72.0, title_size: int = 22) -> VBoxContainer:
	if dialog == null or not is_instance_valid(dialog):
		return null
	## 窗口装饰清理（黑框/标题栏/右上角关闭图标）与详情框一致
	setup_detail_frame_dialog(dialog)
	## 窗口自身 panel 清空：视觉完全由九宫格羊皮纸底承担（无米色/白色衬底）
	dialog.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	## 羊皮纸九宫格底（StyleBoxTexture，边框区 34px 源图）
	var bg := Panel.new()
	bg.name = "CampaignPopupBG"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(bg)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = 0.0
	bg.offset_top = 0.0
	bg.offset_right = 0.0
	bg.offset_bottom = 0.0
	var st := StyleBoxTexture.new()
	st.texture = load(TEX_POPUP_BG)
	st.texture_margin_left = 34.0
	st.texture_margin_top = 34.0
	st.texture_margin_right = 34.0
	st.texture_margin_bottom = 34.0
	bg.add_theme_stylebox_override("panel", st)
	dialog.move_child(bg, 0)
	## 内容边距容器（MarginContainer 是唯一对子节点 margin 生效的方式）
	var margins := MarginContainer.new()
	margins.name = "ContentMargins"
	dialog.add_child(margins)
	margins.anchor_left = 0.0
	margins.anchor_top = 0.0
	margins.anchor_right = 1.0
	margins.anchor_bottom = 1.0
	margins.offset_left = 0.0
	margins.offset_top = 0.0
	margins.offset_right = 0.0
	margins.offset_bottom = 0.0
	margins.add_theme_constant_override("margin_left", 36)
	margins.add_theme_constant_override("margin_right", 36)
	margins.add_theme_constant_override("margin_top", 24)
	margins.add_theme_constant_override("margin_bottom", 28)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margins.add_child(vbox)
	## 标题横幅：与成就窗口 / 兵种解锁窗口同款（button_topbar_2 雕花金边牌匾，整图等比居中）
	vbox.add_child(make_button_banner_title(title_text, banner_height, title_size))
	return vbox

## 显示「获得新兵种！」解锁确认框（#19：通关首通弹窗与战功购买解锁弹窗共用）
## 由 campaign_map（关卡首通）与 unit_unlock_window（战功购买）调用，避免两处重复维护。
## parent: 弹窗父节点（Window 需挂在场景内节点下）；display_name: 兵种显示名；unit_id: 兵种 ID。
static func show_unit_unlock_popup(parent: Node, display_name: String, unit_id: String) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var popup := Window.new()
	popup.title = TranslationServer.translate("UNLOCK_TITLE")
	var popup_size := Vector2i(360, 384)
	popup.size = popup_size
	popup.unresizable = true
	## 弹窗设为始终保持处理（忽略场景暂停）
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	## 2026-10-04：战役风美术弹窗（羊皮纸九宫格底 + 卷轴横幅标题）
	var vbox := setup_campaign_popup(popup, TranslationServer.translate("UNLOCK_NEW"), 64.0, 20)
	if vbox == null:
		popup.queue_free()
		return

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
	## 2026-10-04（晚）：圆角长方形（150×42，圆角 8 与详情框一致，左右内缩 20/上下 6 拉长比例）。
	## 用户拍板反转：早上的「直角长方形」观感偏方，确认/操作按钮统一回圆角。
	btn.custom_minimum_size = Vector2(150, 42)
	setup_detail_frame_button(btn)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var st := get_detail_frame_style()
		st.set_corner_radius_all(8)
		st.content_margin_left = 20.0
		st.content_margin_right = 20.0
		st.content_margin_top = 6.0
		st.content_margin_bottom = 6.0
		match state:
			"hover":
				st.bg_color = Color(1.0, 0.94, 0.78, 1.0)
			"pressed":
				st.bg_color = Color(0.82, 0.75, 0.58, 1.0)
			"disabled":
				st.bg_color = Color(0.7, 0.65, 0.55, 0.6)
		btn.add_theme_stylebox_override(state, st)
	## 焦点态字色必须覆盖：Godot 默认 font_focus_color 是白色，默认按钮（OK）聚焦时会白字配浅底
	btn.add_theme_color_override("font_focus_color", Color(0.35, 0.12, 0.08, 1.0))
	## 文本水平居中（2026-10-04 显式钉死；探针实测默认即居中，这里防主题/调用方改写）
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

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
