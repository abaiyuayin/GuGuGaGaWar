class_name RoguelikeMeta
extends Control
## 肉鸽模式总控台（地图 hub 场景）
##
## 生命周期：战役地图点击「肉鸽模式」→ RoguelikeManager.start_run() 生成地图 →
## GameManager.enter_roguelike_map() 切到本场景。本场景负责：
##   1. 显示分支地图（RoguelikeMap 子节点）
##   2. 监听节点选择，战斗类节点进战斗场景，非战斗类原地结算
##   3. 非战斗结算后重建地图（路径随当前节点推进）
##
## 不持有任何 run 数据 —— 全部状态在 RoguelikeManager 单例中，场景切换安全。

const MAP_SCENE := preload("res://scenes/ui/roguelike_map.tscn")
const CHOICE_SCENE := preload("res://scenes/ui/roguelike_choice.tscn")
const REWARD_SCENE := preload("res://scenes/ui/roguelike_reward.tscn")
const SHOP_SCENE := preload("res://scenes/ui/roguelike_shop.tscn")

## 弹窗 / 提示的 CanvasLayer 层级
## 必须高于 roguelike_map.tscn 的 layer=5，否则地图的整幅羊皮纸背景会盖在弹窗之上，
## 表现为「点了休息/商店/宝物什么都没弹出来，而且地图也点不动了」（#184）。
const POPUP_LAYER: int = 9  ## 临时构建的选择类弹窗（训练选卡等）
const TOAST_LAYER: int = 10  ## 结果提示条，始终显示在最上层
## HUD 层：高于地图（5）、低于弹窗（9），用于常驻顶部信息栏/导航按钮
const HUD_LAYER: int = 6

const AVATAR_SIZE: Vector2 = Vector2(64.0, 64.0)

@onready var title_label: Label = $Title
@onready var exit_btn: Button = $ExitButton

var _map: RoguelikeMap = null
var _hud_layer: CanvasLayer = null
var _info_panel: PanelContainer = null
var _hero_avatar: TextureRect = null
var _hero_name_label: Label = null
var _crystal_label: Label = null
var _gold_label: Label = null
var _artifacts_label: Label = null
var _floor_label: Label = null

func _ready() -> void:
	AudioManager.play_menu_bgm()
	_map = MAP_SCENE.instantiate() as RoguelikeMap
	add_child(_map)
	_map.node_chosen.connect(_on_node_chosen)
	## [临时调试] 直接进入肉鸽 run 以便验证地图生成（验证后删除）
	if RoguelikeManager.map_nodes.is_empty():
		RoguelikeManager.start_run()
	## 旧标题已被常驻信息面板取代，隐藏避免与地图层重叠
	title_label.visible = false
	## 先建 HUD 层（layer>5），再把顶部 UI 放进该层，否则会被地图 CanvasLayer 盖住
	_build_hud_layer()
	_build_top_navbar()
	_build_info_panel()
	_refresh_info_panel()
	## 监听 run 数据变化，实时刷新左上角面板
	RoguelikeManager.gold_changed.connect(_on_gold_changed)
	RoguelikeManager.crystal_hp_changed.connect(_on_crystal_hp_changed)
	RoguelikeManager.artifacts_changed.connect(_on_artifacts_changed)

func _exit_tree() -> void:
	if RoguelikeManager.gold_changed.is_connected(_on_gold_changed):
		RoguelikeManager.gold_changed.disconnect(_on_gold_changed)
	if RoguelikeManager.crystal_hp_changed.is_connected(_on_crystal_hp_changed):
		RoguelikeManager.crystal_hp_changed.disconnect(_on_crystal_hp_changed)
	if RoguelikeManager.artifacts_changed.is_connected(_on_artifacts_changed):
		RoguelikeManager.artifacts_changed.disconnect(_on_artifacts_changed)

func _build_hud_layer() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUDLayer"
	_hud_layer.layer = HUD_LAYER
	add_child(_hud_layer)

## #25：构建顶部导航栏，将 ExitButton 收纳为横向条（与战役页一致）
## #20：按钮放大 ×2 便于触屏点击（尺寸 160×64，字号 26），导航栏相应扩容
func _build_top_navbar() -> void:
	var navbar := HBoxContainer.new()
	navbar.name = "TopNavBar"
	navbar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	navbar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	navbar.offset_left = -520.0
	navbar.offset_top = 12.0
	navbar.offset_right = -16.0
	navbar.offset_bottom = 88.0
	navbar.add_theme_constant_override("separation", 10)
	_hud_layer.add_child(navbar)

	## 返回：复用原 ExitButton，但文案改为「返回」并回到战役地图
	if exit_btn != null and is_instance_valid(exit_btn):
		exit_btn.text = "返回"
		if exit_btn.pressed.is_connected(_on_exit_pressed):
			exit_btn.pressed.disconnect(_on_exit_pressed)
		exit_btn.pressed.connect(_on_return_pressed)
		exit_btn.reparent(navbar)
		exit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		exit_btn.custom_minimum_size = Vector2(160, 64)
		exit_btn.add_theme_font_size_override("font_size", 26)
		UIButtonHelper.setup_button(exit_btn)

	## 设置：弹出全局设置面板
	var settings_btn := Button.new()
	settings_btn.text = "设置"
	settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings_btn.custom_minimum_size = Vector2(160, 64)
	settings_btn.add_theme_font_size_override("font_size", 26)
	settings_btn.pressed.connect(_on_settings_pressed)
	navbar.add_child(settings_btn)
	UIButtonHelper.setup_button(settings_btn)

	## 控制台：打开肉鸽专属调试控制台
	var console_btn := Button.new()
	console_btn.text = "控制台"
	console_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	console_btn.custom_minimum_size = Vector2(160, 64)
	console_btn.add_theme_font_size_override("font_size", 26)
	console_btn.pressed.connect(_on_console_pressed)
	navbar.add_child(console_btn)
	UIButtonHelper.setup_button(console_btn)

## 构建左上角常驻信息面板：英雄头像/名称、水晶血量、金币、文物、层数/关卡
func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.name = "InfoPanel"
	_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_info_panel.offset_left = 16.0
	_info_panel.offset_top = 16.0
	_info_panel.offset_right = 340.0
	_info_panel.offset_bottom = 132.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.42, 0.28, 0.9)
	_info_panel.add_theme_stylebox_override("panel", style)
	_hud_layer.add_child(_info_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	_info_panel.add_child(hbox)

	## 头像容器：无头像时以阵营色兜底
	var avatar_panel := PanelContainer.new()
	avatar_panel.custom_minimum_size = AVATAR_SIZE
	avatar_panel.size = AVATAR_SIZE
	hbox.add_child(avatar_panel)
	var avatar_style := StyleBoxFlat.new()
	avatar_style.corner_radius_top_left = 6
	avatar_style.corner_radius_top_right = 6
	avatar_style.corner_radius_bottom_left = 6
	avatar_style.corner_radius_bottom_right = 6
	avatar_panel.add_theme_stylebox_override("panel", avatar_style)

	_hero_avatar = TextureRect.new()
	_hero_avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hero_avatar.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_hero_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_panel.add_child(_hero_avatar)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_hero_name_label = Label.new()
	_hero_name_label.add_theme_font_size_override("font_size", 18)
	_hero_name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	vbox.add_child(_hero_name_label)

	_crystal_label = Label.new()
	_crystal_label.add_theme_font_size_override("font_size", 14)
	_crystal_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9, 1.0))
	vbox.add_child(_crystal_label)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 14)
	_gold_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9, 1.0))
	vbox.add_child(_gold_label)

	_artifacts_label = Label.new()
	_artifacts_label.add_theme_font_size_override("font_size", 14)
	_artifacts_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9, 1.0))
	vbox.add_child(_artifacts_label)

	_floor_label = Label.new()
	_floor_label.add_theme_font_size_override("font_size", 14)
	_floor_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 1.0))
	vbox.add_child(_floor_label)

func _refresh_info_panel() -> void:
	if _info_panel == null or not is_instance_valid(_info_panel):
		return

	var hero_id: String = RoguelikeManager.selected_hero
	if hero_id.is_empty():
		hero_id = "Hero1"
	var res := UnitDatabase.get_unit(hero_id) as UnitResource
	if res != null:
		_hero_name_label.text = res.get_display_name()
		_hero_avatar.texture = _load_hero_avatar_texture(hero_id)
		## 无头像时以玩家阵营色兜底
		var fallback_color: Color = res.color_red
		if _hero_avatar.texture == null:
			var avatar_style := StyleBoxFlat.new()
			avatar_style.bg_color = fallback_color
			avatar_style.corner_radius_top_left = 6
			avatar_style.corner_radius_top_right = 6
			avatar_style.corner_radius_bottom_left = 6
			avatar_style.corner_radius_bottom_right = 6
			_hero_avatar.get_parent().add_theme_stylebox_override("panel", avatar_style)
	else:
		_hero_name_label.text = "???"

	_crystal_label.text = "水晶 %d / %d" % [RoguelikeManager.crystal_hp, RoguelikeManager.crystal_max_hp]
	_gold_label.text = "金币 %d" % RoguelikeManager.get_gold()

	var artifact_count: int = RoguelikeManager.owned_artifacts.size()
	_artifacts_label.text = "文物 %d" % artifact_count
	if artifact_count > 0:
		var names: Array[String] = []
		for aid in RoguelikeManager.owned_artifacts:
			var art := ItemDatabase.get_artifact(aid) as ArtifactData
			if art != null:
				names.append(art.display_name)
		_artifacts_label.tooltip_text = "已持有文物：\n" + "\n".join(names)
	else:
		_artifacts_label.tooltip_text = "尚未获得文物"

	var visited: int = _count_cleared()
	var floor_idx: int = RoguelikeManager.current_floor
	_floor_label.text = "第 %d 层 / 第 %d 关" % [floor_idx, visited + 1]

## 加载英雄头像：优先用 sprite_texture，否则取动画 move 第一帧
func _load_hero_avatar_texture(hero_id: String) -> Texture2D:
	var res := UnitDatabase.get_unit(hero_id) as UnitResource
	if res != null and res.sprite_texture != null:
		return res.sprite_texture
	var path: String = "res://resources/units/%s/move_frames.tres" % hero_id
	if not ResourceLoader.exists(path):
		return null
	var frames := load(path) as SpriteFrames
	if frames == null:
		return null
	if frames.has_animation("move") and frames.get_frame_count("move") > 0:
		return frames.get_frame_texture("move", 0)
	return null

func _on_gold_changed(_gold: int) -> void:
	_refresh_info_panel()

func _on_crystal_hp_changed(_hp: int, _max_hp: int) -> void:
	_refresh_info_panel()

func _on_artifacts_changed(_artifacts: Array[String]) -> void:
	_refresh_info_panel()

func _count_cleared() -> int:
	var n: int = 0
	for node in RoguelikeManager.map_nodes:
		if node.visited:
			n += 1
	return n

## 地图节点被选中：锁定路径并分流到战斗 / 非战斗处理
func _on_node_chosen(index: int) -> void:
	if index < 0 or index >= RoguelikeManager.map_nodes.size():
		return
	if index not in RoguelikeManager.get_reachable_node_indices():
		return
	RoguelikeManager.select_node(index)
	var node := RoguelikeManager.get_map_node(index)
	## 让 tier 上限 / 波数辅助函数与地图深度挂钩（复用既有 _max_tier_for_floor）
	RoguelikeManager.current_floor = node.floor_index + 1
	match node.node_type:
		RoguelikeManager.NodeType.COMBAT, RoguelikeManager.NodeType.ELITE, RoguelikeManager.NodeType.BOSS:
			GameManager.start_game(1)
		RoguelikeManager.NodeType.REST:
			_open_rest()
		RoguelikeManager.NodeType.TREASURE:
			_open_chest_event()
		RoguelikeManager.NodeType.SHOP:
			_open_shop(node.floor_index)
		RoguelikeManager.NodeType.EVENT:
			_open_event()

# ---------- 非战斗节点结算 ----------

func _open_rest() -> void:
	## #213：休息处 = 恢复 30% 水晶最大耐久 + 升级一张卡牌（英雄卡不可升级）
	RoguelikeManager.heal_crystal(0.30)
	var cur_hp: int = RoguelikeManager.crystal_hp
	var max_hp: int = RoguelikeManager.crystal_max_hp
	_open_train_picker("休息：水晶已恢复 30%% 耐久（%d/%d）。选择一张卡牌升级（英雄卡不可升级）：" % [cur_hp, max_hp])

## 低级卡牌等级前缀：G、D（卡牌等级体系 G < D < F < N，由弱到强、获得难度递增）
const LOW_TIER_PREFIXES: Array[String] = ["G", "D"]

## 休息：随机抽取一张低级卡牌（G/D 级）加入牌库
func _rest_add_low_tier_card() -> void:
	var uid: String = _roll_low_tier_unit_id()
	if not uid.is_empty():
		RoguelikeManager.add_card(uid)
	_after_noncombat()

## 从全局兵种池随机取一张低级卡牌 ID（G/D 级），池空返回 ""
func _roll_low_tier_unit_id() -> String:
	var pool: Array[String] = []
	for res in UnitDatabase.unit_list:
		var res_typed := res as UnitResource
		if res_typed != null and res_typed.unit_id.substr(0, 1) in LOW_TIER_PREFIXES:
			pool.append(res_typed.unit_id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

## 训练：打开卡牌强化选择器，列出牌库中所有兵种（爱弥斯除外），点选其一使召唤人数 +2（#213 休息处复用）
func _open_train_picker(title_text: String = "训练：选择一张卡强化（召唤人数 +2）") -> void:
	var layer := CanvasLayer.new()
	layer.layer = POPUP_LAYER  ## 必须高于地图层，否则弹窗被羊皮纸背景整个盖住
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(backdrop)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vbox)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	var seen: Dictionary = {}
	var trained_any: bool = false
	for uid in RoguelikeManager.deck:
		if uid == "Hero1":
			continue  ## 爱弥斯（特殊英雄）不可训练
		if seen.has(uid):
			continue
		seen[uid] = true
		var res := UnitDatabase.get_unit(uid) as UnitResource
		if res == null:
			continue
		trained_any = true
		var lvl: int = RoguelikeManager.get_card_level(uid)
		var maxed: bool = lvl >= RoguelikeManager.CARD_LEVEL_MAX
		var btn := Button.new()
		btn.text = "%s  (Lv%d · 当前召唤%d%s)" % [
			res.get_display_name(), lvl, RoguelikeManager.get_deploy_count(uid),
			" · 已满级" if maxed else " · 升级后+2"
		]
		btn.add_theme_font_size_override("font_size", 18)
		btn.disabled = maxed
		btn.pressed.connect(_on_train_picked.bind(uid, layer))
		vbox.add_child(btn)
	if not trained_any:
		var hint := Label.new()
		hint.text = "牌库中没有可强化的卡牌（爱弥斯除外）"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 16)
		hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7, 1.0))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(hint)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(layer.queue_free)
	vbox.add_child(cancel)

## 确认训练某兵种卡（召唤人数 +2）并关闭选择器
func _on_train_picked(uid: String, layer: CanvasLayer) -> void:
	RoguelikeManager.upgrade_card(uid)
	layer.queue_free()
	_after_noncombat()

func _open_event() -> void:
	var options: Array[Dictionary] = [
		{"label": "神秘祭坛：50% 获得 / 50% 失去一张卡", "action": _event_altar},
		{"label": "废弃军械库：获得一张随机卡", "action": _event_armory},
		{"label": "受伤的旅人：随机失去一张卡", "action": _event_lost},
		{"label": "路遇传令兵：获得一张随机军令", "action": _gain_order},
	]
	_open_choice("事件：做出选择", options)

func _event_altar() -> void:
	if randf() < 0.5:
		RoguelikeManager.add_card(RoguelikeManager.roll_random_unit_id(3))
	else:
		_remove_random_card()
	_after_noncombat()

func _event_armory() -> void:
	RoguelikeManager.add_card(RoguelikeManager.roll_random_unit_id(2))
	_after_noncombat()

func _event_lost() -> void:
	_remove_random_card()
	_after_noncombat()

# ---------- 通用 UI 辅助 ----------

func _open_choice(title: String, options: Array[Dictionary]) -> void:
	var choice := CHOICE_SCENE.instantiate() as RoguelikeChoice
	add_child(choice)
	choice.options_ready(title, options)

## 打开经济商店：花金币买兵员卡 / 文物 / 军令
## 商店不暂停场景树（奖励界面也不再自行暂停，暂停统一由调用方控制）。
func _open_shop(floor_index: int) -> void:
	var shop := SHOP_SCENE.instantiate() as RoguelikeShop
	if shop == null:
		push_error("RoguelikeMeta: SHOP_SCENE 实例化失败，请检查 %s。" % SHOP_SCENE.resource_path)
		return
	add_child(shop)
	## 越深的商店越可能上架高阶兵员卡
	shop.open_shop(clampi(1 + int(floor_index / 2.0), 1, 4))
	shop.shop_closed.connect(_after_noncombat)

## 打开宝箱奖励：三选一获得文物（排除已持有的）。与战斗通关奖励不同，宝箱给的是文物而非兵种卡。
## 暂停控制：RoguelikeReward 已不再自行暂停场景树；宝箱位于非战斗 hub，正常流程本就无需暂停。
## 顺序要点：先实例化并连接信号，再 add_child / 填充候选 —— 即使渲染中途异常，
## 玩家仍可点「跳过」发出 artifact_chosen("") 正常收尾，杜绝「异常 → 全局暂停永不恢复 → 地图卡死」。
func _open_artifact_reward(title: String) -> void:
	var choices := ItemDatabase.roll_artifacts(3, RoguelikeManager.owned_artifacts)
	var reward := REWARD_SCENE.instantiate() as RoguelikeReward
	reward.artifact_chosen.connect(_on_artifact_chosen)
	add_child(reward)
	reward.choices_artifacts_ready(title, choices)

func _on_artifact_chosen(artifact_id: String) -> void:
	if not artifact_id.is_empty():
		RoguelikeManager.add_artifact(artifact_id)
	_after_noncombat()

# ---------- 宝箱奇遇事件（杀戮尖塔2 式三选一） ----------

## 打开宝箱奇遇事件：随机抽取 1 个事件，提供 3 个选项。
## 事件池缺失时回退为三选一文物，杜绝白屏 / 卡死。
func _open_chest_event() -> void:
	var ev := ItemDatabase.roll_chest_event()
	if ev == null or ev.options.is_empty():
		_open_artifact_reward("宝箱：三选一获得文物")
		return
	var options: Array[Dictionary] = []
	for opt in ev.options:
		var label: String = String(opt.get("label", "（选项缺失）"))
		var effect_type: String = String(opt.get("effect_type", "nothing"))
		var value: float = float(opt.get("value", 0.0))
		var result_text: String = String(opt.get("result", ""))
		options.append({
			"label": label,
			"action": _apply_chest_event.bind(effect_type, value, result_text),
		})
	_open_choice("%s\n%s" % [ev.title, ev.description], options)

## 执行宝箱事件选项的效果，随后给出结果反馈并收尾
## effect_type 由 data/chest_events.json 定义；未知类型按「无事发生」处理
func _apply_chest_event(effect_type: String, value: float, result_text: String) -> void:
	match effect_type:
		"gain_card":
			var uid: String = RoguelikeManager.roll_random_unit_id(maxi(int(value), 1))
			if not uid.is_empty():
				RoguelikeManager.add_card(uid)
		"gain_low_card":
			var low_uid: String = _roll_low_tier_unit_id()
			if not low_uid.is_empty():
				RoguelikeManager.add_card(low_uid)
		"gain_artifact":
			var arts := ItemDatabase.roll_artifacts(1, RoguelikeManager.owned_artifacts)
			if not arts.is_empty():
				RoguelikeManager.add_artifact(arts[0].artifact_id)
		"gain_order":
			var orders := ItemDatabase.roll_orders(1)
			if not orders.is_empty():
				RoguelikeManager.add_order(orders[0].order_id)
		"gain_gold":
			RoguelikeManager.add_gold(maxi(int(value), 0))
		"lose_gold":
			RoguelikeManager.add_gold(-maxi(int(value), 0))
		"lose_card":
			_remove_random_card()
		"upgrade_random":
			_upgrade_random_card()
		_:
			pass  ## nothing / 未知类型：无事发生
	if not result_text.is_empty():
		_show_toast(result_text)
	_after_noncombat()

## 随机升级牌库中一张卡（爱弥斯除外），训练等级 +1（召唤人数 +2）
func _upgrade_random_card() -> void:
	var candidates: Array[String] = []
	for uid in RoguelikeManager.deck:
		if uid != "Hero1" and not candidates.has(uid):
			candidates.append(uid)
	if candidates.is_empty():
		return
	RoguelikeManager.upgrade_card(candidates[randi() % candidates.size()])

## 在屏幕中央短暂显示一条结果提示（宝箱事件结果反馈），2 秒后自动消失
func _show_toast(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = TOAST_LAYER  ## 提示条置于最上层，避免被地图或弹窗遮挡
	add_child(layer)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(lbl)
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)

## 获得一张随机军令（排除已持有的）。军令池耗尽时静默忽略，不报错。
func _gain_order() -> void:
	var rolled := ItemDatabase.roll_orders(1, RoguelikeManager.owned_orders)
	if not rolled.is_empty():
		RoguelikeManager.add_order(rolled[0].order_id)
	_after_noncombat()

func _remove_random_card() -> void:
	if RoguelikeManager.deck.is_empty():
		return
	var uid: String = RoguelikeManager.deck[randi() % RoguelikeManager.deck.size()]
	RoguelikeManager.remove_card(uid)

## 非战斗结算收尾：刷新地图路径与信息面板
func _after_noncombat() -> void:
	_refresh_info_panel()
	if _map != null and is_instance_valid(_map):
		_map.refresh()

func _on_return_pressed() -> void:
	RoguelikeManager.end_run()
	GameManager.change_scene_with_loading("res://scenes/ui/campaign_map.tscn")

func _on_exit_pressed() -> void:
	RoguelikeManager.end_run()
	GameManager.return_to_menu()

func _on_settings_pressed() -> void:
	var layer := CanvasLayer.new()
	layer.layer = POPUP_LAYER
	add_child(layer)
	var dialog := AcceptDialog.new()
	dialog.title = "设置"
	dialog.min_size = Vector2i(450, 600)
	UIButtonHelper.setup_wood_panel(dialog)
	layer.add_child(dialog)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(430, 520)
	dialog.add_child(scroll)
	scroll.add_child(SettingsPanel.new())
	dialog.canceled.connect(_on_settings_closed.bind(layer))
	dialog.confirmed.connect(_on_settings_closed.bind(layer))
	dialog.popup_centered()

func _on_settings_closed(layer: CanvasLayer) -> void:
	if layer != null and is_instance_valid(layer):
		layer.queue_free()

func _on_console_pressed() -> void:
	var layer := CanvasLayer.new()
	layer.layer = POPUP_LAYER
	add_child(layer)
	var panel_script := preload("res://scenes/ui/roguelike_debug_panel.gd")
	var panel: Control = panel_script.new()
	layer.add_child(panel)
