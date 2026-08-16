extends CanvasLayer
## HUD - 顶部基地衢��?计时�?��两侧经济数据，底部兵种��择面板

## 顶部红方基地容器（VBoxContainer，内�??�?+ 扣�?日志条）
@onready var red_hp: VBoxContainer = $TopHBox/RedHP
## 顶部红方基地衢��?
@onready var red_hp_bar: ProgressBar = $TopHBox/RedHP/RedHPBar
## 顶部红方基地扣�?日志�?
@onready var red_battle_log: RichTextLabel = $TopHBox/RedHP/RedBattleLog
## 顶部蓝方基地容器
@onready var blue_hp: VBoxContainer = $TopHBox/BlueHP
## 顶部蓝方基地衢��?
@onready var blue_hp_bar: ProgressBar = $TopHBox/BlueHP/BlueHPBar
## 顶部蓝方基地扣�?日志�?
@onready var blue_battle_log: RichTextLabel = $TopHBox/BlueHP/BlueBattleLog
## #1：水晶�?条上的�?量数字标签（代码构建，叠在�?条中�?��
var red_hp_label: Label = null
var blue_hp_label: Label = null
## #19：中�?��面动态动画精灵（单例复用；旧实现每�?新建 + queue_free 延迟释放�?
## �?��连点�?�?��种时旧精灵跨帧残留，导致多个兵�?同时展示�?
var _center_anim_sprite: AnimatedSprite2D = null
## #19：中�?���?resized 信号连接（换精灵前先�?��旧连接，避免信号�?��触发重�?布局�?
var _center_preview_resize_cb: Callable = Callable()
## 顶部�?��倒�?时与回合标�?
@onready var timer_label: Label = $TopHBox/TimerLabel

## 左侧玩�?金币标�?
@onready var player_gold_label: Label = $LeftSidePanel/PlayerData/PlayerGoldLabel
## 左侧玩�?人口标�?
@onready var player_pop_label: Label = $LeftSidePanel/PlayerData/PlayerPopLabel
## 左侧玩�?收入标�?
@onready var player_income_label: Label = $LeftSidePanel/PlayerData/PlayerIncomeLabel

## 右侧敌人金币标�?
@onready var enemy_gold_label: Label = $RightSidePanel/EnemyData/EnemyGoldLabel
## 右侧敌人人口标�?
@onready var enemy_pop_label: Label = $RightSidePanel/EnemyData/EnemyPopLabel
## 右侧敌人收入标�?
@onready var enemy_income_label: Label = $RightSidePanel/EnemyData/EnemyIncomeLabel

## 底部玩�?兵�?选择容器（VBoxContainer，包�?PlayerScroll 滚动容器内）
@onready var player_grid: VBoxContainer = $BottomPanel/BottomHBox/LeftColumn/PlayerScroll/PlayerGrid
## 底部敌人兵�?选择容器（VBoxContainer，包�?EnemyScroll 滚动容器内，双人模式使用�?
@onready var enemy_grid: VBoxContainer = $BottomPanel/BottomHBox/RightColumn/EnemyScroll/EnemyGrid
## 底部�?��封面图�?览（选中兵�?时放大显示）
@onready var center_preview: TextureRect = $BottomPanel/BottomHBox/CenterPreview

## 顶部�?���?��按钮
@onready var help_btn: Button = $TopCenterButtons/HelpBtn
## 顶部�?��设置按钮
@onready var settings_btn: Button = $TopCenterButtons/SettingsBtn
## 顶部�?��逢�出按�?
@onready var exit_btn: Button = $TopCenterButtons/ExitBtn
## 顶部�?��弢�发工具按�?
@onready var dev_btn: Button = $TopCenterButtons/DevBtn
@onready var adjust_btn: Button = $TopCenterButtons/AdjustBtn
## 顶部难度/模式显示按钮�?2：可点击编辑难度提示文本，由 _setup_difficulty_label 代码构建�?
var diff_btn: Button = null
@onready var left_panel: PanelContainer = $LeftSidePanel
@onready var right_panel: PanelContainer = $RightSidePanel

## 调整面板（实时调节信�?��板位�?尺�?、各数据行位�?�����?时位�?��
var _adjust_panel: Control = null
## 信息面板（左/右经济面板）当前应用的位�?��移，按侧�?���?10）：索引 0=左侧�?=右侧
var _info_panel_offset: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## 信息面板当前应用的尺寸�?量（x=加�?像素, y=加高像素），按侧�?���?3/#10�?
var _info_panel_size: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## 信息面板初�?偏移基准（用于叠加持久化偏移），�?_ready �?���?
var _left_base: Dictionary = {}
var _right_base: Dictionary = {}
## 金币/人口/收入三�?文本各自的位�?��移，按侧�?���?2/#10）：索引 0=左侧�?=右侧
var _row_offsets: Array[Dictionary] = [
	{"gold": Vector2.ZERO, "pop": Vector2.ZERO, "income": Vector2.ZERO},
	{"gold": Vector2.ZERO, "pop": Vector2.ZERO, "income": Vector2.ZERO},
]
## 人口/收入升级按钮（�?�?�?小按�?��相�?行的位置偏移，按侧独立（#8）：索引 0=左侧�?=右侧
var _upgrade_btn_offsets: Array[Dictionary] = [
	{"pop": Vector2.ZERO, "income": Vector2.ZERO},
	{"pop": Vector2.ZERO, "income": Vector2.ZERO},
]
## 升级按钮插槽缓存，key = "%d_%s" % [player_id, kind]，value = Control�?8�?
var _upgrade_btn_slots: Dictionary = {}
## 回合倒�?�?回合数标签的位置偏移�?3�?
var _timer_offset: Vector2 = Vector2.ZERO
## #18�?026-08-11）：顶部水晶 HP 条（RedHP/BlueHP）位�?��移，按侧�?���?=�?�?�?=�?�?
var _hp_bar_offsets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## 数据行�?器缓存，key = "%d_%s" % [player_id, kind]，value = HBoxContainer�?2/#4�?
var _data_rows: Dictionary = {}
## 倒�?时标签的偏移承载容器�?3�?
var _timer_row: Control = null
## #6：本场战斗��用时（秒），暂�?结算期间冻结（countdown_tick 暂停时不发出，天然停止累计）
var _battle_elapsed: float = 0.0

## 玩�?侧兵种按�?��组（TextureButton，非 Button�?
var unit_buttons: Array[TextureButton] = []
## 敌人侧兵种按�?��组（TextureButton，非 Button�?
var enemy_buttons: Array[TextureButton] = []

## 当前打开的游戏内设置对话框引�?
var _settings_dialog: AcceptDialog = null
## #3�?026-08-11）：设置界面的全屏点击遮罩（半��明黑，点击空白处关�??�?���?
## 与�?话�?同时创建/锢�毁；位于对话框下层，对话框区域内点击�?Window 消费，区域�?落到�?���?
var _settings_backdrop: ColorRect = null
## 当前打开的开发工具下拉菜单（PopupMenu �?Window 不是 Control，需�??管理生命周期�?
var _dev_menu: PopupMenu = null
## 调整面板作用侧：0=左右同时（镜像）�?=仅左侧，2=仅右侧（#10�?
var _adjust_side: int = 0
## 设置对话框中霢�要动态更新的标�?数组
var _settings_labels: Array[Label] = []
## 设置对话框中霢�要动态更新的按钮数组
var _settings_buttons: Array[Button] = []
## 设置对话框中�?Tab 容器引用
var _settings_tabs: TabContainer = null
## 当前的暂停是否由「ESC 呼出设置」��成（只有自己��成的暂停才由自己恢复，#186�?
var _settings_paused_game: bool = false
## 上�? ESC 切换设置的时间戳（�?秒），用于吞掉同丢�次按�??多路输入重�?触发
var _last_settings_toggle_msec: int = 0
## #18：上次�?�??话�?�?���?��时间戳（�??）��?
## AcceptDialog �?input 阶�?消费 ESC（canceled �?关闭），battle_root �?process 阶�?�??到同丢�
## �?ESC 边沿，若不隔弢�会�?致��关了又立刻重开」，表现为按丢��?ESC 设置关不掉（霢�连按多�?）��?
var _last_settings_close_msec: int = -9999
## ESC 切换设置的最小间隔（�??�?
const SETTINGS_TOGGLE_COOLDOWN_MSEC: int = 250

## EnemyScroll 的垂直滚动条引用（用于每帧强制重定位到左侧）
var _enemy_vbar: VScrollBar = null

## 升级按钮缓存（key=player_id, value=Dictionary{pop,income} Button），用于刷新花费与可用状态（#138�?
var _upgrade_buttons: Dictionary = {}

## #7：当前是否为夜晚（背�?��黑）
var _is_night: bool = false
## #7：�?晚叠黑层（ColorRect，作�?HUD �?���?��节点，盖住战场但 UI 仍在上层�??�?
var _night_overlay: ColorRect = null
## #7：�?晚叠黑��明度（0=不遮�?=全黑�?
const NIGHT_OVERLAY_ALPHA: float = 0.55


## P1 当前�?��选中的按�?���?
var p1_selected_index: int = 0
## P2 当前�?��选中的按�?���?
var p2_selected_index: int = 0
## 兵�?按钮每�?的按�?��量（按阵�?G/D/F/N 分�?，用于键盘�?�?��
var _player_row_sizes: Array[int] = []
## 敌人侧每行的按钮数量
var _enemy_row_sizes: Array[int] = []
## 兵�?按钮网格每�?朢�大列数（已弃�?��保留防�?外部引用报错�?
const GRID_COLUMNS: int = 8
## 信息面板内单行数�?��金币/人口/收入）的行高�?2/#4�?
const DATA_ROW_HEIGHT: float = 26.0
## 人口/收入行右侧升级按�?��宽度�?4，做窄以免撑破信�?��板）
const UPGRADE_BTN_WIDTH: float = 78.0
## 信息面板与窗口边缘之间必须保留的安全距�?（像素）�?1�?
const INFO_PANEL_MARGIN: float = 4.0
## 调整面板持久化配�?���?
const ADJUST_CFG_PATH: String = "res://data/ui_adjust.json"
## 弢�发工具��经济控制��单次加成�?长（#5�?
const DEV_GOLD_STEP: int = 500
const DEV_POP_STEP: int = 10
const DEV_INCOME_STEP: int = 200
## 水晶下方扣�?日志条最多保留的行数
const MAX_LOG_LINES: int = 3

## 各玩家��中兵�?按钮缓存（key=player_id, value=BaseButton�?
var _selection_borders: Dictionary = {}
## 各玩家出兵闪烁动�?Tween 缓存（key=player_id, value=Tween�?
var _flash_tweens: Dictionary = {}
## #3：玩�?敌人侧按�?��的拖拽滚动�?理器（_setup_drag_scroll 返回，按�?��按滚动共�?��
var _player_drag_handler: Dictionary = {}
var _enemy_drag_handler: Dictionary = {}

## 红色衢�条主�?
const COLOR_RED: Color = Color("#D93025")
## 红色衢�条浅�?�?���?
const COLOR_RED_LIGHT: Color = Color("#FF6B6B")
## 蓝色衢�条主�?
const COLOR_BLUE: Color = Color("#1A73E8")
## 蓝色衢�条浅�?�?���?
const COLOR_BLUE_LIGHT: Color = Color("#4DABF7")
## 选中兵�?按钮的旧高亮色（已弃�?��保留防�?外部引用报错�?
const COLOR_SELECT: Color = Color(1, 0.85, 0)

func _wrap_grid_in_scroll(grid: GridContainer) -> ScrollContainer:
	## �?GridContainer 包进 ScrollContainer，使兵�?按钮超出区域时可滚动
	var parent = grid.get_parent()
	var idx = grid.get_index()
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.remove_child(grid)
	parent.add_child(scroll)
	parent.move_child(scroll, idx)
	scroll.add_child(grid)
	return scroll

## #7：日夜切换����创建全屢�叠黑层（#霢��?：已删除左上角太�?月亮按钮，仅保留叠黑层代码）
## 叠黑层作�?HUD 的�?丢��?��节点（渲染在朢�底层），盖住战场�?HUD 其余 UI 仍在之上�??�?
## 不用额�? CanvasLayer，F6 �?��运�? HUD 场景也不会因缺少父级而崩�?
## 叠黑层��辑（_is_night / _on_day_night_pressed）整体保留，供未来�?间模式入口�?�?
func _setup_day_night_toggle() -> void:
	## 叠黑层：全屏 ColorRect，忽略鼠标事�?
	_night_overlay = ColorRect.new()
	_night_overlay.name = "NightOverlay"
	_night_overlay.color = Color(0, 0, 0, NIGHT_OVERLAY_ALPHA)
	_night_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_overlay.visible = false
	add_child(_night_overlay)
	move_child(_night_overlay, 0)

## #7：切换昼夜（#霢��?：太阳按�?��删除，�?入口保留供未来�?间模式调�?��
func _on_day_night_pressed() -> void:
	AudioManager.play_ui_click()
	_is_night = not _is_night
	if _night_overlay != null and is_instance_valid(_night_overlay):
		_night_overlay.visible = _is_night
	## 首�?切换时解锁隐藏成就��日夜交替��（#7�?
	Achievements.unlock_by_id("day_night")

func _ready() -> void:
	## PlayerGrid �?EnemyGrid 已在 ScrollContainer �?��无需再包�?
	## 加载持久化的 HUD 布局配置
	## 初�?化顶部基地�?条样�?
	_setup_hp_bars()
	## #7：日夜切换����创建叠黑层与左上�?�?��按钮
	_setup_day_night_toggle()
	## 创建底部兵�?选择按钮
	_create_unit_buttons()
	## 配置左侧按钮集（PlayerScroll）的裁剪和滚�?
	call_deferred("_setup_player_scroll")
	## 将右侧按�?��（EnemyScroll）的垂直滚动条移到左�?
	call_deferred("_setup_enemy_scrollbar_left")
	## 设置顶部功能按钮样式
	_setup_buttons()
	## 创建顶部"调整"按钮（用于手动调整底部兵种按�?��的长宽和位置�?
	## 根据当前难度或模式添加顶部难度标签按�?
	_setup_difficulty_label()
	## 顶部按钮居中显示
	_update_top_buttons_centering()
	## 金币标�?应用白色字体
	_apply_bold_black_to_gold_labels()

	## 初�?化玩家经济数�?���?
	_update_gold_display(0, EconomyManager.get_gold(0), EconomyManager.get_income(0))
	## 初�?化敌人经济数�?���?
	_update_gold_display(1, EconomyManager.get_gold(1), EconomyManager.get_income(1))
	## 初�?化双方人口显�?
	_update_population_display()
	## 创建人口/收入升级按钮�?138�?
	_setup_upgrade_buttons()

	## 监听金币变化信号
	EconomyManager.gold_changed.connect(_update_gold_display)
	## 金币变化时同步刷新升级按�?��花费/�?��状��（#138�?
	EconomyManager.gold_changed.connect(_on_gold_changed_refresh_upgrades)
	## 监听倒�?时信号以更新回合时间
	BattleManager.countdown_tick.connect(_update_timer)
	## 监听兵�?生成信号以更新人口与�?��提示
	BattleManager.unit_spawned.connect(_on_unit_spawned)
	## 监听兵�?移除信号以更新人�?
	BattleManager.unit_removed.connect(_on_unit_removed)
	## 监听选中变化信号以高�??应按�?
	BattleManager.selection_changed.connect(_on_selection_changed)
	## 监听基地扣�?信号以更新水晶下方日志条
	BattleManager.base_damaged.connect(_on_base_damaged)
	## 连接顶部按钮点击事件
	help_btn.pressed.connect(_on_help_pressed)
	## #3�?026-08-09）：�?��按钮与兵种按�?��致����鼠标悬�?tooltip 立即显示�?��正文，点击才进编�?
	help_btn.tooltip_text = ItemDatabase.get_help_text()
	## #17：顶部�?�?���?�� ESC 行为丢�致����打弢�设置即暂停��再点关�?��恢�?（原仅打弢�不暂停）
	settings_btn.pressed.connect(toggle_settings_pause)
	exit_btn.pressed.connect(_on_exit_pressed)
	dev_btn.pressed.connect(_on_dev_tool_pressed)
	adjust_btn.pressed.connect(_on_adjust_pressed)
	## #新需求：弢�发工�?调整按钮仅开发��模式可见����初始化显隐并监�?���?
	DevMode.dev_mode_changed.connect(_apply_dev_gating)
	DevMode.hide_in_battle_top_buttons_changed.connect(_on_hide_in_battle_top_buttons_changed)
	_apply_dev_gating()
	## 监听设置变化信号以重新应用本地化
	SettingsManager.settings_changed.connect(_apply_localization)
	## 首�?应用�?��化文�?
	_apply_localization()
	## 肉鸽模式下隐藏经�?兵�?/基地衢�条等无关控件（手牌由 RoguelikeHUD �?��层负责）
	_apply_roguelike_layout()
	## 捕获信息面板初�?偏移基准并应用持久化偏移�?调整面板�?
	_left_base = {"l": left_panel.offset_left, "t": left_panel.offset_top, "r": left_panel.offset_right, "b": left_panel.offset_bottom}
	_right_base = {"l": right_panel.offset_left, "t": right_panel.offset_top, "r": right_panel.offset_right, "b": right_panel.offset_bottom}
	## 把���?时标签包进可�?��偏移的插槽（#3�?
	_setup_timer_slot()
	## #18：把�?蓝顶部水�?HP 条包进可�?��偏移的插�?
	_setup_hp_bar_slots()
	_apply_saved_info_panel_offset()
	## 窗口尺�?变化时重新做边界约束，保证信�?��板永远留在可视区内（#1�?
	get_viewport().size_changed.connect(_on_viewport_resized)

## 肉鸽模式布局：隐藏与金币经济、基地水晶��固定兵种��择相关的控�?
## 常�?模式下�?函数不做任何事，保证对既有战�?双人流程零影�?
func _apply_roguelike_layout() -> void:
	if not RoguelikeManager.is_active:
		return
	## 无基�?�?隐藏顶部双方衢��?
	red_hp.visible = false
	blue_hp.visible = false
	## 无金币经�?�?隐藏两侧经济数据面板
	var left_panel := get_node_or_null("LeftSidePanel") as Control
	if left_panel != null:
		left_panel.visible = false
	var right_panel := get_node_or_null("RightSidePanel") as Control
	if right_panel != null:
		right_panel.visible = false
	## 兵�?不再固定�?��?�?隐藏底部兵�?按钮面板，改由手牌面板出�?
	var bottom_panel := get_node_or_null("BottomPanel") as Control
	if bottom_panel != null:
		bottom_panel.visible = false

## 给两侧金�?人口/收入标�?应用黑色粗体�?14：三行统丢�黑色�?
func _apply_bold_black_to_gold_labels() -> void:
	var bold_font := _make_bold_font()
	for lbl in [player_gold_label, player_pop_label, player_income_label,
			enemy_gold_label, enemy_pop_label, enemy_income_label]:
		if lbl == null or not is_instance_valid(lbl):
			continue
		lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
		if bold_font != null:
			lbl.add_theme_font_override("font", bold_font)

func _setup_hp_bars() -> void:
	## 红方水晶衢�条填充（�?��样式必须挂在 ProgressBar 节点�?��，��非外层 VBox，否则显示默认灰�?
	var red_fill = StyleBoxFlat.new()
	red_fill.bg_color = COLOR_RED
	red_hp_bar.add_theme_stylebox_override("fill", red_fill)

	## 蓝方水晶衢�条填�?
	var blue_fill = StyleBoxFlat.new()
	blue_fill.bg_color = COLOR_BLUE
	blue_hp_bar.add_theme_stylebox_override("fill", blue_fill)

	## #1：在衢�条上叠加衢�量数�?Label（居�?��示��当前�?/满�?」）
	red_hp_label = _create_hp_label(red_hp_bar)
	blue_hp_label = _create_hp_label(blue_hp_bar)
	## #16：水晶�?条数值显隐跟随�?�?��关（默�?弢��?
	red_hp_label.visible = SettingsManager.show_hp_armor_bar
	blue_hp_label.visible = SettingsManager.show_hp_armor_bar

	## �?��水晶下方扣�?日志条可见（�?��应高度，避免�?压扁看不见）
	## 注意：Godot 4 �?RichTextLabel.append_text() 在某些情况下不写�?text�?
	## 故日志一律用 .text += 拼接；关�?bbcode 以免 [名字] �?��成标签吞�?
	for log_label: RichTextLabel in [red_battle_log, blue_battle_log]:
		log_label.bbcode_enabled = false
		log_label.fit_content = true
		log_label.custom_minimum_size = Vector2(0, 48)
		log_label.scroll_active = false
		log_label.text = ""

## #1：在衢�条上创建居中的�?量数�?Label
## bar: 衢��?ProgressBar 节点，Label 叠在其上方居�?
func _create_hp_label(bar: ProgressBar) -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(lbl)
	return lbl

## 更新底部�?��封面图�?览（选中兵�?时放大显示其行走/奔跑动��动画）
## player_id: 触发选中变化的玩�?ID�?=玩�?, 1=敌人�?
func _update_center_preview(player_id: int) -> void:
	var res: UnitResource = null
	## 双人模式优先显示玩�?侧（player_id=0）的选中兵�?；单人模式只处理玩�?�?
	if BattleManager.is_two_player:
		## 双人模式：玩家��中则显示玩家兵种，否则显示敌人兵�?（若敌人有��中�?
		var show_pid: int = 0 if BattleManager.selected_units[0] != null else 1
		res = BattleManager.selected_units[show_pid]
		## 仅当当前触发方与展示方一致时才更新，避免互相覆盖
		if player_id != show_pid and res != null:
			return
	else:
		## 单人模式：只显示玩�?侧��中兵�?
		if player_id != 0:
			return
		res = BattleManager.selected_units[0]
	## 取消选中时隐藏封面图并移除动画精�?
	if res == null:
		center_preview.visible = false
		center_preview.texture = null
		_remove_center_anim_sprite()
		return
	## 加载兵�?动画帧（优先 walk > move > attack�?
	var anim_data = _load_unit_frames(res.unit_id)
	if anim_data.is_empty():
		center_preview.visible = false
		_remove_center_anim_sprite()
		return
	## 隐藏静��?TextureRect，显示动�?AnimatedSprite2D
	center_preview.texture = null
	center_preview.visible = true
	_update_center_anim_sprite(anim_data["frames"], anim_data["anim_name"], res)

## 计算静���?览（视为朝右 forward）时某动画的 flip_h�?
## 逻辑�?unit_base._apply_anim_flip 丢�致（�?��动画 flip_override），
## �?HUD 兵�?按钮/�?��预�?与实际�?屢��?��朝向保持丢�致（�?? D3/N3 朝向反，#141）��?
func _preview_flip_for(res: UnitResource, anim_name: String) -> bool:
	var base_flip: bool = (1 != res.default_facing)  # 预�?假�?兵�?朝右
	var override: int = 0
	match anim_name:
		"move": override = res.move_flip_override
		"walk": override = res.walk_flip_override
		"attack": override = res.attack_flip_override
		"idle": override = res.idle_flip_override
		"sprint": override = res.sprint_flip_override
		_: override = 0
	if override == 1:
		return not base_flip
	return base_flip

## 更新或创建中�?��面的动��动画精�?
func _update_center_anim_sprite(frames: SpriteFrames, anim_name: String, res: UnitResource) -> void:
	## #19：�?用单实例精灵，不再每次新建（旧实�?queue_free 延迟释放 �?�?��连点残留叠加）
	if _center_anim_sprite == null or not is_instance_valid(_center_anim_sprite):
		_center_anim_sprite = AnimatedSprite2D.new()
		_center_anim_sprite.name = "CenterAnimSprite"
		_center_anim_sprite.centered = true
		center_preview.add_child(_center_anim_sprite)
	## �?��旧的 resized 连接，避免信号累�?��同帧多�?更新时旧回调会残留）
	if _center_preview_resize_cb.is_valid() and center_preview.resized.is_connected(_center_preview_resize_cb):
		center_preview.resized.disconnect(_center_preview_resize_cb)
	_center_anim_sprite.sprite_frames = frames
	_center_anim_sprite.play(anim_name)
	## 根据默�?朝向 + 每动画翻�??盖�?�?���?��与�?屢�内一致，#141�?
	_center_anim_sprite.flip_h = _preview_flip_for(res, anim_name)
	## 更新精灵位置和缩放（�?��捕获的是成员引用，�?终指向当前精灵）
	var update_transform := func():
		if _center_anim_sprite == null or not is_instance_valid(_center_anim_sprite):
			return
		_center_anim_sprite.position = center_preview.size * 0.5
		if frames != null and frames.get_frame_count(anim_name) > 0:
			var tex = frames.get_frame_texture(anim_name, 0)
			if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
				## �?��显示尺�?（CenterPreview 大小，取较小边作为统丢�尺�?�?
				var target_size: float = minf(center_preview.size.x, center_preview.size.y)
				var scale_val: float = target_size / maxf(float(tex.get_width()), float(tex.get_height()))
				_center_anim_sprite.scale = Vector2(scale_val, scale_val)
	_center_preview_resize_cb = update_transform
	update_transform.call()
	center_preview.resized.connect(_center_preview_resize_cb)

## 移除�?��封面的动态动画精�?
func _remove_center_anim_sprite() -> void:
	## #19：同步移�?+ �?��信号，杜绝旧精灵跨帧残留
	if _center_preview_resize_cb.is_valid() and center_preview.resized.is_connected(_center_preview_resize_cb):
		center_preview.resized.disconnect(_center_preview_resize_cb)
	_center_preview_resize_cb = Callable()
	if _center_anim_sprite != null and is_instance_valid(_center_anim_sprite):
		center_preview.remove_child(_center_anim_sprite)
		_center_anim_sprite.queue_free()
	_center_anim_sprite = null

func _setup_difficulty_label() -> void:
	## #15：肉鸽模式不显示战役难度按钮（�?按钮服务于战�?双人难度切换，肉鸽无难度概念�?
	if RoguelikeManager.is_active:
		return
	## #2�?026-08-09）：难度/模式按钮由��disabled �?��示��改为��可点击」����点击弹出文�?��辑�?�?
	## 编辑当前模式/难度的悬停提示文�?��与战役地�?#12 的难度提示编辑�?齐），保存后立即生效并持久化�?
	var btn := Button.new()
	btn.name = "DifficultyBtn"
	diff_btn = btn
	## 与其他顶部按�?��持一致的朢�小尺�?
	btn.custom_minimum_size = Vector2(80, 28)
	## 根据当前难度设置文本
	match GameManager.current_difficulty:
		0: btn.text = tr("DIFFICULTY_EASY")
		1: btn.text = tr("DIFFICULTY_NORMAL")
		2: btn.text = tr("DIFFICULTY_HARD")
		_: btn.text = tr("DIFFICULTY_NORMAL")
	## 双人模式显示双人模式文本
	if BattleManager.is_two_player:
		btn.text = tr("TWO_PLAYER_MODE")
	## #2：悬停提�?= �?��义优先，回落内置默�?（文案与战役地图 campaign_map 保持丢�致）
	btn.tooltip_text = _get_hud_diff_tip()
	btn.pressed.connect(_on_diff_btn_pressed)
	## 与其他顶部按�?��丢�使用 UIButtonHelper 设置纹理样式
	UIButtonHelper.setup_button(btn)
	## 将难度按�?��入顶部按�??器最左侧
	$TopCenterButtons.add_child(btn)
	$TopCenterButtons.move_child(btn, 0)
	## 重新居中
	_update_top_buttons_centering()

## HUD 难度/模式提示�?��义文�?��久化�?���?2，与战役地图 campaign_diff_tips.cfg �?��，互不影响）
const HUD_DIFF_TIPS_PATH: String = "user://hud_diff_tips.cfg"

## 当前屢�难度/模式的提示存储键�?2）：双人模式�?���?��其余按难�?0/1/2
func _hud_diff_tip_key() -> String:
	return "2p" if BattleManager.is_two_player else "diff_%d" % GameManager.current_difficulty

## 读取难度/模式�?��提示：自定义优先，回落内�?��认（#2�?
func _get_hud_diff_tip() -> String:
	var key: String = _hud_diff_tip_key()
	var cfg := ConfigFile.new()
	if cfg.load(HUD_DIFF_TIPS_PATH) == OK:
		var custom: String = String(cfg.get_value("tips", key, ""))
		if custom != "":
			return custom
	if BattleManager.is_two_player:
		return "双人模式：左右两侧由两名玩家分别操控，不参与 AI 难度"
	match GameManager.current_difficulty:
		0: return "普通难度：敌方兵种与玩家同档，适合熟悉战斗机制"
		1: return "困难难度：敌方兵种高一个 tier，挑战升级"
		2: return "地狱难度：敌方更强，极限挑战"
	return "普通难度：敌方兵种与玩家同档，适合熟悉战斗机制"

## 保存难度/模式�?��提示�?2）：清空即恢复默�?
func _save_hud_diff_tip(text: String) -> void:
	var key: String = _hud_diff_tip_key()
	var cfg := ConfigFile.new()
	cfg.load(HUD_DIFF_TIPS_PATH)
	var clean: String = text.strip_edges()
	cfg.set_value("tips", key, clean)
	cfg.save(HUD_DIFF_TIPS_PATH)

## 点击难度/模式按钮 �?弹出提示文本编辑框（#2�?
## #7�?026-08-11 用户拍板）：�?DevMode 点击弹出该按�?��说明文本（不再弹「不�?��辑��提示）
func _on_diff_btn_pressed() -> void:
	if not DevMode.enabled:
		_show_toast(_get_hud_diff_tip())
		return
	if diff_btn == null or not is_instance_valid(diff_btn):
		return
	var dlg := ConfirmationDialog.new()  ## �?ConfirmationDialog：Godot 4.7 �?AcceptDialog 已无取消按钮/�?cancel_button_text
	dlg.title = "编辑模式/难度提示"
	dlg.dialog_text = ""
	dlg.ok_button_text = "保存"
	dlg.cancel_button_text = "取消"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dlg)
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(360, 120)
	edit.text = _get_hud_diff_tip()
	edit.placeholder_text = "输入自定义提示文本（清空恢复默认）"
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	dlg.add_child(edit)
	dlg.confirmed.connect(func() -> void:
		_save_hud_diff_tip(edit.text)
		diff_btn.tooltip_text = _get_hud_diff_tip()
		_show_toast("难度提示已保存")
	)
	dlg.popup_centered()

## 顶部居中轻提示（�?�� toast�? 秒后�?��消失；暂停场�?��能显示，process_mode=ALWAYS�?
## #7�?026-08-11）：加自动换行与朢�大�?度，长文�?��如帮助�?文）也能完整展示
func _show_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_left = -400.0
	toast.offset_top = 120.0
	toast.offset_right = 400.0
	toast.offset_bottom = 240.0
	toast.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	toast.add_theme_constant_override("outline_size", 2)
	add_child(toast)
	var t := Timer.new()
	t.wait_time = 2.0
	t.one_shot = true
	add_child(t)
	t.timeout.connect(func() -> void:
		if is_instance_valid(toast):
			toast.queue_free()
		t.queue_free()
	)
	t.start()

func _setup_buttons() -> void:
	## 为帮助���?�?�����出��开发工具按�?��用统丢��?���??�?
	for btn in [help_btn, settings_btn, exit_btn, dev_btn]:
		UIButtonHelper.setup_button(btn)


## 配置左侧按钮集（PlayerScroll）的裁剪和滚�?
## �?��超出容器高度的按�??隐藏，��过滚动查看
func _setup_player_scroll() -> void:
	var player_scroll: ScrollContainer = $BottomPanel/BottomHBox/LeftColumn/PlayerScroll
	## �?��裁剪内�?（超出�?器高度的子节点�?隐藏，��过滚动查看�?
	player_scroll.clip_contents = true
	## 设置垂直滚动模式为自�?��内�?超出时显示滚动条�?
	player_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	## 设置水平滚动模式为�?�?��兵�?按钮集不霢�要水平滚�?��
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	## 强制滚动条�?度为 8px（避免默认主题过粗）
	player_scroll.add_theme_constant_override("scrollbar_margin", 0)
	player_scroll.add_theme_stylebox_override("scrollbar", _make_thin_scroll_style())
	var vbar: VScrollBar = player_scroll.get_v_scroll_bar()
	if vbar != null:
		vbar.custom_minimum_size = Vector2(8, 0)

## 将右侧按�?��（EnemyScroll）的垂直滚动条移到左�?
## 并强制�?�?��动条宽度�?8px（避免默认主题过粗）
func _setup_enemy_scrollbar_left() -> void:
	var enemy_scroll: ScrollContainer = $BottomPanel/BottomHBox/RightColumn/EnemyScroll
	## �?��裁剪内�?（超出�?器高度的子节点�?隐藏，��过滚动查看�?
	enemy_scroll.clip_contents = true
	## 设置垂直滚动模式为自�?��内�?超出时显示滚动条�?
	enemy_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	## 设置水平滚动模式为�?�?��兵�?按钮集不霢�要水平滚�?��
	enemy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbar: VScrollBar = enemy_scroll.get_v_scroll_bar()
	if vbar == null:
		return
	## 通过主�?覆盖强制滚动条�?度为 8px
	enemy_scroll.add_theme_constant_override("scrollbar_margin", -8)
	enemy_scroll.add_theme_stylebox_override("scrollbar", _make_thin_scroll_style())
	## 设置滚动条自�?��朢�小尺寸限�?
	vbar.custom_minimum_size = Vector2(8, 0)
	## 连接信号：滚动条或�?器尺寸变化时重新定位到左�?
	if not vbar.resized.is_connected(_force_vbar_left):
		vbar.resized.connect(_force_vbar_left.bind(vbar))
	if not enemy_scroll.resized.is_connected(_force_vbar_left):
		enemy_scroll.resized.connect(_force_vbar_left.bind(vbar))
	## 立即执�?丢��?
	_force_vbar_left(vbar)

## 生成细滚动条样式（�?�?8px，半透明�?
func _make_thin_scroll_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

## #15a/#3：ScrollContainer 鼠标拖拽滚动（默认只响应滚轮/滚动条）
## 返回滚动处理器字典（#3），包含 scroll / grid 引用�?
## 拖拽状����过 grid 节点 meta 共享，避�?Dictionary 内联�?���?Godot 4 �?
## 因捕获变量生命周期�?致闭包失效��?
func _setup_drag_scroll(scroll: ScrollContainer, grid: Control) -> Dictionary:
	grid.set_meta("_drag_scroll", scroll)
	grid.set_meta("_drag_active", false)
	grid.set_meta("_drag_start_y", 0.0)
	grid.set_meta("_scroll_start", 0)
	grid.gui_input.connect(func(event: InputEvent):
		var s: ScrollContainer = grid.get_meta("_drag_scroll")
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grid.set_meta("_drag_active", true)
				grid.set_meta("_drag_start_y", event.global_position.y)
				grid.set_meta("_scroll_start", s.scroll_vertical)
			else:
				grid.set_meta("_drag_active", false)
		elif event is InputEventMouseMotion and bool(grid.get_meta("_drag_active")):
			var start_y: float = float(grid.get_meta("_drag_start_y"))
			var scroll_start: int = int(grid.get_meta("_scroll_start"))
			var dy: float = event.global_position.y - start_y
			s.scroll_vertical = scroll_start - int(dy)
	)
	return {"scroll": scroll, "grid": grid}

## 强制�?EnemyScroll 的垂直滚动条重定位到左侧
## ScrollContainer 内部布局会�?盖单次�?�?��霢�要每帧持�?���?
func _force_vbar_left(vbar: VScrollBar) -> void:
	## 标�?霢�要在 _process �?���?���?
	_enemy_vbar = vbar
	set_process(true)

## 实际执�?滚动条重定位（将锚点从右侧改到左侧，宽度固定 8px�?
func _do_force_vbar_left(vbar: VScrollBar) -> void:
	if not is_instance_valid(vbar):
		return
	## 锚点设为左边界（anchor_left=0, anchor_right=0），宽度 8px
	vbar.anchor_left = 0.0
	vbar.anchor_right = 0.0
	vbar.offset_left = 0.0
	vbar.offset_right = 8.0
	vbar.offset_top = 0.0
	vbar.offset_bottom = 0.0
	## 强制朢�小�?�?8px（防�?��题�?盖）
	vbar.custom_minimum_size = Vector2(8, 0)

## 每帧强制维护滚动条位�?��覆盖 ScrollContainer 内部布局�?
func _process(_delta: float) -> void:
	if _enemy_vbar != null and is_instance_valid(_enemy_vbar):
		_do_force_vbar_left(_enemy_vbar)

## 创建顶部"调整"按钮（放在四�?���?��前面�?
## 点击后显�?隐藏调整面板，可手动调整底部兵�?按钮集的宽度、高度��X位置、Y位置
func _apply_localization() -> void:
	## 更新顶部按钮文本
	help_btn.text = tr("HELP")
	settings_btn.text = tr("SETTINGS")
	adjust_btn.text = "调整"
	exit_btn.text = tr("EXIT")

	## 更新难度/模式显示按钮文本
	var diff_btn = $TopCenterButtons.get_node_or_null("DifficultyBtn")
	if diff_btn != null:
		if BattleManager.is_two_player:
			diff_btn.text = tr("TWO_PLAYER_MODE")
		else:
			match GameManager.current_difficulty:
				0: diff_btn.text = tr("DIFFICULTY_EASY")
				1: diff_btn.text = tr("DIFFICULTY_NORMAL")
				2: diff_btn.text = tr("DIFFICULTY_HARD")
				_: diff_btn.text = tr("DIFFICULTY_NORMAL")

	## 更新扢�有兵种按�?tooltip（文字信�?��过鼠标�?��显示�?
	for i in range(unit_buttons.size()):
		var res: UnitResource = unit_buttons[i].get_meta("unit_resource")
		unit_buttons[i].tooltip_text = "%s\n$%d\n%s:%d %s:%d %s:%d %s:%.1f %s:%.1f" % [
			res.get_display_name(), res.cost,
			tr("HP_LABEL"), res.max_hp, tr("ARMOR_LABEL"), res.armor_value, tr("DAMAGE_LABEL"), res.damage,
			tr("MOVE_SPEED_LABEL"), res.move_speed, tr("ATTACK_RANGE_LABEL"), res.attack_range]
		if i < enemy_buttons.size():
			enemy_buttons[i].tooltip_text = unit_buttons[i].tooltip_text

	## 刷新经济数据、人口与设置对话框本地化
	_update_gold_display(0, EconomyManager.get_gold(0), EconomyManager.get_income(0))
	_update_gold_display(1, EconomyManager.get_gold(1), EconomyManager.get_income(1))
	_update_population_display()
	_update_settings_dialog_localization()

func _update_top_buttons_centering() -> void:
	## 获取顶部按钮容器
	var top = $TopCenterButtons
	## 重新计算容器大小
	top.reset_size()
	## 获取容器宽度
	var width = top.size.x
	## 以屏幕中心为锚点，左右�?称偏�?
	top.offset_left = -width * 0.5
	top.offset_right = width * 0.5

func _setup_button_style(btn: Button) -> void:
	## �?��状态样�?
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	normal.border_color = Color(0.5, 0.5, 0.5, 0.7)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("disabled", normal)

	## �?��状��样�?
	var hover = normal.duplicate()
	hover.bg_color = Color(0.35, 0.35, 0.35, 0.95)
	hover.border_color = Color(0.8, 0.8, 0.8, 0.9)
	btn.add_theme_stylebox_override("hover", hover)

	## 按下状��样�?
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.15, 0.15, 0.15, 1)
	pressed.border_color = Color(1, 0.85, 0, 1)
	pressed.set_border_width_all(3)
	btn.add_theme_stylebox_override("pressed", pressed)

func _create_unit_buttons() -> void:
	## #3�?026-08-11）：拖拽滚动 handler 必须在创建按�?��就绪（按�?gui_input 依赖它）�?
	## 用已�?���?@onready 节点直接设置，不再依�?_ready �?���?call_deferred 滚动 setup�?
	var player_scroll: ScrollContainer = $BottomPanel/BottomHBox/LeftColumn/PlayerScroll
	var enemy_scroll: ScrollContainer = $BottomPanel/BottomHBox/RightColumn/EnemyScroll
	_player_drag_handler = _setup_drag_scroll(player_scroll, player_grid)
	_enemy_drag_handler = _setup_drag_scroll(enemy_scroll, enemy_grid)

	## 获取扢�有兵种数�?��按解锁顺序）
	var units = UnitDatabase.unit_list.duplicate()  ## 拷贝，避免 DevMode 追加隐藏兵种污染全局 unit_list

	## 战役模式按固定编�?+ 难度过滤，非战役模式全部�?��
	var player_ids: Array[String] = []
	var enemy_ids: Array[String] = []
	if GameManager.is_campaign_mode:
		var level: int = GameManager.selected_campaign_level
		## 玩�?�?��兵�?：普通模式全部已解锁；困�?地狱模式受限为本关固定编�?
		player_ids = CampaignProgress.get_player_unit_ids_for_difficulty(level, GameManager.current_difficulty)
		## 敌方�?��兵�?：本关固定编成（玩�?已解�?+ �?��新兵种）
		enemy_ids = CampaignProgress.get_enemy_unit_ids_for_level(level)
	else:
		## 双人 / 全面战争
		## #15�?026-08-11）：非开发��模式下解锁规则与战役模式一致（常驻 + 关卡首��?+
		## 战功�?�� + 星星），不再「沙盒全放开�?��星星门�?」；弢�发��模式下
		## is_unit_unlocked �?DevMode 分支�?��全解锁（�?���?异象，�? campaign_progress.gd）��?
		for u in units:
			if not CampaignProgress.is_unit_unlocked(u.unit_id):
				continue
			player_ids.append(u.unit_id)
			enemy_ids.append(u.unit_id)
		## #自由事件（2026-08-15）：DevMode 下把有实际素材的隐藏事件兵种 S2（仓鼠士兵）/Y2（凑企鹅）
		## 追加进按钮集。S3/Y3/Y4 为占位兵种（素材待补）不放；战役模式仍走固定编成不受影响。
		if DevMode.enabled:
			for hid in ["S2", "Y2"]:
				if hid in player_ids:
					continue
				player_ids.append(hid)
				enemy_ids.append(hid)
				var hres: Resource = UnitDatabase.get_unit(hid)
				if hres != null:
					units.append(hres)

	## 玩�?�?��兵�?（按 GDFN 顺序排序用于显示�?
	var player_units: Array = []
	for u in units:
		if u.unit_id in player_ids:
			player_units.append(u)
	player_units.sort_custom(func(a, b):
		var ka = _unit_sort_key(a.unit_id)
		var kb = _unit_sort_key(b.unit_id)
		if ka[0] != kb[0]:
			return ka[0] < kb[0]
		return ka[1] < kb[1])

	## 敌方实际拥有的兵种（显示它有仢�么兵�?
	var enemy_units: Array = []
	for u in units:
		if u.unit_id in enemy_ids:
			enemy_units.append(u)
	enemy_units.sort_custom(func(a, b):
		var ka = _unit_sort_key(a.unit_id)
		var kb = _unit_sort_key(b.unit_id)
		if ka[0] != kb[0]:
			return ka[0] < kb[0]
		return ka[1] < kb[1])

	## 加载按钮背景纹理（空白按�?���?��
	var button_bg_tex: Texture2D = load("res://assets/ui/unit_button_bg.png")

	## 按阵�?G/D/F/N 分组创建四�?按钮
	_create_faction_rows(player_units, player_grid, button_bg_tex, 0, unit_buttons, _player_row_sizes, _player_drag_handler)
	_create_faction_rows(enemy_units, enemy_grid, button_bg_tex, 1, enemy_buttons, _enemy_row_sizes, _enemy_drag_handler)

## 按阵�?G/D/F/N 分组创建四�?按钮（每行一�?HBoxContainer�?
## units: 已排序的兵�?资源数组
## container: VBoxContainer 父�?�?
## bg_tex: 按钮背景纹理
## team_id: 阵营 ID�?=玩�?, 1=敌人�?
## buttons_array: 按钮数组（用于存储创建的按钮�?
## row_sizes: 行尺寸数组（用于存储每�?的按�?��量，供键盘�?�?���?��
func _create_faction_rows(units: Array, container: VBoxContainer, bg_tex: Texture2D, team_id: int, buttons_array: Array, row_sizes: Array[int], drag_handler: Dictionary) -> void:
	## 阵营定义：前缢� -> 阵营�?
	var factions: Array = [
		["G", "咕嘎"],
		["D", "Doro"],
		["F", "菲比丘比"],
		["N", "糯糯"],
	]
	## DevMode 下追加特�?异象/英雄阵营行（这些兵�?不在常�? GDFN 分组�?��
	if DevMode.enabled:
		var has_s := false
		var has_y := false
		var has_hero := false
		for res in units:
			if res.unit_id.begins_with("S"): has_s = true
			elif res.unit_id.begins_with("Y"): has_y = true
			elif res.unit_id.begins_with("Hero"): has_hero = true
		if has_hero: factions.append(["Hero", "英雄"])
		if has_s: factions.append(["S", "特殊"])
		if has_y: factions.append(["Y", "异象"])
	row_sizes.clear()
	## 全局按钮索引
	var global_index: int = 0
	for faction in factions:
		var prefix: String = faction[0]
		## 收集该阵营的单位
		var faction_units: Array = []
		for res in units:
			if res.unit_id.begins_with(prefix):
				faction_units.append(res)
		## 记录该�?的按�?��量（0 表示该阵营无�?��单位�?
		row_sizes.append(faction_units.size())
		## 无单位的阵营不创建空行，避免布局留白
		if faction_units.is_empty():
			continue
		## 创建丢��?HBoxContainer
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(row)
		## 添加该阵营的按钮
		for res in faction_units:
			var btn = _create_unit_button(res, bg_tex, team_id, global_index, drag_handler)
			row.add_child(btn)
			buttons_array.append(btn)
			global_index += 1

## 兵�?排序�?��返回 [阵营序号, 数字]，G=0, D=1, F=2, N=3, Hero=4, S=5, Y=6
## 用于�?GDFN+HeroSY 顺序排序（同字母内按数字升序�?
func _unit_sort_key(unit_id: String) -> Array:
	var faction_order = {"G": 0, "D": 1, "F": 2, "N": 3, "Hero": 4, "S": 5, "Y": 6}
	var faction = unit_id[0]
	var num = unit_id.substr(1).to_int()
	return [faction_order.get(faction, 99), num]

## 创建单个兵�?按钮（TextureButton 背景 + 行走/奔跑�?��帧半�?���?
## 文字信息（名�?造价/属��）通过鼠标�?�� tooltip 显示，不在按�?��显示
## res: 兵�?资源
## bg_tex: 按钮背景纹理（空白按�?���?��
## team_id: 阵营 ID�?=玩�?, 1=敌人�?
## index: 按钮索引
## drag_handler: _setup_drag_scroll 返回的滚动�?理器�?3：长按拖动滚动按�?��，不拖动按钮�?���?
## 返回�? 配置好的 TextureButton
func _create_unit_button(res: UnitResource, bg_tex: Texture2D, team_id: int, index: int, drag_handler: Dictionary) -> TextureButton:
	var btn = TextureButton.new()
	btn.custom_minimum_size = Vector2(80, 80)
	## 设置背景纹理（normal/pressed/hover 都用同一张空白按�?���?��
	btn.texture_normal = bg_tex
	btn.texture_pressed = bg_tex
	btn.texture_hover = bg_tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE

	## tooltip 显示完整属��（鼠标�?��时显示）
	btn.tooltip_text = "%s\n$%d\n%s:%d %s:%d %s:%d %s:%.1f %s:%.1f" % [
		res.get_display_name(), res.cost,
		tr("HP_LABEL"), res.max_hp, tr("ARMOR_LABEL"), res.armor_value, tr("DAMAGE_LABEL"), res.damage,
		tr("MOVE_SPEED_LABEL"), res.move_speed, tr("ATTACK_RANGE_LABEL"), res.attack_range]

	## 加载兵�?动画帧（优先 walk > move > attack），�?AnimatedSprite2D 动��显�?
	var anim_data = _load_unit_frames(res.unit_id)
	if not anim_data.is_empty():
		var frames: SpriteFrames = anim_data["frames"]
		var anim_name: String = anim_data["anim_name"]
		## 创建动��精灵节点（AnimatedSprite2D �?Node2D，在 Control 内需手动定位�?
		var sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.centered = true
		sprite.play(anim_name)
		## 根据默�?朝向 + 每动画翻�??盖�?�?���?��与�?屢�内一致，#141�?
		sprite.flip_h = _preview_flip_for(res, anim_name)
		sprite.name = "UnitAnimSprite"
		btn.add_child(sprite)
		## 更新精灵位置和缩放（按钮�?�� + 适应按钮大小�?
		var update_transform = func():
			if not is_instance_valid(sprite):
				return
			sprite.position = btn.size * 0.5
			if frames != null and frames.get_frame_count(anim_name) > 0:
				var tex = frames.get_frame_texture(anim_name, 0)
				if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
					## �?��显示尺�?（按�?���?px后的区域，取较小边作为统丢�尺�?�?
					var target_size: float = minf(btn.size.x - 10.0, btn.size.y - 10.0)
					var scale_val: float = target_size / maxf(float(tex.get_width()), float(tex.get_height()))
					sprite.scale = Vector2(scale_val, scale_val)
		update_transform.call()
		btn.resized.connect(update_transform)

	## 文字信息已改为鼠标悬�?tooltip 显示，不在按�?��创建文字标�?

	## TextureButton 已��过 texture_normal/pressed/hover 设置纹理，不再调�?UIButtonHelper
	## （UIButtonHelper.setup_button 仅接�?Button 类型，TextureButton �?Button 同为 BaseButton 派生�?

	## 绑定兵�?资源与索引元数据
	btn.set_meta("unit_resource", res)
	btn.set_meta("index", index)
	## #3（2026-08-14）：记下所属网格，供 _on_unit_pressed 读取「手势抑制选中」标记
	btn.set_meta("drag_grid", drag_handler["grid"])
	## 非双人模式下禁用敌人侧按�?
	if team_id == 1 and not BattleManager.is_two_player:
		btn.disabled = true
	## 连接点击事件
	btn.pressed.connect(_on_unit_pressed.bind(btn, team_id))
	## 按下时缩小按�?��松开时恢复（以中心为轴缩放）
	btn.button_down.connect(func():
		if is_instance_valid(btn):
			btn.pivot_offset = btn.size / 2.0
			btn.scale = Vector2(0.92, 0.92)
	)
	btn.button_up.connect(func():
		if is_instance_valid(btn):
			btn.scale = Vector2(1.0, 1.0)
	)
	## #3：长按拖动按�?�?滚动整个按钮集（不再�??觉拖动按�?���?��
	## 拖动位移超过 8px 视为滚动手势，松手时屏蔽�?��发的「出兵��点�?
	## 拖拽状��存储在 grid 节点 meta 上，grid 与按�?��用同丢�网格节点即可共享状����?
	var _btn_drag_y := 0.0
	var _btn_dragged := false
	## #2（2026-08-17）：长按详情改为「按住左键并保持不动 + 长按」触发（不再悬停触发）
	var _long_press_timer: Timer = Timer.new()
	_long_press_timer.name = "LongPressTimer"
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = float(UNIT_LONG_PRESS_MSEC) / 1000.0
	btn.add_child(_long_press_timer)
	_long_press_timer.timeout.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		if _btn_dragged:
			return
		btn.set_meta("long_press_triggered", true)
		var lp_res: UnitResource = btn.get_meta("unit_resource")
		## 长按亦视为「非选中手势」：标记网格抑制选中，并在详情弹窗期间屏蔽点兵种
		var _gg: Control = drag_handler["grid"]
		if is_instance_valid(_gg):
			_gg.set_meta("_gesture_scroll", true)
		_show_unit_detail_popup(lp_res, btn)
	)
	## 仅在「按住左键」时启动长按计时（悬停不再触发）；离开按钮或松手取消
	btn.mouse_exited.connect(func() -> void:
		if is_instance_valid(btn):
			_long_press_timer.stop()
	)
	btn.gui_input.connect(func(event: InputEvent):
		if not is_instance_valid(btn):
			return
		var g: Control = drag_handler["grid"]
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_btn_drag_y = event.global_position.y
				_btn_dragged = false
				btn.set_meta("dragging", false)
				btn.set_meta("long_press_triggered", false)
				g.set_meta("_drag_active", true)
				g.set_meta("_drag_start_y", event.global_position.y)
				var s: ScrollContainer = drag_handler["scroll"]
				g.set_meta("_scroll_start", s.scroll_vertical)
				## 手势开始：清除「滚动/长按抑制选中」标记（#3 修复：滚动手势期间不选中兵种）
				g.set_meta("_gesture_scroll", false)
				## 按住左键才开始长按计时（满足「长按且鼠标不动」才弹详情）
				_long_press_timer.start()
			else:
				if _btn_dragged:
					btn.set_meta("dragging", true)
				g.set_meta("_drag_active", false)
				_long_press_timer.stop()
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and bool(g.get_meta("_drag_active")):
			if not _btn_dragged and absf(event.global_position.y - _btn_drag_y) > 8.0:
				_btn_dragged = true
				_long_press_timer.stop()
				## 一旦判定为拖动（滚动手势），立即标记抑制选中：解决「松开时 pressed 先于 dragging 置位」的时序问题
				btn.set_meta("dragging", true)
				g.set_meta("_gesture_scroll", true)
			var start_y: float = float(g.get_meta("_drag_start_y"))
			var scroll_start: int = int(g.get_meta("_scroll_start"))
			var dy: float = event.global_position.y - start_y
			var s2: ScrollContainer = drag_handler["scroll"]
			s2.scroll_vertical = scroll_start - int(dy)
	)

	return btn

## 创建加粗字体（基于默认字体使�?FontVariation 加粗�?
func _make_bold_font() -> Font:
	## 优先使用项目全局字体（书法体）作加粗 base，否则回逢�引擎 fallback 字体�?
	## 旧实现直接把 ProjectSettings 里的「字符串�?��」当 Font �?��永远匹配失败 �?
	## 加粗字体丢�直基于引擎默认字体，与全屢�书法体不丢�致（#11）��?
	var default_font: Font = UIButtonHelper.get_ui_font()
	if default_font == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = default_font
	fv.variation_embolden = 0.8
	return fv

## 加载兵�?动画帧资源（优先 walk > move > attack�?
## 返回字典 {"frames": SpriteFrames, "anim_name": String}，无则返�?null
func _load_unit_frames(unit_id: String) -> Dictionary:
	for anim_name in ["walk", "move", "attack"]:
		var path := "res://resources/units/%s/%s_frames.tres" % [unit_id, anim_name]
		if ResourceLoader.exists(path):
			var frames: SpriteFrames = load(path)
			if frames != null and frames.get_frame_count(anim_name) > 0:
				return {"frames": frames, "anim_name": anim_name}
	return {}

## 加载兵�?行走/奔跑动画的�?丢�帧纹理（用于 tooltip 等需要静态纹理的场景�?
## 优先级：walk > move > attack，返回�?丢��?Texture2D
func _load_unit_first_frame(unit_id: String) -> Texture2D:
	var anim_data = _load_unit_frames(unit_id)
	if anim_data.is_empty():
		return null
	var frames: SpriteFrames = anim_data["frames"]
	var anim_name: String = anim_data["anim_name"]
	return frames.get_frame_texture(anim_name, 0)

func _input(event: InputEvent) -> void:
	## 战斗�?��始时不响应输�?
	if not BattleManager.is_battle_active:
		return

	## P1 �?��选兵：WASD
	if event.is_action_pressed("p1_select_up"):
		_select_by_direction(0, 0, -1)
	elif event.is_action_pressed("p1_select_down"):
		_select_by_direction(0, 0, 1)
	elif event.is_action_pressed("p1_select_left"):
		_select_by_direction(0, -1, 0)
	elif event.is_action_pressed("p1_select_right"):
		_select_by_direction(0, 1, 0)

	## P2 �?��选兵：方向键（仅双人模式�?
	if BattleManager.is_two_player:
		if event.is_action_pressed("p2_select_up"):
			_select_by_direction(1, 0, -1)
		elif event.is_action_pressed("p2_select_down"):
			_select_by_direction(1, 0, 1)
		elif event.is_action_pressed("p2_select_left"):
			_select_by_direction(1, -1, 0)
		elif event.is_action_pressed("p2_select_right"):
			_select_by_direction(1, 1, 0)

	## 双人模式�?���?��级（仅双人模式生效，与升级按�?���?_try_upgrade_by_key 逻辑�?
	## P1：F=升级人口、R=升级收入；P2�?=升级人口�?=升级收入
	if BattleManager.is_two_player and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_try_upgrade_by_key(0, "pop")
			KEY_R:
				_try_upgrade_by_key(0, "income")
			KEY_SLASH:
				_try_upgrade_by_key(1, "pop")
			KEY_PERIOD:
				_try_upgrade_by_key(1, "income")

func _select_by_direction(player_id: int, dx: int, dy: int) -> void:
	## 获取当前玩�?对应的按�?���?
	var buttons = unit_buttons if player_id == 0 else enemy_buttons
	## 获取当前选中索引
	var idx = p1_selected_index if player_id == 0 else p2_selected_index
	## 获取行尺寸数�?
	var row_sizes: Array[int] = _player_row_sizes if player_id == 0 else _enemy_row_sizes
	## 根据行尺寸�?算当前�?�?
	var row: int = 0
	var col: int = idx
	var offset: int = 0
	for i in range(row_sizes.size()):
		if row_sizes[i] <= 0:
			continue
		if idx < offset + row_sizes[i]:
			row = i
			col = idx - offset
			break
		offset += row_sizes[i]
	## 计算新�?（限制在有效行范围内�?
	var valid_rows: Array[int] = []
	for i in range(row_sizes.size()):
		if row_sizes[i] > 0:
			valid_rows.append(i)
	if valid_rows.is_empty():
		return
	var row_idx_in_valid = valid_rows.find(row)
	if row_idx_in_valid < 0:
		row_idx_in_valid = 0
	var new_row_idx = clampi(row_idx_in_valid + dy, 0, valid_rows.size() - 1)
	var new_row = valid_rows[new_row_idx]
	## 计算新列（限制在新�?的按�?��量内�?
	var new_col = clampi(col + dx, 0, row_sizes[new_row] - 1)
	## 计算新索�?
	var new_offset: int = 0
	for i in range(new_row):
		new_offset += row_sizes[i]
	var new_index = new_offset + new_col
	## 限制在按�?��组范围内
	new_index = clampi(new_index, 0, buttons.size() - 1)

	## 更新玩�?索引
	if player_id == 0:
		p1_selected_index = new_index
	else:
		p2_selected_index = new_index

	## 设置对应兵�?为��中（信号会�?��触发 _highlight_buttons，无霢�重�?调用�?
	var btn = buttons[new_index]
	var res: UnitResource = btn.get_meta("unit_resource")
	## �?��该兵种的点击音效
	AudioManager.play_unit_click_sound(res.unit_id)
	BattleManager.set_selected_unit(player_id, res)

func _on_unit_pressed(btn: BaseButton, player_id: int) -> void:
	## #2�?17�?026-08-11）：长按已触发�?情弹�?�?屏蔽此�?松手的出兵点�?
	if btn.has_meta("long_press_triggered") and bool(btn.get_meta("long_press_triggered")):
		btn.set_meta("long_press_triggered", false)
		return
	## #3：若刚执行过长按滚动（拖动位移超过阈值），屏蔽这次松手触发的出兵点击
	if btn.has_meta("dragging") and bool(btn.get_meta("dragging")):
		btn.set_meta("dragging", false)
		return
	## #3（2026-08-14 修复）：长按/拖动滚动手势期间，屏蔽一切出兵点击（按下与松开落在哪个按钮都不选中）
	if btn.has_meta("drag_grid"):
		var _gr: Control = btn.get_meta("drag_grid")
		if is_instance_valid(_gr):
			if bool(_gr.get_meta("_gesture_scroll", false)):
				return
			## 详情弹窗开启期间，点兵种 = 关闭弹窗且抑制选中（避免「点空白处关弹窗」误选背后的兵种）
			if bool(_gr.get_meta("_detail_open", false)):
				if _unit_detail_popup != null and is_instance_valid(_unit_detail_popup):
					_unit_detail_popup.queue_free()
					_unit_detail_popup = null
				_gr.set_meta("_detail_open", false)
				return
	## 获取按钮对应兵�?资源
	var res: UnitResource = btn.get_meta("unit_resource")
	## 获取当前已��中的兵�?
	var current = BattleManager.selected_units[player_id]

	## 再�?点击已��中兵�?则取消��择（信号会�?��触发 _highlight_buttons�?
	if current == res:
		if DevMode.single_spawn:
			## #11 单发出兵：重复点击已选兵种 = 再出 1 个（不取消选择）
			BattleManager.deploy_selected_once(player_id)
		else:
			## 原逻辑：取消选择
			BattleManager.set_selected_unit(player_id, null)
		return

	## 设置新��中的兵种（信号会自动触�?_highlight_buttons�?
	## �?��该兵种的点击音效（仅在��中新兵种时�?���?
	AudioManager.play_unit_click_sound(res.unit_id)
	BattleManager.set_selected_unit(player_id, res)
	## 同�?�?��索引
	if player_id == 0:
		p1_selected_index = btn.get_meta("index")
	else:
		p2_selected_index = btn.get_meta("index")

## #2�?17�?026-08-11）：屢�内兵种按�?��按�?情面板（PopupPanel�?
## 图鉴式内容：名称 / 描述 / 属��表 / 动画预�?；点击�?部或 ESC �?��关闭（Popup 内建行为�?
const UNIT_LONG_PRESS_MSEC: int = 500
var _unit_detail_popup: PopupPanel = null

func _show_unit_detail_popup(res: UnitResource, btn: BaseButton) -> void:
	## 上一次弹窗未关闭则先回收，避免�?�??情堆�?
	if _unit_detail_popup != null and is_instance_valid(_unit_detail_popup):
		_unit_detail_popup.queue_free()
		_unit_detail_popup = null
	var popup := PopupPanel.new()
	popup.name = "UnitDetailPopup"
	_unit_detail_popup = popup
	## 羊皮纸�?面板
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.86, 0.70, 1.0)
	style.border_color = Color(0.35, 0.25, 0.13, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	popup.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)
	## 名称
	var name_lbl := Label.new()
	name_lbl.text = res.get_display_name()
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.35, 0.12, 0.08, 1.0))
	vbox.add_child(name_lbl)
	## 描述
	var desc := ItemDatabase.get_unit_description(res)
	if not desc.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(240, 0)
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.30, 0.22, 0.12, 1.0))
		vbox.add_child(desc_lbl)
	## 属��表
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 16)
	stats_grid.add_theme_constant_override("v_separation", 4)
	_add_detail_stat_row(stats_grid, tr("HP_LABEL"), str(res.max_hp))
	_add_detail_stat_row(stats_grid, tr("ARMOR_LABEL"), str(res.armor_value))
	_add_detail_stat_row(stats_grid, tr("DAMAGE_LABEL"), str(res.damage))
	_add_detail_stat_row(stats_grid, tr("MOVE_SPEED_LABEL"), "%.1f" % res.move_speed)
	_add_detail_stat_row(stats_grid, tr("ATTACK_RANGE_LABEL"), "%.1f" % res.attack_range)
	_add_detail_stat_row(stats_grid, tr("CODEX_PRICE"), "$%d" % res.cost)
	vbox.add_child(stats_grid)
	## 动画预�?（�?用按�?��像的帧加载）
	var anim_data = _load_unit_frames(res.unit_id)
	if not anim_data.is_empty():
		var anim_panel := PanelContainer.new()
		anim_panel.custom_minimum_size = Vector2(120, 120)
		var anim_style := StyleBoxFlat.new()
		anim_style.bg_color = Color(0.55, 0.42, 0.22, 0.35)
		anim_style.set_corner_radius_all(6)
		anim_panel.add_theme_stylebox_override("panel", anim_style)
		vbox.add_child(anim_panel)
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = anim_data["frames"]
		sprite.centered = true
		sprite.play(anim_data["anim_name"])
		sprite.flip_h = _preview_flip_for(res, anim_data["anim_name"])
		anim_panel.add_child(sprite)
		var frame_tex = anim_data["frames"].get_frame_texture(anim_data["anim_name"], 0)
		if frame_tex != null and frame_tex.get_width() > 0 and frame_tex.get_height() > 0:
			var scale_val: float = 110.0 / maxf(float(frame_tex.get_width()), float(frame_tex.get_height()))
			sprite.scale = Vector2(scale_val, scale_val)
		sprite.position = anim_panel.custom_minimum_size * 0.5
	## 弹出：挂在主窗口（保证内嵌弹窗），初始在按钮上方
	## #3（2026-08-14）：标记详情弹窗开启，期间点兵种仅关闭弹窗、不选中（修复「长按弹窗后误选背后兵种」）
	var _dgrid: Control = btn.get_meta("drag_grid", null)
	if _dgrid != null and is_instance_valid(_dgrid):
		_dgrid.set_meta("_detail_open", true)
		popup.popup_hide.connect(func():
			_dgrid.set_meta("_detail_open", false)
		)
	get_tree().root.add_child(popup)
	var pos: Vector2 = btn.global_position + Vector2(0, -10)
	popup.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))
	## 内�?尺�?就绪后按实际大小钳制到主窗口内，避免弹出屏幕
	## #Bug2��2026-08-12����PopupPanel �̳� Window��û�� Control.resized �źš�
	## �����ӳ�һ֡��ʵ�ʴ�С�ж�λ�ã����ⵯ�����������ڡ�
	await get_tree().process_frame
	if is_instance_valid(popup):
		var win_sz: Vector2i = get_window().size
		var p_sz: Vector2i = popup.position
		p_sz.x = clampi(p_sz.x, 0, maxi(0, win_sz.x - popup.size.x))
		p_sz.y = clampi(p_sz.y, 0, maxi(0, win_sz.y - popup.size.y))
		popup.position = p_sz

## #2�?17）：详情属��表行（左标签右数��）
func _add_detail_stat_row(grid: GridContainer, label_text: String, value_text: String) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.40, 0.32, 0.20, 1.0))
	grid.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", Color(0.25, 0.15, 0.08, 1.0))
	grid.add_child(val)

func _highlight_buttons(player_id: int) -> void:
	## 获取当前玩�?按钮数组
	var buttons = unit_buttons if player_id == 0 else enemy_buttons
	## 获取当前选中的兵种资�?
	var selected_res = BattleManager.selected_units[player_id]
	## 先清除旧的��中边�?（移�?Panel 并停止闪烁动画）
	_clear_selection_border(player_id)
	## 没有选中兵�?则直接返回，按钮保持原样
	if selected_res == null:
		return
	## 边�?颜色：己方（player_id=0）红色，对方（player_id=1）蓝�?
	var border_color: Color = Color(1, 0, 0, 1) if player_id == 0 else Color(0.2, 0.4, 1, 1)
	## 遍历按钮找到选中项，添加静��边框（Panel + StyleBoxFlat�?
	for b in buttons:
		if b.get_meta("unit_resource") == selected_res:
			var border = Panel.new()
			border.name = "SelectionBorder"
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			border.set_process_input(false)
			border.set_process_unhandled_input(false)
			border.set_anchors_preset(Control.PRESET_FULL_RECT)
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = border_color
			style.set_border_width_all(3)
			style.set_corner_radius_all(4)
			border.add_theme_stylebox_override("panel", style)
			b.add_child(border)
			_selection_borders[player_id] = border
			break

## 清除指定玩�?的��中边�?（释�?Panel 并停止闪烁动画）
func _clear_selection_border(player_id: int) -> void:
	## 先停止�?在进行的�?��动画，避�?tween 访问已释放的节点
	if _flash_tweens.has(player_id):
		var tw = _flash_tweens[player_id]
		if tw != null and tw.is_valid():
			tw.kill()
		_flash_tweens.erase(player_id)
	## 移除旧的边�? Panel
	if _selection_borders.has(player_id):
		var border = _selection_borders[player_id]
		if border != null and is_instance_valid(border):
			border.set_process_input(false)
			border.set_process_unhandled_input(false)
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			border.queue_free()
		_selection_borders.erase(player_id)

func _update_gold_display(pid: int, gold: int, income: int) -> void:
	## 更新指定阵营的金币与收入显示（图片已有分类文字，�?��示数值）
	if pid == 0:
		player_gold_label.text = "%d" % gold
		player_income_label.text = "+%d" % income
	else:
		enemy_gold_label.text = "%d" % gold
		enemy_income_label.text = "+%d" % income

func _update_timer(t: float) -> void:
	## #6：累计本场���?时（countdown_tick 每帧发出且暂停时不发，累计天然与游戏节�?同�?�?
	_battle_elapsed += get_process_delta_time()
	## 获取回合文本，缺失则回����?��
	var round_text: String = tr("ROUND")
	if round_text == "ROUND":
		round_text = "回合"
	## #6：回合数左侧增加游戏计时（��用时），格�?mm:ss（超�?1 小时显示 h:mm:ss�?
	var elapsed_str: String = _format_battle_elapsed(_battle_elapsed)
	## 更新总�?�?+ 倒�?�?+ 回合数显�?
	timer_label.text = "%s  %s %d / %d" % [elapsed_str, round_text, EconomyManager.current_round, ceil(t)]

## #6：把战斗总用时格式化�?mm:ss / h:mm:ss
func _format_battle_elapsed(secs: float) -> String:
	var total: int = int(secs)
	var h: int = total / 3600
	var m: int = (total % 3600) / 60
	var s: int = total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]

## #6：战斗开始（start_battle）时清零总�?时，避免「再来一屢�」累加上丢�屢�用时
func reset_battle_elapsed() -> void:
	_battle_elapsed = 0.0

func _update_population_display() -> void:
	## 更新玩�?与敌人人口显示（图片已有分类文字，只显示数��）
	## 人口上限取经济基硢�上限 + 人口升级加成�?138�?
	player_pop_label.text = "%d/%d" % [BattleManager.player_units.size(), EconomyManager.get_max_population(0)]
	enemy_pop_label.text = "%d/%d" % [BattleManager.enemy_units.size(), EconomyManager.get_max_population(1)]

## 重建信息面板的三行数�?��金币/人口/收入）结构（#2/#4/#138�?
## 每�?统一包成「Control 插槽 + HBox 行��：插槽不布屢�子节点，因�?行可以自由平移（#2）；
## 人口行与收入行在文本右侧追加升级按钮�?4），旧版整�?大按�?��把面板撑破（#1 根因之一�?
func _setup_upgrade_buttons() -> void:
	_build_data_rows(0)
	_build_data_rows(1)

## 为指定阵营重建三行数�?���?
## pid: 玩�? ID�?=红方/玩�?, 1=蓝方/敌人�?
func _build_data_rows(pid: int) -> void:
	var gold_label: Label = player_gold_label if pid == 0 else enemy_gold_label
	var pop_label: Label = player_pop_label if pid == 0 else enemy_pop_label
	var income_label: Label = player_income_label if pid == 0 else enemy_income_label
	## 升级按钮：玩家侧恒有；敌人侧仅双人模式（AI 侧无霢�手动升级�?
	var with_upgrade: bool = pid == 0 or BattleManager.is_two_player
	_wrap_data_row(gold_label, null, pid, "gold")
	var pop_btn: Button = null
	var inc_btn: Button = null
	if with_upgrade:
		pop_btn = _make_upgrade_button("PopUpgradeBtn", func() -> void:
			## #4�?026-08-09）：升级失败（金币不�?满级）给�??反�?，避免��点了却没反应��的错�?
			_try_upgrade_by_key(pid, "pop")
		)
		inc_btn = _make_upgrade_button("IncomeUpgradeBtn", func() -> void:
			_try_upgrade_by_key(pid, "income")
		)
	_wrap_data_row(pop_label, pop_btn, pid, "pop")
	_wrap_data_row(income_label, inc_btn, pid, "income")
	if with_upgrade:
		_upgrade_buttons[pid] = {"pop": pop_btn, "income": inc_btn}
		_refresh_upgrade_buttons_for(pid)

## 把一�?���?��签从 VBox �?��出，包进�?��由偏移的插槽结构
## label: �?��标�?；btn: 追加到右侧的升级按钮（可�?null�?
## pid: 玩�? ID；kind: 行类型（gold/pop/income），用于位置偏移索引
func _wrap_data_row(label: Label, btn: Button, pid: int, kind: String) -> void:
	if label == null or not is_instance_valid(label):
		return
	var parent := label.get_parent() as VBoxContainer
	if parent == null:
		return
	var idx: int = label.get_index()
	var slot := Control.new()
	slot.name = "%sSlot" % kind.capitalize()
	slot.custom_minimum_size = Vector2(0, DATA_ROW_HEIGHT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.remove_child(label)
	parent.add_child(slot)
	parent.move_child(slot, idx)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	slot.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## 文本占据剩余宽度并允许�?�?��避免长文�?��向撑破信�?��板（#1�?
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.clip_text = true
	## #15：右侧面板文�?��对齐，与左侧左�?齐形成轴对称
	if pid == 1:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(label)
	if btn != null:
		## #8�?026-08-09）：升级按钮包进�?��插槽，支持调整面板单�?��整按�?���?
		## #霢��?1 �??（根因）：旧实现�?btn_slot 挂进 row（HBox）内�?��导致两个�??—��?
		## �?HBox 容器布局会强制�?盖子节点 offset，保存的按钮偏移在重进局内后�?���?��霢��?）；
		## �?调整「文�?���?��平移整�?row 时按�?��睢�丢�起移�?��霢��?）��?
		## 新实现：btn_slot 移出 row，改�?slot 内��右缘锚�?+ �?�� offset」定位，
		## 不受 HBox 布局管理，文�??平移与按�?��移互不干扰��?
		var btn_slot := Control.new()
		btn_slot.name = "%sBtnSlot" % kind.capitalize()
		btn_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		## 右缘锚定（anchor 左右 = 1），top/bottom �?0 �?offset_top 控制垂直位置
		btn_slot.anchor_left = 1.0
		btn_slot.anchor_right = 1.0
		btn_slot.anchor_top = 0.0
		btn_slot.anchor_bottom = 0.0
		slot.add_child(btn_slot)
		btn_slot.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_upgrade_btn_slots["%d_%s" % [pid, kind]] = btn_slot
	_data_rows["%d_%s" % [pid, kind]] = row

## 构��一�??方形升级按钮�?16：仅�?���?��，悬�?tooltip 显示详情�?
## btn_name: 节点名；on_pressed: 点击回调
func _make_upgrade_button(btn_name: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	## #16：�?方形（边�?= 行高 - 4），仅显示上�?��
	btn.custom_minimum_size = Vector2(DATA_ROW_HEIGHT - 4.0, DATA_ROW_HEIGHT - 4.0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.text = "↑"
	btn.clip_text = false
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(on_pressed)
	UIButtonHelper.setup_button(btn)
	return btn

## 应用三�?数据的位�?��移（#2�?
## 右侧敌方面板做水平镜像，保证「向�?向内」的调节手感与左侧一�?
func _apply_row_offsets() -> void:
	for key: String in _data_rows.keys():
		var row: Control = _data_rows[key]
		if row == null or not is_instance_valid(row):
			continue
		var parts: PackedStringArray = key.split("_")
		if parts.size() < 2:
			continue
		## #10：左右两侧各�?��有一套偏移，互不影响
		var pid: int = 0 if parts[0] == "0" else 1
		var off: Vector2 = _row_offsets[pid].get(parts[1], Vector2.ZERO)
		var dx: float = off.x if pid == 0 else -off.x
		row.offset_left = dx
		row.offset_right = dx
		row.offset_top = off.y
		row.offset_bottom = off.y

## 应用人口/收入升级按钮相�?行的位置偏移�?8�?
## 右侧敌方面板做水平镜像，与文�??偏移手感丢��?
## #霢��?1 �??：btn_slot 已改为��右缘锚定��，offset_* �?��对锚点的增量—��?
## offset_right = 基准右间�?4px) + dx；offset_left = offset_right - 按钮边长（保持�?度不变）
func _apply_upgrade_btn_offsets() -> void:
	var btn_size: float = DATA_ROW_HEIGHT - 4.0  ## 按钮边长（与创建时一致）
	for key: String in _upgrade_btn_slots.keys():
		var slot: Control = _upgrade_btn_slots[key]
		if slot == null or not is_instance_valid(slot):
			continue
		var parts: PackedStringArray = key.split("_")
		if parts.size() < 2:
			continue
		var pid: int = 0 if parts[0] == "0" else 1
		var off: Vector2 = _upgrade_btn_offsets[pid].get(parts[1], Vector2.ZERO)
		var dx: float = off.x if pid == 0 else -off.x
		var dy: float = off.y
		## 右缘锚定：offset_right 相�?右缘（负值向左进入面板内侧）= 4px 间距 + dx 偏移
		slot.offset_right = -4.0 + dx
		slot.offset_left = slot.offset_right - btn_size
		## 垂直居中 + dy 偏移（锚�?top/bottom �?0，offset_top 直接�?��对顶部距离）
		var v_center: float = (DATA_ROW_HEIGHT - btn_size) / 2.0
		slot.offset_top = v_center + dy
		slot.offset_bottom = v_center + btn_size + dy

## 把���?时标签包进可�?��偏移的插槽（#3�?
func _setup_timer_slot() -> void:
	if timer_label == null or not is_instance_valid(timer_label):
		return
	var parent := timer_label.get_parent()
	if parent == null:
		return
	var idx: int = timer_label.get_index()
	var slot := Control.new()
	slot.name = "TimerSlot"
	slot.custom_minimum_size = Vector2(100, 24)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.remove_child(timer_label)
	parent.add_child(slot)
	parent.move_child(slot, idx)
	slot.add_child(timer_label)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_timer_row = timer_label
	_apply_timer_offset()

## 应用倒�?�?回合数标签的位置偏移�?3�?
func _apply_timer_offset() -> void:
	if _timer_row == null or not is_instance_valid(_timer_row):
		return
	_timer_row.offset_left = _timer_offset.x
	_timer_row.offset_right = _timer_offset.x
	_timer_row.offset_top = _timer_offset.y
	_timer_row.offset_bottom = _timer_offset.y

## #18�?026-08-11）：把红/蓝顶部水�?HP 条�?器包进可�?��偏移的插槽（复用 #3 倒�?时插槽手法）�?
## HBoxContainer 布局会�?盖子节点 offset，必须先包一层占位插槽（350×80 固定）再偏移�?
## 否则衢��?日志高度变化触发重排时偏移会�?���?��?
func _setup_hp_bar_slots() -> void:
	var entries: Array = [
		{"box": red_hp, "min": Vector2(350, 80)},
		{"box": blue_hp, "min": Vector2(350, 80)},
	]
	for entry: Dictionary in entries:
		var box: Control = entry["box"]
		if box == null or not is_instance_valid(box):
			continue
		var parent := box.get_parent()
		if parent == null:
			continue
		var idx: int = box.get_index()
		var slot := Control.new()
		slot.name = String(box.name) + "OffsetSlot"
		slot.custom_minimum_size = entry["min"]
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.remove_child(box)
		parent.add_child(slot)
		parent.move_child(slot, idx)
		slot.add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_hp_bar_offsets()

## #18：应用顶部水�?HP 条位�?��移（�?右侧 X 水平镜像，与文本行偏移手感一致）
func _apply_hp_bar_offsets() -> void:
	for side: int in [0, 1]:
		var box: Control = red_hp if side == 0 else blue_hp
		if box == null or not is_instance_valid(box):
			continue
		var off: Vector2 = _hp_bar_offsets[side]
		var dx: float = off.x if side == 0 else -off.x
		box.offset_left = dx
		box.offset_right = dx
		box.offset_top = off.y
		box.offset_bottom = off.y

## 升级统一入口：升级按�?��双人模式�?���?���?��#双人�?���?��
## 成功/失败反�?与升级按�?��全一致；无限金币�?upgrade_* 内部放�?、不扣钱，�?处无霢�特判
## pid: 玩�? ID�?=红方, 1=蓝方）；kind: "pop"=人口升级, "income"=收入升级
func _try_upgrade_by_key(pid: int, kind: String) -> void:
	if kind == "pop":
		if EconomyManager.upgrade_population(pid):
			_refresh_upgrade_buttons_for(pid)
			_update_population_display()
		else:
			_show_toast("人口升级失败：金币不足或已达上限")
		return
	if EconomyManager.upgrade_income(pid):
		_refresh_upgrade_buttons_for(pid)
	else:
		_show_toast("收入升级失败：金币不足或已达上限")

## 刷新指定玩�?的两�?��级按�?���?���?��状��（金币不足时�?�?���?138�?
## #18�?026-08-08）：人口/收入满级时按�?��字变「满」��置灰��tooltip 提示已满�?
func _refresh_upgrade_buttons_for(pid: int) -> void:
	if not _upgrade_buttons.has(pid):
		return
	var entry: Dictionary = _upgrade_buttons[pid]
	var gold: int = EconomyManager.get_gold(pid)
	var pop_btn: Button = entry.get("pop")
	if pop_btn != null and is_instance_valid(pop_btn):
		var p_cost: int = EconomyManager.get_pop_upgrade_cost(pid)
		var p_amt: int = EconomyManager.get_pop_upgrade_amount(pid)
		var pop_at_cap: bool = EconomyManager.get_max_population(pid) >= Constants.MAX_POPULATION_CAP
		if pop_at_cap:
			## 满级：文字变「满�? �?�� + 提示
			pop_btn.text = "满"
			pop_btn.tooltip_text = "人口已达上限 %d（满级），无法继续升级" % Constants.MAX_POPULATION_CAP
			pop_btn.disabled = true
			pop_btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		else:
			pop_btn.text = "↑"
			pop_btn.modulate = Color.WHITE
			pop_btn.tooltip_text = "升级人口上限 +%d，花费 %d 金币" % [p_amt, p_cost]
			## #霢��?：无限金币下金币不足不再禁用（点击直接升级不扣钱�?
			pop_btn.disabled = gold < p_cost and not DevMode.infinite_gold
	var inc_btn: Button = entry.get("income")
	if inc_btn != null and is_instance_valid(inc_btn):
		var i_cost: int = EconomyManager.get_income_upgrade_cost(pid)
		var i_amt: int = EconomyManager.get_income_upgrade_amount(pid)
		var inc_at_cap: bool = EconomyManager.bonus_income[pid] >= EconomyManager.INCOME_BONUS_CAP
		if inc_at_cap:
			## 满级：文字变「满�? �?�� + 提示
			inc_btn.text = "满"
			inc_btn.tooltip_text = "收入升级加成已达上限（满级），无法继续升级"
			inc_btn.disabled = true
			inc_btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		else:
			inc_btn.text = "↑"
			inc_btn.modulate = Color.WHITE
			inc_btn.tooltip_text = "升级每回合收入 +%d，花费 %d 金币" % [i_amt, i_cost]
			## #霢��?：无限金币下金币不足不再禁用（点击直接升级不扣钱�?
			inc_btn.disabled = gold < i_cost and not DevMode.infinite_gold

## 金币变化回调：刷新升级按�?��#138�?
func _on_gold_changed_refresh_upgrades(_pid: int, _gold: int, _income: int) -> void:
	_refresh_upgrade_buttons_for(0)
	if BattleManager.is_two_player:
		_refresh_upgrade_buttons_for(1)

func _on_unit_spawned(_unit: Node2D, player_id: int) -> void:
	## 更新人口显示
	_update_population_display()
	## �?��选中按钮�?��提示
	_flash_selection_border(player_id)
	## �?��出兵音效（根�?���?��规则判断�?���?���?
	var unit := _unit as Unit
	if unit != null and unit.unit_resource != null:
		AudioManager.play_unit_spawn_sound(unit.unit_resource.unit_id)

func _on_unit_removed(_player_id: int) -> void:
	## 更新人口显示
	_update_population_display()

func _flash_selection_border(player_id: int) -> void:
	## 出兵时�?选中兵�?按钮的边框做两�?透明度闪烁（1�?.1�?�?.1�?�?
	## 边�?颜色�?_highlight_buttons �?��设置（己方红，�?方蓝�?
	if not _selection_borders.has(player_id):
		return
	var border = _selection_borders[player_id]
	if border == null or not is_instance_valid(border) or not border.is_inside_tree():
		return
	## 先终�?��丢�次未完成的闪烁动画，避免多个 tween 叠加
	if _flash_tweens.has(player_id):
		var old_tw = _flash_tweens[player_id]
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
		_flash_tweens.erase(player_id)
	## 重置透明度，�?���?��从可见状态开�?
	border.modulate.a = 1.0
	## �?��动画绑定到边框本�?��边�?锢�毁时 tween �?��失效，避免�?�?��释放节点
	var tw = border.create_tween()
	_flash_tweens[player_id] = tw
	tw.tween_property(border, "modulate:a", 0.1, 0.08)
	tw.tween_property(border, "modulate:a", 1.0, 0.08)
	tw.tween_property(border, "modulate:a", 0.1, 0.08)
	tw.tween_property(border, "modulate:a", 1.0, 0.08)
	## 动画完成后从缓存�?��除引�?
	tw.tween_callback(func(): _flash_tweens.erase(player_id))

func _on_selection_changed(player_id: int, _unit_res: Resource) -> void:
	## 选中变化时重新高�?���?
	_highlight_buttons(player_id)
	## 更新底部�?��封面图�?�?
	_update_center_preview(player_id)

## #新需求：弢�发��专属入口仅 DevMode �??（局内��开发工具����调整��两�?���?��
## 非开发��模式隐藏按�?��F11 弢��?��恢�?显示；帮助按�?��留（hover 查看�?���?��家功能）
func _apply_dev_gating(_on: bool = false) -> void:
	dev_btn.visible = DevMode.enabled
	adjust_btn.visible = DevMode.enabled
	## #12：开发��模式开�?��默�?打开兵�?攻击距�?显示（仅进入时�?�?��次，之后�?��由开关）�?
	## �?DevMode.dev_mode_changed 信号触发，进入开发��模式即生效；菜单项 20 仍可随时关闭�?
	if DevMode.enabled and not Unit.show_attack_ranges:
		Unit.show_attack_ranges = true
		_dev_redraw_all_units()
	else:
		## 退出开发者模式：自动关闭攻击距离显示（含水晶，水晶同为 Unit）
		if Unit.show_attack_ranges:
			Unit.show_attack_ranges = false
			_dev_redraw_all_units()
	## F12 隐藏局内上方按钮整排（TopCenterButtons）仅在开发者模式内生效；
	## 开发者模式下按 DevMode.hide_in_battle_top_buttons 标志控制显隐（标志可在主菜单预置），
	## 退出（或初始非开发模式）时强制恢复显示，避免玩家界面丢失按钮（F11 已禁用，退出后 F12 不再可用）
	if DevMode.enabled:
		$TopCenterButtons.visible = not DevMode.hide_in_battle_top_buttons
	else:
		$TopCenterButtons.visible = true

## 开发者模式专属快捷键：F12 切换局内上方按钮整排（游戏帮助/游戏设置/调整/退出/开发工具）显隐
## 仅开发者模式下生效（F11 已暂时禁用，2026-08-15）；切换的是全局标志 DevMode.hide_in_battle_top_buttons，
## 因此主菜单按 F12 也能预隐藏，进入战斗后自动套用（主菜单自身按钮不受影响）
func _unhandled_input(event: InputEvent) -> void:
	if not DevMode.enabled:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F12:
		DevMode.hide_in_battle_top_buttons = not DevMode.hide_in_battle_top_buttons
		_show_toast("局内按钮栏：%s" % ("隐藏" if DevMode.hide_in_battle_top_buttons else "显示"))

## 响应 DevMode.hide_in_battle_top_buttons 标志变化（F12 可在主菜单预置），实时套用到局内上方按钮栏
func _on_hide_in_battle_top_buttons_changed(hidden: bool) -> void:
	if DevMode.enabled:
		$TopCenterButtons.visible = not hidden

func _on_help_pressed() -> void:
	## #7�?026-08-11 用户拍板）：�?DevMode 点击弹出游戏�?��正文（不再弹「不�?��辑��提示）
	if not DevMode.enabled:
		_show_toast(ItemDatabase.get_help_text())
		return
	## #3�?026-08-09）：�?��按钮改为「hover tooltip 显示�?��正文 + 点击直接进入内�?编辑」，
	## 与兵种按�?�� tooltip 行为丢�致��旧的��弹窗内�??预�? + 编辑按钮」两段式已废弃��?
	## 创建�?��编辑弹窗：直接以 TextEdit 呈现（悬停已能看�?��，点击即编辑�?
	var dlg := AcceptDialog.new()
	dlg.title = tr("HELP")
	dlg.dialog_text = ""
	dlg.ok_button_text = tr("SAVE")
	## 游戏暂停时场�?��停转，弹窗必须无视暂停才能响应交�?
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	## 编辑态下清空 tooltip，避�?hover 弹层�?��编辑；弹窗关�?��恢�?
	help_btn.tooltip_text = ""
	var edit := TextEdit.new()
	edit.text = ItemDatabase.get_help_text()
	edit.custom_minimum_size = Vector2(540, 360)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	dlg.add_child(edit)
	## �??（点 SAVE）：保存覆盖文本并恢�?tooltip
	dlg.confirmed.connect(func() -> void:
		help_btn.tooltip_text = ItemDatabase.get_help_text()  ## 恢�?�?���?��
		if ItemDatabase.set_help_text_override(edit.text):
			## #10�?026-08-09）：保存后立即�?回校验，�?��文本真�?落盘/生效，杜绝��点了保存却没保存��?
			if ItemDatabase.get_help_text() == edit.text:
				_show_toast("游戏帮助已保存")
			else:
				_show_toast("保存异常：回读不一致，请重试")
		else:
			_show_toast("保存失败：无法写入覆盖文件")
	)
	## 取消（点 X / ESC / 取消按钮）同样保存：#3 �??「保存不奏效」����?
	## 用户习惯�?X/ESC 关闭对话框，旧实现走 canceled 直接丢弃编辑内�?，表现为「保存没生效」��?
	## 进入编辑态后任何关闭方式都落盘，杜绝�?���?10 补保存成功提示，避免「保存了但用户不知道」��?
	dlg.canceled.connect(func() -> void:
		help_btn.tooltip_text = ItemDatabase.get_help_text()  ## 恢�?�?���?��
		if ItemDatabase.set_help_text_override(edit.text):
			_show_toast("游戏帮助已保存")
	)
	add_child(dlg)
	dlg.popup_centered()

## 弢�发��模式保存帮助�?文�?盖（#192�?
func _on_help_edit_saved(edit: TextEdit) -> void:
	if edit == null or not is_instance_valid(edit):
		return
	ItemDatabase.set_help_text_override(edit.text)

## ESC 呼出 / 收起游戏内�?�?���?��并同步暂�?/ 恢�?游戏�?186�?
## �?��严格配�?：由 ESC 打开设置 �?暂停；�?�?���?��ESC / 关闭按钮 / 点�?�?���?恢�?�?
## 空格触发的暂停不受影响，关闭设置时不会�?恢�?它��?
## 设置对话框当前是否�?于打弢�状��（#18：battle_root �?? ESC 时用于区分���?关还�??弢�」）
func is_settings_open() -> bool:
	return _settings_dialog != null and is_instance_valid(_settings_dialog)

## �?��允�?响应丢�次新�?ESC「开设置」边沿（#18�?
## 返回 false 表示设置刚�? ESC 关掉（input 阶�? AcceptDialog 已消费同丢�次按�?���?
## battle_root �?process 阶�?�??看到同一 ESC 时不再重弢��?
func can_toggle_settings() -> bool:
	if is_settings_open():
		return false
	return Time.get_ticks_msec() - _last_settings_close_msec >= SETTINGS_TOGGLE_COOLDOWN_MSEC

func toggle_settings_pause() -> void:
	## 同一次按�?��能�?�??与弹窗各处理丢�遍，冷却窗口内忽略重复触发，避免"弢�了立刻又�?
	var now: int = Time.get_ticks_msec()
	if now - _last_settings_toggle_msec < SETTINGS_TOGGLE_COOLDOWN_MSEC:
		return
	_last_settings_toggle_msec = now
	## 设置界面已打弢� �?关闭并恢复游�?
	if _settings_dialog != null and is_instance_valid(_settings_dialog):
		_on_settings_dialog_closed()
		return
	## 设置界面�?��弢� �?打开并暂停游�?
	_on_settings_pressed()
	if not BattleManager.is_paused:
		_settings_paused_game = true
		BattleManager.set_paused(true)

func _on_settings_pressed() -> void:
	## 如果设置对话框已存在则直接弹�?
	if _settings_dialog != null and is_instance_valid(_settings_dialog):
		_settings_dialog.popup_centered()
		return

	## 创建新的设置对话�?
	_settings_dialog = AcceptDialog.new()
	_settings_dialog.title = tr("SETTINGS_TITLE")
	_settings_dialog.dialog_text = ""
	_settings_dialog.ok_button_text = tr("CLOSE")
	## #19�?026-08-11）：关闭按钮放大 2 倍（标�?�?X 为系统绘制无法缩放，放大底部「关�?��按�?��
	var ok_btn: Button = _settings_dialog.get_ok_button()
	if ok_btn:
		ok_btn.custom_minimum_size = Vector2(180, 56)
	_settings_dialog.confirmed.connect(_on_settings_dialog_closed)
	_settings_dialog.canceled.connect(_on_settings_dialog_closed)
	## 游戏暂停时场�?��停转，�?�?��板必须无视暂停才能继�?��应交互（#186�?
	_settings_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	## 应用木质面板底图
	UIButtonHelper.setup_wood_panel(_settings_dialog)
	## #4�?026-08-09）：屢�内�?�??话�?同样设置朢�小尺寸（与主菜单丢�致）�?
	## 否则设置项超出窗口最下方无法点击；配�?ScrollContainer 内�?�?��动查看��?
	_settings_dialog.min_size = Vector2i(450, 600)
	add_child(_settings_dialog)
	## #3：在对话框下层挂全屏点击�?��（先 add_child 保证�?Window 覆盖，点击空白区域关�??�?��
	_create_settings_backdrop()

	## 清空动��控件引用数组（设置项由统一组件内部�??理）
	_settings_labels.clear()
	_settings_buttons.clear()

	## 创建滚动容器包裹�?��设置面板组件（全部�?�?��统一�?SettingsPanel 提供�?
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(430, 480)
	_settings_dialog.add_child(scroll)
	scroll.add_child(SettingsPanel.new())

	## 居中弹出设置对话�?
	_settings_dialog.popup_centered()

func _on_settings_dialog_closed() -> void:
	## #18：�?录关�?��刻，隔�?「AcceptDialog 消费 ESC」与「battle_root �??同一 ESC」的竞��?
	_last_settings_close_msec = Time.get_ticks_msec()
	## 关闭时释放�?�??话�?
	if _settings_dialog != null and is_instance_valid(_settings_dialog):
		_settings_dialog.hide()  ## 先隐藏，避免 queue_free 前的丢�帧仍能接收输�?
		_settings_dialog.queue_free()
	_settings_dialog = null
	## #3：同时释放全屏点击遮�?
	if _settings_backdrop != null and is_instance_valid(_settings_backdrop):
		_settings_backdrop.queue_free()
	_settings_backdrop = null
	## �?��复由「ESC 呼出设置」自己��成的暂停，空格/结算造成的暂停保持不变（#186�?
	if _settings_paused_game:
		_settings_paused_game = false
		BattleManager.set_paused(false)
	_settings_labels.clear()
	_settings_buttons.clear()
	_settings_tabs = null

## #3：创建�?�?��面的全屏点击�?���?
## 全屏半��明�?+ 拦截鼠标事件；点击�?话�?外的空白区域触发关闭设置（等同点关闭按钮）��?
## 必须 process_mode=ALWAYS，否则游戏暂停时�?��不接收输入��点空白无法关闭�?
func _create_settings_backdrop() -> void:
	if _settings_backdrop != null and is_instance_valid(_settings_backdrop):
		return
	_settings_backdrop = ColorRect.new()
	_settings_backdrop.color = Color(0, 0, 0, 0.35)  ## 半��明黑：压暗背景并暗示��点击空白关�?��?
	_settings_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	add_child(_settings_backdrop)

func _on_settings_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_settings_dialog_closed()

func _update_settings_dialog_localization() -> void:
	## 设置对话框不存在则直接返�?
	if _settings_dialog == null or not is_instance_valid(_settings_dialog):
		return
	## 更新标�?和关�?���?���?
	_settings_dialog.title = tr("SETTINGS_TITLE")
	_settings_dialog.ok_button_text = tr("CLOSE")
	## 更新 Tab 标�?
	if _settings_tabs != null:
		_settings_tabs.set_tab_title(0, tr("WINDOW_SETTINGS"))
		_settings_tabs.set_tab_title(1, tr("LANGUAGE_SETTINGS"))
		_settings_tabs.set_tab_title(2, tr("AUDIO_SETTINGS"))
		_settings_tabs.set_tab_title(3, "战斗设置")
		_settings_tabs.set_tab_title(4, "背景音乐")
	## 更新动��标签文�?
	for lbl in _settings_labels:
		if is_instance_valid(lbl):
			match lbl.text:
				"窗口设置", "Window":
					lbl.text = tr("WINDOW_SETTINGS")
				"语言设置", "Language":
					lbl.text = tr("LANGUAGE_SETTINGS")
				"主音量", "Master Volume":
					lbl.text = tr("MASTER_VOLUME")
	## 更新动��按�?���?
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

## 创建丢��?BGM 下拉选择（标�?+ OptionButton�?
func _create_bgm_row(label_text: String, options: Array[String], current_value: String, callback: Callable) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for o in options:
		opt.add_item(o)
	_select_option_by_value(opt, current_value)
	opt.item_selected.connect(func(idx: int) -> void:
		callback.call(opt.get_item_text(idx))
	)
	hbox.add_child(opt)
	return hbox

## 刷新 BGM 标�?页中扢��?OptionButton 的当前��中�?
func _refresh_bgm_options(tab_bgm: VBoxContainer) -> void:
	var values: Array[String] = [SettingsManager.menu_bgm, SettingsManager.battle_bgm, SettingsManager.victory_bgm]
	var idx: int = 0
	for child in tab_bgm.get_children():
		var hbox := child as HBoxContainer
		if hbox == null:
			continue
		for sub in hbox.get_children():
			if sub is OptionButton and idx < values.size():
				_select_option_by_value(sub as OptionButton, values[idx])
				idx += 1
				break

## �?OptionButton �?��中�?value 匹配的项，未匹配则��中�?0 �?
func _select_option_by_value(opt: OptionButton, value: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == value:
			opt.select(i)
			return
	opt.select(0)

func _update_window_button_state(buttons: Array) -> void:
	## 获取当前窗口模式
	var mode = SettingsManager.window_mode
	## 根据当前模式设置按钮颜色反�?
	buttons[0].modulate = Color(1, 1, 1) if mode != SettingsManager.WINDOW_MODE_WINDOWED else Color(0.5, 1, 0.5)
	buttons[1].modulate = Color(1, 1, 1) if mode != SettingsManager.WINDOW_MODE_FULLSCREEN else Color(0.5, 1, 0.5)
	buttons[2].modulate = Color(1, 1, 1) if mode != SettingsManager.WINDOW_MODE_BORDERLESS else Color(0.5, 1, 0.5)

func _update_lang_button_state(buttons: Array) -> void:
	## 获取当前�?��
	var lang = SettingsManager.language
	## 根据当前�?��设置按钮颜色反�?（按按钮 meta �?�� locale 码匹配）
	for btn in buttons:
		var code: String = String(btn.get_meta("lang", ""))
		btn.modulate = Color(0.5, 1, 0.5) if lang == code else Color(1, 1, 1)

## �?��按钮按下：切换�?訢�并刷新全部本地化与高�?��与开始菜单共用�?訢�码体系）
func _on_lang_button_pressed(btn: Button, lang_buttons: Array) -> void:
	var code: String = String(btn.get_meta("lang", ""))
	SettingsManager.set_language(code)
	_update_lang_button_state(lang_buttons)
	_apply_localization()

func _on_exit_pressed() -> void:
	## 退出确认弹窗：返回地图 / 返回主菜单 / 退出游戏 三选项（2026-08-13）
	## 用 ConfirmationDialog：OK=退出游戏，Cancel=取消，add_button 追加「返回地图」「返回主菜单」
	var confirm := ConfirmationDialog.new()
	confirm.title = tr("TIP_TITLE")
	confirm.dialog_text = tr("EXIT_CONFIRM")
	confirm.ok_button_text = tr("EXIT_GAME")
	confirm.get_cancel_button().text = tr("CANCEL")
	## ESC 打开设置会暂停场景树，确认框必须无视暂停才能继续响应输入
	confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	## 公共清理：结束战斗状态 / 双人模式 / 肉鸽 run，恢复暂停（避免状态残留）
	var cleanup_battle := func() -> void:
		BattleManager.is_battle_active = false
		BattleManager.is_two_player = false
		RoguelikeManager.end_run()
		get_tree().paused = false
	## ① 返回地图：仅战役模式且非肉鸽时提供（肉鸽/双人/全面战争无地图可返回，隐藏该按钮）
	var btn_map := confirm.add_button(tr("RETURN_MAP"))
	btn_map.visible = GameManager.is_campaign_mode and not RoguelikeManager.is_active
	btn_map.pressed.connect(func() -> void:
		cleanup_battle.call()
		AudioManager.play_menu_bgm()
		get_tree().change_scene_to_file("res://scenes/ui/campaign_map.tscn")
	)
	## ② 返回主菜单
	var btn_menu := confirm.add_button(tr("MAIN_MENU"))
	btn_menu.pressed.connect(func() -> void:
		cleanup_battle.call()
		AudioManager.play_menu_bgm()
		GameManager.return_to_menu()
	)
	## ③ 退出游戏（OK 按钮）
	confirm.confirmed.connect(func() -> void:
		get_tree().quit()
	)
	## 取消按钮 / 右上角关闭 / ESC 关闭：销毁弹窗回到战斗，不做任何状态变更
	confirm.canceled.connect(confirm.queue_free)
	confirm.close_requested.connect(confirm.queue_free)
	## 强制按钮顺序：退出游戏 / 返回地图 / 返回菜单 / 取消
	## （Godot 默认 ConfirmationDialog 把「确定」钉在最右、「取消」在中部，需手动重排）
	var _btn_box: Node = confirm.get_ok_button().get_parent()
	for _b in [confirm.get_ok_button(), btn_map, btn_menu, confirm.get_cancel_button()]:
		_btn_box.move_child(_b, -1)
	## 默认高亮「取消」：聚焦 + 白边框（用户 2026-08-15：取消为默认选中项）
	var _cancel_btn: Button = confirm.get_cancel_button()
	var _white_border := StyleBoxFlat.new()
	_white_border.bg_color = Color(0, 0, 0, 0)
	_white_border.border_color = Color(1, 1, 1, 1)
	_white_border.set_border_width_all(2)
	_cancel_btn.add_theme_stylebox_override("focus", _white_border)
	add_child(confirm)
	confirm.popup_centered()
	_cancel_btn.grab_focus()

func _on_dev_tool_pressed() -> void:
	## 上一次的菜单�?���?���?��空白处隐藏（PopupMenu �?Window，不会自动销毁）�?
	## 重�?点开发工具会不断堆积僵尸 Window，先回收旧的�?
	if _dev_menu != null and is_instance_valid(_dev_menu):
		_dev_menu.queue_free()
	var menu := PopupMenu.new()
	_dev_menu = menu
	## #1：开发��工具菜单用引擎默�?字体（避弢�全局书法体），保证调试界面清晰可�?
	menu.theme = UIButtonHelper.make_dev_system_theme()
	## #霢��?：无限金币开关（菜单朢�上方）��注：id �?22�?0=攻击距�?显示�?1=水晶攻击已�?占用�?
	menu.add_check_item("无限金币（敌我购买升级免费）", 22)
	menu.set_item_checked(menu.get_item_index(22), DevMode.infinite_gold)
	## #11：出兵限制开关����开�?��玩�?方每次出兵严格只�?1 �?��AI 不受影响�?
	menu.add_check_item("出兵限制（玩家每次只出一个）", 25)
	menu.set_item_checked(menu.get_item_index(25), DevMode.single_spawn)
	menu.add_item("给自己 +1000 金币", 0)
	menu.add_item("清空场上所有兵种", 1)
	menu.add_item("清空对面兵种", 2)
	## #9�?026-08-09）：文本与��辑统一�?300（��辑早已 300，仅文本滞后�?
	menu.add_item("扣除敌方水晶血量 100", 3)
	menu.add_separator()
	## #21：水晶直接加衢�（可超上限），用于测试��更肉的水晶�?
	## #11�?026-08-09 用户拍板）：+5000 -> +1000（文�?��数��同步）
	menu.add_item("己方水晶 +1000 血量", 4)
	menu.add_item("敌方水晶 +1000 血量", 5)
	menu.add_separator()
	menu.add_item("【蓝色女巫事件】召唤蓝女巫(红方)", 23)
	## 仓鼠士兵事件二级菜单：直接触发 / 百分百概率
	var hamster_sub := PopupMenu.new()
	hamster_sub.name = "HamsterSubmenu"
	hamster_sub.add_item("召唤仓鼠士兵", 0)
	hamster_sub.add_item("仓鼠士兵触发概率调为百分之百开关", 1)
	menu.add_child(hamster_sub)
	menu.add_submenu_item("【仓鼠士兵事件】", "HamsterSubmenu", 26)
	menu.add_item("【死亡使者异象】召唤死亡使者(蓝方)", 27)
	menu.add_item("【凑企鹅异象】召唤凑企鹅(蓝方)", 28)
	## 敌方兵�?阵营二级菜单（咕�?Doro/菲比/�?��），默�?全部勾��；
	## 仅在全面战争（非双人、非战役）中生效，过�?AI �?��兵�?
	var faction_sub := PopupMenu.new()
	faction_sub.name = "FactionSubmenu"
	faction_sub.add_check_item("咕嘎 (G)", 0)
	faction_sub.add_check_item("Doro (D)", 1)
	faction_sub.add_check_item("菲比 (F)", 2)
	faction_sub.add_check_item("糯糯 (N)", 3)
	faction_sub.set_item_checked(0, BattleManager.enemy_faction_enabled.get("G", true))
	faction_sub.set_item_checked(1, BattleManager.enemy_faction_enabled.get("D", true))
	faction_sub.set_item_checked(2, BattleManager.enemy_faction_enabled.get("F", true))
	faction_sub.set_item_checked(3, BattleManager.enemy_faction_enabled.get("N", true))
	menu.add_child(faction_sub)
	menu.add_submenu_item("敌方兵种（仅全面战争）", "FactionSubmenu", 10)
	## #3：经济控制拆成��金�?/ 人口 / 收入」三�?��立子菜单，每�?��菜单各自包含我方/敌方
	var gold_sub := PopupMenu.new()
	gold_sub.name = "GoldSubmenu"
	gold_sub.add_item("我方 +%d 金币" % DEV_GOLD_STEP, 0)
	gold_sub.add_item("敌方 +%d 金币" % DEV_GOLD_STEP, 1)
	var pop_sub := PopupMenu.new()
	pop_sub.name = "PopSubmenu"
	pop_sub.add_item("我方 +%d 人口" % DEV_POP_STEP, 0)
	pop_sub.add_item("敌方 +%d 人口" % DEV_POP_STEP, 1)
	pop_sub.add_separator()
	## #4：人口升级入口（EconomyManager.upgrade_population—��扣金币、有等级、阶�?���?��
	pop_sub.add_item("我方升级人口", 10)
	pop_sub.add_item("敌方升级人口", 11)
	var income_sub := PopupMenu.new()
	income_sub.name = "IncomeSubmenu"
	income_sub.add_item("我方 +%d 收入" % DEV_INCOME_STEP, 0)
	income_sub.add_item("敌方 +%d 收入" % DEV_INCOME_STEP, 1)
	income_sub.add_separator()
	## #4：收入升级入口（EconomyManager.upgrade_income—��扣金币、有等级、阶�?���?��
	income_sub.add_item("我方升级收入", 10)
	income_sub.add_item("敌方升级收入", 11)
	menu.add_child(gold_sub)
	menu.add_child(pop_sub)
	menu.add_child(income_sub)
	menu.add_submenu_item("金币", "GoldSubmenu", 11)
	menu.add_submenu_item("人口", "PopSubmenu", 12)
	menu.add_submenu_item("收入", "IncomeSubmenu", 13)
	gold_sub.id_pressed.connect(func(id: int) -> void: _on_dev_econ_kind_selected(0, id))
	pop_sub.id_pressed.connect(func(id: int) -> void: _on_dev_econ_kind_selected(1, id))
	income_sub.id_pressed.connect(func(id: int) -> void: _on_dev_econ_kind_selected(2, id))
	## #4：所有二�?三级子菜单点击后不自动关�?��与主菜单 hide_on_item_selection=false 丢�致）�?
	## 方便连续点��升级人�?�?升级收入」等操作；关�?��丢�走主菜单「关�?��发工具��? ESC / 点击外部�?
	for sub in [faction_sub, gold_sub, pop_sub, income_sub]:
		sub.hide_on_item_selection = false
	var faction_keys: Array[String] = ["G", "D", "F", "N"]
	faction_sub.id_pressed.connect(func(id: int) -> void:
		var key: String = faction_keys[id]
		var new_val: bool = not BattleManager.enemy_faction_enabled.get(key, true)
		BattleManager.enemy_faction_enabled[key] = new_val
		faction_sub.set_item_checked(id, new_val)
		push_warning("敌方阵营 %s %s（仅全面战争生效）" % [key, "启用" if new_val else "禁用"])
	)
	## 仓鼠士兵事件子菜单（#自由事件 2026-08-15 / #18-8：手动触发=直接召唤；百分百=部署 G1 必变）
	hamster_sub.hide_on_item_selection = false
	hamster_sub.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			BattleManager.dev_trigger_hamster_event()
			_show_toast("已召唤仓鼠士兵加入%s" % ("红蓝双方" if BattleManager.is_two_player else "我方"))
		elif id == 1:
			BattleManager.dev_set_hamster_100pct()
			_show_toast("仓鼠士兵触发概率已调为百分之百（每次部署 G1 必变仓鼠）")
	)
	add_child(menu)
	## 在开发工具按�??下方弹出
	var popup_pos: Vector2 = dev_btn.global_position + Vector2(0, dev_btn.size.y + 4)
	## #15：显示兵种攻击距离（全局静��开关，默�?关闭；切换后立即重绘全场兵�?�?
	menu.add_check_item("显示兵种攻击距离", 20)
	menu.set_item_checked(menu.get_item_index(20), Unit.show_attack_ranges)
	## #霢��?1：水晶是否可攻击（战�?双人基地水晶；肉鸽水晶本就静态不受影响）
	menu.add_check_item("水晶可否攻击", 21)
	menu.set_item_checked(menu.get_item_index(21), _get_battlefield_crystal_attack())
	## #12�?026-08-11）：攻击距�?显示改为真�?的开关������开发��模式默认开�?��下沉到
	## _apply_dev_gating（进入开发��模式时�??�?��次），�?后玩家可�?��弢�关，不再每�?
	## 打开菜单都�?强制拉回弢��?��旧��辑�?��次打弢�菜单强制打开，�?致��关不掉」）�?
	## #8：点击��项后不�?��关闭菜单（hide_on_item_selection=false）；
	## 仅��关�?��项 / ESC / 点击菜单外部（失去焦点，Popup 默�?行为）才收起�?
	menu.hide_on_item_selection = false
	menu.add_separator()
	menu.add_item("关闭开发者工具", 99)
	menu.id_pressed.connect(func(id: int) -> void:
		## 菜单�?��已�?「关�?��发工具��或重新打开时回收，先校验再操作，避免�?�?��释放对象
		if not is_instance_valid(menu):
			return
		if id == 99:
			menu.queue_free()
			return
		if id == 0:
			_dev_add_gold_1000()
		elif id == 1:
			_dev_clear_all_units()
		elif id == 2:
			_dev_clear_enemy_units()
		elif id == 3:
			_dev_damage_enemy_base()
		elif id == 4:
			## #11：己方水�?+1000 衢�
			BattleManager.dev_boost_base_hp(0, 1000)
		elif id == 5:
			## #11：敌方水�?+1000 衢�
			BattleManager.dev_boost_base_hp(1, 1000)
		elif id == 20:
			## #15：切换兵种攻击距离显�?
			Unit.show_attack_ranges = not Unit.show_attack_ranges
			menu.set_item_checked(menu.get_item_index(20), Unit.show_attack_ranges)
			_dev_redraw_all_units()
			print("[调试] 兵种攻击距离显示: ", "开" if Unit.show_attack_ranges else "关")
		elif id == 22:
			## #霢��?：切换无限金币（敌我�?��/升级免费�?
			DevMode.set_infinite_gold(not DevMode.infinite_gold)
			menu.set_item_checked(menu.get_item_index(22), DevMode.infinite_gold)
			## 刷新升级按钮�?��状��（无限金币下金币不足不再�?�?��
			_refresh_upgrade_buttons_for(0)
			if BattleManager.is_two_player:
				_refresh_upgrade_buttons_for(1)
		elif id == 25:
			## #11：切换出兵限制（玩�?方每次只�?1 �?��AI 不受影响�?
			DevMode.set_single_spawn(not DevMode.single_spawn)
			menu.set_item_checked(menu.get_item_index(25), DevMode.single_spawn)
		elif id == 23:
			## #自由事件：直接触发蓝色女巫事件（专召 S1 蓝女巫入红方）
			BattleManager.dev_trigger_blue_witch_event()
		elif id == 27:
			## #自由事件：直接触发死亡使者异象（专召 Y1 死亡使者入蓝方）
			BattleManager.dev_trigger_death_reaper_event()
		elif id == 28:
			## #自由事件：直接触发凑企鹅异象（专召 Y2 凑企鹅入蓝方 + 5%/秒蓝女巫追踪）
			BattleManager.dev_trigger_penguin_event()
		elif id == 21:
			## #霢��?1：切换水晶是否可攻击
			var bf: Node = _get_battlefield_node()
			if bf != null:
				bf.crystal_can_attack = not bf.crystal_can_attack
				menu.set_item_checked(menu.get_item_index(21), bf.crystal_can_attack)
				print("[调试] 水晶攻击: ", "开" if bf.crystal_can_attack else "关")
			else:
				_show_toast("当前无战场（水晶开关仅在战斗中生效）")
		## #8：菜单保持打弢�（不再手动重�?popup，由 hide_on_item_selection=false 保证�?
	)
	## ESC 关闭弢�发工具菜�?
	## #9：PopupMenu 继承�?Window 而非 Control，没�?gui_input 信号�?
	## 旧代�?menu.gui_input.connect(...) 会在点开发工具时直接�?
	## 「Invalid access to property or key 'gui_input'」��Window 的等价信号是 window_input�?
	menu.window_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
			if is_instance_valid(menu):
				menu.queue_free()
	)
	menu.popup(Rect2i(popup_pos, Vector2i(260, 220)))

## #15：切换攻击距离开关后让全场兵种立即重绘（静��标志不会自动触�?_draw�?
func _dev_redraw_all_units() -> void:
	var unit_container = get_parent().get_node_or_null("Battlefield/UnitContainer")
	if unit_container:
		for unit in unit_container.get_children():
			if unit is Unit:
				unit.queue_redraw()

## 获取当前战场节点（hud 的父节点 battle_root 下挂 Battlefield�?
func _get_battlefield_node() -> Node:
	var parent_node: Node = get_parent()
	if parent_node != null:
		return parent_node.get_node_or_null("Battlefield")
	return null

## 读取当前战场的水晶攻击开关（#霢��?1；无战场时默认开�?
func _get_battlefield_crystal_attack() -> bool:
	var bf: Node = _get_battlefield_node()
	if bf != null:
		return bool(bf.crystal_can_attack)
	return true

## 弢�发工具：给当前玩�?+1000 金币（肉鸽模式走 RoguelikeManager，常规模式走 EconomyManager�?
func _dev_add_gold_1000() -> void:
	if RoguelikeManager.is_active:
		RoguelikeManager.add_gold(1000)
	else:
		EconomyManager.add_gold(0, 1000)

## 弢�发工具：清空场上扢�有兵种（保留基地/水晶；肉鸽模式下敌军清空后波次自然推进）
func _dev_clear_all_units() -> void:
	BattleManager.clear_all_units()

## 弢�发工具：�?��空�?�?��敌方 team 1）兵种，己方部队保留
## 用于单独验证「己方推�?/ 攻城」��不受敌军干扰；水晶不受影响
func _dev_clear_enemy_units() -> void:
	BattleManager.clear_enemy_units()

## 弢�发工具：直接对敌方（team 1）水晶扣�?300 衢��?1�?22 2026-08-09�?00 �?300�?
func _dev_damage_enemy_base() -> void:
	BattleManager.dev_damage_base(1, 300)

## 弢�发工具：从指定阵营前缢�随机选兵种生成单�?
## prefix: "S"=特殊(红方) / "Y"=异象(蓝方)
## player_id: 扢�属玩家（0=红方, 1=蓝方�?
func _dev_spawn_random_faction(prefix: String, player_id: int) -> void:
	## #9：防�?—��?UnitDatabase._ready �?��尚未跑完（开发工具在极早期打弢�时）
	## 此情�?�� unit_list 为空，会�?candidates.is_empty() 分支；保留兜底避免空引用�?
	if UnitDatabase.unit_list == null or UnitDatabase.unit_list.is_empty():
		_show_toast("兵�?数据库尚�?��载（请稍候）")
		return
	var candidates: Array[String] = []
	for res in UnitDatabase.unit_list:
		if res.unit_id.begins_with(prefix):
			candidates.append(res.unit_id)
	if candidates.is_empty():
		_show_toast("无可召唤%s兵种" % ("特殊" if prefix == "S" else "异象"))
		return
	var unit_id: String = candidates[randi() % candidates.size()]
	var res: Resource = UnitDatabase.get_unit(unit_id)
	if res == null:
		_show_toast("载入兵种 %s 失败" % unit_id)
		return
	BattleManager.spawn_unit(res, player_id)
	_show_toast("已召唤 %s 到 %s" % [unit_id, "蓝方" if player_id == 0 else "红方"])
	print("[调试] 开发者工具召唤 %s (%s)" % [unit_id, "蓝方" if player_id == 0 else "红方"])
	## #9：��Nonexistent function 'get_unit_resource' in base 'Node (unit_database.gd)'�?
	## �?�� .pck 缓存导致的����函数从�?��过这�?��（当前代码用 get_unit）��?
	## 用户重启编辑�?重新构建 .pck 后即消失。�?处无代码改动，仅记录�??说明�?

## 弢�发工具��经济控制��三级菜单回调（#3�?
## kind: 0=金币 / 1=人口 / 2=收入；id: 0=我方(pid=0) / 1=敌方(pid=1)；id 10/11 = 我方/敌方升级�?4�?
func _on_dev_econ_kind_selected(kind: int, id: int) -> void:
	## #4：人�?收入升级（走 EconomyManager.upgrade_*，扣金币、有等级、阶�?���?��封顶�?
	if kind == 1 and id >= 10:
		var pop_pid: int = id - 10
		if EconomyManager.upgrade_population(pop_pid):
			_refresh_upgrade_buttons_for(pop_pid)
			_update_population_display()
			_show_toast("人口升级成功（我方）" if pop_pid == 0 else "人口升级成功（敌方）")
		else:
			_show_toast("人口升级失败：金币不足或已达上限")
		return
	if kind == 2 and id >= 10:
		var inc_pid: int = id - 10
		if EconomyManager.upgrade_income(inc_pid):
			_refresh_upgrade_buttons_for(inc_pid)
			_show_toast("收入升级成功（我方）" if inc_pid == 0 else "收入升级成功（敌方）")
		else:
			_show_toast("收入升级失败：金币不足或已达上限")
		return
	## id 0 = 己方（pid=0），id 1 = 敌方（pid=1�?
	var pid: int = id
	if kind == 0:
		## 肉鸽模式没有 EconomyManager 经济，己方金币走 RoguelikeManager
		if RoguelikeManager.is_active and pid == 0:
			RoguelikeManager.add_gold(DEV_GOLD_STEP)
		else:
			EconomyManager.add_gold(pid, DEV_GOLD_STEP)
	elif kind == 1:
		EconomyManager.add_max_population(pid, DEV_POP_STEP)
		_update_population_display()
	else:
		EconomyManager.add_income_bonus(pid, DEV_INCOME_STEP)
	_refresh_upgrade_buttons_for(0)
	if BattleManager.is_two_player:
		_refresh_upgrade_buttons_for(1)

## 调整面板：实时调节局内金�?人口/收入三项与信�?��板背�?���?��并提供保存到项目的按�?��#3�?
## 肉鸽模式无局内经济，调整面板不可�?
func _on_adjust_pressed() -> void:
	if _adjust_panel != null and is_instance_valid(_adjust_panel):
		_adjust_panel.queue_free()
		_adjust_panel = null
		return
	if RoguelikeManager.is_active:
		var toast := Label.new()
		toast.text = "肉鸽模式无局内经济，调整面板不可用"
		toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		toast.offset_top = 120.0
		add_child(toast)
		var t := Timer.new()
		t.wait_time = 2.0
		t.one_shot = true
		add_child(t)
		t.timeout.connect(func() -> void:
			if is_instance_valid(toast):
				toast.queue_free()
			t.queue_free()
		)
		t.start()
		return

	var panel := PanelContainer.new()
	panel.name = "AdjustPanel"
	panel.position = Vector2(40, 80)
	panel.custom_minimum_size = Vector2(330, 520)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.15, 0.92)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	_adjust_panel = panel

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)

	var title := Label.new()
	title.text = "调整面板：位置/尺寸实时生效，点保存写入项目"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## #7：编辑�?�?��拖动顶部移动—��按住标题栏拖动整个面板
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	outer.add_child(title)
	var drag_state: Dictionary = {"active": false, "offset": Vector2.ZERO}
	title.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			drag_state["active"] = ev.pressed
			if ev.pressed:
				drag_state["offset"] = panel.position - get_viewport().get_mouse_position()
		elif ev is InputEventMouseMotion and bool(drag_state["active"]):
			panel.position = get_viewport().get_mouse_position() + (drag_state["offset"] as Vector2)
	)

	## #4�?026-08-09）：人口/收入升级入口已迁出调整面板，改放弢�发工具菜单（�?���?敌方两侧）��?
	## 调整面板�?��留��位�?尺�?/文本偏移」的实时调节职责�?

	## #10：作用侧选择器����左右两侧组件可以分�?���?
	var side_row := HBoxContainer.new()
	side_row.add_theme_constant_override("separation", 6)
	outer.add_child(side_row)
	var side_label := Label.new()
	side_label.text = "作用侧："
	side_label.add_theme_font_size_override("font_size", 13)
	side_row.add_child(side_label)
	var side_opt := OptionButton.new()
	side_opt.add_item("左右同时（镜像）", 0)
	side_opt.add_item("仅左侧（我方）", 1)
	side_opt.add_item("仅右侧（敌方）", 2)
	side_opt.select(_adjust_side)
	side_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_row.add_child(side_opt)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(310, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(296, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)
	_build_adjust_sliders(vbox)

	## 切换作用侧后重建滑杆：�?滑杆立刻显示�?��侧的真实取��（#10�?
	side_opt.item_selected.connect(func(idx: int) -> void:
		_adjust_side = idx
		_build_adjust_sliders(vbox)
	)

	## 保存按钮
	var save_btn := Button.new()
	save_btn.text = "保存（写入项目）"
	outer.add_child(save_btn)
	save_btn.pressed.connect(_on_adjust_save_pressed)

## 当前作用侧�?应的「取值参考侧」：仅右侧取�?1)，其余取�?0)�?10�?
func _adjust_side_primary() -> int:
	return 1 if _adjust_side == 2 else 0

## 当前作用侧�?应的写入�?��列表�?10�?
func _adjust_side_targets() -> Array[int]:
	var targets: Array[int] = [0, 1]
	if _adjust_side == 1:
		targets = [0]
	elif _adjust_side == 2:
		targets = [1]
	return targets

## 按当前作用侧重建调整面板�?��扢�有滑杆组�?10�?
## vbox: 承载滑杆的�?�?��重建前会�?���?
func _build_adjust_sliders(vbox: VBoxContainer) -> void:
	if vbox == null or not is_instance_valid(vbox):
		return
	for child: Node in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	var primary: int = _adjust_side_primary()

	## #2：金�?/ 人口 / 收入三�?文本改为「位�?��整��，不再直接改数�?
	var row_titles: Dictionary = {"gold": "金币文本位置", "pop": "人口文本位置", "income": "收入文本位置"}
	for kind: String in ["gold", "pop", "income"]:
		_add_xy_slider(vbox, String(row_titles[kind]), _row_offsets[primary].get(kind, Vector2.ZERO),
			Vector2(-200, -120), Vector2(200, 120),
			func(v: Vector2) -> void:
				for side: int in _adjust_side_targets():
					_row_offsets[side][kind] = v
				_apply_row_offsets()
		)
	## 信息面板整体位置（右侧面板水平方向自动镜像，且带边界约束�?
	_add_xy_slider(vbox, "信息面板位置", _info_panel_offset[primary], Vector2(-400, -300), Vector2(400, 300),
		func(v: Vector2) -> void:
			for side: int in _adjust_side_targets():
				_info_panel_offset[side] = v
			_apply_info_panel_offset()
	)
	## #3：信�?��板尺寸（X=加�?，Y=加高�?
	_add_xy_slider(vbox, "信息面板尺寸(横/竖)", _info_panel_size[primary], Vector2(-60, -60), Vector2(300, 240),
		func(v: Vector2) -> void:
			for side: int in _adjust_side_targets():
				_info_panel_size[side] = v
			_apply_info_panel_offset()
	)
	## #8�?026-08-09）：人口/收入升级按钮位置（信�?��板�?�?�?按钮，独立于文本行偏移）
	var btn_row_titles: Dictionary = {"pop": "人口升级按钮位置", "income": "收入升级按钮位置"}
	for kind: String in ["pop", "income"]:
		_add_xy_slider(vbox, String(btn_row_titles[kind]), _upgrade_btn_offsets[primary].get(kind, Vector2.ZERO),
			Vector2(-200, -120), Vector2(200, 120),
			func(v: Vector2) -> void:
				for side: int in _adjust_side_targets():
					_upgrade_btn_offsets[side][kind] = v
				_apply_upgrade_btn_offsets()
		)
	## #3：回合���?�?/ 当前回合数标签位�?��全局�?��控件，不分左右）
	_add_xy_slider(vbox, "倒计时/回合数位置", _timer_offset, Vector2(-600, -100), Vector2(600, 300),
		func(v: Vector2) -> void:
			_timer_offset = v
			_apply_timer_offset()
	)
	## #18�?026-08-11）：顶部水晶 HP 条位�?��按侧�?��，蓝/右侧 X �?��镜像�?
	_add_xy_slider(vbox, "水晶HP条位置", _hp_bar_offsets[primary], Vector2(-400, -40), Vector2(400, 40),
		func(v: Vector2) -> void:
			for side: int in _adjust_side_targets():
				_hp_bar_offsets[side] = v
			_apply_hp_bar_offsets()
	)

## 在调整面板中追加丢�组��标�?+ X 滑杆 + Y 滑杆�?
## vbox: �?��容器；title: 分组标�?；current: 当前偏移�?
## min_v / max_v: X、Y 两个方向的取值范围；on_changed: 值变化回调（实时应用�?
func _add_xy_slider(vbox: VBoxContainer, title: String, current: Vector2, min_v: Vector2, max_v: Vector2, on_changed: Callable) -> void:
	## �?Dictionary 承载�?��状��：GDScript �?��按��捕获局部变量，
	## 直接捕获 Vector2 会�? X/Y 两个 lambda 各自持有�?���?��，互相�?�?
	var state: Dictionary = {"v": current}
	var label := Label.new()
	label.text = "%s  X:%d  Y:%d" % [title, current.x, current.y]
	label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(label)
	var sx := HSlider.new()
	sx.min_value = min_v.x
	sx.max_value = max_v.x
	sx.step = 1.0
	sx.value = current.x
	sx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(sx)
	var sy := HSlider.new()
	sy.min_value = min_v.y
	sy.max_value = max_v.y
	sy.step = 1.0
	sy.value = current.y
	sy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(sy)
	sx.value_changed.connect(func(v: float) -> void:
		var nv: Vector2 = state["v"]
		nv.x = v
		state["v"] = nv
		label.text = "%s  X:%d  Y:%d" % [title, nv.x, nv.y]
		on_changed.call(nv)
	)
	sy.value_changed.connect(func(v: float) -> void:
		var nv: Vector2 = state["v"]
		nv.y = v
		state["v"] = nv
		label.text = "%s  X:%d  Y:%d" % [title, nv.x, nv.y]
		on_changed.call(nv)
	)

## 将当前信�?��板偏移与尺�?应用到左/右经济面板，并做窗口边界约束�?1/#3�?
func _apply_info_panel_offset() -> void:
	if _left_base.is_empty() or _right_base.is_empty():
		return
	## #10：左右两侧各�?��有一套偏移与尺�?增量
	var lo: Vector2 = _info_panel_offset[0]
	var ls: Vector2 = _info_panel_size[0]
	var ro: Vector2 = _info_panel_offset[1]
	var rs: Vector2 = _info_panel_size[1]
	## 左面板锚在左下�?：向右加宽��向上加�?
	left_panel.offset_left = _left_base["l"] + lo.x
	left_panel.offset_top = _left_base["t"] + lo.y - ls.y
	left_panel.offset_right = _left_base["r"] + lo.x + ls.x
	left_panel.offset_bottom = _left_base["b"] + lo.y
	## 右面板锚在右下�?：水平偏移取镜像（旧版同向偏移会把它直接推出屏幕�?1 根因），向左加�?
	right_panel.offset_left = _right_base["l"] - ro.x - rs.x
	right_panel.offset_top = _right_base["t"] + ro.y - rs.y
	right_panel.offset_right = _right_base["r"] - ro.x
	right_panel.offset_bottom = _right_base["b"] + ro.y
	## 兜底：任何偏�?尺�?组合都不允�?把面板推出可视区�?1�?
	_clamp_panel_into_viewport(left_panel)
	_clamp_panel_into_viewport(right_panel)

## 把面板拉回�?口内（含内�?朢�小尺寸，防�?内�?溢出面板后仍仍�?��定为「没超界」）�?1�?
## p: 霢�要约束的面板控件
func _clamp_panel_into_viewport(p: Control) -> void:
	if p == null or not is_instance_valid(p):
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var vp_size: Vector2 = vp.get_visible_rect().size
	## 用实际占用尺寸约束即可，get_combined_minimum_size() 在移动端可能因内�?朢�未稳定而偏大，
	## 导致面板被错误地向左/上拉扯，�?此不再用它覆盖 p.size
	var occupied := p.size
	var pos: Vector2 = p.global_position
	var dx: float = 0.0
	var dy: float = 0.0
	if pos.x < INFO_PANEL_MARGIN:
		dx = INFO_PANEL_MARGIN - pos.x
	elif pos.x + occupied.x > vp_size.x - INFO_PANEL_MARGIN:
		dx = vp_size.x - INFO_PANEL_MARGIN - pos.x - occupied.x
	if pos.y < INFO_PANEL_MARGIN:
		dy = INFO_PANEL_MARGIN - pos.y
	elif pos.y + occupied.y > vp_size.y - INFO_PANEL_MARGIN:
		dy = vp_size.y - INFO_PANEL_MARGIN - pos.y - occupied.y
	if is_zero_approx(dx) and is_zero_approx(dy):
		return
	p.offset_left += dx
	p.offset_right += dx
	p.offset_top += dy
	p.offset_bottom += dy

## 窗口尺�?变化回调：重新做丢�次边界约束（#1�?
func _on_viewport_resized() -> void:
	_apply_info_panel_offset()

## 场景加载时应用持久化�?UI 布局（保存到项目后下次进入生效）�?2/#3�?
func _apply_saved_info_panel_offset() -> void:
	var config := ConfigFile.new()
	if config.load(ADJUST_CFG_PATH) == OK and config.has_section("battle_defaults"):
		_timer_offset = Vector2(
			config.get_value("battle_defaults", "timer_offset_x", 0.0),
			config.get_value("battle_defaults", "timer_offset_y", 0.0)
		)
		## #10：分侧�?取；旧配�?��有一份共�?��屢�，�?不到分侧�?��回落到旧�?��保证老存档仍生效
		for side: int in [0, 1]:
			var p: String = "l_" if side == 0 else "r_"
			_info_panel_offset[side] = Vector2(
				config.get_value("battle_defaults", p + "info_offset_x", config.get_value("battle_defaults", "info_offset_x", 0.0)),
				config.get_value("battle_defaults", p + "info_offset_y", config.get_value("battle_defaults", "info_offset_y", 0.0))
			)
			_info_panel_size[side] = Vector2(
				config.get_value("battle_defaults", p + "info_size_w", config.get_value("battle_defaults", "info_size_w", 0.0)),
				config.get_value("battle_defaults", p + "info_size_h", config.get_value("battle_defaults", "info_size_h", 0.0))
			)
			for kind: String in ["gold", "pop", "income"]:
				_row_offsets[side][kind] = Vector2(
					config.get_value("battle_defaults", "%s%s_offset_x" % [p, kind], config.get_value("battle_defaults", "%s_offset_x" % kind, 0.0)),
					config.get_value("battle_defaults", "%s%s_offset_y" % [p, kind], config.get_value("battle_defaults", "%s_offset_y" % kind, 0.0))
				)
			## #8：人�?收入升级按钮位置
			for b_kind: String in ["pop", "income"]:
				_upgrade_btn_offsets[side][b_kind] = Vector2(
					config.get_value("battle_defaults", "%s%s_btn_offset_x" % [p, b_kind], 0.0),
					config.get_value("battle_defaults", "%s%s_btn_offset_y" % [p, b_kind], 0.0)
				)
			## #16 修复：加载水晶 HP 条位置（与保存配套）
			_hp_bar_offsets[side] = Vector2(
				config.get_value("battle_defaults", p + "hp_bar_offset_x", 0.0),
				config.get_value("battle_defaults", p + "hp_bar_offset_y", 0.0)
			)
	## 无无�?�?��读到配置，都跑一遍应用��辑：边界约束必须在首帧生效�?1�?
	_apply_info_panel_offset()
	_apply_row_offsets()
	_apply_upgrade_btn_offsets()
	_apply_timer_offset()
	## #18 修复（2026-08-15）：加载水晶 HP 条位置后必须重新应用——
	## 此前 _setup_hp_bar_slots 在加载前用默认 ZERO 应用过一次，加载函数只读值不应用，
	## 导致保存的水晶条偏移「存了但重进不生效」。
	_apply_hp_bar_offsets()
	## 移动端额外做安全区内缩，避免系统手势条/刘海把面板或按钮压到屏幕边缘
	if SettingsManager.is_touch_input():
		_nudge_panels_for_safe_area()

## 移动端安全区内缩：在已应用的 PC 布局基础上整体向内/向上推，避免被系统手势条/刘海/圆角遮挡
func _nudge_panels_for_safe_area() -> void:
	const SAFE_BOTTOM: float = 24.0
	const SAFE_SIDE: float = 12.0
	if left_panel != null and is_instance_valid(left_panel):
		left_panel.offset_left += SAFE_SIDE
		left_panel.offset_right += SAFE_SIDE
		left_panel.offset_top -= SAFE_BOTTOM
		left_panel.offset_bottom -= SAFE_BOTTOM
	if right_panel != null and is_instance_valid(right_panel):
		right_panel.offset_left -= SAFE_SIDE
		right_panel.offset_right -= SAFE_SIDE
		right_panel.offset_top -= SAFE_BOTTOM
		right_panel.offset_bottom -= SAFE_BOTTOM

## 调整面板：把当前 UI 位置/尺�?写入项目（res://data/ui_adjust.json）
## #2：不再持久化任何经济数��，旧配配�?��的经济键会�?顺手清掉
func _on_adjust_save_pressed() -> void:
	var config := ConfigFile.new()
	## 先加载已有文件，保留其它节（data/ �?��已存在于项目根，save 不会因缺�?��失败�?
	config.load(ADJUST_CFG_PATH)
	## 旧版经济数��键 + #10 之前的��左右共�?��布屢��?��丢�并清理（分侧�?��完整覆盖其�?义）
	var legacy_keys: Array[String] = [
		"gold", "population_bonus", "income_bonus",
		"info_offset_x", "info_offset_y", "info_size_w", "info_size_h",
		"gold_offset_x", "gold_offset_y", "pop_offset_x", "pop_offset_y",
		"income_offset_x", "income_offset_y",
	]
	for legacy_key: String in legacy_keys:
		if config.has_section_key("battle_defaults", legacy_key):
			config.erase_section_key("battle_defaults", legacy_key)
	config.set_value("battle_defaults", "timer_offset_x", _timer_offset.x)
	config.set_value("battle_defaults", "timer_offset_y", _timer_offset.y)
	## #10：左右两侧分�?���?
	for side: int in [0, 1]:
		var p: String = "l_" if side == 0 else "r_"
		config.set_value("battle_defaults", p + "info_offset_x", _info_panel_offset[side].x)
		config.set_value("battle_defaults", p + "info_offset_y", _info_panel_offset[side].y)
		config.set_value("battle_defaults", p + "info_size_w", _info_panel_size[side].x)
		config.set_value("battle_defaults", p + "info_size_h", _info_panel_size[side].y)
		for kind: String in ["gold", "pop", "income"]:
			var off: Vector2 = _row_offsets[side].get(kind, Vector2.ZERO)
			config.set_value("battle_defaults", "%s%s_offset_x" % [p, kind], off.x)
			config.set_value("battle_defaults", "%s%s_offset_y" % [p, kind], off.y)
		## #8：人�?收入升级按钮位置
		for b_kind: String in ["pop", "income"]:
			var b_off: Vector2 = _upgrade_btn_offsets[side].get(b_kind, Vector2.ZERO)
			config.set_value("battle_defaults", "%s%s_btn_offset_x" % [p, b_kind], b_off.x)
			config.set_value("battle_defaults", "%s%s_btn_offset_y" % [p, b_kind], b_off.y)
		## #16 修复：水晶 HP 条位置此前「只实时生效、保存漏写、加载漏读」→ 改滑块保存后重进还原。
		config.set_value("battle_defaults", p + "hp_bar_offset_x", _hp_bar_offsets[side].x)
		config.set_value("battle_defaults", p + "hp_bar_offset_y", _hp_bar_offsets[side].y)
	var save_err: int = config.save(ADJUST_CFG_PATH)
	if save_err == OK:
		push_warning("调整面板：已将当前 UI 布局保存到 %s" % ADJUST_CFG_PATH)
		## #4�?026-08-09）：保存后立即重新应用一遍布屢�（含边界约束�? �??反�?�?
		## 避免「点了保存却看不到任何变�?霢�重启才生效��的错�?
		_apply_saved_info_panel_offset()
		_show_toast("UI 布局已保存并应用")
	else:
		push_error("调整面板：保存失败，错误码 %d" % save_err)
		_show_toast("UI 布局保存失败（错误码 %d）" % save_err)

func update_base_hp(team: int, hp: int, max_hp: int) -> void:
	## 更新指定阵营基地衢��?
	if team == 0:
		red_hp_bar.max_value = max_hp
		red_hp_bar.value = hp
		## #1：同步更新�?量数�?
		if red_hp_label != null and is_instance_valid(red_hp_label):
			red_hp_label.text = "%d / %d" % [hp, max_hp]
			red_hp_label.visible = SettingsManager.show_hp_armor_bar  ## #16：跟随开�?
	else:
		blue_hp_bar.max_value = max_hp
		blue_hp_bar.value = hp
		## #1：同步更新�?量数�?
		if blue_hp_label != null and is_instance_valid(blue_hp_label):
			blue_hp_label.text = "%d / %d" % [hp, max_hp]
			blue_hp_label.visible = SettingsManager.show_hp_armor_bar  ## #16：跟随开�?


## 处理基地扣�?事件：在对应水晶下方的日志条追加丢��?
## 显示"[时间标�?] 来源单位 �?[红方/蓝方] 水晶 造成 X 点伤�?
func _on_base_damaged(team: int, damage: int, attacker: Node) -> void:
	## 攻击者显示名：优先取兵�?资源 display_name，否则取节点 name
	var src_name: String = "未知"
	if attacker != null and is_instance_valid(attacker):
		if attacker.has_method("get"):
			var res: Variant = attacker.get("unit_resource")
			if res != null and res is Resource:
				var d: Variant = res.get("display_name")
				if d != null and String(d) != "":
					src_name = String(d)
		if src_name == "未知":
			src_name = String(attacker.name)
	var target_name: String = "红方" if team == 0 else "蓝方"
	var line: String = "[%s] %s 水晶 造成 %d 点伤害" % [src_name, target_name, damage]
	var log_label: RichTextLabel = red_battle_log if team == 0 else blue_battle_log
	log_label.text += line + "\n"
	## �?��留最近若干�?，避免长战斗把日志条撑爆
	_trim_battle_log(log_label)

## 裁剪日志条，仅保留最�?MAX_LOG_LINES �?
func _trim_battle_log(log_label: RichTextLabel) -> void:
	var lines: PackedStringArray = log_label.text.split("\n", false)
	if lines.size() <= MAX_LOG_LINES:
		return
	var kept: PackedStringArray = lines.slice(lines.size() - MAX_LOG_LINES)
	log_label.text = "\n".join(kept) + "\n"
