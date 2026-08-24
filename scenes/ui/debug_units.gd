extends Control
## 兵种调试台
## Tab1: 尺寸调试 - 每个兵种的移动/攻击动画独立调整显示宽高
## Tab2: 数值调试 - 实时调整兵种的各项数值属性
## Tab3: 帧图编辑 - 可视化精灵图并手动调整帧顺序与裁切区域

## 兵种排序顺序（数字从小到大排列，包含全部兵种用于调试展示）
const UNIT_ORDER: Array[String] = [
	"G1", "G2", "G3", "G4", "G5", "G6",
	"D1", "D2", "D3", "D4", "D5", "D6",
	"F1", "F2", "F3", "F4", "F5",
	"N1", "N2", "N3", "N4", "N5",
	"Hero1",  ## 特殊英雄单位（爱弥斯），归入第 5 阵营「英雄」
	"Hero2",  ## Doro勇士（隐藏成就「为了欧润橘！」解锁），归入第 5 阵营「英雄」
	"Hero3",  ## 菲比Hero（肉鸽首发英雄 / 开发者模式解锁），归入第 5 阵营「英雄」
	"Hero4",  ## 咕咕嘎嘎Hero（成就「咕嘎军团」+20 星解锁），归入第 5 阵营「英雄」
	"Hero5",  ## 糯糯Hero（成就「糯糯大军」+20 星解锁），归入第 5 阵营「英雄」
	"S1",  ## 蓝女巫：特殊阵营，归入第 6 阵营「特殊」
	"S2",  ## 仓鼠士兵：特殊阵营（G1 替换事件兵种）
	"S3",  ## 天命人：特殊阵营（占位，素材待补）
	"Y1",  ## 死亡使者：异象阵营，归入第 7 阵营「异象」
	"Y2",  ## 凑企鹅：异象阵营（回合触发敌兵，双攻击轮流）
	"Y3",  ## 香蕉猫：异象阵营（占位，素材待补）
	"Y4",  ## 我的刀盾：异象阵营（占位，素材待补）
]

## 非解锁单位（仅在调试界面展示，不加入战役）
## 当前所有单位均加入全面战争模式，列表为空
const NON_UNLOCKED_UNITS: Array[String] = []

## 动画资源根目录
const ANIM_ROOT_DIR := "res://resources/units"
## 动画类型到文件名的映射
const ANIM_FILE_MAP: Dictionary = {
	"idle": "idle_frames.tres",
	"walk": "walk_frames.tres",
	"move": "move_frames.tres",
	"sprint": "sprint_frames.tres",
	"attack": "attack_frames.tres",
	"attack2": "attack2_frames.tres",  ## 备用攻击动画（attack_alt_frames，凑企鹅等双攻击兵种）
}

## 预览区域固定基准高度（像素）
const PREVIEW_BASE_SIZE: float = 120.0

## 兵种资源缓存
var _resources: Dictionary = {}

## 音效配置路径输入框引用（key: "unit_id|click"/"unit_id|spawn", value: LineEdit）
var _sound_path_edits: Dictionary = {}
## 扫描到的已配置音效路径列表（用于下拉菜单）
var _cached_sound_paths: Array[String] = []
## 音效管理面板的条目容器（用于刷新列表）
var _sound_library_box: VBoxContainer = null
## 音效管理面板的统计文字
var _sound_library_count_label: Label = null
## 音效库分类筛选：all=全部 / shared / G / D / F / N（按归属过滤，#143）
var _sound_filter: String = "all"
## 帧预览音效的上一帧号（用于边沿触发，避免同一帧重复播放，#147）
var _prev_preview_sound_frame: int = -1
## 音效配置页在 TabContainer 中的索引（文件拖入时判断当前是否在该页）
var _sound_tab_index: int = -1
## 拖放排序时被拖动条目的路径（空串表示当前无拖动）
var _dragging_sound_path: String = ""
## 音效配置页左侧各阵营分组的展开状态（key: 阵营前缀 G/D/F/N，value: bool，缺省视为展开）（#3）
var _sound_faction_expanded: Dictionary = {}
## 音效配置页左侧各阵营分组的折叠标题按钮（供「全部展开/收起」批量操作）（#3）
var _sound_faction_headers: Array[Button] = []
## #17：音效「调整」视图的滚动容器（音量拖动条按五阵营分类）
var _sound_adjust_box: ScrollContainer = null
## #2：调整视图各阵营分组的展开状态（key: 阵营名，value: bool，缺省视为展开）
## 刷新重建分组时保持用户折叠状态
var _sound_adjust_expanded: Dictionary = {}

## 精灵图边界显示开关（true=在预览中用红框标出精灵图实际边界）
var _show_sprite_boundary: bool = false
var _pending_import_kind: String = "size"  ## 记录刚点的「导入配置」属于哪一页，用于显示外部数据提示

func _ready() -> void:
	## #1：调试台用引擎默认字体（避开全局书法体），长表格/数值密集界面保持清晰可读
	theme = UIButtonHelper.make_dev_system_theme()
	## 加载所有兵种资源
	## 使用 CACHE_MODE_IGNORE 绕过缓存，确保每次打开调试界面都从磁盘读取最新数据
	## 避免上一会话修改的 default_facing 等字段被缓存覆盖回旧值
	for unit_id in UNIT_ORDER:
		var path := "%s/%s.tres" % [ANIM_ROOT_DIR, unit_id]
		if ResourceLoader.exists(path):
			_resources[unit_id] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	## 构建各 Tab 的内容
	_build_size_grid()
	_build_stats_grid()
	_build_frame_tab()
	_build_damage_test_tab()
	_build_sound_tab()
	## Tab 中文标题（音效配置的标题在 _build_sound_tab 内设置，保持原名）
	var tabs: TabContainer = $VBox/TabContainer
	tabs.set_tab_title(0, "动画调整")
	tabs.set_tab_title(1, "数值调整")
	tabs.set_tab_title(2, "帧图调整")
	tabs.set_tab_title(3, "对战模拟")
	## 连接按钮
	$VBox/TopBar/BtnBack.pressed.connect(_on_back_pressed)
	$VBox/TopBar/BtnReset.pressed.connect(_on_reset_pressed)
	## 配置 导出 / 导入 / 重置配置（动画+数值两个调整页的字段）
	## 按钮条已从顶部移到两个调整页内部（动画调整页 / 数值调整页各一组）
	$VBox/TabContainer/SizeTab/SizeBtnBar/SizeBtnExport.pressed.connect(_on_export_config_pressed)
	$VBox/TabContainer/SizeTab/SizeBtnBar/SizeBtnImport.pressed.connect(_on_import_config_pressed.bind("size"))
	$VBox/TabContainer/SizeTab/SizeBtnBar/SizeBtnRestore.pressed.connect(_on_restore_config_pressed)
	$VBox/TabContainer/StatsTab/StatsBtnBar/StatsBtnExport.pressed.connect(_on_export_config_pressed)
	$VBox/TabContainer/StatsTab/StatsBtnBar/StatsBtnImport.pressed.connect(_on_import_config_pressed.bind("stats"))
	$VBox/TabContainer/StatsTab/StatsBtnBar/StatsBtnRestore.pressed.connect(_on_restore_config_pressed)
	## 创建配置导入/导出用的文件对话框（延迟创建，避免阻塞 _ready）
	_create_config_file_dialogs.call_deferred()

## ============================================================
## Tab1: 尺寸调试
## ============================================================

## 阵营分组：前缀 -> 阵营名称（用户拍板排序：咕嘎/Doro/菲比丘比/糯糯/英雄/特殊/异象）
## 特殊（S）/异象（Y）为预置空分类，等待后续兵种数据加入（空行显示占位）
const FACTION_GROUPS: Array = [
	["G", "咕嘎"],
	["D", "Doro"],
	["F", "菲比丘比"],
	["N", "糯糯"],
	["H", "英雄"],  ## 特殊英雄阵营（爱弥斯/Doro勇士），第 5 行
	["S", "特殊"],
	["Y", "异象"],
]

## 构建尺寸调试网格（按 G/D/F/N 四行分组，每行横向排列同阵营兵种）
func _build_size_grid() -> void:
	var _scroll: ScrollContainer = $VBox/TabContainer/SizeTab/SizeScroll
	var grid: GridContainer = $VBox/TabContainer/SizeTab/SizeScroll/SizeGrid
	## 在 SizeTab 顶部插入边界显示开关按钮（仅创建一次）
	if not grid.has_meta("_boundary_btn_created"):
		grid.set_meta("_boundary_btn_created", true)
		var top_bar := HBoxContainer.new()
		top_bar.add_theme_constant_override("separation", 12)
		## 精灵图边界显示开关
		var btn_boundary := Button.new()
		btn_boundary.text = "精灵图边界显示: 关"
		btn_boundary.tooltip_text = "打开后在预览中用红框标出精灵图的实际内容边界"
		btn_boundary.toggle_mode = true
		btn_boundary.custom_minimum_size = Vector2(180, 0)
		btn_boundary.toggled.connect(func(pressed: bool) -> void:
			_show_sprite_boundary = pressed
			btn_boundary.text = "精灵图边界显示: %s" % ("开" if pressed else "关")
			grid.queue_redraw()
			## 刷新所有预览控件的绘制
			_redraw_all_previews()
		)
		top_bar.add_child(btn_boundary)
		## 弹性间隔
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_bar.add_child(spacer)
		## 将 top_bar 添加到 SizeGrid 之前（作为第一个子节点）
		grid.add_child(top_bar)
	for child in grid.get_children():
		if child is HBoxContainer and child.get_meta("_boundary_btn_created", false):
			continue  ## 跳过顶部按钮行
		if child == grid.get_child(0) and child is HBoxContainer:
			child.set_meta("_boundary_btn_created", true)
			continue
		child.queue_free()
	## 按阵营分组生成四行
	for group in FACTION_GROUPS:
		var prefix: String = group[0]
		var faction_name: String = group[1]
		## 收集该阵营的所有兵种 ID
		var faction_units: Array[String] = []
		for uid in UNIT_ORDER:
			if uid.begins_with(prefix):
				faction_units.append(uid)
		## 创建一行：阵营标签 + 横向排列的兵种卡片
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		## 阵营标签
		var faction_label := Label.new()
		faction_label.text = faction_name
		faction_label.custom_minimum_size = Vector2(60, 0)
		faction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		faction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if prefix == "H":
			faction_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9, 1))  ## 英雄特殊行：青绿色
		elif faction_units.is_empty():
			faction_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))  ## 预置空分类行：灰色
		else:
			faction_label.add_theme_color_override("font_color", Color(1, 0.7, 0.3, 1))
		faction_label.add_theme_font_size_override("font_size", 16)
		row.add_child(faction_label)
		if faction_units.is_empty():
			## 预置空分类（特殊/异象等）：显示占位提示，等待后续数据加入
			var placeholder := Label.new()
			placeholder.text = "（待添加）"
			placeholder.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(placeholder)
			grid.add_child(row)
			continue
		## 添加该阵营的兵种卡片
		for unit_id in faction_units:
			var res: UnitResource = _resources.get(unit_id)
			if res == null:
				continue
			row.add_child(_create_size_card(unit_id, res))
		grid.add_child(row)

## 为单个兵种创建尺寸卡片（水平行布局：标题 + 行走 + 奔跑 + 攻击）
func _create_size_card(unit_id: String, res: UnitResource) -> Control:
	## 整个卡片为一行 HBoxContainer
	var card := HBoxContainer.new()
	## #7：取消 EXPAND_FILL —— 否则英雄行只两张卡时会被强行拉到整行宽度，导致两卡之间留出大片空白。
	## 改用 SHRINK_BEGIN 让卡片以自然宽度左对齐排列，阵营内间距由 HBoxContainer separation 控制。
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.add_theme_constant_override("separation", 12)

	## 兵种标题列（标题 + 统一的方向翻转按钮）
	var title_col := VBoxContainer.new()
	title_col.alignment = BoxContainer.ALIGNMENT_CENTER
	title_col.add_theme_constant_override("separation", 6)
	title_col.custom_minimum_size = Vector2(80, 0)
	card.add_child(title_col)

	## 兵种标题（非解锁单位标记 *）
	var title := Label.new()
	var title_text := "%s\n%s" % [unit_id, res.display_name]
	if NON_UNLOCKED_UNITS.has(unit_id):
		title_text = "* " + title_text + "\n（调试）"
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## 非解锁单位用灰色，已解锁用金色
	if NON_UNLOCKED_UNITS.has(unit_id):
		title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	else:
		title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	title.add_theme_font_size_override("font_size", 14)
	title_col.add_child(title)

	## 加载动画帧（仅展示：行走、奔跑、攻击；待机和冲刺已隐藏）
	var walk_frames := _load_anim_frames(unit_id, "walk")
	var move_frames := _load_anim_frames(unit_id, "move")
	var attack_frames := _load_anim_frames(unit_id, "attack")
	## 三列动画：行走、奔跑、攻击（每列有独立的翻转按钮，可分别设置不同朝向）
	var walk_col := _create_anim_column("行走", walk_frames, "walk", res, unit_id)
	var move_col := _create_anim_column("奔跑", move_frames, "move", res, unit_id)
	var attack_col := _create_anim_column("攻击", attack_frames, "attack", res, unit_id)
	card.add_child(walk_col)
	card.add_child(move_col)
	card.add_child(attack_col)

	## 方向状态标签（显示当前 default_facing 基础朝向，仅供参考）
	## 每个动画的独立翻转由各自列内的按钮控制（绑定 xxx_flip_override）
	var facing_label := Label.new()
	facing_label.text = "默认朝左" if (res.default_facing == -1) else "默认朝右"
	facing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	facing_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	facing_label.add_theme_font_size_override("font_size", 10)
	facing_label.tooltip_text = "default_facing 基础参考朝向。每个动画可通过各自列内的翻转按钮独立覆盖。"
	title_col.add_child(facing_label)

	## 近战/远程切换按钮（控制 is_ranged_override：-1=自动, 0=近战, 1=远程）
	var btn_ranged := Button.new()
	## 根据 override 和 attack_range 判断当前显示文本
	var _is_current_ranged: bool = res.is_ranged
	btn_ranged.text = "远程" if _is_current_ranged else "近战"
	btn_ranged.custom_minimum_size = Vector2(70, 0)
	btn_ranged.tooltip_text = "切换近战/远程类型（保存到 .tres）\n-1=自动, 0=强制近战, 1=强制远程\n当前: %s" % ("远程" if _is_current_ranged else "近战")
	title_col.add_child(btn_ranged)

	## 切换按钮：循环 -1→0→1→-1，并保存到 .tres
	btn_ranged.pressed.connect(func() -> void:
		## 循环切换：-1(自动) → 0(近战) → 1(远程) → -1(自动)
		match res.is_ranged_override:
			-1:
				res.is_ranged_override = 0  ## 切换到强制近战
			0:
				res.is_ranged_override = 1  ## 切换到强制远程
			_:
				res.is_ranged_override = -1  ## 切换回自动
		_save_resource(unit_id, res)
		## 更新按钮显示
		var now_ranged: bool = res.is_ranged
		btn_ranged.text = "远程" if now_ranged else "近战"
		btn_ranged.tooltip_text = "切换近战/远程类型（保存到 .tres）\n-1=自动, 0=强制近战, 1=强制远程\n当前: %s" % ("远程" if now_ranged else "近战")
	)

	return card

## 预览控件绘制回调：绘制精灵图边界（红框）
func _on_preview_draw(preview: Control, _sprite: AnimatedSprite2D, frames: SpriteFrames, anim_name: String, res: UnitResource, edit_state: Dictionary = {}) -> void:
	if res == null:
		return
	var center := Vector2(PREVIEW_BASE_SIZE * 0.5, PREVIEW_BASE_SIZE * 0.5)
	var preview_scale: float = PREVIEW_BASE_SIZE / 40.0  ## 与 _apply_preview_scale 一致
	## 始终绘制精灵图红色边框（标出精灵图实际内容边界）
	if frames != null and frames.get_frame_count(anim_name) > 0:
		var tex = frames.get_frame_texture(anim_name, 0)
		if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
			## 计算精灵在预览中的实际显示尺寸（与 _apply_preview_scale 一致）
			var target_w: float = _get_anim_display_width(res, anim_name)
			if target_w <= 0.0:
				target_w = 40.0
			var target_h: float = _get_anim_display_height(res, anim_name)
			if target_h <= 0.0:
				target_h = 40.0
			var scale_w: float = (target_w * preview_scale) / float(tex.get_width())
			var scale_h: float = (target_h * preview_scale) / float(tex.get_height())
			var s: float = min(scale_w, scale_h)
			var disp_w: float = float(tex.get_width()) * s
			var disp_h: float = float(tex.get_height()) * s
			## 编辑模式下应用精灵图 Y 偏移
			var offset_y: float = 0.0
			if edit_state.has("sprite_offset_y"):
				offset_y = float(edit_state["sprite_offset_y"])
			var boundary_rect := Rect2(center.x - disp_w * 0.5, center.y - disp_h * 0.5 + offset_y, disp_w, disp_h)
			## 红框线宽随边界开关加粗（开关开启时更醒目，关闭时仍显示细线）
			var line_width: float = 2.0 if _show_sprite_boundary else 1.0
			var line_color: Color = Color(1, 0, 0, 0.8) if _show_sprite_boundary else Color(1, 0, 0, 0.5)
			preview.draw_rect(boundary_rect, line_color, false, line_width)
	## 编辑模式：绘制蓝色基准线
	if edit_state != null and edit_state.get("enabled", false):
		var baseline_y: float = float(edit_state.get("baseline_y", PREVIEW_BASE_SIZE * 0.7))
		## 蓝色基准线（横跨整个预览区）
		preview.draw_line(Vector2(0, baseline_y), Vector2(PREVIEW_BASE_SIZE, baseline_y), Color(0.3, 0.6, 1.0, 0.9), 2.0)
		## 基准线两端的小方块（拖动手柄）
		preview.draw_rect(Rect2(0, baseline_y - 3, 6, 6), Color(0.3, 0.6, 1.0, 1.0), true)
		preview.draw_rect(Rect2(PREVIEW_BASE_SIZE - 6, baseline_y - 3, 6, 6), Color(0.3, 0.6, 1.0, 1.0), true)

## 编辑模式下的鼠标输入处理
## 功能：拖动蓝色基准线移动其Y位置；拖动精灵图调整Y偏移对齐基准线；
##       拖动红色边框上/下边调整裁剪高度（修改 display_height）
func _on_preview_edit_input(preview: Control, sprite: AnimatedSprite2D, frames: SpriteFrames, anim_name: String, res: UnitResource, edit_state: Dictionary, event: InputEvent) -> void:
	if edit_state == null or not edit_state.get("enabled", false):
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				## 判断点击位置：基准线手柄 / 红框上边 / 红框下边 / 精灵图内部
				var pos: Vector2 = mb.position
				var baseline_y: float = float(edit_state.get("baseline_y", PREVIEW_BASE_SIZE * 0.7))
				## 优先判断基准线手柄（两端 6×6 方块）
				if absf(pos.y - baseline_y) <= 4.0 and (pos.x <= 6.0 or pos.x >= PREVIEW_BASE_SIZE - 6.0):
					edit_state["dragging_baseline"] = true
					edit_state["drag_start_y"] = pos.y
				else:
					## 计算红框位置
					var boundary_rect: Rect2 = _compute_preview_boundary_rect(frames, anim_name, res, edit_state)
					if boundary_rect.size.y > 0:
						## 红框上边（误差 3px）
						if absf(pos.y - boundary_rect.position.y) <= 3.0 and absf(pos.x - boundary_rect.position.x - boundary_rect.size.x * 0.5) <= boundary_rect.size.x * 0.5:
							edit_state["dragging_top"] = true
							edit_state["drag_start_y"] = pos.y
						## 红框下边（误差 3px）
						elif absf(pos.y - (boundary_rect.position.y + boundary_rect.size.y)) <= 3.0 and absf(pos.x - boundary_rect.position.x - boundary_rect.size.x * 0.5) <= boundary_rect.size.x * 0.5:
							edit_state["dragging_bottom"] = true
							edit_state["drag_start_y"] = pos.y
						## 红框内部：拖动精灵图
						elif boundary_rect.has_point(pos):
							edit_state["dragging_sprite"] = true
							edit_state["drag_start_y"] = pos.y
			else:
				## 释放鼠标：清除所有拖动状态
				edit_state["dragging_baseline"] = false
				edit_state["dragging_sprite"] = false
				edit_state["dragging_top"] = false
				edit_state["dragging_bottom"] = false
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		var pos: Vector2 = mm.position
		var prev_y: float = float(edit_state.get("drag_start_y", pos.y))
		var dy: float = pos.y - prev_y
		if edit_state.get("dragging_baseline", false):
			## 拖动蓝色基准线
			var new_y: float = float(edit_state.get("baseline_y", PREVIEW_BASE_SIZE * 0.7)) + dy
			edit_state["baseline_y"] = clampf(new_y, 0.0, PREVIEW_BASE_SIZE)
			edit_state["drag_start_y"] = pos.y
			preview.queue_redraw()
		elif edit_state.get("dragging_sprite", false):
			## 拖动精灵图调整 Y 偏移
			var old_offset: float = float(edit_state.get("sprite_offset_y", 0.0))
			edit_state["sprite_offset_y"] = old_offset + dy
			edit_state["drag_start_y"] = pos.y
			if sprite != null:
				sprite.position.y = PREVIEW_BASE_SIZE * 0.5 + float(edit_state["sprite_offset_y"])
			preview.queue_redraw()
		elif edit_state.get("dragging_top", false) or edit_state.get("dragging_bottom", false):
			## 拖动红框上/下边调整裁剪高度（修改 display_height）
			## 向上拖上边=增大高度，向下拖下边=增大高度
			var target_h: float = _get_anim_display_height(res, anim_name)
			if target_h <= 0.0:
				target_h = 40.0
			var preview_scale: float = PREVIEW_BASE_SIZE / 40.0
			## dy 正值=向下拖，负值=向上拖
			## 拖上边：向下拖=减小高度，向上拖=增大高度（dy 取反）
			## 拖下边：向下拖=增大高度，向上拖=减小高度（dy 正向）
			var delta_pixels: float = dy
			if edit_state.get("dragging_top", false):
				delta_pixels = -dy  ## 拖上边反向
			## 像素变化转换为 display_height 变化（preview_scale 倍）
			var delta_height: float = delta_pixels / preview_scale
			var new_h: float = clampf(target_h + delta_height, 5.0, 200.0)
			## 写入对应动画的 display_height 字段
			match anim_name:
				"move":
					res.move_display_height = new_h
				"walk":
					res.walk_display_height = new_h
				"attack":
					res.attack_display_height = new_h
				"idle":
					res.idle_display_height = new_h
				"sprint":
					res.sprint_display_height = new_h
				_:
					res.display_height = new_h
			_save_resource(res.unit_id, res)
			## 应用新缩放
			if sprite != null:
				_apply_preview_scale(sprite, frames, anim_name, res)
			edit_state["drag_start_y"] = pos.y
			preview.queue_redraw()

## 计算预览中红框的当前位置（编辑模式拖动判定用）
func _compute_preview_boundary_rect(frames: SpriteFrames, anim_name: String, res: UnitResource, edit_state: Dictionary) -> Rect2:
	if frames == null or frames.get_frame_count(anim_name) <= 0:
		return Rect2()
	var tex = frames.get_frame_texture(anim_name, 0)
	if tex == null or tex.get_width() <= 0 or tex.get_height() <= 0:
		return Rect2()
	var center := Vector2(PREVIEW_BASE_SIZE * 0.5, PREVIEW_BASE_SIZE * 0.5)
	var preview_scale: float = PREVIEW_BASE_SIZE / 40.0
	var target_w: float = _get_anim_display_width(res, anim_name)
	if target_w <= 0.0:
		target_w = 40.0
	var target_h: float = _get_anim_display_height(res, anim_name)
	if target_h <= 0.0:
		target_h = 40.0
	var scale_w: float = (target_w * preview_scale) / float(tex.get_width())
	var scale_h: float = (target_h * preview_scale) / float(tex.get_height())
	var s: float = min(scale_w, scale_h)
	var disp_w: float = float(tex.get_width()) * s
	var disp_h: float = float(tex.get_height()) * s
	var offset_y: float = float(edit_state.get("sprite_offset_y", 0.0))
	return Rect2(center.x - disp_w * 0.5, center.y - disp_h * 0.5 + offset_y, disp_w, disp_h)

## 刷新所有预览控件的绘制
func _redraw_all_previews() -> void:
	var grid: GridContainer = $VBox/TabContainer/SizeTab/SizeScroll/SizeGrid
	for row in grid.get_children():
		if row is HBoxContainer:
			for card in row.get_children():
				if card is HBoxContainer:
					for col in card.get_children():
						if col is VBoxContainer:
							for child in col.get_children():
								if child is Control and child.has_method("queue_redraw"):
									child.queue_redraw()

## 创建动画列（标签 + 预览 + 帧尺寸 + 独立宽高调整）
func _create_anim_column(label_text: String, frames: SpriteFrames, anim_name: String, res: UnitResource, unit_id: String) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)

	## 动画名称标签
	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	lbl.add_theme_font_size_override("font_size", 12)
	col.add_child(lbl)

	## 预览容器
	var sprite: AnimatedSprite2D = null
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(PREVIEW_BASE_SIZE, PREVIEW_BASE_SIZE)
	## 编辑模式状态（每个动画列独立）
	var edit_state: Dictionary = {
		"enabled": false,             ## 是否开启编辑模式
		"baseline_y": PREVIEW_BASE_SIZE * 0.7,  ## 蓝色基准线 Y 位置
		"sprite_offset_y": 0.0,       ## 精灵图 Y 偏移（拖动对齐用）
		"dragging_sprite": false,     ## 是否正在拖动精灵图
		"dragging_baseline": false,   ## 是否正在拖动基准线
		"dragging_top": false,        ## 是否正在拖动红框上边
		"dragging_bottom": false,     ## 是否正在拖动红框下边
		"drag_start_y": 0.0,          ## 拖动起始 Y
	}
	preview.draw.connect(func() -> void:
		_on_preview_draw(preview, sprite, frames, anim_name, res, edit_state)
	)
	## 编辑模式下的鼠标输入处理：拖动精灵图对齐基准线、拖动红框裁剪
	preview.gui_input.connect(func(event: InputEvent) -> void:
		_on_preview_edit_input(preview, sprite, frames, anim_name, res, edit_state, event)
	)
	col.add_child(preview)

	## 编辑模式开关按钮
	var btn_edit := Button.new()
	btn_edit.text = "编辑模式: 关"
	btn_edit.toggle_mode = true
	btn_edit.custom_minimum_size = Vector2(100, 22)
	btn_edit.add_theme_font_size_override("font_size", 10)
	btn_edit.tooltip_text = "开启后显示蓝色基准线，可拖动精灵图对齐基准线，拖动红色边框上下边调整裁剪高度"
	btn_edit.toggled.connect(func(pressed: bool) -> void:
		edit_state["enabled"] = pressed
		btn_edit.text = "编辑模式: %s" % ("开" if pressed else "关")
		preview.queue_redraw()
	)
	col.add_child(btn_edit)

	if frames != null and frames.get_frame_count(anim_name) > 0:
		sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.centered = true
		sprite.position = Vector2(PREVIEW_BASE_SIZE * 0.5, PREVIEW_BASE_SIZE * 0.5)
		_apply_preview_scale(sprite, frames, anim_name, res)
		## 根据该动画的独立翻转 override 计算预览 flip_h
		sprite.flip_h = _compute_preview_flip_h(res, anim_name)
		## #回归修复 2026-08-15：局内 play_anim 会把共享 SpriteFrames 资源的 loop 改为 false（防多连挥），
		## 控制台预览与局内走同一份 load() 缓存实例，故此处回置 loop=true 让预览循环播放（仅内存，不写盘）。
		frames.set_animation_loop(anim_name, true)
		sprite.play(anim_name)
		preview.add_child(sprite)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.3, 0.3, 0.3, 0.5)
		placeholder.size = Vector2(PREVIEW_BASE_SIZE * 0.6, PREVIEW_BASE_SIZE * 0.6)
		placeholder.position = Vector2(PREVIEW_BASE_SIZE * 0.2, PREVIEW_BASE_SIZE * 0.2)
		preview.add_child(placeholder)
		var no_anim := Label.new()
		no_anim.text = "无"
		no_anim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_anim.position = Vector2(0, PREVIEW_BASE_SIZE * 0.4)
		no_anim.size = Vector2(PREVIEW_BASE_SIZE, 20)
		no_anim.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		preview.add_child(no_anim)

	## 播放速度调整行（task 8 / #4）
	## 注意：这里调的是「动画播放速度」，与数值页的「攻速(秒)」是两个独立概念
	var speed_row := HBoxContainer.new()
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 4)
	col.add_child(speed_row)
	var speed_label := Label.new()
	speed_label.text = "播放速度:"
	speed_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	speed_label.add_theme_font_size_override("font_size", 10)
	speed_row.add_child(speed_label)
	var speed_spin := SpinBox.new()
	speed_spin.min_value = 0.1
	speed_spin.max_value = 5.0
	speed_spin.step = 0.1
	## #4：读取资源里已保存的倍率，而不是永远显示 1.0
	speed_spin.value = res.get_anim_speed(anim_name)
	speed_spin.custom_minimum_size = Vector2(56, 0)
	speed_spin.tooltip_text = "动画播放速度倍率（1.0=按原始帧率播放）\n只影响动画播多快，不影响出手频率（出手频率见数值页「攻速(秒)」）\n修改后立即写入 .tres，局内同步生效"
	speed_row.add_child(speed_spin)
	## #4：写回兵种资源并保存，局内才能吃到（旧版只改了预览的 speed_scale，进局就丢）
	speed_spin.value_changed.connect(func(v: float) -> void:
		if sprite != null and is_instance_valid(sprite):
			sprite.speed_scale = v
		res.set_anim_speed(anim_name, v)
		_save_resource(unit_id, res)
	)
	if sprite != null:
		sprite.speed_scale = speed_spin.value
	## #4：攻击动画额外提供「跟随攻速」开关——勾上=一次攻击刚好播完一遍动画（攻速加成同步影响动画）
	if anim_name == "attack":
		var sync_chk := CheckBox.new()
		sync_chk.text = "跟随攻速"
		sync_chk.button_pressed = res.attack_anim_sync_interval
		sync_chk.add_theme_font_size_override("font_size", 10)
		sync_chk.tooltip_text = "勾选：攻击动画被拉伸到与攻击间隔等长，攻速变快动画也变快\n取消：攻击动画只按上面的播放速度倍率播放，与攻速完全解耦"
		speed_row.add_child(sync_chk)
		sync_chk.toggled.connect(func(on: bool) -> void:
			res.attack_anim_sync_interval = on
			_save_resource(unit_id, res)
		)

	## 帧尺寸信息
	var frame_info := Label.new()
	if frames != null and frames.get_frame_count(anim_name) > 0:
		var tex = frames.get_frame_texture(anim_name, 0)
		if tex != null:
			frame_info.text = "%dx%d" % [tex.get_width(), tex.get_height()]
	frame_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	frame_info.add_theme_font_size_override("font_size", 11)
	col.add_child(frame_info)

	## 独立宽高调整行
	var adjust_row := HBoxContainer.new()
	adjust_row.alignment = BoxContainer.ALIGNMENT_CENTER
	adjust_row.add_theme_constant_override("separation", 4)
	col.add_child(adjust_row)

	var w_label := Label.new()
	w_label.text = "宽:"
	w_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	adjust_row.add_child(w_label)
	var w_spin := SpinBox.new()
	w_spin.min_value = 0.0
	w_spin.max_value = 200.0
	w_spin.step = 1.0
	w_spin.value = _get_anim_display_width(res, anim_name)
	w_spin.custom_minimum_size = Vector2(60, 0)
	w_spin.tooltip_text = "显示宽度（0=用通用值）"
	adjust_row.add_child(w_spin)

	var h_label := Label.new()
	h_label.text = "高:"
	h_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	adjust_row.add_child(h_label)
	var h_spin := SpinBox.new()
	h_spin.min_value = 0.0
	h_spin.max_value = 200.0
	h_spin.step = 1.0
	h_spin.value = _get_anim_display_height(res, anim_name)
	h_spin.custom_minimum_size = Vector2(60, 0)
	h_spin.tooltip_text = "显示高度（0=用通用值）"
	adjust_row.add_child(h_spin)

	## 连接信号
	if sprite != null:
		var on_changed := func(_v: float) -> void:
			_on_anim_size_changed(unit_id, res, anim_name, w_spin, h_spin, sprite)
		w_spin.value_changed.connect(on_changed)
		h_spin.value_changed.connect(on_changed)

	## 独立翻转按钮行：每个动画列单独控制翻转（绑定到 xxx_flip_override）
	if sprite != null:
		var flip_row := HBoxContainer.new()
		flip_row.alignment = BoxContainer.ALIGNMENT_CENTER
		flip_row.add_theme_constant_override("separation", 4)
		col.add_child(flip_row)

		var btn_flip := Button.new()
		var override_val: int = _get_anim_flip_override(res, anim_name)
		btn_flip.text = "翻转" if override_val == 0 else "已翻转"
		btn_flip.custom_minimum_size = Vector2(70, 0)
		btn_flip.tooltip_text = "独立翻转此动画（0=跟随默认朝向，1=强制翻转），保存到 .tres\n每个动画可独立设置不同朝向"
		btn_flip.toggle_mode = true
		btn_flip.button_pressed = (override_val == 1)
		flip_row.add_child(btn_flip)

		## 翻转按钮：切换 xxx_flip_override 并保存到 .tres，同步更新预览 flip_h
		btn_flip.toggled.connect(func(pressed: bool) -> void:
			var new_override: int = 1 if pressed else 0
			_set_anim_flip_override(res, anim_name, new_override)
			_save_resource(unit_id, res)
			btn_flip.text = "翻转" if not pressed else "已翻转"
			## 同步更新预览 sprite 的 flip_h
			if is_instance_valid(sprite):
				sprite.flip_h = _compute_preview_flip_h(res, anim_name)
		)

	## 将 sprite 引用存到 col 的 meta 中
	col.set_meta("preview_sprite", sprite)

	return col

## 获取动画的独立翻转 override 值（0=跟随默认，1=强制翻转）
func _get_anim_flip_override(res: UnitResource, anim_name: String) -> int:
	match anim_name:
		"move":
			return res.move_flip_override
		"walk":
			return res.walk_flip_override
		"attack":
			return res.attack_flip_override
		"idle":
			return res.idle_flip_override
		"sprint":
			return res.sprint_flip_override
		_:
			return 0

## 设置动画的独立翻转 override 值
func _set_anim_flip_override(res: UnitResource, anim_name: String, value: int) -> void:
	match anim_name:
		"move":
			res.move_flip_override = value
		"walk":
			res.walk_flip_override = value
		"attack":
			res.attack_flip_override = value
		"idle":
			res.idle_flip_override = value
		"sprint":
			res.sprint_flip_override = value

## 计算预览中该动画的 flip_h（预览假设 facing_dir=1 朝右）
## base_flip = (1 != default_facing)，override=1 时取反，override=0 时跟随 base_flip
func _compute_preview_flip_h(res: UnitResource, anim_name: String) -> bool:
	var default_facing: int = res.default_facing
	var base_flip: bool = (1 != default_facing)
	var override: int = _get_anim_flip_override(res, anim_name)
	if override == 1:
		return not base_flip
	return base_flip

## 获取动画显示宽度（0=用通用值）
func _get_anim_display_width(res: UnitResource, anim_name: String) -> float:
	match anim_name:
		"move":
			return res.move_display_width if res.move_display_width > 0.0 else res.display_width
		"walk":
			return res.walk_display_width if res.walk_display_width > 0.0 else res.display_width
		"attack":
			return res.attack_display_width if res.attack_display_width > 0.0 else res.display_width
		"sprint":
			return res.sprint_display_width if res.sprint_display_width > 0.0 else res.display_width
		"idle":
			return res.idle_display_width if res.idle_display_width > 0.0 else res.display_width
		_:
			return res.display_width

## 获取动画显示高度（0=用通用值）
func _get_anim_display_height(res: UnitResource, anim_name: String) -> float:
	match anim_name:
		"move":
			return res.move_display_height if res.move_display_height > 0.0 else res.display_height
		"walk":
			return res.walk_display_height if res.walk_display_height > 0.0 else res.display_height
		"attack":
			return res.attack_display_height if res.attack_display_height > 0.0 else res.display_height
		"sprint":
			return res.sprint_display_height if res.sprint_display_height > 0.0 else res.display_height
		"idle":
			return res.idle_display_height if res.idle_display_height > 0.0 else res.display_height
		_:
			return res.display_height

## 应用预览缩放
func _apply_preview_scale(sprite: AnimatedSprite2D, frames: SpriteFrames, anim_name: String, res: UnitResource) -> void:
	if frames.get_frame_count(anim_name) <= 0:
		return
	var frame_tex = frames.get_frame_texture(anim_name, 0)
	if frame_tex == null:
		return
	var fw: float = frame_tex.get_width()
	var fh: float = frame_tex.get_height()
	if fw <= 0 or fh <= 0:
		return
	var target_w: float = _get_anim_display_width(res, anim_name)
	if target_w <= 0.0:
		target_w = 40.0
	var target_h: float = _get_anim_display_height(res, anim_name)
	if target_h <= 0.0:
		target_h = 40.0
	var preview_scale: float = PREVIEW_BASE_SIZE / 40.0
	var scale_w: float = (target_w * preview_scale) / fw
	var scale_h: float = (target_h * preview_scale) / fh
	var s: float = min(scale_w, scale_h)
	sprite.scale = Vector2(s, s)

## 加载动画帧资源
## 加载后验证第一帧纹理有效性（RID 未初始化的纹理视为无效，返回 null）
func _load_anim_frames(unit_id: String, anim_name: String) -> SpriteFrames:
	var file_name: String = ANIM_FILE_MAP.get(anim_name, "")
	if file_name.is_empty():
		return null
	var path := "%s/%s/%s" % [ANIM_ROOT_DIR, unit_id, file_name]
	if ResourceLoader.exists(path):
		var frames: SpriteFrames = load(path)
		if frames == null:
			return null
		## 验证帧纹理有效性：纹理为 null 或尺寸<=0 视为未正确导入，返回 null 避免后续报错
		if frames.get_frame_count(anim_name) > 0:
			var tex = frames.get_frame_texture(anim_name, 0)
			if tex == null or tex.get_width() <= 0 or tex.get_height() <= 0:
				push_warning("[debug_units] %s 的 %s 动画帧纹理无效，可能未正确导入，跳过" % [unit_id, anim_name])
				return null
		## #13 帧图调整支持 attack2：attack2_frames.tres 里的 animation name 是 "attack"（#11 改造时统一，
		## 让 unit_base.play_anim("attack") 能播两套动画）。帧图调整 UI 上下文用 "attack2" 作 key 以示与主攻击区分，
		## 加载后克隆帧到 "attack2" 动画、移除"attack"避免和 attack_frames.tres 互串（每次加载 frames 是新对象，无副作用）。
		if anim_name == "attack2" and frames.has_animation("attack") and not frames.has_animation("attack2"):
			var src_speed: float = frames.get_animation_speed("attack")
			var src_loop: bool = frames.get_animation_loop("attack")
			var src_count: int = frames.get_frame_count("attack")
			frames.add_animation("attack2")
			frames.set_animation_speed("attack2", src_speed)
			frames.set_animation_loop("attack2", src_loop)
			for i in range(src_count):
				frames.add_frame("attack2", frames.get_frame_texture("attack", i))
			frames.remove_animation("attack")
		return frames
	return null

## 尺寸调整回调
func _on_anim_size_changed(unit_id: String, res: UnitResource, anim_name: String, w_spin: SpinBox, h_spin: SpinBox, sprite: AnimatedSprite2D) -> void:
	var new_w: float = w_spin.value
	var new_h: float = h_spin.value
	match anim_name:
		"move":
			res.move_display_width = new_w
			res.move_display_height = new_h
		"walk":
			res.walk_display_width = new_w
			res.walk_display_height = new_h
		"attack":
			res.attack_display_width = new_w
			res.attack_display_height = new_h
		"sprint":
			res.sprint_display_width = new_w
			res.sprint_display_height = new_h
		"idle":
			res.idle_display_width = new_w
			res.idle_display_height = new_h
	_save_resource(unit_id, res)
	_apply_preview_scale(sprite, sprite.sprite_frames, anim_name, res)

## ============================================================
## Tab2: 数值调试
## ============================================================

## 构建数值调试网格（按 G/D/F/N 四行分组，每行横向排列同阵营兵种，卡片样式保持垂直布局）
func _build_stats_grid() -> void:
	var grid: GridContainer = $VBox/TabContainer/StatsTab/StatsScroll/StatsGrid
	for child in grid.get_children():
		child.queue_free()
	## 按阵营分组生成四行
	for group in FACTION_GROUPS:
		var prefix: String = group[0]
		var faction_name: String = group[1]
		## 收集该阵营的所有兵种 ID
		var faction_units: Array[String] = []
		for uid in UNIT_ORDER:
			if uid.begins_with(prefix):
				faction_units.append(uid)
		## 创建一行：阵营标签 + 横向排列的兵种卡片
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		## 阵营标签
		var faction_label := Label.new()
		faction_label.text = faction_name
		faction_label.custom_minimum_size = Vector2(60, 0)
		faction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		faction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if prefix == "H":
			faction_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9, 1))  ## 英雄特殊行：青绿色
		elif faction_units.is_empty():
			faction_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))  ## 预置空分类行：灰色
		else:
			faction_label.add_theme_color_override("font_color", Color(1, 0.7, 0.3, 1))
		faction_label.add_theme_font_size_override("font_size", 16)
		row.add_child(faction_label)
		if faction_units.is_empty():
			## 预置空分类（特殊/异象等）：显示占位提示，等待后续数据加入
			var placeholder := Label.new()
			placeholder.text = "（待添加）"
			placeholder.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(placeholder)
			grid.add_child(row)
			continue
		## 添加该阵营的兵种卡片
		for unit_id in faction_units:
			var res: UnitResource = _resources.get(unit_id)
			if res == null:
				continue
			row.add_child(_create_stats_card(unit_id, res))
		grid.add_child(row)

	## #1：开始菜单控制台移除肉鸽 AI 调参区（战役与肉鸽数值数据完全隔离）。
	## 肉鸽专属控制台（#26）保留该调参区（_append_roguelike_ai_tuning 函数保留供复用）。
	## _append_roguelike_ai_tuning(grid)

## 在「数值调整」页尾追加肉鸽模式专属调参区
## 仅影响肉鸽模式：追击范围 / 牵引半径改动后对「新生成」的单位生效，下一局自动复位
func _append_roguelike_ai_tuning(grid: GridContainer) -> void:
	var section := PanelContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.14, 0.18, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	section.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	section.add_child(vbox)

	var header := Label.new()
	header.text = "—— 肉鸽 AI 调参（仅肉鸽模式生效） ——"
	header.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9, 1))
	header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(header)

	## 追击敌方范围
	var range_row := HBoxContainer.new()
	range_row.add_theme_constant_override("separation", 8)
	vbox.add_child(range_row)
	var range_label := Label.new()
	range_label.text = "追击敌方范围 (px):"
	range_label.custom_minimum_size = Vector2(150, 0)
	range_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	range_row.add_child(range_label)
	var range_spin := SpinBox.new()
	range_spin.min_value = 50.0
	range_spin.max_value = 800.0
	range_spin.step = 5.0
	range_spin.value = RoguelikeManager.chase_range_px
	range_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_spin.value_changed.connect(func(v: float) -> void:
		RoguelikeManager.chase_range_px = v
	)
	range_row.add_child(range_spin)

	## 追击牵引半径
	var leash_row := HBoxContainer.new()
	leash_row.add_theme_constant_override("separation", 8)
	vbox.add_child(leash_row)
	var leash_label := Label.new()
	leash_label.text = "追击牵引半径 (px):"
	leash_label.custom_minimum_size = Vector2(150, 0)
	leash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	leash_row.add_child(leash_label)
	var leash_spin := SpinBox.new()
	leash_spin.min_value = 50.0
	leash_spin.max_value = 1200.0
	leash_spin.step = 5.0
	leash_spin.value = RoguelikeManager.chase_leash_px
	leash_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leash_spin.value_changed.connect(func(v: float) -> void:
		RoguelikeManager.chase_leash_px = v
	)
	leash_row.add_child(leash_spin)

	var note := Label.new()
	note.text = "改动对之后生成的单位生效；进入下一局自动复位为默认值。"
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	note.add_theme_font_size_override("font_size", 11)
	vbox.add_child(note)

	## 卡牌等级（白绿蓝紫金红）图例：对应兵种 tier 1–6（仅作参考，调整请改各兵种数值卡的 tier）
	var legend_row := HBoxContainer.new()
	legend_row.add_theme_constant_override("separation", 10)
	vbox.add_child(legend_row)
	var tier_defs: Array = [
		["白", Color(0.9, 0.9, 0.9, 1), 1],
		["绿", Color(0.3, 0.9, 0.4, 1), 2],
		["蓝", Color(0.3, 0.6, 1.0, 1), 3],
		["紫", Color(0.7, 0.4, 0.9, 1), 4],
		["金", Color(1.0, 0.8, 0.2, 1), 5],
		["红", Color(1.0, 0.3, 0.3, 1), 6],
	]
	for def in tier_defs:
		var t_name: String = def[0]
		var t_color: Color = def[1]
		var t_tier: int = def[2]
		var t_label := Label.new()
		t_label.text = "%s (tier %d)" % [t_name, t_tier]
		t_label.add_theme_color_override("font_color", t_color)
		t_label.add_theme_font_size_override("font_size", 12)
		legend_row.add_child(t_label)

	grid.add_child(section)

## 创建数值调试卡片（保持垂直 VBox 布局：标题 + 各字段行）
func _create_stats_card(unit_id: String, res: UnitResource) -> Control:
	var card := PanelContainer.new()
	## #7：与尺寸卡片保持一致 —— 取消 EXPAND_FILL 改 SHRINK_BEGIN，避免英雄行两张卡之间被拉出大量空白
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	## 标题
	var title := Label.new()
	title.text = "%s %s" % [unit_id, res.display_name]
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	## 数值字段定义：(标签, 属性名, 最小值, 最大值, 步长, 是否整数)
	var fields: Array = [
		["造价", "cost", 0, 9999, 5, true],
		["生命值", "max_hp", 1, 9999, 1, true],
		["护甲", "armor_value", 0, 999, 1, true],
		["移速", "move_speed", 0.1, 20.0, 0.1, false],
		["攻击距离", "attack_range", 0.1, 20.0, 0.1, false],
		["横范围(H)", "attack_range_h", 0.0, 20.0, 0.1, false],
		["纵范围(V)", "attack_range_v", 0.0, 20.0, 0.1, false],
		["攻速(秒)", "attack_speed", 0.1, 10.0, 0.1, false],
		["后摇(秒)", "attack_recovery_time", 0.0, 5.0, 0.05, false],
	]

	for field in fields:
		var label_text: String = field[0]
		var prop_name: String = field[1]
		var min_val: float = field[2]
		var max_val: float = field[3]
		var step: float = field[4]
		var is_int: bool = field[5]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)

		var lbl2 := Label.new()
		lbl2.text = label_text
		lbl2.custom_minimum_size = Vector2(80, 0)
		lbl2.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
		row.add_child(lbl2)

		var spin := SpinBox.new()
		spin.min_value = min_val
		spin.max_value = max_val
		spin.step = step
		## 后摇字段特殊处理：资源里 -1 表示「跟随兵种类型默认」（远程 0.5 / 近战 0），
		## SpinBox 直接显示生效值，用户调校时所见即所得（改动后写入显式值）
		if prop_name == "attack_recovery_time":
			spin.value = res.get_attack_recovery_time()
		else:
			var raw_val: Variant = res.get(prop_name)
			spin.value = raw_val if raw_val != null else 0
		spin.custom_minimum_size = Vector2(100, 0)
		spin.tooltip_text = "%s（%s）%s" % [
			label_text, "整数" if is_int else "小数",
			"\n后摇=攻击周期结束后的固定僵直（中远程默认 0.5s，近战 0）" if prop_name == "attack_recovery_time" else "",
		]
		row.add_child(spin)

		## 连接值变化信号
		var on_changed := func(_v: float) -> void:
			_on_stat_changed(unit_id, res, prop_name, spin, is_int)
		spin.value_changed.connect(on_changed)

	## 连击伤害配置区域（连击次数 + 每击折叠面板 + 多类型添加）
	## 兼容旧数据：若 damage_by_type 缺失已选类型，用默认 damage 填充
	for dt in res.damage_types:
		if not res.damage_by_type.has(dt):
			res.damage_by_type[dt] = res.damage

	var combo_section := VBoxContainer.new()
	combo_section.add_theme_constant_override("separation", 4)
	vbox.add_child(combo_section)

	## 区域标题
	var combo_title := Label.new()
	combo_title.text = "连击伤害配置（连击次数=%d）" % res.attack_count
	combo_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 1))
	combo_title.add_theme_font_size_override("font_size", 13)
	combo_section.add_child(combo_title)

	## 连击次数调整
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 8)
	combo_section.add_child(count_row)
	var count_label := Label.new()
	count_label.text = "连击次数:"
	count_label.custom_minimum_size = Vector2(80, 0)
	count_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	count_row.add_child(count_label)
	var count_spin := SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 5
	count_spin.value = res.attack_count
	count_spin.custom_minimum_size = Vector2(80, 0)
	count_spin.tooltip_text = "连击次数（1~5），改变后下方行数会重建"
	count_row.add_child(count_spin)

	## 连击伤害配置容器（每次 attack_count 变化时重建）
	var combo_config_container := VBoxContainer.new()
	combo_config_container.add_theme_constant_override("separation", 4)
	combo_section.add_child(combo_config_container)

	## 构建连击伤害配置行的函数（每击折叠面板 + 多类型/多数值）
	var _build_combo_rows := func() -> void:
		for child in combo_config_container.get_children():
			child.queue_free()
		var count: int = int(count_spin.value)
		combo_title.text = "连击伤害配置（连击次数=%d）" % count
		## 确保 damage_by_hit 数组大小足够
		while res.damage_by_hit.size() < count:
			res.damage_by_hit.append({})
		for i in range(count):
			var section := VBoxContainer.new()
			section.add_theme_constant_override("separation", 4)
			combo_config_container.add_child(section)

			## 折叠标题按钮
			var hit_index: int = i
			var toggle_btn := Button.new()
			toggle_btn.text = "▼ 第%d击" % (hit_index + 1)
			toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			toggle_btn.custom_minimum_size = Vector2(200, 26)
			toggle_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
			toggle_btn.add_theme_font_size_override("font_size", 14)
			section.add_child(toggle_btn)

			## 内容容器
			var content := VBoxContainer.new()
			content.add_theme_constant_override("separation", 4)
			content.name = "content"
			section.add_child(content)

			## 折叠/展开切换
			toggle_btn.pressed.connect(func() -> void:
				content.visible = not content.visible
				toggle_btn.text = ("▼ " if content.visible else "▶ ") + "第%d击" % (hit_index + 1)
			)

			## 初始构建
			_rebuild_combo_hit_content(content, unit_id, res, hit_index)

			## 确保 damage_by_hit[hit_index] 非空时默认展开，为空时收起
			if res.damage_by_hit[hit_index] is Dictionary and (res.damage_by_hit[hit_index] as Dictionary).is_empty():
				content.visible = false
				toggle_btn.text = "▶ 第%d击" % (hit_index + 1)

	## 初始构建
	_build_combo_rows.call()

	## 连击次数变化时更新 res.attack_count 并重建下方配置行
	count_spin.value_changed.connect(func(_v: float) -> void:
		res.attack_count = int(count_spin.value)
		_save_resource(unit_id, res)
		_build_combo_rows.call()
	)

	## #5：远程技能配置（仅当 ranged_skill_cooldown > 0 时显示，如 Y1 死亡使者）
	## Y1 独有的 5 秒冷却远程暗影弹：技能冷却 / 伤害 / 射程 三项独立可调
	if res.ranged_skill_cooldown > 0.0:
		var skill_section := VBoxContainer.new()
		skill_section.add_theme_constant_override("separation", 4)
		vbox.add_child(skill_section)

		var skill_title := Label.new()
		skill_title.text = "—— 远程技能配置（每 %ss 发射一次） ——" % str(snappedf(res.ranged_skill_cooldown, 0.1))
		skill_title.add_theme_color_override("font_color", Color(0.85, 0.45, 0.95, 1))
		skill_title.add_theme_font_size_override("font_size", 13)
		skill_section.add_child(skill_title)

		var skill_fields: Array = [
			["技能冷却(秒)", "ranged_skill_cooldown", 0.0, 30.0, 0.1, false],
			["技能伤害", "ranged_skill_damage", 0, 9999, 1, true],
			["技能射程", "ranged_skill_range", 0.0, 20.0, 0.1, false],
		]
		for sf in skill_fields:
			var s_label: String = sf[0]
			var s_prop: String = sf[1]
			var s_min: float = sf[2]
			var s_max: float = sf[3]
			var s_step: float = sf[4]
			var s_int: bool = sf[5]
			var s_row := HBoxContainer.new()
			s_row.add_theme_constant_override("separation", 6)
			skill_section.add_child(s_row)
			var s_lbl := Label.new()
			s_lbl.text = s_label
			s_lbl.custom_minimum_size = Vector2(80, 0)
			s_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
			s_row.add_child(s_lbl)
			var s_spin := SpinBox.new()
			s_spin.min_value = s_min
			s_spin.max_value = s_max
			s_spin.step = s_step
			s_spin.value = float(res.get(s_prop))
			s_spin.custom_minimum_size = Vector2(100, 0)
			s_spin.tooltip_text = "远程自动技能的 %s（远程技能每 ranged_skill_cooldown 秒触发一次，命中最近敌方单位/基地造成 ranged_skill_damage 伤害，搜索半径 = ranged_skill_range × 32px）" % s_label
			s_row.add_child(s_spin)
			s_spin.value_changed.connect(func(_v: float) -> void:
				_on_stat_changed(unit_id, res, s_prop, s_spin, s_int)
				## 改冷却时同步刷新标题
				if s_prop == "ranged_skill_cooldown":
					skill_title.text = "—— 远程技能配置（每 %ss 发射一次） ——" % str(snappedf(_v, 0.1))
			)

	## ============================================================
	## 词条配置区域（底部）
	## ============================================================
	var affix_section := VBoxContainer.new()
	affix_section.add_theme_constant_override("separation", 4)
	vbox.add_child(affix_section)

	var affix_title := Label.new()
	affix_title.text = "—— 词条配置 ——"
	affix_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 1))
	affix_title.add_theme_font_size_override("font_size", 13)
	affix_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	affix_section.add_child(affix_title)

	## 已应用词条列表容器
	var affix_list_container := VBoxContainer.new()
	affix_list_container.add_theme_constant_override("separation", 2)
	affix_section.add_child(affix_list_container)

	## 可用词条资源路径
	var affix_paths: Array = [
		"res://resources/affixes/bleed.tres",
		"res://resources/affixes/poison.tres",
		"res://resources/affixes/knockback.tres",  ## #14：击退词条（命中时把目标推开一小段）
		"res://resources/affixes/frost.tres",  ## 冰霜：攻速-30% 持续1秒
		"res://resources/affixes/erosion.tres",  ## 侵蚀：伤害-10%/层 最多3层 持续到死亡
	]

## 词条列表刷新逻辑已抽离为类方法 _refresh_affix_list(container, res, unit_id)

	## 添加词条行：下拉选择 + 添加按钮
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	affix_section.add_child(add_row)

	var affix_option := OptionButton.new()
	affix_option.custom_minimum_size = Vector2(150, 0)
	affix_option.add_item("选择词条...", 0)
	var loaded_affixes: Array = []
	for i in range(affix_paths.size()):
		var path: String = affix_paths[i]
		if ResourceLoader.exists(path):
			var affix_res = load(path)
			if affix_res != null:
				affix_option.add_item(affix_res.display_name, i + 1)
				loaded_affixes.append(affix_res)
	add_row.add_child(affix_option)

	var btn_add := Button.new()
	btn_add.text = "应用词条"
	btn_add.custom_minimum_size = Vector2(80, 0)
	btn_add.add_theme_font_size_override("font_size", 11)
	btn_add.pressed.connect(func() -> void:
		var sel_idx: int = affix_option.get_selected_id()
		if sel_idx <= 0 or sel_idx > loaded_affixes.size():
			return
		var sel_affix = loaded_affixes[sel_idx - 1]
		## 检查是否已存在相同词条（避免重复添加）
		for existing in res.affixes:
			if existing != null and existing.affix_id == sel_affix.affix_id:
				return
		res.affixes.append(sel_affix)
		_save_resource(unit_id, res)
		_refresh_affix_list(affix_list_container, res, unit_id)
	)
	add_row.add_child(btn_add)

	## 初始刷新词条列表
	_refresh_affix_list(affix_list_container, res, unit_id)

	return card

## #3 连击伤害—重建单击内容面板（类型/数值/删除/添加按钮）
func _rebuild_combo_hit_content(
	content: VBoxContainer, unit_id: String, res: UnitResource, hit_index: int
) -> void:
	for child in content.get_children():
		child.queue_free()
	## 确保 damage_by_hit[hit_index] 是字典
	if hit_index >= res.damage_by_hit.size() or not (res.damage_by_hit[hit_index] is Dictionary):
		while res.damage_by_hit.size() <= hit_index:
			res.damage_by_hit.append({})
		if not (res.damage_by_hit[hit_index] is Dictionary):
			res.damage_by_hit[hit_index] = {}
	var hit_dict: Dictionary = res.damage_by_hit[hit_index]

	for dt in hit_dict.keys():
		var val: int = int(hit_dict[dt])
		var entry_row := HBoxContainer.new()
		entry_row.add_theme_constant_override("separation", 6)
		content.add_child(entry_row)

		var type_opt := OptionButton.new()
		type_opt.add_item("挥砍", 0)
		type_opt.add_item("穿刺", 1)
		type_opt.add_item("钝击", 2)
		type_opt.add_item("魔法", 3)
		type_opt.select(int(dt))
		type_opt.custom_minimum_size = Vector2(80, 0)
		entry_row.add_child(type_opt)

		var val_spin := SpinBox.new()
		val_spin.min_value = 1
		val_spin.max_value = 500
		val_spin.step = 1
		val_spin.value = val
		val_spin.custom_minimum_size = Vector2(80, 0)
		entry_row.add_child(val_spin)

		var del_btn := Button.new()
		del_btn.text = "✕"
		del_btn.custom_minimum_size = Vector2(26, 26)
		del_btn.tooltip_text = "删除此伤害类型"
		del_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 1))
		entry_row.add_child(del_btn)

		## 类型变化 → 更新键名 + 重建
		type_opt.item_selected.connect(func(new_type: int) -> void:
			var old_type: int = dt
			if old_type == new_type:
				return
			var old_val: int = int(hit_dict.get(old_type, 0))
			hit_dict.erase(old_type)
			hit_dict[new_type] = old_val
			_save_resource(unit_id, res)
			_rebuild_combo_hit_content(content, unit_id, res, hit_index)
		)

		## 数值变化 → 更新值
		val_spin.value_changed.connect(func(v: float) -> void:
			var cur_type: int = type_opt.get_selected_id()
			hit_dict[cur_type] = int(v)
			_save_resource(unit_id, res)
		)

		## 删除此条目 + 重建
		del_btn.pressed.connect(func() -> void:
			var cur_type_del: int = type_opt.get_selected_id()
			hit_dict.erase(cur_type_del)
			_save_resource(unit_id, res)
			_rebuild_combo_hit_content(content, unit_id, res, hit_index)
		)

	## 添加按钮
	var add_btn := Button.new()
	add_btn.text = "+ 添加伤害类型"
	add_btn.custom_minimum_size = Vector2(180, 26)
	add_btn.add_theme_color_override("font_color", Color(0.5, 1, 0.5, 1))
	add_btn.tooltip_text = "为第%d击添加新的伤害类型(最多4种)" % (hit_index + 1)
	add_btn.pressed.connect(func() -> void:
		for t in [0, 1, 2, 3]:
			if not hit_dict.has(t):
				hit_dict[t] = res.damage_by_type.get(t, res.damage)
				break
		_save_resource(unit_id, res)
		_rebuild_combo_hit_content(content, unit_id, res, hit_index)
	)
	if hit_dict.size() < 4:
		content.add_child(add_btn)

	## 空列表占位
	if hit_dict.is_empty():
		var hint := Label.new()
		hint.text = "（点击上方按钮添加伤害类型）"
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		content.add_child(hint)

## 数值调整回调
func _on_stat_changed(unit_id: String, res: UnitResource, prop_name: String, spin: SpinBox, is_int: bool) -> void:
	var val: float = spin.value
	if is_int:
		res.set(prop_name, int(val))
	else:
		res.set(prop_name, val)
	_save_resource(unit_id, res)

## ============================================================
## 通用方法
## ============================================================

## 保存资源到 .tres
func _save_resource(unit_id: String, res: UnitResource) -> void:
	var path := "%s/%s.tres" % [ANIM_ROOT_DIR, unit_id]
	## 使用 FLAG_REPLACE_SUBRESOURCE_PATHS 确保完整保存所有字段
	## 包括等于脚本默认值的字段（如 default_facing=-1 也会显式写入文件）
	var err := ResourceSaver.save(res, path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	if err != OK:
		push_warning("保存 %s 失败，错误码: %d" % [unit_id, err])
	## 标记资源为已修改，强制 Godot 丢弃缓存中的旧版本
	res.take_over_path(path)
	## #需求7：同步 UnitDatabase 缓存——本界面用 CACHE_MODE_IGNORE 加载的新实例修改并保存，
	## 但战斗中 unit_base.setup 是从 UnitDatabase.units/unit_list 取资源（启动时缓存的旧实例），
	## 不同步会导致「控制台改了动画速度/后摇，局内实时不生效」。
	## 这里把数据库里的旧实例替换为本次保存的新实例，局内立即吃到新值。
	var db_res: Variant = UnitDatabase.units.get(unit_id)
	if db_res != null and db_res != res:
		UnitDatabase.units[unit_id] = res
		var idx: int = UnitDatabase.unit_list.find(db_res)
		if idx >= 0:
			UnitDatabase.unit_list[idx] = res
	## 清空局内动画缩放缓存，确保控制台调校的显示尺寸立即在战场生效
	Unit.clear_anim_scale_cache()
	## #需求7：落盘校验——重新从磁盘读取并核对动画速度，保证重启后仍生效
	## （磁盘 .tres 是文本资源，运行时 load 直接解析文件，不依赖导入缓存）
	var verify: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if verify is UnitResource:
		var v: UnitResource = verify
		var speeds: Array = ["move", "attack", "sprint", "idle"]
		for s in speeds:
			if not is_equal_approx(v.get_anim_speed(s), res.get_anim_speed(s)):
				push_warning("落盘校验失败: %s %s 速度 %.2f != %.2f" % [unit_id, s, v.get_anim_speed(s), res.get_anim_speed(s)])

## ============================================================
## 配置 导出 / 导入 / 重置配置（UnitConfigIO 驱动）
## 范围：动画调整 + 数值调整 两个页面的全部可调字段；不包含帧图与音效配置
## ============================================================

## 取兵种资源（供 UnitConfigIO 序列化/反序列化，复用 _resources 缓存）
func _config_resolver(unit_id: String) -> UnitResource:
	return _resources.get(unit_id)

## 创建配置导入/导出文件对话框（导出保存 + 导入打开，各一个）
func _create_config_file_dialogs() -> void:
	## 导出：选保存路径
	var save_dialog := FileDialog.new()
	save_dialog.name = "ConfigSaveDialog"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = ["*.json ; 兵种配置 JSON"]
	save_dialog.title = "导出兵种配置"
	save_dialog.current_file = "unit_config.json"
	save_dialog.file_selected.connect(_on_export_path_selected)
	add_child(save_dialog)
	## 导入：选 JSON 文件
	var open_dialog := FileDialog.new()
	open_dialog.name = "ConfigOpenDialog"
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.filters = ["*.json ; 兵种配置 JSON"]
	open_dialog.title = "导入兵种配置"
	open_dialog.file_selected.connect(_on_import_path_selected)
	add_child(open_dialog)

## 导出按钮：弹出保存对话框
func _on_export_config_pressed() -> void:
	var d: FileDialog = get_node_or_null("ConfigSaveDialog")
	if d != null:
		d.popup_centered(Vector2i(800, 600))

## 导入按钮：弹出打开对话框
func _on_import_config_pressed(kind: String = "size") -> void:
	_pending_import_kind = kind
	var d: FileDialog = get_node_or_null("ConfigOpenDialog")
	if d != null:
		d.popup_centered(Vector2i(800, 600))

## 导出回调：把所有兵种动画+数值写为 JSON
func _on_export_path_selected(path: String) -> void:
	var json_text: String = UnitConfigIO.serialize_units(UNIT_ORDER, _config_resolver)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_config_result("导出失败", "无法写入文件:\n%s\n（错误码 %d）" % [path, FileAccess.get_open_error()])
		return
	f.store_string(json_text)
	f.close()
	_show_config_result("导出成功", "已导出 %d 个兵种的动画+数值配置:\n%s" % [UNIT_ORDER.size(), path])

## 导入回调：读取 JSON 覆盖应用到兵种资源
func _on_import_path_selected(path: String) -> void:
	if _apply_config_file(path):
		## 导入成功 = 当前使用外部数据，在对应调整页的按钮下方显示提示
		if _pending_import_kind == "stats":
			$VBox/TabContainer/StatsTab/StatsExternalHint.visible = true
		else:
			$VBox/TabContainer/SizeTab/SizeExternalHint.visible = true

## 重置配置按钮：从项目内置出厂快照恢复（出厂快照永不随导入被覆盖）
func _on_restore_config_pressed() -> void:
	_apply_config_file("res://data/unit_default_config.json", true)
	## 重置回基础配置 = 不再使用外部数据，隐藏提示
	$VBox/TabContainer/SizeTab/SizeExternalHint.visible = false
	$VBox/TabContainer/StatsTab/StatsExternalHint.visible = false

## 从 JSON 文件应用配置（导入 / 重置配置共用）
## path: 配置文件路径（支持 res:// 与绝对路径）
## is_restore: true=重置配置（结果提示语不同）
func _apply_config_file(path: String, is_restore: bool = false) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_show_config_result("读取失败", "无法打开配置文件:\n%s" % path)
		return false
	var json_text: String = f.get_as_text()
	var result: Dictionary = UnitConfigIO.apply_serialized(json_text, _config_resolver)
	if not result["ok"]:
		_show_config_result("导入失败", str(result["message"]))
		return false
	## 保存全部兵种资源（改动已写入 _resources 实例，统一落盘 .tres 并同步 UnitDatabase）
	for uid in _resources:
		var res: UnitResource = _resources[uid]
		_save_resource(uid, res)
	## 刷新调整页与帧图页，展示新配置
	_build_size_grid()
	_build_stats_grid()
	_build_frame_tab()
	var title: String = "重置配置完成" if is_restore else "导入完成"
	_show_config_result(title, "已应用 %d 个兵种，跳过 %d 个。\n动画调整 / 数值调整页已刷新。" % [int(result["applied"]), int(result["skipped"])])
	return true

## 提示对话框（复用实例避免反复创建）
func _show_config_result(title: String, text: String) -> void:
	var dialog: AcceptDialog = get_node_or_null("ConfigResultDialog")
	if dialog == null:
		dialog = AcceptDialog.new()
		dialog.name = "ConfigResultDialog"
		add_child(dialog)
	dialog.title = title
	dialog.dialog_text = text
	dialog.popup_centered()

## 刷新词条列表显示（从 _create_stats_card 抽出为类方法，规避局部 lambda 自引用导致的解析错误）
func _refresh_affix_list(container: Container, res: UnitResource, unit_id: String) -> void:
	for child in container.get_children():
		child.queue_free()
	if res.affixes.is_empty():
		var empty_label := Label.new()
		empty_label.text = "（暂无词条）"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(empty_label)
		return
	for i in range(res.affixes.size()):
		var affix_res = res.affixes[i]
		if affix_res == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		container.add_child(row)
		var name_label := Label.new()
		name_label.text = affix_res.display_name + "（" + affix_res.description + "）"
		name_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.3))
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		## 删除按钮
		var btn_del := Button.new()
		btn_del.text = "删除"
		btn_del.custom_minimum_size = Vector2(50, 0)
		btn_del.add_theme_font_size_override("font_size", 11)
		var del_idx := i
		btn_del.pressed.connect(func() -> void:
			res.affixes.remove_at(del_idx)
			_save_resource(unit_id, res)
			_refresh_affix_list(container, res, unit_id)
		)
		row.add_child(btn_del)
## 按 G/D/F/N 四行分组，每行卡片左右两部分：左=点击音效，右=出兵音效
func _build_sound_tab() -> void:
	var tab_container: TabContainer = $VBox/TabContainer
	## 动态创建 SoundTab（.tscn 中没有预定义）
	## #17：顶层改为纵向——顶部「配置/调整」双按钮 + 下方两个互斥视图
	var sound_tab := VBoxContainer.new()
	sound_tab.name = "SoundTab"
	sound_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sound_tab.add_theme_constant_override("separation", 6)
	tab_container.add_child(sound_tab)
	## 设置 Tab 标题为中文
	var tab_idx: int = tab_container.get_tab_count() - 1
	tab_container.set_tab_title(tab_idx, "音效配置")
	_sound_tab_index = tab_idx  ## 记录页签索引，供文件拖入时判断

	## #17：顶部「配置 / 调整」双按钮（互斥切换，默认停在「配置」）
	var mode_bar := HBoxContainer.new()
	mode_bar.add_theme_constant_override("separation", 8)
	sound_tab.add_child(mode_bar)
	var btn_config_mode := Button.new()
	btn_config_mode.text = "配置"
	btn_config_mode.toggle_mode = true
	btn_config_mode.button_pressed = true
	btn_config_mode.custom_minimum_size = Vector2(90, 0)
	btn_config_mode.tooltip_text = "配置：各兵种的点击/出兵/攻击音效绑定，以及音效管理（上传/改名/删除/归属分类）"
	var btn_adjust_mode := Button.new()
	btn_adjust_mode.text = "调整"
	btn_adjust_mode.toggle_mode = true
	btn_adjust_mode.custom_minimum_size = Vector2(90, 0)
	btn_adjust_mode.tooltip_text = "调整：按五阵营分类列出全部音效，为每条音效单独调节音量"
	mode_bar.add_child(btn_config_mode)
	mode_bar.add_child(btn_adjust_mode)
	var mode_hint := Label.new()
	mode_hint.text = "调整视图按阵营分类，为每条音效单独调音量"
	mode_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	mode_hint.add_theme_font_size_override("font_size", 11)
	mode_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_bar.add_child(mode_hint)

	## 配置视图（原左右分栏）：左=各兵种配置（可滚动），右=音效管理面板
	var config_box := HBoxContainer.new()
	config_box.name = "ConfigBox"
	config_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	config_box.add_theme_constant_override("separation", 10)
	sound_tab.add_child(config_box)

	## 左侧滚动区：原有的兵种音效配置内容
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	config_box.add_child(left_scroll)

	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 16)
	grid.add_theme_constant_override("h_separation", 12)
	left_scroll.add_child(grid)

	## 右侧：音效管理面板
	config_box.add_child(_create_sound_library_panel())
	## 监听操作系统文件拖入（拖动上传）
	_setup_files_dropped_handler()

	## #17：调整视图（按五阵营分类的音量拖动条，默认隐藏，首次打开时刷新）
	var adjust_box := ScrollContainer.new()
	adjust_box.name = "AdjustBox"
	adjust_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	adjust_box.visible = false
	sound_tab.add_child(adjust_box)
	_sound_adjust_box = adjust_box
	_build_sound_adjust_view()

	## #17：双按钮互斥切换（只对"按下"一侧做动作，互斥靠把另一侧 button_pressed 置 false）
	btn_config_mode.toggled.connect(func(on: bool) -> void:
		if on:
			btn_adjust_mode.button_pressed = false
			config_box.visible = true
			adjust_box.visible = false
	)
	btn_adjust_mode.toggled.connect(func(on: bool) -> void:
		if on:
			btn_config_mode.button_pressed = false
			config_box.visible = false
			adjust_box.visible = true
			## 每次打开都重新扫描音效，反映新上传/删除的文件
			_refresh_sound_adjust_view()
	)

	## 创建共享的单文件选择对话框（通过 meta 记录当前配置的 unit_id 和 sound_type）
	var file_dialog := FileDialog.new()
	file_dialog.name = "SoundFileDialog"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.wav;WAV音频", "*.mp3;MP3音频", "*.ogg;OGG音频"]
	file_dialog.title = "选择音频文件"
	sound_tab.add_child(file_dialog)
	file_dialog.file_selected.connect(_on_sound_file_selected.bind(file_dialog))

	## 创建批量上传文件对话框（多选）
	var batch_dialog := FileDialog.new()
	batch_dialog.name = "BatchSoundFileDialog"
	batch_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	batch_dialog.access = FileDialog.ACCESS_FILESYSTEM
	batch_dialog.filters = ["*.wav;WAV音频", "*.mp3;MP3音频", "*.ogg;OGG音频"]
	batch_dialog.title = "批量选择音频文件上传"
	sound_tab.add_child(batch_dialog)
	batch_dialog.files_selected.connect(_on_batch_files_selected)

	## 顶部上传区：标题 + 上传按钮
	var upload_header := HBoxContainer.new()
	upload_header.add_theme_constant_override("separation", 8)
	grid.add_child(upload_header)

	var upload_title := Label.new()
	upload_title.text = "音频上传（上传后自动存入项目 assets/audio 目录）"
	upload_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	upload_title.add_theme_font_size_override("font_size", 14)
	upload_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	upload_header.add_child(upload_title)

	var btn_single_upload := Button.new()
	btn_single_upload.text = "上传单个文件"
	btn_single_upload.custom_minimum_size = Vector2(110, 0)
	btn_single_upload.tooltip_text = "上传单个音频文件到项目。上传后可在各兵种的下拉菜单中选用。"
	btn_single_upload.pressed.connect(func() -> void:
		## 单文件上传使用共享文件对话框，无 unit_id/sound_type 绑定
		file_dialog.set_meta("current_unit_id", "")
		file_dialog.set_meta("current_sound_type", "")
		file_dialog.popup_centered(Vector2i(800, 600))
	)
	upload_header.add_child(btn_single_upload)

	var btn_batch_upload := Button.new()
	btn_batch_upload.text = "批量上传"
	btn_batch_upload.custom_minimum_size = Vector2(90, 0)
	btn_batch_upload.tooltip_text = "一次性选择多个音频文件批量上传到项目音频目录"
	btn_batch_upload.pressed.connect(func() -> void:
		batch_dialog.popup_centered(Vector2i(800, 600))
	)
	upload_header.add_child(btn_batch_upload)

	## #3：阵营分组的批量折叠操作
	var btn_expand_all := Button.new()
	btn_expand_all.text = "全部展开"
	btn_expand_all.custom_minimum_size = Vector2(80, 0)
	btn_expand_all.tooltip_text = "展开左侧全部阵营的兵种音效配置"
	btn_expand_all.pressed.connect(_set_all_sound_factions_expanded.bind(true))
	upload_header.add_child(btn_expand_all)

	var btn_collapse_all := Button.new()
	btn_collapse_all.text = "全部收起"
	btn_collapse_all.custom_minimum_size = Vector2(80, 0)
	btn_collapse_all.tooltip_text = "收起左侧全部阵营，只留阵营标题，方便快速定位"
	btn_collapse_all.pressed.connect(_set_all_sound_factions_expanded.bind(false))
	upload_header.add_child(btn_collapse_all)

	## 扫描已配置音频路径供下拉菜单使用
	_refresh_cached_sound_paths()

	## 使用说明
	var help_label := Label.new()
	help_label.text = "上传文件：音频 → res://assets/audio/shared/；各兵种点 ▾ 从已上传列表选用，或\"浏览\"上传绑定。每条出兵规则可单独指定语音（留空用默认）；每次出兵与累计出兵相撞时只播放累计；多条同类型规则随机挑一播放。"
	help_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.custom_minimum_size = Vector2(800, 0)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid.add_child(help_label)

	## 清空路径输入框引用缓存（重建 Tab 时重新填充）
	_sound_path_edits.clear()
	_sound_faction_headers.clear()

	## 按阵营分组生成四行（#3：每个阵营可单独展开/收起）
	for group in FACTION_GROUPS:
		var prefix: String = group[0]
		var faction_name: String = group[1]
		## 收集该阵营的兵种 ID
		var faction_units: Array[String] = []
		for uid in UNIT_ORDER:
			if uid.begins_with(prefix):
				faction_units.append(uid)
		if faction_units.is_empty():
			continue
		## #3：阵营标题行改为折叠按钮，点击展开/收起本阵营的全部兵种卡片
		var expanded: bool = bool(_sound_faction_expanded.get(prefix, true))
		var header := Button.new()
		header.toggle_mode = true
		header.button_pressed = expanded
		header.focus_mode = Control.FOCUS_NONE
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.text = _sound_faction_header_text(expanded, faction_name, faction_units.size())
		header.add_theme_color_override("font_color", Color(1, 0.7, 0.3, 1))
		header.add_theme_font_size_override("font_size", 14)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.tooltip_text = "点击展开 / 收起「%s」的兵种音效配置" % faction_name
		grid.add_child(header)
		_sound_faction_headers.append(header)
		## 卡片容器：收起时整体隐藏，Grid 会自动回收这块高度
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 12)
		body.visible = expanded
		grid.add_child(body)
		## 添加该阵营的兵种卡片
		for unit_id in faction_units:
			var res: UnitResource = _resources.get(unit_id)
			if res == null:
				continue
			body.add_child(_create_sound_card(unit_id, res, file_dialog))
		header.toggled.connect(func(on: bool) -> void:
			_sound_faction_expanded[prefix] = on
			if is_instance_valid(body):
				body.visible = on
			if is_instance_valid(header):
				header.text = _sound_faction_header_text(on, faction_name, faction_units.size())
		)

## 音效配置页阵营折叠标题文本（#3）
## expanded: 是否展开；faction_name: 阵营名；count: 该阵营兵种数
func _sound_faction_header_text(expanded: bool, faction_name: String, count: int) -> String:
	return "%s %s（%d 个兵种）" % ["▼" if expanded else "▶", faction_name, count]

## 音效配置页：批量展开 / 收起全部阵营（#3）
## expand: true=全部展开，false=全部收起
func _set_all_sound_factions_expanded(expand: bool) -> void:
	for header: Button in _sound_faction_headers:
		if is_instance_valid(header):
			header.button_pressed = expand  ## 触发 toggled，走统一的折叠逻辑

## ============================================================
## #17：音效「调整」视图（按五阵营分类，每条音效独立音量拖动条）
## ============================================================

## 构建调整视图骨架（说明文字 + 分组容器；条目内容由 _refresh_sound_adjust_view 填充）
func _build_sound_adjust_view() -> void:
	if _sound_adjust_box == null:
		return
	var vbox := VBoxContainer.new()
	vbox.name = "AdjustVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	_sound_adjust_box.add_child(vbox)
	var hint := Label.new()
	hint.text = "拖拽滑块调节每条音效的独立音量（叠加在音效总线音量之上）；阵营归属在「配置」视图的音效管理面板中修改。"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

## 刷新调整视图：清空旧分组，按五阵营 + 共享 重新扫描并生成音量条
func _refresh_sound_adjust_view() -> void:
	if _sound_adjust_box == null:
		return
	var vbox: VBoxContainer = _sound_adjust_box.get_node_or_null("AdjustVBox")
	if vbox == null:
		return
	## 保留第一个子节点（说明文字），其余分组全部重建
	for child in vbox.get_children():
		if child != vbox.get_child(0):
			child.queue_free()
	_refresh_cached_sound_paths()
	## 分类规则：按归属打标分入五阵营行；未打标（shared/空）的音效归入顶部「共享」行
	var groups: Array = [["shared", "共享音效"], ["G", "咕嘎"], ["D", "Doro"], ["F", "菲比丘比"], ["N", "糯糯"], ["H", "英雄"]]
	for group in groups:
		var tag: String = group[0]
		var faction_name: String = group[1]
		var paths: Array[String] = []
		for p in _cached_sound_paths:
			var att: String = SettingsManager.get_sound_attribution(p)
			if (tag == "shared" and (att == "" or att == "shared")) or (tag != "shared" and att == tag):
				paths.append(p)
		if paths.is_empty():
			continue
		vbox.add_child(_create_sound_adjust_group(faction_name, paths))

## 创建单个阵营分组的音量调节面板（#2：标题为可点击折叠按钮，收起时隐藏音量条）
func _create_sound_adjust_group(faction_name: String, paths: Array[String]) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	style.border_color = Color(0.3, 0.35, 0.45, 1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	## #2：标题改为 toggle 按钮，点击展开/收起本阵营音量条（与配置页 #3 同款交互）
	var expanded: bool = bool(_sound_adjust_expanded.get(faction_name, true))
	var title := Button.new()
	title.toggle_mode = true
	title.button_pressed = expanded
	title.focus_mode = Control.FOCUS_NONE
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.text = "%s %s（%d 条）" % ["▼" if expanded else "▶", faction_name, paths.size()]
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = "点击展开 / 收起「%s」的音量调节" % faction_name
	vbox.add_child(title)

	## 音量行容器：收起时整体隐藏
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.visible = expanded
	vbox.add_child(body)

	for path in paths:
		body.add_child(_create_sound_volume_row(path))

	title.toggled.connect(func(on: bool) -> void:
		_sound_adjust_expanded[faction_name] = on
		if is_instance_valid(body):
			body.visible = on
		if is_instance_valid(title):
			title.text = "%s %s（%d 条）" % ["▼" if on else "▶", faction_name, paths.size()]
	)
	return panel

## 创建单条音效的音量调节行（名称 + 滑块 + 百分比 + 试听）
func _create_sound_volume_row(path: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = _sound_display_label(path)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.tooltip_text = path
	name_label.add_theme_font_size_override("font_size", 11)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 2.0  ## #1：单条音效音量上限与全局一致，最高 200%
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(220, 0)
	slider.value = SettingsManager.get_sound_volume(path)
	slider.tooltip_text = "该音效的独立音量（叠加在音效总线音量之上，最高 200%）"
	row.add_child(slider)

	var percent_label := Label.new()
	percent_label.custom_minimum_size = Vector2(56, 0)
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent_label.text = "%d%%" % int(round(slider.value * 100.0))
	percent_label.add_theme_font_size_override("font_size", 11)
	row.add_child(percent_label)

	var btn_preview := Button.new()
	btn_preview.text = "▶"
	btn_preview.custom_minimum_size = Vector2(30, 0)
	btn_preview.tooltip_text = "以当前音量试听"
	btn_preview.pressed.connect(func() -> void:
		AudioManager.play_sound_path(path, true)  ## force=true 跳过同名防抖
	)
	row.add_child(btn_preview)

	slider.value_changed.connect(func(v: float) -> void:
		SettingsManager.set_sound_volume(path, v)
		percent_label.text = "%d%%" % int(round(v * 100.0))
	)
	return row

## ============================================================
## 音效管理面板（右侧栏）：预览 / 改名 / 删除 / 拖动排序 / 拖入上传
## ============================================================

## 创建右侧音效管理面板
## 返回值: 面板根节点
func _create_sound_library_panel() -> Control:  ## 定义创建音效管理面板的方法
	var panel := PanelContainer.new()
	panel.name = "SoundLibraryPanel"
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.15, 0.95)
	style.border_color = Color(0.3, 0.35, 0.45, 1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "音效管理"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)

	## 拖入上传提示区
	var drop_hint := PanelContainer.new()
	drop_hint.custom_minimum_size = Vector2(0, 52)
	var drop_style := StyleBoxFlat.new()
	drop_style.bg_color = Color(0.15, 0.18, 0.24, 0.9)
	drop_style.border_color = Color(0.45, 0.55, 0.7, 1)
	drop_style.set_border_width_all(1)
	drop_style.set_corner_radius_all(4)
	drop_hint.add_theme_stylebox_override("panel", drop_style)
	box.add_child(drop_hint)

	var drop_label := Label.new()
	drop_label.text = "把音频文件拖到窗口任意位置即可上传\n（支持 wav / mp3 / ogg，可多选）"
	drop_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9, 1))
	drop_label.add_theme_font_size_override("font_size", 11)
	drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drop_hint.add_child(drop_label)

	## 工具行：刷新 + 统计
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	box.add_child(tool_row)

	## 分类筛选：按归属（全部 / 共享 / G / D / F / N）过滤音效列表（#143）
	var filter_option := OptionButton.new()
	filter_option.custom_minimum_size = Vector2(96, 0)
	filter_option.tooltip_text = "按归属筛选音效"
	filter_option.add_item("全部", 0)
	filter_option.add_item("共享", 1)
	filter_option.add_item("G", 2)
	filter_option.add_item("D", 3)
	filter_option.add_item("F", 4)
	filter_option.add_item("N", 5)
	filter_option.add_item("Hero", 6)
	var _filter_map: Array[String] = ["all", "shared", "G", "D", "F", "N", "Hero"]
	filter_option.select(0)
	filter_option.item_selected.connect(func(idx: int) -> void:
		_sound_filter = _filter_map[idx]
		_refresh_sound_library()
	)
	tool_row.add_child(filter_option)

	_sound_library_count_label = Label.new()
	_sound_library_count_label.text = "共 0 个音效"
	_sound_library_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	_sound_library_count_label.add_theme_font_size_override("font_size", 11)
	_sound_library_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_row.add_child(_sound_library_count_label)

	var btn_refresh := Button.new()
	btn_refresh.text = "刷新"
	btn_refresh.custom_minimum_size = Vector2(56, 0)
	btn_refresh.tooltip_text = "重新扫描音频目录"
	btn_refresh.pressed.connect(_refresh_sound_library)
	tool_row.add_child(btn_refresh)

	## 条目滚动区
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_sound_library_box = VBoxContainer.new()
	_sound_library_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_library_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_sound_library_box)

	_refresh_sound_library()
	return panel

## 刷新音效管理面板的条目列表
func _refresh_sound_library() -> void:  ## 定义刷新音效库列表的方法
	if _sound_library_box == null:
		return
	for child in _sound_library_box.get_children():
		child.queue_free()
	_refresh_cached_sound_paths()
	## 按当前分类筛选（归属来源：SettingsManager.get_sound_attribution）
	var paths: Array[String] = []
	for p in _cached_sound_paths:
		if _sound_filter == "all" or _effective_attr(p) == _sound_filter:
			paths.append(p)
	if _sound_library_count_label != null:
		_sound_library_count_label.text = "共 %d 个音效" % paths.size()
	if paths.is_empty():
		var empty := Label.new()
		empty.text = "还没有音效，拖入或点上传按钮添加"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		empty.add_theme_font_size_override("font_size", 11)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sound_library_box.add_child(empty)
		return
	for path in paths:
		_sound_library_box.add_child(_create_sound_library_row(path))

## 创建单条音效管理条目
## path: 音频 res:// 路径
## 返回值: 条目根节点
func _create_sound_library_row(path: String) -> Control:  ## 定义创建音效条目的方法
	var row_panel := PanelContainer.new()
	row_panel.set_meta("sound_path", path)
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.16, 0.17, 0.21, 0.9)
	row_style.set_corner_radius_all(3)
	row_style.set_content_margin_all(4)
	row_panel.add_theme_stylebox_override("panel", row_style)
	## 拖放排序：用 drag forwarding 避免为条目单独定义子类
	row_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	row_panel.set_drag_forwarding(
		_sound_row_get_drag_data.bind(path),
		_sound_row_can_drop_data,
		_sound_row_drop_data.bind(path)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row_panel.add_child(row)

	## 拖动手柄（视觉提示，实际整行都可拖）
	var handle := Label.new()
	handle.text = "≡"
	handle.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 1))
	handle.tooltip_text = "按住拖动可调整顺序"
	row.add_child(handle)

	## 播放预览
	var btn_play := Button.new()
	btn_play.text = "▶"
	btn_play.custom_minimum_size = Vector2(28, 0)
	btn_play.tooltip_text = "试听"
	btn_play.pressed.connect(func() -> void:
		AudioManager.play_sound_path(path, true)  ## #4：试听跳过同名防抖，每次点击立即重播
	)
	row.add_child(btn_play)

	## 名称（只读展示，改名走独立按钮以免误触）
	var name_label := Label.new()
	name_label.text = _sound_display_label(path)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.tooltip_text = path
	row.add_child(name_label)

	## 改名
	var btn_rename := Button.new()
	btn_rename.text = "改名"
	btn_rename.custom_minimum_size = Vector2(48, 0)
	btn_rename.tooltip_text = "重命名该音频文件（引用会自动同步）"
	btn_rename.pressed.connect(func() -> void:
		_popup_rename_sound(path)
	)
	row.add_child(btn_rename)

	## 删除
	var btn_delete := Button.new()
	btn_delete.text = "✕"
	btn_delete.custom_minimum_size = Vector2(28, 0)
	btn_delete.tooltip_text = "删除该音频文件"
	btn_delete.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
	btn_delete.pressed.connect(func() -> void:
		_popup_delete_sound(path)
	)
	row.add_child(btn_delete)

	## 归属类型编辑（共享 / G / D / F / N），修改后持久化（#101）
	var attr_option := OptionButton.new()
	attr_option.custom_minimum_size = Vector2(74, 0)
	attr_option.tooltip_text = "归属类型：共享=所有兵种可选；G/D/F/N=仅该阵营兵种可选"
	attr_option.add_item("共享", 0)
	attr_option.add_item("G", 1)
	attr_option.add_item("D", 2)
	attr_option.add_item("F", 3)
	attr_option.add_item("N", 4)
	attr_option.add_item("Hero", 5)
	var _attr_type_map: Array[String] = ["shared", "G", "D", "F", "N", "Hero"]
	## 用有效归属决定当前选中项（hero/ 路径无显式归属时也正确显示为 Hero）
	var _cur_attr: String = _effective_attr(path)
	var _attr_idx: int = 0
	match _cur_attr:
		"shared": _attr_idx = 0
		"G": _attr_idx = 1
		"D": _attr_idx = 2
		"F": _attr_idx = 3
		"N": _attr_idx = 4
		"Hero": _attr_idx = 5
	## 先连接信号再 select：避免个别 Godot 版本 select() 立即触发 item_selected 时，
	## 把尚未持久化的默认值（共享）反向写回，覆盖已配置的 G/D/F/N 归属（#202 防御）
	attr_option.item_selected.connect(func(idx: int) -> void:
		var new_attr: String = _attr_type_map[idx]
		## 与当前已保存值一致时跳过写入：列表重建时 select() 可能重复触发，避免无谓的回写（#202）
		if SettingsManager.get_sound_attribution(path) == new_attr:
			return
		SettingsManager.set_sound_attribution(path, new_attr)
		## 归属变更后立即刷新音效管理列表，使 [共享]/[G] 等后缀实时更新（#142）
		_refresh_sound_library()
	)
	attr_option.select(_attr_idx)
	row.add_child(attr_option)

	return row_panel

## 拖放排序：开始拖动时提供数据与拖动预览
func _sound_row_get_drag_data(_at_position: Vector2, path: String) -> Variant:  ## 定义获取拖动数据的方法
	_dragging_sound_path = path
	var preview := Label.new()
	preview.text = "↕ " + path.get_file()
	preview.add_theme_color_override("font_color", Color(1, 0.9, 0.5, 1))
	set_drag_preview(preview)
	return {"type": "sound_row", "path": path}

## 拖放排序：判断是否接受落点
func _sound_row_can_drop_data(_at_position: Vector2, data: Variant) -> bool:  ## 定义判断可否放置的方法
	return data is Dictionary and data.get("type", "") == "sound_row"

## 拖放排序：完成放置，把被拖条目移动到目标条目位置
func _sound_row_drop_data(_at_position: Vector2, data: Variant, target_path: String) -> void:  ## 定义放置处理的方法
	if not (data is Dictionary):
		return
	var src_path: String = str(data.get("path", ""))
	if src_path == "" or src_path == target_path:
		return
	var order: Array[String] = []
	for p in _cached_sound_paths:
		order.append(p)
	var src_idx: int = order.find(src_path)
	if src_idx < 0:
		return
	order.remove_at(src_idx)
	var dst_idx: int = order.find(target_path)
	if dst_idx < 0:
		dst_idx = order.size()
	order.insert(dst_idx, src_path)
	SettingsManager.set_sound_library_order(order)
	_dragging_sound_path = ""
	_refresh_sound_library()

## 弹出重命名对话框
## path: 待重命名的音频 res:// 路径
func _popup_rename_sound(path: String) -> void:  ## 定义弹出重命名对话框的方法
	var dialog := ConfirmationDialog.new()
	dialog.title = "重命名音效"
	dialog.min_size = Vector2i(420, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	var tip := Label.new()
	tip.text = "输入新的文件名（保留扩展名），所有引用会自动同步："
	tip.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tip)

	var edit := LineEdit.new()
	edit.text = path.get_file()
	edit.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(edit)

	dialog.confirmed.connect(func() -> void:
		_rename_sound_file(path, edit.text.strip_edges())
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()
	edit.grab_focus()
	edit.select_all()

## 执行重命名：改磁盘文件名并同步所有引用
## old_path: 原 res:// 路径；new_name: 新文件名（含扩展名）
func _rename_sound_file(old_path: String, new_name: String) -> void:  ## 定义重命名音频文件的方法
	if new_name == "" or new_name == old_path.get_file():
		return
	if new_name.contains("/") or new_name.contains("\\"):
		push_warning("[音效管理] 文件名不能包含路径分隔符: %s" % new_name)
		return
	## 未写扩展名时沿用原扩展名
	if new_name.get_extension() == "":
		new_name += "." + old_path.get_extension()
	var dir_path: String = old_path.get_base_dir()
	var new_path: String = "%s/%s" % [dir_path, new_name]
	if FileAccess.file_exists(new_path):
		push_warning("[音效管理] 同名文件已存在，取消重命名: %s" % new_path)
		return
	var old_abs: String = ProjectSettings.globalize_path(old_path)
	var new_abs: String = ProjectSettings.globalize_path(new_path)
	var err: int = DirAccess.rename_absolute(old_abs, new_abs)
	if err != OK:
		push_warning("[音效管理] 重命名失败: %s -> %s (错误码 %d)" % [old_path, new_path, err])
		return
	## 顺带迁移 .import 文件，避免 Godot 残留旧导入元数据
	var old_import_abs: String = old_abs + ".import"
	if FileAccess.file_exists(old_import_abs):
		DirAccess.rename_absolute(old_import_abs, new_abs + ".import")
	SettingsManager.replace_sound_path(old_path, new_path)
	AudioManager.clear_all_sound_cache()
	_sync_sound_path_edits()
	_refresh_sound_library()
	print("[音效管理] 已重命名: %s -> %s" % [old_path.get_file(), new_name])

## 弹出删除确认对话框
## path: 待删除的音频 res:// 路径
func _popup_delete_sound(path: String) -> void:  ## 定义弹出删除确认的方法
	var dialog := ConfirmationDialog.new()
	dialog.title = "删除音效"
	dialog.dialog_text = "确定删除音频文件？\n%s\n\n所有引用该音效的配置会被一并清空。" % path.get_file()
	dialog.confirmed.connect(func() -> void:
		_delete_sound_file(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()

## 执行删除：删除磁盘文件并清空所有引用
## path: 待删除的音频 res:// 路径
func _delete_sound_file(path: String) -> void:  ## 定义删除音频文件的方法
	var abs_path: String = ProjectSettings.globalize_path(path)
	var err: int = DirAccess.remove_absolute(abs_path)
	if err != OK:
		push_warning("[音效管理] 删除失败: %s (错误码 %d)" % [path, err])
		return
	if FileAccess.file_exists(abs_path + ".import"):
		DirAccess.remove_absolute(abs_path + ".import")
	SettingsManager.replace_sound_path(path, "")
	AudioManager.clear_all_sound_cache()
	_sync_sound_path_edits()
	_refresh_sound_library()
	print("[音效管理] 已删除: %s" % path)

## 点击音效多配置辅助：路径数组 ↔ 文本框文本（逗号分隔）
## 存储格式为 Array[String]（可多个，播放时随机选一个），文本框用 ", " 连接展示
func _click_list_to_text(list: Variant) -> String:
	if not list is Array:
		return str(list)
	var parts: Array[String] = []
	for p in list:
		if str(p) != "":
			parts.append(str(p))
	return ", ".join(parts)

## #3：音效输入框显示「可读名称」而非 res:// 路径。
## text 显示 _sound_display_label 生成的名称（多配置用逗号连接），真实路径存 meta：
##   - 单路径模式（attack/spawn）：meta["sound_path"] = 完整路径
##   - 多配置模式（click）：meta["sound_paths"] = Array[String] 路径列表
## 手动输入路径功能保留：text_submitted 仍接收用户输入，保存后本函数刷新显示名。
func _set_sound_edit_display(edit: LineEdit, is_click: bool, value: Variant) -> void:
	if edit == null or not is_instance_valid(edit):
		return
	if is_click:
		var list: Array = []
		var src: Variant = value if value is Array else [value]
		for p in src:
			if str(p) != "":
				list.append(str(p))
		edit.set_meta("sound_paths", list)
		var names: Array[String] = []
		for p in list:
			names.append(_sound_display_label(str(p)))
		edit.text = ", ".join(names)
	else:
		var path: String = str(value)
		edit.set_meta("sound_path", path)
		edit.text = _sound_display_label(path) if path != "" else ""

## 读取音效输入框的真实路径（单路径模式）：meta 优先，回退 text（兼容旧代码路径）
func _get_sound_edit_path(edit: LineEdit) -> String:
	if edit != null and is_instance_valid(edit) and edit.has_meta("sound_path"):
		return str(edit.get_meta("sound_path"))
	return edit.text if edit != null else ""

## 读取音效输入框的真实路径列表（click 多配置模式）：meta 优先，回退 text 解析
func _get_sound_edit_paths(edit: LineEdit) -> Array:
	if edit != null and is_instance_valid(edit) and edit.has_meta("sound_paths"):
		return edit.get_meta("sound_paths")
	return _text_to_click_list(edit.text if edit != null else "")

## 文本框文本 → 路径数组（按逗号/换行分割、去空白、去重）
func _text_to_click_list(text: String) -> Array:
	var result: Array = []
	for part in text.split(","):
		var p: String = part.strip_edges()
		if p != "" and not result.has(p):
			result.append(p)
	return result

## 保存点击音效多配置并清除播放缓存
func _save_click_sound_config(unit_id: String, list: Array) -> void:
	var cfg: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
	cfg["click_sound"] = list
	SettingsManager.set_unit_sound_config(unit_id, cfg)
	AudioManager.clear_unit_sound_cache(unit_id)

## 将各兵种配置的最新值同步回界面上的输入框（改名/删除后调用）
func _sync_sound_path_edits() -> void:  ## 定义同步输入框显示的方法
	for key in _sound_path_edits:
		var parts: PackedStringArray = str(key).split("|")
		if parts.size() != 2:
			continue
		var edit: LineEdit = _sound_path_edits[key]
		if not is_instance_valid(edit):
			continue
		var cfg: Dictionary = SettingsManager.get_unit_sound_config(parts[0])
		var val: Variant = cfg.get(parts[1] + "_sound", "")
		## #3：显示可读名称，真实路径存 meta（不再把完整 res:// 路径铺在输入框里）
		_set_sound_edit_display(edit, parts[1] == "click", val)

## 注册操作系统文件拖入回调（拖动上传）
func _setup_files_dropped_handler() -> void:  ## 定义注册文件拖入回调的方法
	var win: Window = get_window()
	if win == null:
		return
	if not win.files_dropped.is_connected(_on_files_dropped):
		win.files_dropped.connect(_on_files_dropped)

## 操作系统文件拖入回调：把音频文件复制到共享目录
## files: 被拖入的绝对路径列表
func _on_files_dropped(files: PackedStringArray) -> void:  ## 定义文件拖入处理的方法
	## 仅在音效配置页生效，避免在其他页误触发
	var tab_container: TabContainer = $VBox/TabContainer
	if tab_container == null or tab_container.current_tab != _sound_tab_index:
		return
	var audio_files: PackedStringArray = PackedStringArray()
	for f in files:
		if f.get_extension().to_lower() in ["wav", "mp3", "ogg"]:
			audio_files.append(f)
	if audio_files.is_empty():
		print("[音效管理] 拖入的文件中没有支持的音频格式（wav/mp3/ogg）")
		return
	_on_batch_files_selected(audio_files)
	_refresh_sound_library()

## 为单个兵种创建音效配置卡片（左右两部分：点击音效 | 出兵音效）
func _create_sound_card(unit_id: String, res: UnitResource, file_dialog: FileDialog) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## 卡片背景样式
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	style.border_color = Color(0.4, 0.35, 0.2, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	## 兵种标题
	var title := Label.new()
	title.text = "%s %s" % [unit_id, res.display_name]
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	## 内容行：左=点击音效，右=出兵音效
	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 16)
	vbox.add_child(content_row)

	## 读取当前配置
	var config: Dictionary = SettingsManager.get_unit_sound_config(unit_id)

	## ============ 左侧：点击音效 ============
	var click_section := VBoxContainer.new()
	click_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click_section.add_theme_constant_override("separation", 4)
	content_row.add_child(click_section)

	var click_title := Label.new()
	click_title.text = "点击音效"
	click_title.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 1))
	click_title.add_theme_font_size_override("font_size", 13)
	click_section.add_child(click_title)

	## 路径行：LineEdit + 下拉菜单 + 浏览按钮
	var click_path_row := HBoxContainer.new()
	click_path_row.add_theme_constant_override("separation", 4)
	click_section.add_child(click_path_row)

	var click_edit := LineEdit.new()
	click_edit.editable = true
	var click_val: Variant = config.get("click_sound", "")
	## #3：输入框显示名称（多配置逗号连接），真实路径存 meta
	_set_sound_edit_display(click_edit, true, click_val)
	click_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click_edit.custom_minimum_size = Vector2(200, 0)
	click_edit.tooltip_text = "可配置多个点击音效（用逗号分隔），播放时随机选一个。点击输入框展开下拉菜单追加选择，或手动输入路径。"
	click_edit.placeholder_text = "多个音效用逗号分隔，随机播放..."
	## 手动输入后回车立即持久化，避免关闭窗口丢失配置（#116）
	click_edit.text_submitted.connect(func(t: String) -> void:
		var list: Array = _text_to_click_list(t)
		_save_click_sound_config(unit_id, list)
		## #3：保存后刷新显示名
		_set_sound_edit_display(click_edit, true, list)
	)
	click_path_row.add_child(click_edit)
	_sound_path_edits["%s|click" % unit_id] = click_edit
	## ▾ 下拉按钮：点击展开已上传音效列表（比靠焦点触发更可靠，避免首次点击无响应）
	var btn_click_dropdown := Button.new()
	btn_click_dropdown.text = "▾"
	btn_click_dropdown.custom_minimum_size = Vector2(34, 0)
	btn_click_dropdown.tooltip_text = "从已上传音效列表中选择点击音效"
	btn_click_dropdown.pressed.connect(func() -> void:
		_show_sound_dropdown(click_edit, unit_id, "click")
	)
	click_path_row.add_child(btn_click_dropdown)

	var btn_click_browse := Button.new()
	btn_click_browse.text = "浏览"
	btn_click_browse.custom_minimum_size = Vector2(60, 0)
	btn_click_browse.tooltip_text = "选择音频文件作为点击音效"
	btn_click_browse.pressed.connect(func() -> void:
		file_dialog.set_meta("current_unit_id", unit_id)
		file_dialog.set_meta("current_sound_type", "click")
		file_dialog.popup_centered(Vector2i(800, 600))
	)
	click_path_row.add_child(btn_click_browse)

	## 操作行：预览 + 清除
	var click_action_row := HBoxContainer.new()
	click_action_row.add_theme_constant_override("separation", 4)
	click_section.add_child(click_action_row)

	var btn_click_preview := Button.new()
	btn_click_preview.text = "播放"
	btn_click_preview.custom_minimum_size = Vector2(60, 0)
	btn_click_preview.tooltip_text = "随机试听当前配置中的一个点击音效"
	btn_click_preview.pressed.connect(func() -> void:
		var list: Array = _get_sound_edit_paths(click_edit)  ## #3：从 meta 读真实路径
		if not list.is_empty():
			AudioManager.play_sound_path(str(list[randi() % list.size()]), true)  ## #4：试听跳过防抖
	)
	click_action_row.add_child(btn_click_preview)

	var btn_click_clear := Button.new()
	btn_click_clear.text = "清除"
	btn_click_clear.custom_minimum_size = Vector2(60, 0)
	btn_click_clear.tooltip_text = "清除全部点击音效配置"
	btn_click_clear.pressed.connect(func() -> void:
		_save_click_sound_config(unit_id, [])
		## #3：清空显示与 meta
		_set_sound_edit_display(click_edit, true, [])
	)
	click_action_row.add_child(btn_click_clear)

	## ---- 攻击音效（位于"点击音效"下方，共用左侧栏，#102）----
	var attack_title := Label.new()
	attack_title.text = "攻击音效"
	attack_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5, 1))
	attack_title.add_theme_font_size_override("font_size", 13)
	click_section.add_child(attack_title)

	var attack_path_row := HBoxContainer.new()
	attack_path_row.add_theme_constant_override("separation", 4)
	click_section.add_child(attack_path_row)

	var attack_edit := LineEdit.new()
	attack_edit.editable = true
	## #3：输入框显示名称，真实路径存 meta
	_set_sound_edit_display(attack_edit, false, config.get("attack_sound", ""))
	attack_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attack_edit.custom_minimum_size = Vector2(200, 0)
	attack_edit.tooltip_text = "点击输入框展开下拉菜单，或手动输入路径。留空则使用默认 attack.mp3"
	attack_edit.placeholder_text = "输入路径或点击选择..."
	attack_edit.text_submitted.connect(func(t: String) -> void:
		## #3：优先取 meta 里的真实路径，回退到输入框文本（手动键入）
		var p: String = _get_sound_edit_path(attack_edit).strip_edges()
		if p == "":
			p = t.strip_edges()
		var cfg2: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
		cfg2["attack_sound"] = p
		SettingsManager.set_unit_sound_config(unit_id, cfg2)
		AudioManager.clear_unit_sound_cache(unit_id)
		## #3：保存后刷新显示名
		_set_sound_edit_display(attack_edit, false, p)
	)
	attack_path_row.add_child(attack_edit)
	_sound_path_edits["%s|attack" % unit_id] = attack_edit

	var btn_attack_dropdown := Button.new()
	btn_attack_dropdown.text = "▾"
	btn_attack_dropdown.custom_minimum_size = Vector2(34, 0)
	btn_attack_dropdown.tooltip_text = "从已上传音效列表中选择攻击音效"
	btn_attack_dropdown.pressed.connect(func() -> void:
		_show_sound_dropdown(attack_edit, unit_id, "attack")
	)
	attack_path_row.add_child(btn_attack_dropdown)

	var btn_attack_browse := Button.new()
	btn_attack_browse.text = "浏览"
	btn_attack_browse.custom_minimum_size = Vector2(60, 0)
	btn_attack_browse.tooltip_text = "选择音频文件作为攻击音效"
	btn_attack_browse.pressed.connect(func() -> void:
		file_dialog.set_meta("current_unit_id", unit_id)
		file_dialog.set_meta("current_sound_type", "attack")
		file_dialog.popup_centered(Vector2i(800, 600))
	)
	attack_path_row.add_child(btn_attack_browse)

	var attack_action_row := HBoxContainer.new()
	attack_action_row.add_theme_constant_override("separation", 4)
	click_section.add_child(attack_action_row)

	var btn_attack_preview := Button.new()
	btn_attack_preview.text = "播放"
	btn_attack_preview.custom_minimum_size = Vector2(60, 0)
	btn_attack_preview.tooltip_text = "试听当前配置的攻击音效"
	btn_attack_preview.pressed.connect(func() -> void:
		var p: String = _get_sound_edit_path(attack_edit)  ## #3：从 meta 读真实路径
		if p != "":
			AudioManager.play_sound_path(p, true)  ## #4：试听跳过防抖
	)
	attack_action_row.add_child(btn_attack_preview)

	var btn_attack_clear := Button.new()
	btn_attack_clear.text = "清除"
	btn_attack_clear.custom_minimum_size = Vector2(60, 0)
	btn_attack_clear.tooltip_text = "清除攻击音效配置（恢复默认 attack.mp3）"
	btn_attack_clear.pressed.connect(func() -> void:
		var cfg2: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
		cfg2["attack_sound"] = ""
		SettingsManager.set_unit_sound_config(unit_id, cfg2)
		AudioManager.clear_unit_sound_cache(unit_id)
		attack_edit.text = ""
	)
	attack_action_row.add_child(btn_attack_clear)

	## ============ 右侧：出兵音效 ============
	var spawn_section := VBoxContainer.new()
	spawn_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_section.add_theme_constant_override("separation", 4)
	content_row.add_child(spawn_section)

	var spawn_title := Label.new()
	spawn_title.text = "出兵音效"
	spawn_title.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6, 1))
	spawn_title.add_theme_font_size_override("font_size", 13)
	spawn_section.add_child(spawn_title)

	## 说明：解释顶层这个单独输入框的用途，避免与下方"出兵规则"混淆
	var spawn_hint := Label.new()
	spawn_hint.text = "默认音效：下方规则未单独指定语音时，用这条兜底。"
	spawn_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	spawn_hint.add_theme_font_size_override("font_size", 11)
	spawn_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spawn_section.add_child(spawn_hint)

	## 路径行
	var spawn_path_row := HBoxContainer.new()
	spawn_path_row.add_theme_constant_override("separation", 4)
	spawn_section.add_child(spawn_path_row)

	var spawn_edit := LineEdit.new()
	spawn_edit.editable = true
	## #3：输入框显示名称，真实路径存 meta
	_set_sound_edit_display(spawn_edit, false, config.get("spawn_sound", ""))
	spawn_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_edit.custom_minimum_size = Vector2(200, 0)
	spawn_edit.tooltip_text = "点击输入框展开下拉菜单，或手动输入路径"
	spawn_edit.placeholder_text = "输入路径或点击选择..."
	## 手动输入后回车立即持久化（#116：修复关闭窗口后出兵音效被清空）
	spawn_edit.text_submitted.connect(func(t: String) -> void:
		## #3：优先取 meta 里的真实路径（下拉/浏览选择后存的是真实路径），回退到输入框文本（手动键入）
		var p: String = _get_sound_edit_path(spawn_edit).strip_edges()
		if p == "":
			p = t.strip_edges()
		var cfg2: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
		cfg2["spawn_sound"] = p
		SettingsManager.set_unit_sound_config(unit_id, cfg2)
		AudioManager.clear_unit_sound_cache(unit_id)
		## #3：保存后刷新显示名
		_set_sound_edit_display(spawn_edit, false, p)
	)
	spawn_path_row.add_child(spawn_edit)
	_sound_path_edits["%s|spawn" % unit_id] = spawn_edit
	## ▾ 下拉按钮：点击展开已上传音效列表（比靠焦点触发更可靠，避免首次点击无响应）
	var btn_spawn_dropdown := Button.new()
	btn_spawn_dropdown.text = "▾"
	btn_spawn_dropdown.custom_minimum_size = Vector2(34, 0)
	btn_spawn_dropdown.tooltip_text = "从已上传音效列表中选择出兵音效"
	btn_spawn_dropdown.pressed.connect(func() -> void:
		_show_sound_dropdown(spawn_edit, unit_id, "spawn")
	)
	spawn_path_row.add_child(btn_spawn_dropdown)

	var btn_spawn_browse := Button.new()
	btn_spawn_browse.text = "浏览"
	btn_spawn_browse.custom_minimum_size = Vector2(60, 0)
	btn_spawn_browse.tooltip_text = "选择音频文件作为出兵音效"
	btn_spawn_browse.pressed.connect(func() -> void:
		file_dialog.set_meta("current_unit_id", unit_id)
		file_dialog.set_meta("current_sound_type", "spawn")
		file_dialog.popup_centered(Vector2i(800, 600))
	)
	spawn_path_row.add_child(btn_spawn_browse)

	## 操作行
	var spawn_action_row := HBoxContainer.new()
	spawn_action_row.add_theme_constant_override("separation", 4)
	spawn_section.add_child(spawn_action_row)

	var btn_spawn_clear := Button.new()
	btn_spawn_clear.text = "清除"
	btn_spawn_clear.custom_minimum_size = Vector2(60, 0)
	btn_spawn_clear.tooltip_text = "清除顶层默认出兵音效（规则未单独指定语音时作为兜底）"
	btn_spawn_clear.pressed.connect(func() -> void:
		var cfg: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
		cfg["spawn_sound"] = ""
		SettingsManager.set_unit_sound_config(unit_id, cfg)
		AudioManager.clear_unit_sound_cache(unit_id)
		spawn_edit.text = ""
	)
	spawn_action_row.add_child(btn_spawn_clear)

	## ============ 出兵音效规则列表（支持多条） ============
	## 规则标题行 + 添加按钮
	var rules_header := HBoxContainer.new()
	rules_header.add_theme_constant_override("separation", 4)
	spawn_section.add_child(rules_header)

	var rules_title := Label.new()
	rules_title.text = "出兵规则（可配置多条；每条可单独指定语音；相撞按优先级/随机播放）:"
	rules_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	rules_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_title.add_theme_font_size_override("font_size", 12)
	rules_header.add_child(rules_title)

	var btn_add_rule := Button.new()
	btn_add_rule.text = "+添加规则"
	btn_add_rule.custom_minimum_size = Vector2(90, 0)
	btn_add_rule.tooltip_text = "添加一条出兵音效规则（可配置多条，同时生效）"
	rules_header.add_child(btn_add_rule)

	## 规则行容器（每条规则一行）
	var rules_list_box := VBoxContainer.new()
	rules_list_box.add_theme_constant_override("separation", 3)
	spawn_section.add_child(rules_list_box)

	## 重建规则列表 UI 的闭包（增删规则后调用以刷新显示）
	## 注意：GDScript lambda 按值捕获外部变量。若 lambda 内部需要引用自身，
	## 直接捕获 _rebuild_rules 会得到 null，因此用 Array[Callable] 作为可变引用盒。
	var _rebuild_rules_box: Array[Callable] = [Callable()]
	_rebuild_rules_box[0] = func() -> void:
		## 清空旧规则行
		for child in rules_list_box.get_children():
			child.queue_free()
		var cfg: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
		var rules: Array = cfg.get("spawn_rules", [])
		if rules.is_empty():
			var empty_label := Label.new()
			empty_label.text = "  （暂无规则，默认每次出兵都播放）"
			empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
			empty_label.add_theme_font_size_override("font_size", 11)
			rules_list_box.add_child(empty_label)
			return
		for i in range(rules.size()):
			var rule: Dictionary = rules[i]
			var rule_row := HBoxContainer.new()
			rule_row.add_theme_constant_override("separation", 4)
			rules_list_box.add_child(rule_row)

			var rule_idx_label := Label.new()
			rule_idx_label.text = "%d." % (i + 1)
			rule_idx_label.custom_minimum_size = Vector2(20, 0)
			rule_idx_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
			rule_idx_label.add_theme_font_size_override("font_size", 12)
			rule_row.add_child(rule_idx_label)

			var rule_option := OptionButton.new()
			## add_item 的第二个参数是「ID」，与列表「索引」是两套编号，不能混用
			rule_option.add_item("每次播放", 0)
			rule_option.add_item("同时出N兵", 1)
			rule_option.add_item("累计出N兵", 2)
			## select() 收的是索引而非 ID：旧代码直接 select(type)，type=2 时越界导致
			## 回显永远停在"每次播放"，看起来就像配置根本没保存（#183）
			var type_idx: int = rule_option.get_item_index(int(rule.get("type", 0)))
			rule_option.select(maxi(type_idx, 0))
			rule_option.custom_minimum_size = Vector2(120, 0)
			rule_option.tooltip_text = "出兵音效播放规则：\n每次播放=每次出兵都播放\n同时出N兵=1.2秒窗口内出满N兵时播放\n累计出N兵=累计出满N兵时播放（触发后重置计数）"
			rule_row.add_child(rule_option)

			var count_label := Label.new()
			count_label.text = "N:"
			count_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
			rule_row.add_child(count_label)

			var count_spin := SpinBox.new()
			count_spin.min_value = 1
			count_spin.max_value = 99
			count_spin.step = 1
			count_spin.value = int(rule.get("count", 1))
			count_spin.custom_minimum_size = Vector2(60, 0)
			count_spin.tooltip_text = "规则N值（累计出N兵的N）"
			rule_row.add_child(count_spin)

			## 该规则单独配置的语音路径（留空则使用顶层默认出兵音效）
			var rule_sound_edit := LineEdit.new()
			rule_sound_edit.editable = true
			rule_sound_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rule_sound_edit.custom_minimum_size = Vector2(160, 0)
			rule_sound_edit.placeholder_text = "规则语音(留空用默认)"
			rule_sound_edit.tooltip_text = "本条规则单独指定的语音；留空则使用上方默认出兵音效"
			## #2：按 #3 约定，显示可读名称、真实路径存 meta（初始也要设，否则 _get_sound_edit_path 回落到 text 旧值）
			_set_sound_edit_display(rule_sound_edit, false, rule.get("sound", ""))
			## 回车提交：手输/粘贴路径也能保存（修复：原来没有 text_submitted，手输不触发保存 → 规则语音不落盘）
			var _on_rule_sound_text := func(t: String, rule_idx: int) -> void:
				var p: String = _get_sound_edit_path(rule_sound_edit).strip_edges()
				if p == "":
					p = t.strip_edges()
				var c: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
				var rs: Array = c.get("spawn_rules", [])
				if rule_idx < rs.size():
					rs[rule_idx]["sound"] = p
					c["spawn_rules"] = rs
					SettingsManager.set_unit_sound_config(unit_id, c)
					AudioManager.clear_unit_sound_cache(unit_id)
				_set_sound_edit_display(rule_sound_edit, false, p)
			rule_sound_edit.text_submitted.connect(_on_rule_sound_text.bind(i))
			rule_row.add_child(rule_sound_edit)

			var btn_rule_dropdown := Button.new()
			btn_rule_dropdown.text = "▾"
			btn_rule_dropdown.custom_minimum_size = Vector2(30, 0)
			btn_rule_dropdown.tooltip_text = "从已上传音效列表中选择本条规则的语音"
			## 规则语音下拉保存回调：通过 bind 绑定当前规则索引（修复：原来按引用捕获 i，多规则单位会把语音存到错误规则）
			var _on_rule_sound_selected := func(p: String, rule_idx: int) -> void:
				var c: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
				var rs: Array = c.get("spawn_rules", [])
				if rule_idx < rs.size():
					rs[rule_idx]["sound"] = p
					c["spawn_rules"] = rs
					SettingsManager.set_unit_sound_config(unit_id, c)
					AudioManager.clear_unit_sound_cache(unit_id)
			btn_rule_dropdown.pressed.connect(func() -> void:
				_show_sound_dropdown(rule_sound_edit, unit_id, "", _on_rule_sound_selected.bind(i))
			)
			rule_row.add_child(btn_rule_dropdown)

			## ▶ 播放本规则语音（放在删除按钮前方，满足"播放按钮在删除按钮前"的要求）
			var btn_rule_play := Button.new()
			btn_rule_play.text = "▶"
			btn_rule_play.custom_minimum_size = Vector2(34, 0)
			btn_rule_play.tooltip_text = "试听本条规则当前配置的语音"
			## 通过 bind 绑定规则索引（修复：原来按引用捕获 i，多规则单位会试听错规则）
			var _on_rule_play := func(rule_idx: int) -> void:
				var c: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
				var rs: Array = c.get("spawn_rules", [])
				var snd: String = ""
				if rule_idx < rs.size():
					snd = rs[rule_idx].get("sound", "")
				if snd == "":
					snd = c.get("spawn_sound", "")
				AudioManager.play_sound_path(snd, true)  ## #4：试听跳过防抖
			btn_rule_play.pressed.connect(_on_rule_play.bind(i))
			rule_row.add_child(btn_rule_play)

			var btn_del := Button.new()
			btn_del.text = "删除"
			btn_del.custom_minimum_size = Vector2(50, 0)
			btn_del.tooltip_text = "删除此条规则"
			rule_row.add_child(btn_del)

			## 规则类型变化回调：通过 bind 绑定当前规则索引（避免循环闭包捕获陷阱）
			var _on_type_changed := func(sel_idx: int, rule_idx: int) -> void:
				var c: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
				var rs: Array = c.get("spawn_rules", [])
				if rule_idx < rs.size():
					rs[rule_idx]["type"] = sel_idx
					c["spawn_rules"] = rs
					SettingsManager.set_unit_sound_config(unit_id, c)
			rule_option.item_selected.connect(_on_type_changed.bind(i))
			## N值变化回调：通过 bind 绑定当前规则索引
			var _on_count_changed := func(new_val: float, rule_idx: int) -> void:
				var c: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
				var rs: Array = c.get("spawn_rules", [])
				if rule_idx < rs.size():
					rs[rule_idx]["count"] = int(new_val)
					c["spawn_rules"] = rs
					SettingsManager.set_unit_sound_config(unit_id, c)
			count_spin.value_changed.connect(_on_count_changed.bind(i))
			## 删除规则回调：通过 bind 绑定当前规则索引，移除后重建 UI
			var _on_del_pressed := func(rule_idx: int) -> void:
				var c: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
				var rs: Array = c.get("spawn_rules", [])
				if rule_idx < rs.size():
					rs.remove_at(rule_idx)
					c["spawn_rules"] = rs
					SettingsManager.set_unit_sound_config(unit_id, c)
					AudioManager.clear_unit_sound_cache(unit_id)
					_rebuild_rules_box[0].call()
			btn_del.pressed.connect(_on_del_pressed.bind(i))

	## 添加规则按钮回调：新增一条默认规则并重建 UI
	btn_add_rule.pressed.connect(func() -> void:
		var c: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
		var rs: Array = c.get("spawn_rules", [])
		rs.append({"type": 0, "count": 1, "sound": ""})
		c["spawn_rules"] = rs
		SettingsManager.set_unit_sound_config(unit_id, c)
		AudioManager.clear_unit_sound_cache(unit_id)
		_rebuild_rules_box[0].call()
	)

	## 初始构建规则列表
	_rebuild_rules_box[0].call()

	return card

## 文件选择完成回调：复制音频文件到 res://assets/audio/units/{unit_id}/ 并更新配置
func _on_sound_file_selected(path: String, file_dialog: FileDialog) -> void:
	var unit_id: String = file_dialog.get_meta("current_unit_id", "")
	var sound_type: String = file_dialog.get_meta("current_sound_type", "")
	## 获取文件扩展名
	var ext: String = path.get_extension().to_lower()
	if ext == "":
		ext = "wav"
	var original_filename: String = path.get_file()
	var dest_path: String

	## 判断：如果来自顶部"上传单个文件"（unit_id 为空），存入共享目录；否则存入兵种目录
	if unit_id == "":
		## 顶部上传：存入 res://assets/audio/shared/，保留原文件名
		var shared_dir: String = "res://assets/audio/shared"
		var dir := DirAccess.open("res://")
		if dir != null:
			dir.make_dir_recursive("assets/audio/shared")
		dest_path = "%s/%s" % [shared_dir, original_filename]
		## 复制文件
		var dest_abs: String = ProjectSettings.globalize_path(dest_path)
		var err: int = DirAccess.copy_absolute(path, dest_abs)
		if err != OK:
			push_warning("复制音频文件到共享目录失败: %s -> %s (错误码: %d)" % [path, dest_path, err])
			return
		## #2：新上传音效默认标记「共享」——必须写入筛选数据源 SettingsManager.sound_attribution，
		## 否则共享筛选结果中不显示（原来只刷新缓存路径，靠物理目录兜底，筛选数据源无登记）。
		SettingsManager.set_sound_attribution(dest_path, "shared")
		_refresh_cached_sound_paths()
		print("[音效配置] 音频已上传到共享目录: %s" % dest_path)
		return

	## 兵种绑定上传：存入 res://assets/audio/units/<unit_id>/
	## 【务必保留用户原文件名】早期版本会强制改名为 click.wav / spawn.wav，
	## 导致用户上传的音频丢失原始命名。用途区分交给配置项与 UI 标签，不靠文件名。
	if sound_type == "":
		return
	var dest_filename: String = original_filename
	if dest_filename == "":  ## 极端兜底：源路径无文件名时才用类型名
		dest_filename = "%s.%s" % [sound_type, ext]
	var dest_dir: String = "res://assets/audio/units/%s" % unit_id
	## 创建目录（如果不存在）
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("assets/audio/units/%s" % unit_id)
	dest_path = "%s/%s" % [dest_dir, dest_filename]
	## 复制文件（源是 OS 绝对路径，目标需转为 OS 绝对路径）
	var dest_abs: String = ProjectSettings.globalize_path(dest_path)
	var err: int = DirAccess.copy_absolute(path, dest_abs)
	if err != OK:
		push_warning("复制音频文件失败: %s -> %s (错误码: %d)" % [path, dest_path, err])
		return
	## 更新配置
	var config: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
	if sound_type == "click":
		## 点击音效：多配置追加（去重），播放时随机
		var list: Array = _text_to_click_list(str(config.get("click_sound", "")))
		if not list.has(dest_path):
			list.append(dest_path)
		config["click_sound"] = list
	else:
		config[sound_type + "_sound"] = dest_path
	SettingsManager.set_unit_sound_config(unit_id, config)
	## 清除 AudioManager 缓存（确保下次播放时重新加载）
	AudioManager.clear_unit_sound_cache(unit_id)
	_refresh_cached_sound_paths()
	## 更新 LineEdit 显示（#3：显示名称，真实路径存 meta）
	var key: String = "%s|%s" % [unit_id, sound_type]
	if _sound_path_edits.has(key):
		var edit: LineEdit = _sound_path_edits[key]
		var cfg_val: Variant = config.get("click_sound", []) if sound_type == "click" else dest_path
		_set_sound_edit_display(edit, sound_type == "click", cfg_val)
	print("[音效配置] %s 的 %s 音效已更新: %s" % [unit_id, sound_type, dest_path])

## 批量上传文件回调：将选中的多个文件全部复制到 res://assets/audio/shared/
func _on_batch_files_selected(paths: PackedStringArray) -> void:
	var shared_dir: String = "res://assets/audio/shared"
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("assets/audio/shared")
	var count: int = 0
	for path in paths:
		var filename: String = path.get_file()
		var dest_path: String = "%s/%s" % [shared_dir, filename]
		var dest_abs: String = ProjectSettings.globalize_path(dest_path)
		var err: int = DirAccess.copy_absolute(path, dest_abs)
		if err == OK:
			count += 1
			## #2：批量上传同样写入「共享」归属到筛选数据源（否则共享筛选不显示）
			SettingsManager.set_sound_attribution(dest_path, "shared")
		else:
			push_warning("批量上传失败: %s (错误码: %d)" % [filename, err])
	_refresh_cached_sound_paths()
	print("[音效配置] 批量上传完成: %d/%d 个文件" % [count, paths.size()])

## 扫描项目中所有已配置的单位音效文件路径（仅 units/ 与 shared/ 两个目录）
## 刻意排除 assets/audio/bgm/ 背景音乐，使本页音效与游戏背景 BGM / 战斗 BGM 彻底分离
## 用于下拉菜单和自动补全
func _refresh_cached_sound_paths() -> void:
	_cached_sound_paths.clear()
	## 扫描单位音效目录、共享上传目录、Hero 专属目录；刻意排除 bgm/ 背景音乐
	_scan_sound_dir("res://assets/audio/units")
	_scan_sound_dir("res://assets/audio/shared")
	_scan_sound_dir("res://assets/audio/hero")
	_cached_sound_paths.sort()
	_apply_sound_library_order()

## 按用户在"音效管理"面板中拖动保存的顺序重排扫描结果
## 排序表中存在的项按表内顺序排前面，新增（表中没有的）文件按字母序追加到末尾
func _apply_sound_library_order() -> void:  ## 定义应用音效库自定义排序的方法
	var saved_order: Array[String] = SettingsManager.sound_library_order
	if saved_order.is_empty():
		return
	var ordered: Array[String] = []
	for p in saved_order:
		if _cached_sound_paths.has(p) and not ordered.has(p):
			ordered.append(p)
	for p in _cached_sound_paths:
		if not ordered.has(p):
			ordered.append(p)
	_cached_sound_paths = ordered

## 递归扫描指定目录下的音频文件，缓存其相对路径
func _scan_sound_dir(base_dir: String) -> void:
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path: String = base_dir + "/" + file_name
		if dir.current_is_dir():
			_scan_sound_dir(full_path)
		else:
			var ext: String = file_name.get_extension().to_lower()
			if ext in ["mp3", "wav", "ogg"]:
				## 排除兵种自带的攻击/行走/奔跑等战斗音效文件，
				## 使音效配置页下拉列表只列"点击/出兵"可配置的音频，不与战斗音效混淆
				var base_name: String = file_name.get_basename().to_lower()
				if base_name in ["attack", "walk", "run"]:
					file_name = dir.get_next()
					continue
				_cached_sound_paths.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

## 为音效路径生成人类可读的显示标签
## 规则：主体永远是【用户的原始文件名】，后缀括号内标注归属与用途，绝不改动实际文件名
##   res://assets/audio/shared/咕咕嘎嘎1.wav      → 咕咕嘎嘎1.wav  [共享]
##   res://assets/audio/units/D1/click.wav        → click.wav  [D1·点击]
##   res://assets/audio/units/D1/我的音效.wav      → 我的音效.wav  [D1]
## path: res:// 音频路径
## 返回值: 显示用标签
## 计算音频的有效归属（用于显示标签与分类筛选）
## 优先取管理面板设置的归属；未设置时按物理目录推断：
##   shared/ → "shared"，units/<id>/ → 阵营首字母，hero/ → "Hero"，其余 → ""
func _effective_attr(path: String) -> String:  ## 定义计算有效归属的方法
	var a: String = SettingsManager.get_sound_attribution(path)
	if a != "":
		return a
	if path.begins_with("res://assets/audio/hero/"):
		return "Hero"
	if path.begins_with("res://assets/audio/shared/"):
		return "shared"
	if path.begins_with("res://assets/audio/units/"):
		var rest: String = path.trim_prefix("res://assets/audio/units/")  ## <unit_id>/<file>
		var slash_idx: int = rest.find("/")
		return rest.substr(0, slash_idx) if slash_idx > 0 else rest
	return ""

func _sound_display_label(path: String) -> String:  ## 定义生成音效显示标签的方法
	var file_name: String = path.get_file()  ## 原始文件名（保持不变）
	## 归属标签以「有效归属」为准：优先用用户在管理面板设置的归属类型，
	## 未设置时按物理目录推断（shared/→共享、units/<id>/→阵营、hero/→Hero），
	## 这样把"共享"改成某阵营专属后，[共享] 后缀会立即消失（#142）
	var attr: String = _effective_attr(path)
	var tag: String = ""
	match attr:
		"shared":
			tag = "共享"
		"G", "D", "F", "N":
			tag = attr
		"Hero":
			tag = "Hero"
		_:
			pass  ## 未识别归属：无 tag
	## 兼容历史被强制改名的文件：按 basename 推断用途，展示成中文用途标签
	var base_name: String = file_name.get_basename().to_lower()
	if base_name == "click":
		tag += "·点击"
	elif base_name == "spawn":
		tag += "·出兵"
	if tag == "":
		return file_name
	return "%s  [%s]" % [file_name, tag]

## 按兵种过滤可用音效：实现音效「专享」——G 兵种下拉只出现 G 阵营 + 共享音，不混入 D/F/N 阵营专属音
## 满足「G 兵种下拉框中只有 G 音效」的需求（#185）。
## 一条音频进入某兵种下拉，满足以下任一即显示：
##   1) 物理上就在本兵种专属目录 units/<unit_id>/ 下（最严格的专属）
##   2) 在音效管理面板里把「归属」标成了本兵种所在阵营（G/D/F/N）——解决 shared/ 里混放阵营音的问题
##   3) 归属为「共享」或尚未设置归属的共享目录音频（兼容历史：没打标签的默认所有人可用）
func _filter_sounds_for_unit(unit_id: String) -> Array[String]:
	var out: Array[String] = []
	var faction: String = unit_id.left(1).to_upper() if unit_id.length() > 0 else ""
	var own_prefix: String = "res://assets/audio/units/%s/" % unit_id
	for p in _cached_sound_paths:
		## 1) 本兵种自己的物理目录：永远显示
		if p.begins_with(own_prefix):
			out.append(p)
			continue
		## 归属判定：让「专属音频」真正生效（#185）
		var attr: String = SettingsManager.get_sound_attribution(p)
		if attr == faction:
			## 2) 标成了本阵营专属 → 只有该阵营兵种能看到
			out.append(p)
			continue
		if attr == "shared":
			## 3a) 明确标为共享 → 所有人可用
			out.append(p)
			continue
		if attr == "" and p.begins_with("res://assets/audio/shared/"):
			## 3b) 未设置归属的共享音频 → 兼容旧数据，仍所有人可用
			out.append(p)
	return out

## 弹出音效下拉菜单，让用户从已上传的音频列表中选用
## line_edit: 选中后回写的输入框
## unit_id / sound_type: 顶层配置键（"click"/"spawn"），仅当 on_selected 为空时使用
## on_selected: 可选回调，传入选中路径；提供时由回调负责持久化（用于每条规则单独配置语音）
func _show_sound_dropdown(line_edit: LineEdit, unit_id: String, sound_type: String, on_selected: Callable = Callable()) -> void:
	## 刷新缓存以确保最新上传的文件被包含
	_refresh_cached_sound_paths()
	## 专享逻辑：仅展示「共享音频」+「本兵种自身目录音频」，其他兵种的上传音不外泄
	var paths: Array[String] = _cached_sound_paths
	if unit_id != "":
		paths = _filter_sounds_for_unit(unit_id)
	if paths.is_empty():
		print("[音效配置] 未找到可用的音频文件（共享或本兵种专属），请先上传")
		return
	## 移除任何旧的残留下拉菜单
	_remove_existing_dropdown()
	## 创建弹出式 PopupMenu
	var popup := PopupMenu.new()
	popup.name = "SoundDropdown"
	## 添加菜单项：每条对应一个音频文件（显示"原文件名 + 归属标签"，不暴露内部路径）
	for i in range(paths.size()):
		var p: String = paths[i]
		popup.add_item(_sound_display_label(p), i)
		## #3：不再给菜单项设置路径 tooltip（悬停会暴露完整 res:// 路径）
	## 当前值高亮（#3：用 meta 里的真实路径匹配，text 显示的是名称）
	var cur_path: String = _get_sound_edit_path(line_edit)
	if cur_path != "":
		var cur_idx: int = paths.find(cur_path)
		if cur_idx >= 0:
			popup.set_item_checked(cur_idx, true)
	## 连接选中回调：更新 LineEdit，并按模式持久化
	popup.id_pressed.connect(func(idx: int) -> void:
		## 注意：菜单项由过滤后的 paths 构建，必须用 paths 取值，不能用 _cached_sound_paths
		if idx < 0 or idx >= paths.size():
			return
		var selected_path: String = paths[idx]
		if on_selected.is_valid():
			## 规则级配置：由调用方回调决定如何保存
			## #3：显示名称，真实路径存 meta
			_set_sound_edit_display(line_edit, false, selected_path)
			on_selected.call(selected_path)
		elif sound_type == "click":
			## 点击音效：多配置模式 —— 追加选中音频（去重），播放时随机
			var list: Array = _get_sound_edit_paths(line_edit)
			if not list.has(selected_path):
				list.append(selected_path)
			_set_sound_edit_display(line_edit, true, list)
			_save_click_sound_config(unit_id, list)
		else:
			## 顶层出兵音效：单路径替换
			## #3：显示名称，真实路径存 meta
			_set_sound_edit_display(line_edit, false, selected_path)
			var config: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
			config[sound_type + "_sound"] = selected_path
			SettingsManager.set_unit_sound_config(unit_id, config)
			AudioManager.clear_unit_sound_cache(unit_id)
		popup.queue_free()
	)
	## 关闭时清理自身
	popup.popup_hide.connect(func() -> void:
		popup.queue_free()
	)
	## 弹出在 LineEdit 下方
	add_child(popup)
	var pos: Vector2 = line_edit.global_position
	var y_offset: int = int(line_edit.size.y)
	var menu_width: int = maxi(int(line_edit.size.x), 300)
	popup.popup(Rect2i(int(pos.x), int(pos.y) + y_offset, menu_width, 0))

## 移除残留的下拉菜单（清理用）
func _remove_existing_dropdown() -> void:
	for child in get_children():
		if child is PopupMenu and child.name == "SoundDropdown":
			if is_instance_valid(child):
				child.queue_free()

## ============================================================
## Tab4: 伤害测试（真实模拟环境）
## ============================================================

## 伤害类型名称
const DAMAGE_TYPE_NAMES: Array = ["挥砍", "穿刺", "钝击", "魔法"]
## 伤害类型颜色
const DAMAGE_TYPE_COLORS: Array = [Color(1, 0.6, 0.4), Color(0.6, 1, 0.6), Color(0.7, 0.7, 1), Color(0.9, 0.5, 1)]

## 测试状态：红方和蓝方兵种 ID
var _test_red_id: String = "G1"
var _test_blue_id: String = "N1"
## 真实 Unit 实例引用
var _test_red_unit: Unit = null
var _test_blue_unit: Unit = null
## 测试战场容器（Node2D，放置单位）
var _test_arena: Node2D = null
## 伤害记录列表（每条记录含攻击方/受击方/伤害类型/伤害值/扣护甲/扣HP/剩余血量）
var _test_damage_logs: Array = []
## 伤害记录显示区引用
var _test_log_container: VBoxContainer = null
## 状态显示标签引用
var _test_status_label: Label = null
## 测试模式：true=对战模式（双方互打），false=单向测试（红方打蓝方）
var _test_battle_mode: bool = true
## 攻击计数器
var _test_attack_no: int = 0
## 是否正在模拟中
var _test_simulating: bool = false

## 构建伤害测试 Tab
func _build_damage_test_tab() -> void:
	var container: VBoxContainer = $VBox/TabContainer/DamageTestTab/DamageTestContainer
	## 清空旧内容
	for child in container.get_children():
		child.queue_free()

	## 顶部说明
	var lbl_hint := Label.new()
	lbl_hint.text = "选择两个兵种进行真实对战模拟，记录每次攻击的伤害详情。攻击规则：挥砍先扣护甲再扣HP；穿刺有护甲时对HP造成20%伤害；钝击对护甲双倍伤害；魔法同时扣护甲和HP。"
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_hint.custom_minimum_size = Vector2(800, 0)
	lbl_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	lbl_hint.add_theme_font_size_override("font_size", 12)
	container.add_child(lbl_hint)

	## 兵种选择行
	var select_row := HBoxContainer.new()
	select_row.add_theme_constant_override("separation", 12)
	container.add_child(select_row)

	## 红方选择
	var red_box := VBoxContainer.new()
	red_box.add_theme_constant_override("separation", 4)
	select_row.add_child(red_box)
	var red_title := Label.new()
	red_title.text = "红方（左）"
	red_title.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 1))
	red_title.add_theme_font_size_override("font_size", 14)
	red_box.add_child(red_title)
	var red_option := OptionButton.new()
	red_option.custom_minimum_size = Vector2(200, 0)
	for uid in UNIT_ORDER:
		var res: UnitResource = _resources.get(uid)
		if res != null:
			red_option.add_item("%s %s" % [uid, res.display_name])
			red_option.set_item_metadata(red_option.item_count - 1, uid)
			if uid == _test_red_id:
				red_option.select(red_option.item_count - 1)
	red_box.add_child(red_option)
	red_option.item_selected.connect(func(idx: int) -> void:
		_test_red_id = red_option.get_item_metadata(idx)
		_setup_test_arena()
	)

	## 蓝方选择
	var blue_box := VBoxContainer.new()
	blue_box.add_theme_constant_override("separation", 4)
	select_row.add_child(blue_box)
	var blue_title := Label.new()
	blue_title.text = "蓝方（右）"
	blue_title.add_theme_color_override("font_color", Color(0.4, 0.6, 1, 1))
	blue_title.add_theme_font_size_override("font_size", 14)
	blue_box.add_child(blue_title)
	var blue_option := OptionButton.new()
	blue_option.custom_minimum_size = Vector2(200, 0)
	for uid in UNIT_ORDER:
		var res: UnitResource = _resources.get(uid)
		if res != null:
			blue_option.add_item("%s %s" % [uid, res.display_name])
			blue_option.set_item_metadata(blue_option.item_count - 1, uid)
			if uid == _test_blue_id:
				blue_option.select(blue_option.item_count - 1)
	blue_box.add_child(blue_option)
	blue_option.item_selected.connect(func(idx: int) -> void:
		_test_blue_id = blue_option.get_item_metadata(idx)
		_setup_test_arena()
	)

	## 模式切换
	var mode_box := VBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 4)
	select_row.add_child(mode_box)
	var mode_title := Label.new()
	mode_title.text = "对战模式"
	mode_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4, 1))
	mode_title.add_theme_font_size_override("font_size", 14)
	mode_box.add_child(mode_title)
	var mode_option := OptionButton.new()
	mode_option.add_item("双方互打")
	mode_option.add_item("单向测试（红打蓝）")
	mode_option.select(0 if _test_battle_mode else 1)
	mode_option.custom_minimum_size = Vector2(160, 0)
	mode_box.add_child(mode_option)
	mode_option.item_selected.connect(func(idx: int) -> void:
		_test_battle_mode = (idx == 0)
	)

	## 操作按钮行
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	container.add_child(btn_row)

	var btn_start := Button.new()
	btn_start.text = "开始对战"
	btn_start.custom_minimum_size = Vector2(100, 32)
	btn_start.tooltip_text = "部署两个兵种并开始自动对战"
	btn_row.add_child(btn_start)

	var btn_stop := Button.new()
	btn_stop.text = "停止"
	btn_stop.custom_minimum_size = Vector2(80, 32)
	btn_stop.tooltip_text = "停止当前对战"
	btn_row.add_child(btn_stop)

	var btn_reset := Button.new()
	btn_reset.text = "重置"
	btn_reset.custom_minimum_size = Vector2(80, 32)
	btn_reset.tooltip_text = "重置双方血量并清空记录"
	btn_row.add_child(btn_reset)

	var btn_clear_log := Button.new()
	btn_clear_log.text = "清空记录"
	btn_clear_log.custom_minimum_size = Vector2(90, 32)
	btn_clear_log.tooltip_text = "仅清空伤害记录"
	btn_row.add_child(btn_clear_log)

	## 战场预览区（用 ColorRect 作为背景，内部放置 Unit 实例）
	var arena_container := PanelContainer.new()
	var arena_style := StyleBoxFlat.new()
	arena_style.bg_color = Color(0.08, 0.1, 0.12, 1)
	arena_style.border_width_top = 1
	arena_style.border_width_bottom = 1
	arena_style.border_width_left = 1
	arena_style.border_width_right = 1
	arena_style.border_color = Color(0.3, 0.3, 0.3, 1)
	arena_container.add_theme_stylebox_override("panel", arena_style)
	arena_container.custom_minimum_size = Vector2(900, 200)
	container.add_child(arena_container)

	_test_arena = Node2D.new()
	## 设置 _test_arena 的 position 为 PanelContainer 内容区域的中心
	## Node2D 在 Control 中不会被自动布局，需要手动指定位置
	_test_arena.position = Vector2(450, 100)
	arena_container.add_child(_test_arena)

	## 状态显示
	_test_status_label = Label.new()
	_test_status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	_test_status_label.add_theme_font_size_override("font_size", 13)
	container.add_child(_test_status_label)

	## 伤害记录标题
	var log_title := Label.new()
	log_title.text = "伤害记录"
	log_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	log_title.add_theme_font_size_override("font_size", 14)
	container.add_child(log_title)

	## 伤害记录区（可滚动）
	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(900, 250)
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(log_scroll)

	_test_log_container = VBoxContainer.new()
	_test_log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_test_log_container.add_theme_constant_override("separation", 2)
	log_scroll.add_child(_test_log_container)

	## 连接按钮信号
	btn_start.pressed.connect(_start_test_battle)
	btn_stop.pressed.connect(_stop_test_battle)
	btn_reset.pressed.connect(_reset_test_battle)
	btn_clear_log.pressed.connect(_clear_test_logs)

	## 初始部署
	_setup_test_arena()
	_update_test_status()

## 部署测试单位到战场
func _setup_test_arena() -> void:
	## 清理旧单位
	if _test_red_unit != null and is_instance_valid(_test_red_unit):
		_test_red_unit.queue_free()
	if _test_blue_unit != null and is_instance_valid(_test_blue_unit):
		_test_blue_unit.queue_free()
	_test_red_unit = null
	_test_blue_unit = null
	_test_simulating = false
	## 创建红方单位
	var red_res: UnitResource = _resources.get(_test_red_id)
	if red_res == null:
		return
	var unit_scene = load("res://scenes/units/unit_base.tscn")
	_test_red_unit = unit_scene.instantiate()
	## 必须在 add_child 和 setup 之前设置 ai_disabled，确保 _finalize_setup 看到正确的值
	_test_red_unit.ai_disabled = true
	_test_arena.add_child(_test_red_unit)
	_test_red_unit.setup(red_res, 0)
	## 同步执行 _finalize_setup，确保 deferred 调用不会在后续手动状态切换后覆盖状态
	if _test_red_unit.has_method("_finalize_setup"):
		_test_red_unit.call("_finalize_setup")
	## 位置相对于 _test_arena（中心点 450,100），红方在左、蓝方在右
	_test_red_unit.position = Vector2(-30, 0)
	_test_red_unit.set_facing_direction(1.0)
	## 监听红方受伤信号
	if not _test_red_unit.unit_damaged.is_connected(_on_test_unit_damaged):
		_test_red_unit.unit_damaged.connect(_on_test_unit_damaged)
	## 创建蓝方单位
	var blue_res: UnitResource = _resources.get(_test_blue_id)
	if blue_res == null:
		return
	_test_blue_unit = unit_scene.instantiate()
	## 必须在 add_child 和 setup 之前设置 ai_disabled
	_test_blue_unit.ai_disabled = true
	_test_arena.add_child(_test_blue_unit)
	_test_blue_unit.setup(blue_res, 1)
	## 同步执行 _finalize_setup
	if _test_blue_unit.has_method("_finalize_setup"):
		_test_blue_unit.call("_finalize_setup")
	## 位置相对于 _test_arena（中心点 450,100），蓝方在右
	_test_blue_unit.position = Vector2(30, 0)
	_test_blue_unit.set_facing_direction(-1.0)
	## 监听蓝方受伤信号
	if not _test_blue_unit.unit_damaged.is_connected(_on_test_unit_damaged):
		_test_blue_unit.unit_damaged.connect(_on_test_unit_damaged)
	## 强制设置双方为 idle 状态，不自动移动（必须手动点击"开始对战"）
	if _test_red_unit != null and is_instance_valid(_test_red_unit):
		_test_red_unit.change_state("idle")
		_test_red_unit.velocity = Vector2.ZERO
	if _test_blue_unit != null and is_instance_valid(_test_blue_unit):
		_test_blue_unit.change_state("idle")
		_test_blue_unit.velocity = Vector2.ZERO
	_update_test_status()

## 开始对战
func _start_test_battle() -> void:
	## 如果单位无效或已死亡，重置场地后继续开始战斗
	if _test_red_unit == null or _test_blue_unit == null \
		or not is_instance_valid(_test_red_unit) or not is_instance_valid(_test_blue_unit) \
		or _test_red_unit.is_dead or _test_blue_unit.is_dead:
		_setup_test_arena()
	## 将双方放置在攻击范围内（距离 20px，近战 attack_range=1.0*40px=40px，在范围内）
	_test_red_unit.position = Vector2(-10, 0)
	_test_blue_unit.position = Vector2(10, 0)
	_test_red_unit.set_facing_direction(1.0)
	_test_blue_unit.set_facing_direction(-1.0)
	## 先重置攻击帧标志，确保新攻击周期能正常触发
	_test_red_unit.reset_attack_frame_flags()
	_test_blue_unit.reset_attack_frame_flags()
	## 清除双方 target，避免 body_entered 干扰
	_test_red_unit.target = null
	_test_blue_unit.target = null
	## 确保双方都处于 idle 状态再切换到 attack
	_test_red_unit.ai_disabled = true
	_test_blue_unit.ai_disabled = true
	_test_red_unit.change_state("idle")
	_test_blue_unit.change_state("idle")
	## 启用 AI，允许战斗
	_test_red_unit.ai_disabled = false
	if _test_battle_mode:
		_test_blue_unit.ai_disabled = false
	else:
		_test_blue_unit.ai_disabled = true
	## 设置双方互为目标
	_test_red_unit.target = _test_blue_unit
	_test_blue_unit.target = _test_red_unit
	## 标记模拟中
	_test_simulating = true
	## 进入攻击状态
	_test_red_unit.change_state("attack")
	if _test_battle_mode:
		_test_blue_unit.change_state("attack")
	else:
		_test_blue_unit.change_state("idle")
	_update_test_status()

## 停止对战
func _stop_test_battle() -> void:
	_test_simulating = false
	## 禁用 AI，停止单位行动
	if _test_red_unit != null and is_instance_valid(_test_red_unit):
		_test_red_unit.ai_disabled = true
		_test_red_unit.target = null
		_test_red_unit.velocity = Vector2.ZERO
		_test_red_unit.clear_all_affixes()  ## 清除所有词条效果，防止持续掉血
		_test_red_unit.change_state("idle")
		_test_red_unit.move_and_slide()  ## 立即应用 velocity=0
		## 强制停止精灵动画播放，防止"停止后还在攻击"的错觉
		if _test_red_unit.unit_sprite != null:
			_test_red_unit.unit_sprite.stop()
	if _test_blue_unit != null and is_instance_valid(_test_blue_unit):
		_test_blue_unit.ai_disabled = true
		_test_blue_unit.target = null
		_test_blue_unit.velocity = Vector2.ZERO
		_test_blue_unit.clear_all_affixes()
		_test_blue_unit.change_state("idle")
		_test_blue_unit.move_and_slide()
		## 强制停止精灵动画播放
		if _test_blue_unit.unit_sprite != null:
			_test_blue_unit.unit_sprite.stop()
	_update_test_status()

## 重置对战
func _reset_test_battle() -> void:
	_test_simulating = false
	_test_damage_logs.clear()
	_test_attack_no = 0
	_refresh_log_display()
	_setup_test_arena()

## 清空伤害记录
func _clear_test_logs() -> void:
	_test_damage_logs.clear()
	_test_attack_no = 0
	_refresh_log_display()

## 单位受伤信号回调（记录伤害）
## unit: 受伤的单位
## damage: 伤害值
func _on_test_unit_damaged(unit: Unit, damage: int) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_test_attack_no += 1
	## 判断攻击方
	var attacker_name: String = "未知"
	var defender_name: String = unit.unit_resource.display_name if unit.unit_resource != null else "未知"
	if unit == _test_red_unit:
		defender_name = "红方 " + defender_name
		attacker_name = "蓝方 " + (_test_blue_unit.unit_resource.display_name if _test_blue_unit != null and _test_blue_unit.unit_resource != null else "")
	else:
		defender_name = "蓝方 " + defender_name
		attacker_name = "红方 " + (_test_red_unit.unit_resource.display_name if _test_red_unit != null and _test_red_unit.unit_resource != null else "")
	## 记录当前血量护甲
	var hp_after: int = unit.current_hp
	var armor_after: int = unit.current_armor
	var max_hp: int = unit.unit_resource.max_hp if unit.unit_resource != null else 100
	var max_armor: int = unit.unit_resource.armor_value if unit.unit_resource != null else 0
	_test_damage_logs.append({
		"attack_no": _test_attack_no,
		"attacker": attacker_name,
		"defender": defender_name,
		"damage": damage,
		"hp_after": hp_after,
		"max_hp": max_hp,
		"armor_after": armor_after,
		"max_armor": max_armor,
		"dead": hp_after <= 0,
	})
	_refresh_log_display()
	_update_test_status()
	## 若一方死亡，停止模拟
	if hp_after <= 0:
		_test_simulating = false
		_stop_test_battle()

## 更新状态显示
func _update_test_status() -> void:
	if _test_status_label == null:
		return
	var red_res: UnitResource = _resources.get(_test_red_id)
	var blue_res: UnitResource = _resources.get(_test_blue_id)
	if red_res == null or blue_res == null:
		_test_status_label.text = "请选择兵种"
		return
	var red_hp: String = "?"
	var red_armor: String = "?"
	var blue_hp: String = "?"
	var blue_armor: String = "?"
	if _test_red_unit != null and is_instance_valid(_test_red_unit):
		red_hp = "%d/%d" % [_test_red_unit.current_hp, red_res.max_hp]
		red_armor = "%d/%d" % [_test_red_unit.current_armor, red_res.armor_value]
	if _test_blue_unit != null and is_instance_valid(_test_blue_unit):
		blue_hp = "%d/%d" % [_test_blue_unit.current_hp, blue_res.max_hp]
		blue_armor = "%d/%d" % [_test_blue_unit.current_armor, blue_res.armor_value]
	var state_str: String = "进行中" if _test_simulating else "已停止"
	_test_status_label.text = "[%s] 红方 %s（HP:%s 护甲:%s） vs 蓝方 %s（HP:%s 护甲:%s）" % [
		state_str, red_res.display_name, red_hp, red_armor,
		blue_res.display_name, blue_hp, blue_armor]

## 刷新伤害记录显示（表格形式：红方记录红色边框，蓝方记录蓝色边框）
func _refresh_log_display() -> void:
	if _test_log_container == null:
		return
	## 清空旧内容
	for child in _test_log_container.get_children():
		child.queue_free()
	if _test_damage_logs.is_empty():
		var empty_label := Label.new()
		empty_label.text = "（暂无伤害记录）"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_test_log_container.add_child(empty_label)
		return
	## 表格表头
	var headers: Array = ["序号", "攻击方", "防守方", "伤害", "剩余血量", "剩余护甲"]
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	for h in headers:
		var lbl := Label.new()
		lbl.text = h
		lbl.custom_minimum_size = Vector2(80, 0)
		lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_row.add_child(lbl)
	_test_log_container.add_child(header_row)
	## 表格数据行
	for log in _test_damage_logs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		## 判断攻击方颜色：红方=红色边框，蓝方=蓝色边框
		var attacker_str: String = String(log["attacker"])
		var is_red_attacker: bool = attacker_str.begins_with("红方")
		var border_color: Color = Color(1, 0.3, 0.3, 0.8) if is_red_attacker else Color(0.3, 0.5, 1.0, 0.8)
		var style := StyleBoxFlat.new()
		style.border_color = border_color
		style.set_border_width_all(2)
		style.set_corner_radius_all(2)
		style.content_margin_left = 2
		style.content_margin_right = 2
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		row.add_theme_stylebox_override("panel", style)
		## 各列数据
		var values: Array = [
			str(log["attack_no"]),
			log["attacker"],
			log["defender"],
			str(log["damage"]),
			"%d/%d" % [int(log["hp_after"]), int(log["max_hp"])],
			"%d/%d" % [int(log["armor_after"]), int(log["max_armor"])],
		]
		for v in values:
			var lbl := Label.new()
			lbl.text = v
			lbl.custom_minimum_size = Vector2(80, 0)
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			## 死亡行的伤害列用红色文字
			if bool(log["dead"]) and v == str(log["damage"]):
				lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			row.add_child(lbl)
		_test_log_container.add_child(row)

## 全部重置（尺寸 Tab 重置宽高为 0；帧图 Tab 重载文件）
func _on_reset_pressed() -> void:
	var current_tab: int = $VBox/TabContainer.current_tab
	if current_tab == 0:
		## 尺寸 Tab：重置宽高为 0（回退到通用值 40）
		for unit_id in UNIT_ORDER:
			var res: UnitResource = _resources.get(unit_id)
			if res == null:
				continue
			res.move_display_width = 0.0
			res.move_display_height = 0.0
			res.walk_display_width = 0.0
			res.walk_display_height = 0.0
			res.attack_display_width = 0.0
			res.attack_display_height = 0.0
			res.sprint_display_width = 0.0
			res.sprint_display_height = 0.0
			res.idle_display_width = 0.0
			res.idle_display_height = 0.0
			## #4：播放速度倍率一并复位
			res.move_anim_speed = 1.0
			res.attack_anim_speed = 1.0
			res.sprint_anim_speed = 1.0
			res.idle_anim_speed = 1.0
			res.attack_anim_sync_interval = true
			_save_resource(unit_id, res)
		_build_size_grid()
	elif current_tab == 2:
		## 帧图 Tab：重载文件（放弃当前修改）
		_on_frame_load()
	else:
		## 数值 Tab：重置为默认值
		for unit_id in UNIT_ORDER:
			var res: UnitResource = _resources.get(unit_id)
			if res == null:
				continue
			res.cost = 50
			res.max_hp = 100
			res.armor_value = 10
			res.move_speed = 2.5
			res.damage = 10
			res.attack_range = 1.0
			res.attack_speed = 1.5
			res.attack_count = 1
			_save_resource(unit_id, res)
		_build_stats_grid()

## 返回主菜单
func _on_back_pressed() -> void:
	GameManager.change_scene_with_loading("res://scenes/ui/main_menu.tscn")

## ============================================================
## Tab3: 帧图可视化与编辑
## ============================================================

## 帧图编辑相关状态
var _frame_unit_id: String = ""  ## 当前编辑的单位 ID
var _frame_anim_name: String = "move"  ## 当前编辑的动画名
var _frame_edits: Array = []  ## 帧区域列表，每项为 {x,y,w,h,ox,oy}
var _frame_sheet_tex: Texture2D = null  ## 精灵图贴图
var _sheet_scale: float = 1.0  ## 精灵图预览缩放（贴图像素 → 预览像素）
var _sheet_offset: Vector2 = Vector2.ZERO  ## 精灵图预览偏移（居中）
var _frame_selected: int = -1  ## 选中的帧索引
var _sheet_preview: Control = null  ## 精灵图预览控件
var _frame_list_vbox: VBoxContainer = null  ## 帧列表容器
var _frame_font: Font = null  ## 缓存字体（用于帧索引绘制）
var _anim_sprite: AnimatedSprite2D = null  ## 动画播放预览精灵
var _btn_anim_pause: Button = null  ## 动画预览暂停按钮（开启后停播、展示选中帧）
var _overlap_preview: Control = null  ## 重叠预览控件
var _overlap_dragging: bool = false  ## 是否正在拖动重叠预览中的帧（调整偏移）
var _overlap_drag_start: Vector2 = Vector2.ZERO  ## 拖动起始位置
var _overlap_drag_off_start: Vector2 = Vector2.ZERO  ## 拖动起始时的帧偏移
## 边框拖动缩放状态
var _overlap_resize_dragging: bool = false  ## 是否正在拖动边框手柄缩放
var _overlap_resize_handle: int = -1  ## 当前拖动的手柄编号（0~3 四角，4~7 四边中点）
var _overlap_resize_start_size: Vector2 = Vector2.ZERO  ## 拖动起始时的帧 w/h
var _overlap_resize_start_pos: Vector2 = Vector2.ZERO  ## 拖动起始鼠标位置
## 边框手柄半边长（像素）
const OVERLAP_HANDLE_HALF: float = 6.0
## 重叠预览的缩放系数缓存：加载帧时锁定一次，之后拖动缩放单个帧不影响整体缩放
var _overlap_scale_cached: float = -1.0
## 撤销栈：保存每次修改前的 _frame_edits 深拷贝快照（最多 50 步）
var _undo_stack: Array = []
const UNDO_MAX_SIZE: int = 50
## 攻击判定/音效帧配置（仅 attack 动画显示）
## 改为可视化帧条选择：在动画预览下方显示所有帧缩略图，点击选择"判定帧"或"音效帧"
var _hit_sound_bar: VBoxContainer = null  ## 判定/音效配置栏（VBox 容纳 [模式按钮行 + 提示 + 帧条]）
var _btn_hit_sound_apply: Button = null  ## 应用按钮
## 帧条相关
var _frame_bar: Control = null  ## 帧条预览控件（绘制所有帧缩略图）
var _btn_mode_hit: Button = null  ## 模式按钮：设置判定帧
var _btn_mode_sound: Button = null  ## 模式按钮：设置音效帧
var _btn_clear_hit: Button = null  ## 清除判定帧按钮
var _btn_clear_sound: Button = null  ## 清除音效帧按钮
var _hit_sound_mode: String = "hit"  ## 当前选择模式："hit"=判定帧, "sound"=音效帧
var _cur_hit_frame: int = -1  ## 当前编辑中的判定帧（-1=未设置）
var _cur_hit_frames: Array[int] = []  ## 多段连击判定帧（按点击顺序对应第1击、第2击...）
var _cur_sound_frame: int = -1  ## 当前编辑中的音效帧（-1=未设置）
var _hs_hint_label: Label = null  ## 配置栏提示标签（显示当前模式 + 已选帧）
## 帧条布局常量
const FRAME_BAR_PAD: float = 8.0  ## 帧条内边距
const FRAME_BAR_CELL_W: float = 80.0  ## 每帧单元格宽度
const FRAME_BAR_CELL_H: float = 80.0  ## 每帧单元格高度
const FRAME_BAR_GAP: float = 4.0  ## 帧之间间隔
const FRAME_BAR_MARK_H: float = 14.0  ## 顶部标记区高度（用于绘制判定/音效标记）
## 可选动画列表
const FRAME_ANIM_OPTIONS: Array[String] = ["idle", "walk", "move", "sprint", "attack", "attack2"]
## 重叠预览区域的固定显示尺寸（帧内容基准大小）
const OVERLAP_PREVIEW_SIZE: float = 200.0

## 构建帧图编辑 Tab
func _build_frame_tab() -> void:
	var tab: VBoxContainer = $VBox/TabContainer/FrameTab
	for child in tab.get_children():
		child.queue_free()
	## 顶栏：单位选择 + 动画选择 + 加载/保存/重载（固定在顶部，不随滚动）
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	tab.add_child(top_bar)

	var lbl_unit := Label.new()
	lbl_unit.text = "单位:"
	lbl_unit.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	top_bar.add_child(lbl_unit)
	var opt_unit := OptionButton.new()
	opt_unit.custom_minimum_size = Vector2(120, 0)
	for uid in UNIT_ORDER:
		opt_unit.add_item(uid)
	opt_unit.select(0)
	_frame_unit_id = UNIT_ORDER[0]
	top_bar.add_child(opt_unit)

	var lbl_anim := Label.new()
	lbl_anim.text = "动画:"
	lbl_anim.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	top_bar.add_child(lbl_anim)
	var opt_anim := OptionButton.new()
	opt_anim.custom_minimum_size = Vector2(100, 0)
	for anim_name in FRAME_ANIM_OPTIONS:
		opt_anim.add_item(anim_name)
	opt_anim.select(FRAME_ANIM_OPTIONS.find("move"))
	_frame_anim_name = "move"
	top_bar.add_child(opt_anim)

	var btn_load := Button.new()
	btn_load.text = "加载"
	btn_load.custom_minimum_size = Vector2(80, 0)
	btn_load.tooltip_text = "加载该单位动画的精灵图与帧区域"
	top_bar.add_child(btn_load)

	var btn_save := Button.new()
	btn_save.text = "保存"
	btn_save.custom_minimum_size = Vector2(80, 0)
	btn_save.tooltip_text = "保存帧顺序与区域到 .tres 文件"
	top_bar.add_child(btn_save)

	var btn_reload := Button.new()
	btn_reload.text = "重载"
	btn_reload.custom_minimum_size = Vector2(80, 0)
	btn_reload.tooltip_text = "重新从文件加载（放弃当前修改）"
	top_bar.add_child(btn_reload)

	var btn_add := Button.new()
	btn_add.text = "添加帧"
	btn_add.custom_minimum_size = Vector2(80, 0)
	btn_add.tooltip_text = "在末尾添加一帧（默认区域 0,0,400,400）"
	top_bar.add_child(btn_add)

	## 提示文字
	var hint := Label.new()
	hint.text = "提示：上方动画预览实时播放；中为精灵图（点击添加/选中帧）；下为重叠预览（拖动选中帧调整位置）；右侧列表可调整顺序与区域"
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	hint.add_theme_font_size_override("font_size", 12)
	tab.add_child(hint)

	## 攻击判定/音效帧配置栏（仅 attack 动画显示）
	## 改为可视化帧条选择：VBox 容纳 [模式按钮行 + 帧条]
	_hit_sound_bar = VBoxContainer.new()
	_hit_sound_bar.add_theme_constant_override("separation", 4)
	_hit_sound_bar.visible = false  ## 默认隐藏，仅 attack 动画时显示
	tab.add_child(_hit_sound_bar)

	## 第一行：模式切换 + 清除 + 应用 + 试听
	var hs_top_row := HBoxContainer.new()
	hs_top_row.add_theme_constant_override("separation", 6)
	_hit_sound_bar.add_child(hs_top_row)

	_btn_mode_hit = Button.new()
	_btn_mode_hit.text = "设置判定帧"
	_btn_mode_hit.custom_minimum_size = Vector2(110, 28)
	_btn_mode_hit.tooltip_text = "点击后进入“判定帧”模式：在下方帧条点击某一帧，将其设为攻击命中帧"
	_btn_mode_hit.toggle_mode = true
	_btn_mode_hit.pressed.connect(_on_mode_hit_pressed)
	hs_top_row.add_child(_btn_mode_hit)

	_btn_mode_sound = Button.new()
	_btn_mode_sound.text = "设置音效帧"
	_btn_mode_sound.custom_minimum_size = Vector2(110, 28)
	_btn_mode_sound.tooltip_text = "点击后进入“音效帧”模式：在下方帧条点击某一帧，将其设为音效播放帧"
	_btn_mode_sound.toggle_mode = true
	_btn_mode_sound.pressed.connect(_on_mode_sound_pressed)
	hs_top_row.add_child(_btn_mode_sound)

	_btn_clear_hit = Button.new()
	_btn_clear_hit.text = "清除判定"
	_btn_clear_hit.custom_minimum_size = Vector2(80, 28)
	_btn_clear_hit.tooltip_text = "清除判定帧（恢复为 -1，使用时间比例自动命中）"
	_btn_clear_hit.pressed.connect(_on_clear_hit_pressed)
	hs_top_row.add_child(_btn_clear_hit)

	_btn_clear_sound = Button.new()
	_btn_clear_sound.text = "清除音效"
	_btn_clear_sound.custom_minimum_size = Vector2(80, 28)
	_btn_clear_sound.tooltip_text = "清除音效帧（恢复为 -1，使用 attack_sound_timing 比例播放）"
	_btn_clear_sound.pressed.connect(_on_clear_sound_pressed)
	hs_top_row.add_child(_btn_clear_sound)

	_btn_hit_sound_apply = Button.new()
	_btn_hit_sound_apply.text = "应用到 .tres"
	_btn_hit_sound_apply.custom_minimum_size = Vector2(110, 28)
	_btn_hit_sound_apply.tooltip_text = "把当前判定/音效帧配置写入兵种的 .tres 资源文件"
	_btn_hit_sound_apply.pressed.connect(_on_hit_sound_apply)
	hs_top_row.add_child(_btn_hit_sound_apply)

	## 攻击音效改为随预览动画播放到“音效帧”时自动同步播放（见 _on_anim_preview_frame_changed，#147）

	## 第二行：提示标签（显示当前模式 + 当前已选帧）
	_hs_hint_label = Label.new()
	_hs_hint_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	_hs_hint_label.add_theme_font_size_override("font_size", 14)
	_hit_sound_bar.add_child(_hs_hint_label)

	## 多段连击判定帧说明
	var hs_combo_hint := Label.new()
	hs_combo_hint.text = "连击兵种可点击多个帧设置多段判定（按点击顺序对应第1击、第2击...），双击帧可清空多段判定"
	hs_combo_hint.add_theme_color_override("font_color", Color(0.6, 0.75, 1, 1))
	hs_combo_hint.add_theme_font_size_override("font_size", 12)
	_hit_sound_bar.add_child(hs_combo_hint)

	## 第三行：帧条（包裹在 ScrollContainer 中，支持左右滚动）
	var frame_bar_scroll := ScrollContainer.new()
	frame_bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	frame_bar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame_bar_scroll.custom_minimum_size = Vector2(820, 110)
	_hit_sound_bar.add_child(frame_bar_scroll)

	_frame_bar = Control.new()
	_frame_bar.custom_minimum_size = Vector2(820, 110)
	_frame_bar.draw.connect(_on_frame_bar_draw)
	_frame_bar.gui_input.connect(_on_frame_bar_input)
	_frame_bar.resized.connect(_frame_bar.queue_redraw)
	_frame_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	frame_bar_scroll.add_child(_frame_bar)

	## 主区域：用 ScrollContainer 包裹，防止内容超出窗口（顶栏/提示/配置栏固定，主区域可滚动）
	var main_scroll := ScrollContainer.new()
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tab.add_child(main_scroll)

	## 主区域：左侧三预览 + 右帧列表
	var main := HBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	main_scroll.add_child(main)

	## 左侧：垂直排列三个预览面板
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 6)
	main.add_child(left_vbox)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 1)

	## 1. 动画播放预览面板（宽度增加到 820，高度 280，确保 400×400 帧缩放后完整显示）
	var anim_panel := PanelContainer.new()
	anim_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_panel.custom_minimum_size = Vector2(820, 280)
	anim_panel.add_theme_stylebox_override("panel", panel_style)
	left_vbox.add_child(anim_panel)

	## 内层 VBox：标题栏 + 预览区，避免 PanelContainer 直接管理子节点导致布局错乱
	var anim_vbox := VBoxContainer.new()
	anim_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	anim_vbox.add_theme_constant_override("separation", 4)
	anim_panel.add_child(anim_vbox)

	## 标题行：标题（左） + 暂停按钮（右）
	var anim_title_row := HBoxContainer.new()
	anim_title_row.add_theme_constant_override("separation", 8)
	anim_vbox.add_child(anim_title_row)

	var anim_title := Label.new()
	anim_title.text = "动画播放预览"
	anim_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	anim_title.add_theme_font_size_override("font_size", 13)
	anim_title_row.add_child(anim_title)

	## 暂停按钮：开启后停播动画并定格展示当前选中的帧（attack 分栏时左右两侧都定格）
	_btn_anim_pause = Button.new()
	_btn_anim_pause.text = "暂停"
	_btn_anim_pause.custom_minimum_size = Vector2(70, 26)
	_btn_anim_pause.toggle_mode = true
	_btn_anim_pause.tooltip_text = "点击后停止播放动画，切换为展示当前选中的帧（再点恢复循环播放）"
	_btn_anim_pause.toggled.connect(_on_anim_pause_toggled)
	anim_title_row.add_child(_btn_anim_pause)

	## 攻击帧（整条）预览区域
	var anim_preview := Control.new()
	anim_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	anim_preview.custom_minimum_size = Vector2(800, 220)
	anim_vbox.add_child(anim_preview)

	_anim_sprite = AnimatedSprite2D.new()
	_anim_sprite.centered = true
	_anim_sprite.position = Vector2(400, 110)
	anim_preview.add_child(_anim_sprite)
	## 面板尺寸稳定后再重算攻击预览的缩放与居中
	anim_preview.resized.connect(func() -> void:
		if _anim_sprite.sprite_frames != null:
			_apply_anim_preview_scale(_anim_sprite.sprite_frames)
	)
	## 帧预览播放到“音效帧”时自动同步播放攻击音效（替代原“试听音效”按钮，#147）
	_anim_sprite.frame_changed.connect(_on_anim_preview_frame_changed)

	## 2. 精灵图预览面板
	var sheet_panel := PanelContainer.new()
	sheet_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_panel.custom_minimum_size = Vector2(640, 260)
	sheet_panel.add_theme_stylebox_override("panel", panel_style)
	left_vbox.add_child(sheet_panel)

	## 内层 VBox：标题栏 + 预览区
	var sheet_vbox := VBoxContainer.new()
	sheet_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_vbox.add_theme_constant_override("separation", 4)
	sheet_panel.add_child(sheet_vbox)

	var sheet_title := Label.new()
	sheet_title.text = "精灵图（单击选中并暂停播放，双击取消选中，点击空白添加帧）"
	sheet_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	sheet_title.add_theme_font_size_override("font_size", 13)
	sheet_vbox.add_child(sheet_title)

	_sheet_preview = Control.new()
	_sheet_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet_preview.custom_minimum_size = Vector2(620, 200)
	_sheet_preview.draw.connect(_on_sheet_preview_draw)
	_sheet_preview.gui_input.connect(_on_sheet_preview_input)
	sheet_vbox.add_child(_sheet_preview)

	## 3. 重叠预览面板（所有帧叠加 + 基准线 + 可拖动调整位置）
	var overlap_panel := PanelContainer.new()
	overlap_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlap_panel.custom_minimum_size = Vector2(640, 300)
	overlap_panel.add_theme_stylebox_override("panel", panel_style)
	left_vbox.add_child(overlap_panel)

	## 内层 VBox：标题栏 + 预览区，避免 PanelContainer 直接管理子节点导致布局错乱
	var overlap_vbox := VBoxContainer.new()
	overlap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlap_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlap_vbox.add_theme_constant_override("separation", 4)
	overlap_panel.add_child(overlap_vbox)

	var overlap_title_bar := HBoxContainer.new()
	overlap_title_bar.add_theme_constant_override("separation", 8)
	overlap_vbox.add_child(overlap_title_bar)

	var overlap_title := Label.new()
	overlap_title.text = "重叠预览（拖动选中帧调整位置，底部基准线为地面参考）"
	overlap_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	overlap_title.add_theme_font_size_override("font_size", 13)
	overlap_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlap_title_bar.add_child(overlap_title)

	var btn_reset_off := Button.new()
	btn_reset_off.text = "重置偏移"
	btn_reset_off.custom_minimum_size = Vector2(90, 0)
	btn_reset_off.tooltip_text = "清零所有帧的偏移 ox/oy（会弹出二次确认）"
	overlap_title_bar.add_child(btn_reset_off)
	btn_reset_off.pressed.connect(_on_reset_offsets_clicked)

	_overlap_preview = Control.new()
	_overlap_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlap_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	## 设置最小尺寸，确保布局完成前 size 不会塌缩为 0
	_overlap_preview.custom_minimum_size = Vector2(620, 240)
	_overlap_preview.draw.connect(_on_overlap_preview_draw)
	_overlap_preview.gui_input.connect(_on_overlap_preview_input)
	overlap_vbox.add_child(_overlap_preview)

	## 右侧：帧列表
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(440, 480)
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(list_scroll)

	_frame_list_vbox = VBoxContainer.new()
	_frame_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_list_vbox.add_theme_constant_override("separation", 12)
	list_scroll.add_child(_frame_list_vbox)

	## 连接信号
	opt_unit.item_selected.connect(func(idx: int) -> void:
		_frame_unit_id = UNIT_ORDER[idx]
		_on_frame_load()
	)
	opt_anim.item_selected.connect(func(idx: int) -> void:
		_frame_anim_name = FRAME_ANIM_OPTIONS[idx]
		_on_frame_load()
	)
	btn_load.pressed.connect(_on_frame_load)
	btn_save.pressed.connect(_on_frame_save)
	btn_reload.pressed.connect(_on_frame_load)
	btn_add.pressed.connect(_on_frame_add)

	## 自动加载初始单位动画
	_on_frame_load()

## 攻击判定/音效帧配置：根据当前动画类型显示/隐藏配置栏，并加载现有值
func _update_hit_sound_bar() -> void:
	if _hit_sound_bar == null:
		return
	## 仅 attack 动画显示配置栏
	_hit_sound_bar.visible = _frame_anim_name.begins_with("attack")  ## 攻击/攻击2 都显示判定栏
	if not _hit_sound_bar.visible:
		return
	## 加载当前单位的 .tres 资源，读取已配置的字段值到 _cur_hit_frame / _cur_hit_frames / _cur_sound_frame
	var res := _load_unit_resource(_frame_unit_id)
	if res == null:
		_cur_hit_frame = -1
		_cur_hit_frames.clear()
		_cur_sound_frame = -1
	else:
		## #18-5（2026-08-15）：attack2（备用攻击动画）用独立的判定/音效帧字段。
		## 此前无条件读 attack_hit_frame_start / attack_sound_frame——在 attack2 下编辑时
		## 加载的是攻击一的值，应用时又写回攻击一 → 两套动画判定帧互相覆盖（用户反馈「帧图调整
		## 设定判定帧仍影响另一个攻击动画」）。
		var is_alt: bool = _frame_anim_name == "attack2"
		_cur_hit_frame = res.attack_hit_frame_start_alt if is_alt else res.attack_hit_frame_start
		## 加载多段连击判定帧（字段为 Array[int]，用 assign 显式拷贝，避免泛型 Array 赋给 Array[int] 报错）
		_cur_hit_frames.assign(res.attack_hit_frames)
		_cur_sound_frame = res.attack_sound_frame_alt if is_alt else res.attack_sound_frame
	## 默认进入"判定帧"模式
	_hit_sound_mode = "hit"
	_refresh_mode_buttons()
	_refresh_hs_hint()
	_frame_bar.queue_redraw()

## 加载指定单位的 UnitResource（从 .tres 文件读取）
func _load_unit_resource(unit_id: String) -> UnitResource:
	if unit_id == "":
		return null
	var path := "%s/%s.tres" % [ANIM_ROOT_DIR, unit_id]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as UnitResource

## 应用按钮：把当前 _cur_hit_frame / _cur_sound_frame 写入兵种的 .tres 资源文件
func _on_hit_sound_apply() -> void:
	if _frame_unit_id == "":
		push_warning("未选择单位")
		return
	var res := _load_unit_resource(_frame_unit_id)
	if res == null:
		push_warning("无法加载单位资源: %s" % _frame_unit_id)
		return
	## #18-5（2026-08-15）：attack2 独立判定/音效帧——按当前动画分流写入 alt 字段，
	## 与 _update_hit_sound_bar 的读取分流配对，两套攻击动画判定帧彻底互不干扰。
	var is_alt: bool = _frame_anim_name == "attack2"
	## 保存多段连击判定帧：显式拷贝到新 Array[int]，避免 duplicate() 返回泛型 Array 赋给 Array[int] 报错
	var hit_dst: Array[int] = []
	hit_dst.assign(_cur_hit_frames)
	res.attack_hit_frames = hit_dst
	## 如果多段判定帧非空，清空旧的单帧配置（避免冲突）
	if not _cur_hit_frames.is_empty():
		if is_alt:
			res.attack_hit_frame_start_alt = -1
		else:
			res.attack_hit_frame_start = -1
	else:
		if is_alt:
			res.attack_hit_frame_start_alt = _cur_hit_frame
		else:
			res.attack_hit_frame_start = _cur_hit_frame
	if is_alt:
		res.attack_sound_frame_alt = _cur_sound_frame
	else:
		res.attack_sound_frame = _cur_sound_frame
	var path := "%s/%s.tres" % [ANIM_ROOT_DIR, _frame_unit_id]
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_warning("保存失败，错误码: %d" % err)
	else:
		print("已应用 %s 的判定/音效帧配置（动画=%s）：单帧=%d, 音效帧=%d" % [
			_frame_unit_id, _frame_anim_name,
			res.attack_hit_frame_start_alt if is_alt else res.attack_hit_frame_start,
			res.attack_sound_frame_alt if is_alt else res.attack_sound_frame])

## ============================================================
## 攻击判定/音效帧 - 可视化帧条交互
## ============================================================

## 切换到"判定帧"模式
func _on_mode_hit_pressed() -> void:
	_hit_sound_mode = "hit"
	_refresh_mode_buttons()
	_refresh_hs_hint()

## 切换到"音效帧"模式
func _on_mode_sound_pressed() -> void:
	_hit_sound_mode = "sound"
	_refresh_mode_buttons()
	_refresh_hs_hint()

## 清除判定帧
func _on_clear_hit_pressed() -> void:
	_cur_hit_frame = -1
	_cur_hit_frames.clear()
	_refresh_hs_hint()
	_frame_bar.queue_redraw()

## 清除音效帧
func _on_clear_sound_pressed() -> void:
	_cur_sound_frame = -1
	_refresh_hs_hint()
	_frame_bar.queue_redraw()

## 刷新两个模式按钮的按下状态与配色
func _refresh_mode_buttons() -> void:
	if _btn_mode_hit != null:
		_btn_mode_hit.button_pressed = (_hit_sound_mode == "hit")
		## 判定帧模式 = 红色高亮
		if _hit_sound_mode == "hit":
			_btn_mode_hit.add_theme_color_override("font_color", Color(1, 0.4, 0.3, 1))
			_btn_mode_hit.add_theme_color_override("font_hover_color", Color(1, 0.5, 0.4, 1))
		else:
			_btn_mode_hit.remove_theme_color_override("font_color")
			_btn_mode_hit.remove_theme_color_override("font_hover_color")
	if _btn_mode_sound != null:
		_btn_mode_sound.button_pressed = (_hit_sound_mode == "sound")
		## 音效帧模式 = 蓝色高亮
		if _hit_sound_mode == "sound":
			_btn_mode_sound.add_theme_color_override("font_color", Color(0.4, 0.8, 1, 1))
			_btn_mode_sound.add_theme_color_override("font_hover_color", Color(0.5, 0.85, 1, 1))
		else:
			_btn_mode_sound.remove_theme_color_override("font_color")
			_btn_mode_sound.remove_theme_color_override("font_hover_color")

## 刷新提示标签：显示当前模式 + 已选帧
func _refresh_hs_hint() -> void:
	if _hs_hint_label == null:
		return
	var mode_text: String = "判定帧" if _hit_sound_mode == "hit" else "音效帧"
	var hit_text: String
	if not _cur_hit_frames.is_empty():
		## 显示多段判定帧列表，如 [5, 15]
		hit_text = str(_cur_hit_frames)
	elif _cur_hit_frame < 0:
		hit_text = "未设置（用时间比例自动）"
	else:
		hit_text = "第 %d 帧" % _cur_hit_frame
	var sound_text: String = "未设置（用 attack_sound_timing）" if _cur_sound_frame < 0 else "第 %d 帧" % _cur_sound_frame
	_hs_hint_label.text = "当前模式: %s    |    判定帧: %s    |    音效帧: %s" % [mode_text, hit_text, sound_text]

## 计算第 idx 帧在帧条上的矩形区域（单元格）
func _frame_bar_cell_rect(idx: int) -> Rect2:
	var x: float = FRAME_BAR_PAD + idx * (FRAME_BAR_CELL_W + FRAME_BAR_GAP)
	var y: float = FRAME_BAR_PAD + FRAME_BAR_MARK_H
	return Rect2(x, y, FRAME_BAR_CELL_W, FRAME_BAR_CELL_H)

## 根据鼠标 x 坐标计算点击到的帧索引（-1 = 没点中任何帧）
func _frame_bar_pick_index(mouse_pos: Vector2) -> int:
	var count: int = _frame_edits.size()
	for i in range(count):
		if _frame_bar_cell_rect(i).has_point(mouse_pos):
			return i
	return -1

## 帧条绘制：每帧缩略图 + 帧号 + 判定帧红标记 + 音效帧蓝标记
func _on_frame_bar_draw() -> void:
	if _frame_bar == null:
		return
	var count: int = _frame_edits.size()
	if count <= 0:
		return
	## 背景
	var bg_rect := Rect2(Vector2.ZERO, _frame_bar.size)
	_frame_bar.draw_rect(bg_rect, Color(0.08, 0.08, 0.1, 1), true)
	## 逐帧绘制
	for i in range(count):
		var cell: Rect2 = _frame_bar_cell_rect(i)
		## 单元格背景（深色）
		_frame_bar.draw_rect(cell, Color(0.15, 0.15, 0.18, 1), true)
		## 帧缩略图：从精灵图按区域取图，绘制到单元格内（保持比例居中）
		if _frame_sheet_tex != null:
			var edit: Dictionary = _frame_edits[i]
			var src_rect := Rect2(
				float(edit.get("x", 0)),
				float(edit.get("y", 0)),
				float(edit.get("w", 0)),
				float(edit.get("h", 0))
			)
			if src_rect.size.x > 0 and src_rect.size.y > 0:
				## 计算缩放，使帧内容适配单元格（保持比例）
				var sx: float = FRAME_BAR_CELL_W / src_rect.size.x
				var sy: float = FRAME_BAR_CELL_H / src_rect.size.y
				var s: float = min(sx, sy)
				var dst_w: float = src_rect.size.x * s
				var dst_h: float = src_rect.size.y * s
				var dst_x: float = cell.position.x + (FRAME_BAR_CELL_W - dst_w) * 0.5
				var dst_y: float = cell.position.y + (FRAME_BAR_CELL_H - dst_h) * 0.5
				var dst_rect := Rect2(dst_x, dst_y, dst_w, dst_h)
				_frame_bar.draw_texture_rect_region(_frame_sheet_tex, dst_rect, src_rect)
		## 单元格边框
		_frame_bar.draw_rect(cell, Color(0.4, 0.4, 0.45, 1), false, 1.0)
		## 帧号
		var num_text: String = str(i)
		_frame_bar.draw_string(
			UIButtonHelper.get_ui_font(),
			Vector2(cell.position.x + 4, cell.position.y + FRAME_BAR_CELL_H + 12),
			num_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			11,
			Color(0.8, 0.8, 0.8, 1)
		)
		## 判定帧标记（红色三角 + 红色边框）
		if _cur_hit_frame == i:
			_frame_bar.draw_rect(cell, Color(1, 0.3, 0.3, 1), false, 2.0)
			var tri := PackedVector2Array([
				Vector2(cell.position.x + 4, cell.position.y - 2),
				Vector2(cell.position.x + 14, cell.position.y - 2),
				Vector2(cell.position.x + 9, cell.position.y + 8),
			])
			_frame_bar.draw_colored_polygon(tri, Color(1, 0.3, 0.3, 1))
		## 多段连击判定帧标记（红色边框 + 红色三角 + 序号）
		for hit_idx in range(_cur_hit_frames.size()):
			var frame_no: int = _cur_hit_frames[hit_idx]
			if frame_no == i:
				_frame_bar.draw_rect(cell, Color(1, 0.3, 0.3, 1), false, 2.0)
				var tri_m := PackedVector2Array([
					Vector2(cell.position.x + 4, cell.position.y - 2),
					Vector2(cell.position.x + 14, cell.position.y - 2),
					Vector2(cell.position.x + 9, cell.position.y + 8),
				])
				_frame_bar.draw_colored_polygon(tri_m, Color(1, 0.3, 0.3, 1))
				## 序号文字（第几击，1-based）
				_frame_bar.draw_string(
					UIButtonHelper.get_ui_font(),
					Vector2(cell.position.x + 18, cell.position.y + 8),
					str(hit_idx + 1),
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					11,
					Color(1, 0.6, 0.3, 1)
				)
		## 音效帧标记（蓝色三角 + 蓝色边框）
		if _cur_sound_frame == i:
			_frame_bar.draw_rect(cell, Color(0.3, 0.7, 1, 1), false, 2.0)
			var tri2 := PackedVector2Array([
				Vector2(cell.position.x + FRAME_BAR_CELL_W - 14, cell.position.y - 2),
				Vector2(cell.position.x + FRAME_BAR_CELL_W - 4, cell.position.y - 2),
				Vector2(cell.position.x + FRAME_BAR_CELL_W - 9, cell.position.y + 8),
			])
			_frame_bar.draw_colored_polygon(tri2, Color(0.3, 0.7, 1, 1))

## 帧条点击：根据当前模式设置判定帧/音效帧
func _on_frame_bar_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var idx: int = _frame_bar_pick_index(event.position)
	if idx < 0:
		return
	## 双击或右键可清除该帧的标记（便捷操作）
	if event.double_click:
		if _hit_sound_mode == "hit":
			## 多段连击兵种：双击清空所有多段判定帧；单段兵种：清除单帧
			var res_hit := _load_unit_resource(_frame_unit_id)
			if res_hit != null and res_hit.attack_count > 1:
				_cur_hit_frames.clear()
			elif _cur_hit_frame == idx:
				_cur_hit_frame = -1
		elif _hit_sound_mode == "sound" and _cur_sound_frame == idx:
			_cur_sound_frame = -1
	else:
		match _hit_sound_mode:
			"hit":
				## 多段连击兵种（attack_count > 1）：点击添加到 _cur_hit_frames（已存在则取消）
				## 单段兵种：替换 _cur_hit_frame
				var res_click := _load_unit_resource(_frame_unit_id)
				if res_click != null and res_click.attack_count > 1:
					var existing_idx := _cur_hit_frames.find(idx)
					if existing_idx >= 0:
						_cur_hit_frames.remove_at(existing_idx)
					else:
						_cur_hit_frames.append(idx)
				else:
					_cur_hit_frame = idx
			"sound":
				_cur_sound_frame = idx
	_refresh_hs_hint()
	_frame_bar.queue_redraw()

## 重置偏移按钮：弹出二次确认对话框，确认后清零所有帧的 ox/oy
func _on_reset_offsets_clicked() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "重置偏移"
	dialog.dialog_text = "确定要清零所有帧的偏移（ox/oy）吗？此操作不可撤销。"
	dialog.confirmed.connect(_on_reset_offsets_confirmed)
	add_child(dialog)
	dialog.popup_centered()

## 二次确认后实际执行重置
func _on_reset_offsets_confirmed() -> void:
	for edit in _frame_edits:
		edit.ox = 0
		edit.oy = 0
	_rebuild_frame_list()
	_sheet_preview.queue_redraw()
	_overlap_preview.queue_redraw()
	_refresh_anim_preview_from_edits()
	print("已重置 %s %s 所有帧偏移" % [_frame_unit_id, _frame_anim_name])

## 更新帧条宽度以适应所有帧（帧数多时支持横向滚动）
func _update_frame_bar_width() -> void:
	if _frame_bar == null:
		return
	var frame_count: int = _frame_edits.size()
	## 计算所有帧的总宽度：内边距 + 帧数 × (单元格宽 + 间隔) - 最后一帧的间隔
	var bar_w: float = FRAME_BAR_PAD * 2 + frame_count * (FRAME_BAR_CELL_W + FRAME_BAR_GAP) - FRAME_BAR_GAP
	## 最小宽度 820（不足时不需要滚动）
	if bar_w < 820:
		bar_w = 820
	_frame_bar.custom_minimum_size = Vector2(bar_w, 110)
	_frame_bar.queue_redraw()

## 加载当前选中单位/动画的精灵图与帧区域
func _on_frame_load() -> void:
	_frame_edits.clear()
	_frame_selected = -1
	_frame_sheet_tex = null
	_overlap_scale_cached = -1.0  ## 清缓存，新动画需要重算缩放
	_prev_preview_sound_frame = -1  ## 重置帧预览音效边沿触发状态（#147）
	var frames := _load_anim_frames(_frame_unit_id, _frame_anim_name)
	if frames == null or frames.get_frame_count(_frame_anim_name) <= 0:
		_rebuild_frame_list()
		_sheet_preview.queue_redraw()
		_update_anim_preview(null)
		_overlap_preview.queue_redraw()
		return
	## 取第一帧的贴图作为精灵图（AtlasTexture 的 atlas 即整张精灵图）
	var first_tex = frames.get_frame_texture(_frame_anim_name, 0)
	if first_tex is AtlasTexture:
		_frame_sheet_tex = (first_tex as AtlasTexture).atlas
	## 读取所有帧的区域与偏移
	var count: int = frames.get_frame_count(_frame_anim_name)
	for i in range(count):
		var tex = frames.get_frame_texture(_frame_anim_name, i)
		if tex is AtlasTexture:
			var at := tex as AtlasTexture
			_frame_edits.append({
				"x": int(at.region.position.x),
				"y": int(at.region.position.y),
				"w": int(at.region.size.x),
				"h": int(at.region.size.y),
				"ox": int(at.margin.position.x),
				"oy": int(at.margin.position.y),
			})
		else:
			## 非图集纹理，整张作为一个帧
			_frame_edits.append({
				"x": 0, "y": 0,
				"w": int(tex.get_width()) if tex else 400,
				"h": int(tex.get_height()) if tex else 400,
				"ox": 0, "oy": 0,
			})
	_rebuild_frame_list()
	_sheet_preview.queue_redraw()
	_update_anim_preview(frames)
	_overlap_preview.queue_redraw()
	## 更新判定/音效配置栏的可见性与值
	_update_hit_sound_bar()
	## 更新帧条宽度以适应所有帧（支持横向滚动）
	_update_frame_bar_width()

## 帧预览动画播放到“音效帧”时自动同步播放攻击音效（替代旧“试听音效”按钮，#147）
## 注意：Godot 4.x 的 AnimatedSprite2D.frame_changed 信号不带参数，故方法签名取 0 参，
## 帧号从 _anim_sprite.frame 读取（避免 “Method expected 1 argument(s), but called with 0” 报错）
func _on_anim_preview_frame_changed() -> void:
	var frame: int = _anim_sprite.frame if _anim_sprite != null else -1
	if not _frame_anim_name.begins_with("attack"):
		_prev_preview_sound_frame = frame
		return
	var res := _load_unit_resource(_frame_unit_id)
	if res == null or res.attack_sound_frame < 0:
		_prev_preview_sound_frame = frame
		return
	## 边沿触发：仅在帧号刚到达音效帧时播放一次（避免每一帧重复触发）
	if frame == res.attack_sound_frame and _prev_preview_sound_frame != res.attack_sound_frame:
		AudioManager.play_attack_sound(_frame_unit_id)
	_prev_preview_sound_frame = frame

## 更新动画播放预览
func _update_anim_preview(frames: SpriteFrames) -> void:
	if _anim_sprite == null:
		return
	if frames == null or frames.get_frame_count(_frame_anim_name) <= 0:
		_anim_sprite.stop()
		_anim_sprite.sprite_frames = null
		_apply_anim_pause_state()
		return
	_anim_sprite.sprite_frames = frames
	_apply_anim_preview_scale(frames)
	## #回归修复 2026-08-15：同 _create_anim_column，回置 loop=true 让帧图预览循环播放（仅内存，不写盘）
	frames.set_animation_loop(_frame_anim_name, true)
	_anim_sprite.play(_frame_anim_name)
	## 暂停开启时停播并定格到选中帧
	_apply_anim_pause_state()

## 暂停状态：选中有帧（_frame_selected >= 0）或暂停按钮开启时停播并定格到选中帧；否则恢复循环播放
func _apply_anim_pause_state() -> void:
	if _anim_sprite == null:
		return
	var should_pause: bool = (_btn_anim_pause != null and _btn_anim_pause.button_pressed) or _frame_selected >= 0
	if not should_pause:
		## 恢复循环播放（仅当存在精灵帧与对应动画名）
		if _anim_sprite.sprite_frames != null and _frame_anim_name != "":
			_anim_sprite.play(_frame_anim_name)
		return
	## 停播并定格到当前选中的帧（有选中帧时）
	if _frame_selected >= 0 and _anim_sprite.sprite_frames != null \
			and _frame_selected < _anim_sprite.sprite_frames.get_frame_count(_frame_anim_name):
		_anim_sprite.frame = _frame_selected
	_anim_sprite.pause()

## 暂停按钮切换回调
func _on_anim_pause_toggled(on: bool) -> void:
	_apply_anim_pause_state()

## 根据精灵帧实际尺寸与预览面板大小自动计算缩放，确保帧完整显示（上下不被遮盖）
## 使用 anim_preview 父节点的实际 size 计算可用区域
func _apply_anim_preview_scale(frames: SpriteFrames) -> void:
	if _anim_sprite == null or frames == null:
		return
	if frames.get_frame_count(_frame_anim_name) <= 0:
		return
	var tex = frames.get_frame_texture(_frame_anim_name, 0)
	if tex == null:
		return
	var fw: float = float(tex.get_width())
	var fh: float = float(tex.get_height())
	if fw <= 0 or fh <= 0:
		return
	## 使用 _anim_sprite 父节点的实际 size 计算可用区域
	var parent := _anim_sprite.get_parent()
	if parent == null or not (parent is Control):
		return
	var ctrl: Control = parent
	var rect: Rect2 = ctrl.get_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		## 布局未完成时使用自定义最小尺寸，避免缩放塌缩为 0
		rect = Rect2(rect.position, ctrl.custom_minimum_size)
	## 留 10px 边距
	var area_w: float = max(1.0, rect.size.x - 20.0)
	var area_h: float = max(1.0, rect.size.y - 20.0)
	var sx: float = area_w / fw
	var sy: float = area_h / fh
	var s: float = min(sx, sy)
	_anim_sprite.scale = Vector2(s, s)
	## 重新居中
	_anim_sprite.position = Vector2(rect.size.x * 0.5, rect.size.y * 0.5)

## 保存帧顺序与区域到 .tres 文件
func _on_frame_save() -> void:
	if _frame_edits.is_empty():
		push_warning("无帧可保存")
		return
	if _frame_sheet_tex == null:
		push_warning("无精灵图贴图")
		return
	## 构建新的 SpriteFrames 资源
	var new_frames := SpriteFrames.new()
	new_frames.remove_animation("default")
	## 动画速率：攻击 15，其他 10
	var speed: float = 15.0 if _frame_anim_name.begins_with("attack") else 10.0
	## 添加动画（先创建空动画）
	if not new_frames.has_animation(_frame_anim_name):
		new_frames.add_animation(_frame_anim_name)
	new_frames.set_animation_speed(_frame_anim_name, speed)
	new_frames.set_animation_loop(_frame_anim_name, true)
	## 清空已有帧
	while new_frames.get_frame_count(_frame_anim_name) > 0:
		new_frames.remove_frame(_frame_anim_name, 0)
	## 逐帧添加 AtlasTexture（含区域与偏移）
	for edit in _frame_edits:
		var at := AtlasTexture.new()
		at.atlas = _frame_sheet_tex
		at.region = Rect2(float(edit.x), float(edit.y), float(edit.w), float(edit.h))
		at.margin = Rect2(float(edit.ox), float(edit.oy), 0.0, 0.0)
		new_frames.add_frame(_frame_anim_name, at)
	## 保存
	var path := "%s/%s/%s" % [ANIM_ROOT_DIR, _frame_unit_id, ANIM_FILE_MAP.get(_frame_anim_name, "")]
	var err := ResourceSaver.save(new_frames, path)
	if err != OK:
		push_warning("保存失败，错误码: %d" % err)
	else:
		print("已保存 %s %s 动画到 %s" % [_frame_unit_id, _frame_anim_name, path])
		## #6（2026-08-09）：保存的是全新 SpriteFrames 对象，必须接管路径缓存，
		## 并清空 Unit 的 SpriteFrames 静态缓存——否则编辑器同进程内 load() 仍返回旧帧，
		## 表现为「控制台调好的攻击动画在游戏中不生效」（连本页预览刷新都可能读旧缓存）。
		new_frames.take_over_path(path)
		Unit.clear_sprite_frames_cache()
		Unit.clear_anim_scale_cache()
		## 保存后重新加载以刷新动画预览
		_on_frame_load()

## 添加新帧
func _on_frame_add() -> void:
	_frame_edits.append({"x": 0, "y": 0, "w": 400, "h": 400, "ox": 0, "oy": 0})
	_rebuild_frame_list()
	_sheet_preview.queue_redraw()
	_overlap_preview.queue_redraw()
	_refresh_anim_preview_from_edits()

## 重建帧列表 UI（卡片式布局，每帧一张卡片，行间留白）
func _rebuild_frame_list() -> void:
	if _frame_list_vbox == null:
		return
	for child in _frame_list_vbox.get_children():
		child.queue_free()
	for i in range(_frame_edits.size()):
		var edit: Dictionary = _frame_edits[i]
		## 每帧包装为带边框的卡片，增加上下留白
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style := StyleBoxFlat.new()
		if i == _frame_selected:
			card_style.bg_color = Color(0.2, 0.18, 0.1, 1)
			card_style.border_color = Color(1, 0.8, 0.2, 1)
			card_style.border_width_left = 2
			card_style.border_width_right = 2
			card_style.border_width_top = 2
			card_style.border_width_bottom = 2
		else:
			card_style.bg_color = Color(0.14, 0.14, 0.18, 1)
			card_style.border_color = Color(0.3, 0.3, 0.35, 1)
			card_style.border_width_left = 1
			card_style.border_width_right = 1
			card_style.border_width_top = 1
			card_style.border_width_bottom = 1
		card_style.corner_radius_top_left = 4
		card_style.corner_radius_top_right = 4
		card_style.corner_radius_bottom_left = 4
		card_style.corner_radius_bottom_right = 4
		card_style.content_margin_left = 6
		card_style.content_margin_right = 6
		card_style.content_margin_top = 6
		card_style.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", card_style)
		_frame_list_vbox.add_child(card)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)
		card.add_child(card_vbox)

		## 第一行：索引 + 缩略图 + 操作按钮
		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 6)
		card_vbox.add_child(top_row)

		var idx_label := Label.new()
		idx_label.text = "#%d" % i
		idx_label.custom_minimum_size = Vector2(36, 0)
		idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idx_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		idx_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1) if i == _frame_selected else Color(0.7, 0.7, 0.7, 1))
		top_row.add_child(idx_label)

		var thumb := TextureRect.new()
		thumb.custom_minimum_size = Vector2(56, 56)
		thumb.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		thumb.stretch_mode = TextureRect.STRETCH_SCALE
		if _frame_sheet_tex != null:
			var at := AtlasTexture.new()
			at.atlas = _frame_sheet_tex
			at.region = Rect2(float(edit.x), float(edit.y), float(edit.w), float(edit.h))
			thumb.texture = at
		top_row.add_child(thumb)

		## 选中按钮
		var btn_sel := Button.new()
		btn_sel.text = "选中"
		btn_sel.custom_minimum_size = Vector2(50, 0)
		btn_sel.toggle_mode = true
		btn_sel.button_pressed = (i == _frame_selected)
		var idx_sel := i
		btn_sel.pressed.connect(func() -> void:
			_frame_selected = idx_sel
			_rebuild_frame_list()
			_sheet_preview.queue_redraw()
			_overlap_preview.queue_redraw()
			_apply_anim_pause_state()
		)
		top_row.add_child(btn_sel)

		var btn_up := Button.new()
		btn_up.text = "↑"
		btn_up.custom_minimum_size = Vector2(32, 0)
		btn_up.disabled = (i == 0)
		var idx_up := i
		btn_up.pressed.connect(func() -> void:
			_frame_move(idx_up, -1)
		)
		top_row.add_child(btn_up)

		var btn_down := Button.new()
		btn_down.text = "↓"
		btn_down.custom_minimum_size = Vector2(32, 0)
		btn_down.disabled = (i >= _frame_edits.size() - 1)
		var idx_down := i
		btn_down.pressed.connect(func() -> void:
			_frame_move(idx_down, 1)
		)
		top_row.add_child(btn_down)

		var btn_del := Button.new()
		btn_del.text = "✕"
		btn_del.custom_minimum_size = Vector2(32, 0)
		var idx_del := i
		btn_del.pressed.connect(func() -> void:
			_frame_delete(idx_del)
		)
		top_row.add_child(btn_del)

		## 第二行：区域 x/y/w/h
		var region_row := HBoxContainer.new()
		region_row.add_theme_constant_override("separation", 4)
		card_vbox.add_child(region_row)

		var region_label := Label.new()
		region_label.text = "区域:"
		region_label.custom_minimum_size = Vector2(36, 0)
		region_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		region_row.add_child(region_label)

		var fields: Array = [
			["x", edit.x, -4096, 4096],
			["y", edit.y, -4096, 4096],
			["w", edit.w, 1, 1024],
			["h", edit.h, 1, 1024],
		]
		for field in fields:
			var fname: String = field[0]
			var fval: int = field[1]
			var fmin: int = field[2]
			var fmax: int = field[3]
			var lbl := Label.new()
			lbl.text = fname
			lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
			lbl.custom_minimum_size = Vector2(12, 0)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			region_row.add_child(lbl)
			var spin := SpinBox.new()
			spin.min_value = fmin
			spin.max_value = fmax
			spin.step = 1.0
			spin.value = fval
			spin.custom_minimum_size = Vector2(54, 0)
			spin.allow_greater = true
			spin.allow_lesser = true
			var idx := i
			var on_changed := func(_v: float) -> void:
				_on_frame_field_changed(idx, fname, spin)
			spin.value_changed.connect(on_changed)
			region_row.add_child(spin)

		## 第三行：偏移 ox/oy
		var offset_row := HBoxContainer.new()
		offset_row.add_theme_constant_override("separation", 4)
		card_vbox.add_child(offset_row)

		var offset_label := Label.new()
		offset_label.text = "偏移:"
		offset_label.custom_minimum_size = Vector2(36, 0)
		offset_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		offset_row.add_child(offset_label)

		var offset_fields: Array = [
			["ox", edit.ox, -400, 400],
			["oy", edit.oy, -400, 400],
		]
		for field in offset_fields:
			var fname: String = field[0]
			var fval: int = field[1]
			var fmin: int = field[2]
			var fmax: int = field[3]
			var lbl := Label.new()
			lbl.text = fname
			lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
			lbl.custom_minimum_size = Vector2(12, 0)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			offset_row.add_child(lbl)
			var spin := SpinBox.new()
			spin.min_value = fmin
			spin.max_value = fmax
			spin.step = 1.0
			spin.value = fval
			spin.custom_minimum_size = Vector2(54, 0)
			spin.allow_greater = true
			spin.allow_lesser = true
			var idx := i
			var on_changed := func(_v: float) -> void:
				_on_frame_field_changed(idx, fname, spin)
			spin.value_changed.connect(on_changed)
			offset_row.add_child(spin)

## 帧字段修改回调（区域 x/y/w/h 与偏移 ox/oy 通用）
func _on_frame_field_changed(idx: int, field: String, spin: SpinBox) -> void:
	if idx < 0 or idx >= _frame_edits.size():
		return
	_frame_edits[idx][field] = int(spin.value)
	_sheet_preview.queue_redraw()
	_overlap_preview.queue_redraw()
	_refresh_anim_preview_from_edits()

## 从当前编辑数据构建临时 SpriteFrames 刷新动画预览
func _refresh_anim_preview_from_edits() -> void:
	if _anim_sprite == null or _frame_sheet_tex == null:
		return
	if _frame_edits.is_empty():
		_anim_sprite.stop()
		_anim_sprite.sprite_frames = null
		_apply_anim_pause_state()
		return
	var tmp_frames := SpriteFrames.new()
	tmp_frames.remove_animation("default")
	if not tmp_frames.has_animation(_frame_anim_name):
		tmp_frames.add_animation(_frame_anim_name)
	var speed: float = 15.0 if _frame_anim_name.begins_with("attack") else 10.0
	tmp_frames.set_animation_speed(_frame_anim_name, speed)
	tmp_frames.set_animation_loop(_frame_anim_name, true)
	for edit in _frame_edits:
		var at := AtlasTexture.new()
		at.atlas = _frame_sheet_tex
		at.region = Rect2(float(edit.x), float(edit.y), float(edit.w), float(edit.h))
		at.margin = Rect2(float(edit.ox), float(edit.oy), 0.0, 0.0)
		tmp_frames.add_frame(_frame_anim_name, at)
	_anim_sprite.sprite_frames = tmp_frames
	_apply_anim_preview_scale(tmp_frames)
	if not _anim_sprite.is_playing():
		_anim_sprite.play(_frame_anim_name)
	_apply_anim_pause_state()

## 移动帧顺序
func _frame_move(idx: int, dir: int) -> void:
	var new_idx: int = idx + dir
	if new_idx < 0 or new_idx >= _frame_edits.size():
		return
	var tmp = _frame_edits[idx]
	_frame_edits[idx] = _frame_edits[new_idx]
	_frame_edits[new_idx] = tmp
	_frame_selected = new_idx
	_rebuild_frame_list()
	_sheet_preview.queue_redraw()
	_overlap_preview.queue_redraw()
	_apply_anim_pause_state()
	_refresh_anim_preview_from_edits()

## 删除帧
func _frame_delete(idx: int) -> void:
	if idx < 0 or idx >= _frame_edits.size():
		return
	_frame_edits.remove_at(idx)
	if _frame_selected == idx:
		_frame_selected = -1
	elif _frame_selected > idx:
		_frame_selected -= 1
	_rebuild_frame_list()
	_sheet_preview.queue_redraw()
	_overlap_preview.queue_redraw()
	_refresh_anim_preview_from_edits()

## 计算精灵图预览的缩放与偏移（贴图居中适配预览区域，上下留出标题空间）
func _compute_sheet_transform() -> void:
	if _frame_sheet_tex == null:
		_sheet_scale = 1.0
		_sheet_offset = Vector2.ZERO
		return
	var tex_w: float = float(_frame_sheet_tex.get_width())
	var tex_h: float = float(_frame_sheet_tex.get_height())
	var rect := _sheet_preview.get_rect()
	## 预览区域：左右各留 10px，上下各留 10px（标题已由外层 VBox 处理）
	var area_w: float = max(1.0, rect.size.x - 20.0)
	var area_h: float = max(1.0, rect.size.y - 20.0)
	var sx: float = area_w / tex_w if tex_w > 0 else 1.0
	var sy: float = area_h / tex_h if tex_h > 0 else 1.0
	_sheet_scale = min(sx, sy)
	var draw_w: float = tex_w * _sheet_scale
	var draw_h: float = tex_h * _sheet_scale
	## 水平居中，垂直居中（标题已在外层 VBox 占位）
	_sheet_offset = Vector2((rect.size.x - draw_w) * 0.5, (rect.size.y - draw_h) * 0.5)

## 绘制精灵图预览（贴图 + 帧区域方框）
func _on_sheet_preview_draw() -> void:
	_compute_sheet_transform()
	if _frame_sheet_tex == null:
		return
	var tex_w: float = float(_frame_sheet_tex.get_width())
	var tex_h: float = float(_frame_sheet_tex.get_height())
	## 绘制贴图（按缩放）
	var tex_dst := Rect2(_sheet_offset, Vector2(tex_w * _sheet_scale, tex_h * _sheet_scale))
	_sheet_preview.draw_texture_rect(_frame_sheet_tex, tex_dst, false)
	## 绘制每个帧的区域方框
	for i in range(_frame_edits.size()):
		var edit: Dictionary = _frame_edits[i]
		var r := Rect2(
			_sheet_offset + Vector2(float(edit.x) * _sheet_scale, float(edit.y) * _sheet_scale),
			Vector2(float(edit.w) * _sheet_scale, float(edit.h) * _sheet_scale)
		)
		var color: Color = Color(1, 0.8, 0.2, 1) if i == _frame_selected else Color(1, 0.4, 0.4, 0.8)
		_sheet_preview.draw_rect(r, color, false, 2.0)
		## 帧索引标注
		if _frame_font == null:
			_frame_font = get_theme_default_font()
		if _frame_font != null:
			_sheet_preview.draw_string(_frame_font, r.position + Vector2(2, 14), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

## 精灵图预览鼠标输入：左键点击选中或添加帧
func _on_sheet_preview_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _frame_sheet_tex == null:
		return
	_compute_sheet_transform()
	## 将点击位置转换为贴图像素坐标
	var px: float = (mb.position.x - _sheet_offset.x) / _sheet_scale
	var py: float = (mb.position.y - _sheet_offset.y) / _sheet_scale
	## 检查是否点击在已有帧上
	for i in range(_frame_edits.size()):
		var edit: Dictionary = _frame_edits[i]
		var r := Rect2(float(edit.x), float(edit.y), float(edit.w), float(edit.h))
		if r.has_point(Vector2(px, py)):
			if mb.double_click:
				## 双击：取消选中（仅当双击的是当前选中的帧）
				if _frame_selected == i:
					_frame_selected = -1
			else:
				## 单击：选中该帧（有选中帧 → _apply_anim_pause_state 自动定格暂停）
				_frame_selected = i
			_rebuild_frame_list()
			_sheet_preview.queue_redraw()
			_overlap_preview.queue_redraw()
			_apply_anim_pause_state()
			return
	## 未点中任何帧：若在贴图范围内，添加新帧（以点击点为左上角，400×400）
	var tex_w: float = float(_frame_sheet_tex.get_width())
	var tex_h: float = float(_frame_sheet_tex.get_height())
	if px < 0 or py < 0 or px >= tex_w or py >= tex_h:
		return
	var new_w: int = min(400, int(tex_w - px))
	var new_h: int = min(400, int(tex_h - py))
	_frame_edits.append({"x": int(px), "y": int(py), "w": new_w, "h": new_h, "ox": 0, "oy": 0})
	_frame_selected = _frame_edits.size() - 1
	_rebuild_frame_list()
	_sheet_preview.queue_redraw()
	_overlap_preview.queue_redraw()
	_refresh_anim_preview_from_edits()

## ============================================================
## 重叠预览：所有帧叠加显示 + 底部基准线 + 拖动调整偏移
## ============================================================

## 计算重叠预览的缩放（以最大帧尺寸适配预览区域，考虑上方标题与下方基准线留白）
## 首次调用时根据所有帧的最大 w/h 计算并缓存，之后拖动缩放单个帧不会重算（避免其他帧视觉跟着变）
func _compute_overlap_scale() -> float:
	if _frame_edits.is_empty():
		return 0.4
	## 已缓存则直接返回，保证拖动单个帧时其他帧视觉不变
	if _overlap_scale_cached > 0.0:
		return _overlap_scale_cached
	var max_w: float = 0.0
	var max_h: float = 0.0
	for edit in _frame_edits:
		max_w = max(max_w, float(edit.w))
		max_h = max(max_h, float(edit.h))
	if max_w <= 0 or max_h <= 0:
		return 0.4
	## 使用 get_rect 避免布局未完成时 size 异常
	var rect := _overlap_preview.get_rect()
	var area_w: float = max(1.0, rect.size.x - 20.0)  ## 左右各留 10px
	## 上方留 10px，下方留 50px（基准线 + 标注 + 安全边距）
	var area_h: float = max(1.0, rect.size.y - 60.0)
	var sx: float = area_w / max_w
	var sy: float = area_h / max_h
	_overlap_scale_cached = min(sx, sy)
	return _overlap_scale_cached

## 绘制重叠预览（所有帧半透明叠加 + 选中帧高亮 + 底部基准线）
func _on_overlap_preview_draw() -> void:
	if _frame_font == null:
		_frame_font = get_theme_default_font()
	var s: float = _compute_overlap_scale()
	var rect := _overlap_preview.get_rect()
	var area_w: float = max(1.0, rect.size.x)
	var area_h: float = max(1.0, rect.size.y)
	## 基准线 Y 坐标（距底部 30px，给标注留空间），夹紧到 [10, area_h-10] 防止跑出窗口
	var baseline_y: float = clampf(area_h - 30.0, 10.0, area_h - 10.0)
	## 所有帧的绘制中心 X（水平居中）
	var center_x: float = area_w * 0.5
	## 绘制基准线（白色水平线 + 标注）
	_overlap_preview.draw_line(Vector2(10, baseline_y), Vector2(area_w - 10, baseline_y), Color(0.6, 0.8, 1, 0.8), 2.0)
	if _frame_font != null:
		_overlap_preview.draw_string(_frame_font, Vector2(12, baseline_y + 18), "基准线", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.8, 1, 0.8))
	## 绘制所有帧（从后往前画，选中帧最后画在最上层）
	var draw_order: Array = []
	for i in range(_frame_edits.size()):
		if i != _frame_selected:
			draw_order.append(i)
	if _frame_selected >= 0 and _frame_selected < _frame_edits.size():
		draw_order.append(_frame_selected)
	for i in draw_order:
		var edit: Dictionary = _frame_edits[i]
		if _frame_sheet_tex == null:
			continue
		var at := AtlasTexture.new()
		at.atlas = _frame_sheet_tex
		at.region = Rect2(float(edit.x), float(edit.y), float(edit.w), float(edit.h))
		## 单帧缩放系数 scale（默认 1.0），边框拖动只改 scale 不改 w/h（w/h 是切图区域，不能动）
		var frame_scale: float = float(edit.get("scale", 1.0))
		var draw_w: float = float(edit.w) * s * frame_scale
		var draw_h: float = float(edit.h) * s * frame_scale
		## ox 正值向右、oy 正值向下（与鼠标方向一致）
		## 帧默认底部对齐到基准线，偏移后：oy>0 向下移动（越过基准线），oy<0 向上移动
		## 偏移基于原始尺寸（不含 scale），保持拖动一致性
		var draw_x: float = center_x - draw_w * 0.5 + float(edit.ox) * s
		var draw_y: float = baseline_y - draw_h + float(edit.oy) * s
		var dst := Rect2(draw_x, draw_y, draw_w, draw_h)
		if i == _frame_selected:
			## 选中帧：不透明 + 金色边框
			_overlap_preview.draw_texture_rect(at, dst, false)
			_overlap_preview.draw_rect(dst, Color(1, 0.8, 0.2, 1), false, 2.0)
		else:
			## 非选中帧：半透明红色边框
			_overlap_preview.draw_texture_rect(at, dst, false, Color(1, 1, 1, 0.3))
			_overlap_preview.draw_rect(dst, Color(1, 0.4, 0.4, 0.4), false, 1.0)
		## 帧索引标注
		if _frame_font != null:
			var label_color: Color = Color(1, 0.8, 0.2, 1) if i == _frame_selected else Color(0.7, 0.7, 0.7, 0.6)
			_overlap_preview.draw_string(_frame_font, dst.position + Vector2(2, 14), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_color)
	## 给选中帧绘制四角手柄（用于拖动缩放显示比例）
	if _frame_selected >= 0 and _frame_selected < _frame_edits.size():
		var sel_edit: Dictionary = _frame_edits[_frame_selected]
		var sel_scale: float = float(sel_edit.get("scale", 1.0))
		var sel_w: float = float(sel_edit.w) * s * sel_scale
		var sel_h: float = float(sel_edit.h) * s * sel_scale
		var sel_x: float = center_x - sel_w * 0.5 + float(sel_edit.ox) * s
		var sel_y: float = baseline_y - sel_h + float(sel_edit.oy) * s
		## 四角手柄位置：左上、右上、右下、左下
		var handles := [
			Vector2(sel_x, sel_y),
			Vector2(sel_x + sel_w, sel_y),
			Vector2(sel_x + sel_w, sel_y + sel_h),
			Vector2(sel_x, sel_y + sel_h),
		]
		for hpos in handles:
			var hr := Rect2(hpos.x - OVERLAP_HANDLE_HALF, hpos.y - OVERLAP_HANDLE_HALF, OVERLAP_HANDLE_HALF * 2, OVERLAP_HANDLE_HALF * 2)
			_overlap_preview.draw_rect(hr, Color(0.2, 0.2, 0.2, 1), true)
			_overlap_preview.draw_rect(hr, Color(1, 0.8, 0.2, 1), false, 1.5)

## 计算选中帧在重叠预览中的绘制矩形
func _get_selected_overlap_rect(s: float, baseline_y: float, center_x: float) -> Rect2:
	if _frame_selected < 0 or _frame_selected >= _frame_edits.size():
		return Rect2()
	var edit: Dictionary = _frame_edits[_frame_selected]
	var frame_scale: float = float(edit.get("scale", 1.0))
	var draw_w: float = float(edit.w) * s * frame_scale
	var draw_h: float = float(edit.h) * s * frame_scale
	var draw_x: float = center_x - draw_w * 0.5 + float(edit.ox) * s
	var draw_y: float = baseline_y - draw_h + float(edit.oy) * s
	return Rect2(draw_x, draw_y, draw_w, draw_h)

## 检测鼠标位置命中哪个手柄（0=左上,1=右上,2=右下,3=左下，-1=无）
func _hit_resize_handle(mouse_pos: Vector2, rect: Rect2) -> int:
	var handles := [
		rect.position,  ## 左上
		Vector2(rect.position.x + rect.size.x, rect.position.y),  ## 右上
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),  ## 右下
		Vector2(rect.position.x, rect.position.y + rect.size.y),  ## 左下
	]
	for i in range(handles.size()):
		var hpos: Vector2 = handles[i]
		var hr := Rect2(hpos.x - OVERLAP_HANDLE_HALF, hpos.y - OVERLAP_HANDLE_HALF, OVERLAP_HANDLE_HALF * 2, OVERLAP_HANDLE_HALF * 2)
		if hr.has_point(mouse_pos):
			return i
	return -1

## 重叠预览鼠标输入：
## - 不点击选中帧（选中通过右侧帧列表完成）
## - 拖动选中帧内部 = 调整该帧 ox/oy 偏移
## - 拖动选中帧四角手柄 = 调整该帧显示缩放 scale（不改 w/h，w/h 是切图区域）
func _on_overlap_preview_input(event: InputEvent) -> void:
	if not is_inside_tree() or _frame_sheet_tex == null or _frame_edits.is_empty():
		return
	var s: float = _compute_overlap_scale()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var rect := _overlap_preview.get_rect()
		var area_h: float = max(1.0, rect.size.y)
		var baseline_y: float = clampf(area_h - 30.0, 10.0, area_h - 10.0)
		var area_w: float = max(1.0, rect.size.x)
		var center_x: float = area_w * 0.5
		if mb.pressed:
			if _frame_selected < 0 or _frame_selected >= _frame_edits.size():
				return  ## 无选中帧，不做任何操作（不点击选中）
			var sel_rect := _get_selected_overlap_rect(s, baseline_y, center_x)
			## 优先检测四角手柄
			var handle_idx: int = _hit_resize_handle(mb.position, sel_rect)
			if handle_idx >= 0:
				_overlap_resize_dragging = true
				_overlap_resize_handle = handle_idx
				_overlap_resize_start_pos = mb.position
				var sel_edit: Dictionary = _frame_edits[_frame_selected]
				_overlap_resize_start_size = Vector2(float(sel_edit.get("scale", 1.0)), float(sel_edit.get("scale", 1.0)))
				_undo_push()  ## 拖动前压栈
				return
			## 点击在选中帧内部 = 开始拖动偏移
			if sel_rect.has_point(mb.position):
				_overlap_dragging = true
				_overlap_drag_start = mb.position
				var sel_edit: Dictionary = _frame_edits[_frame_selected]
				_overlap_drag_off_start = Vector2(float(sel_edit.ox), float(sel_edit.oy))
				_undo_push()  ## 拖动前压栈
				return
			## 点击其他位置：不改变选中，不做操作
		else:
			## 释放：结束拖动
			if _overlap_dragging:
				_overlap_dragging = false
				_rebuild_frame_list()
				_sheet_preview.queue_redraw()
				_refresh_anim_preview_from_edits()
			if _overlap_resize_dragging:
				_overlap_resize_dragging = false
				_overlap_resize_handle = -1
				_rebuild_frame_list()
				_sheet_preview.queue_redraw()
				_refresh_anim_preview_from_edits()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _frame_selected < 0 or _frame_selected >= _frame_edits.size():
			return
		## 拖动偏移
		if _overlap_dragging:
			var dx: float = (mm.position.x - _overlap_drag_start.x) / s
			var dy: float = (mm.position.y - _overlap_drag_start.y) / s
			_frame_edits[_frame_selected].ox = int(_overlap_drag_off_start.x + dx)
			_frame_edits[_frame_selected].oy = int(_overlap_drag_off_start.y + dy)
			_overlap_preview.queue_redraw()
		## 拖动缩放：只改 scale 不改 w/h（w/h 是切图区域，改了会破坏精灵图）
		elif _overlap_resize_dragging:
			## 取拖动距离的对角线分量作为缩放比例变化
			var dx: float = mm.position.x - _overlap_resize_start_pos.x
			var dy: float = mm.position.y - _overlap_resize_start_pos.y
			var start_scale: float = _overlap_resize_start_size.x
			## 根据手柄位置决定缩放方向（左上/左下：dx 反向；右上/右下：dx 正向）
			var dir_x: float = 1.0
			var dir_y: float = 1.0
			match _overlap_resize_handle:
				0:  ## 左上：dx 反向、dy 反向
					dir_x = -1.0
					dir_y = -1.0
				1:  ## 右上：dx 正向、dy 反向
					dir_x = 1.0
					dir_y = -1.0
				2:  ## 右下：dx 正向、dy 正向
					dir_x = 1.0
					dir_y = 1.0
				3:  ## 左下：dx 反向、dy 正向
					dir_x = -1.0
					dir_y = 1.0
			## 用对角线方向的位移作为缩放因子，每 100px 位移 = 1.0 倍 scale 变化
			var delta: float = (dx * dir_x + dy * dir_y) * 0.01
			var new_scale: float = max(0.1, start_scale + delta)
			_frame_edits[_frame_selected].scale = new_scale
			_overlap_preview.queue_redraw()

## 撤销栈：压入当前 _frame_edits 的深拷贝快照
func _undo_push() -> void:
	var snapshot: Array = []
	for edit in _frame_edits:
		snapshot.append(edit.duplicate())
	_undo_stack.append(snapshot)
	if _undo_stack.size() > UNDO_MAX_SIZE:
		_undo_stack.pop_front()

## 撤销：恢复上一次快照
func _undo_pop() -> void:
	if _undo_stack.is_empty():
		return
	var snapshot: Array = _undo_stack.pop_back()
	_frame_edits.clear()
	for edit in snapshot:
		_frame_edits.append(edit.duplicate())
	_rebuild_frame_list()
	_sheet_preview.queue_redraw()
	_overlap_preview.queue_redraw()
	_refresh_anim_preview_from_edits()

## 快捷键处理：Ctrl+Z 撤销
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_Z and event.ctrl_pressed:
		_undo_pop()
