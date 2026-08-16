class_name RoguelikeShop
extends CanvasLayer
## 肉鸽模式经济商店（付费购买：兵员卡牌 / 文物 / 军令）
##
## 生命周期：RoguelikeMeta 在踩到 SHOP 节点时实例化，玩家点「离开商店」时自行 queue_free()。
## 与奖励界面的区别：商店不暂停场景树 —— 它只在地图 hub 上弹出，
##   用全屏 backdrop（MOUSE_FILTER_STOP）拦截下层点击即可，避免出现「关闭后地图失活」的暂停态泄漏。
##
## 全代码构建 UI，配套 .tscn 只保留根节点 + 脚本引用。

## 玩家关闭商店时发出（无论是否买过东西）
signal shop_closed

## 单件商品卡尺寸
const CARD_SIZE: Vector2 = Vector2(236, 112)
## 刷新商品的固定花费
const REROLL_COST: int = 20
## 上方固定上架的兵员卡数量
const CARD_STOCK: int = 3
## 下方随机上架的文物 / 军令槽位数量
const MIX_STOCK: int = 3

## 本次进店允许出现的最高兵种阶层（由 RoguelikeMeta 传入）
var _max_tier: int = 4
## 当前上架的兵员卡 ID
var _stock_cards: Array[String] = []
## 当前下方槽位的随机商品：每个元素 {"kind": "artifact"/"order", "data": ArtifactData/MilitaryOrderData}
var _stock_mix: Array[Dictionary] = []
## 已售出的商品 key（"card:G1" / "artifact:war_drum" / "order:volley"），售出后置灰
var _sold: Dictionary = {}

## 顶部金币文案（_build_ui 创建）
var _gold_label: Label = null
## 刷新商品按钮（_build_ui 创建）
var _reroll_btn: Button = null
## 上排兵员卡行与下排文物/军令行
var _card_row: HBoxContainer = null
var _mix_row: HBoxContainer = null

func _ready() -> void:
	## 商店本身不暂停游戏，但保证即便外部处于暂停态按钮依然可点
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_restock()

## 由 RoguelikeMeta 在实例化后调用，设定本店的兵种阶层上限并刷新货架
func open_shop(max_tier: int) -> void:
	_max_tier = maxi(max_tier, 1)
	_restock()

# ---------- UI 构建 ----------

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.78)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var title := Label.new()
	title.text = "军 需 商 店"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	_gold_label = Label.new()
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.add_theme_color_override("font_color", Color(0.98, 0.84, 0.36, 1.0))
	_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_gold_label)

	## 上方：固定三张兵员卡
	_add_section_label(root, "兵 员 卡（固定三张）", Color(0.68, 0.86, 1.0, 1.0))
	_card_row = _make_row(root)
	## 下方：随机三个文物或军令
	_add_section_label(root, "文 物 / 军 令（随机三件）", Color(0.9, 0.8, 0.6, 1.0))
	_mix_row = _make_row(root)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 20)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(footer)

	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(180, 40)
	_reroll_btn.add_theme_font_size_override("font_size", 16)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	footer.add_child(_reroll_btn)

	var leave := Button.new()
	leave.text = "离开商店"
	leave.custom_minimum_size = Vector2(180, 40)
	leave.add_theme_font_size_override("font_size", 16)
	leave.pressed.connect(_on_leave_pressed)
	footer.add_child(leave)

## 创建一排行容器（居中排列商品卡）
func _make_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row

## 添加小节标题标签
func _add_section_label(parent: Control, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)

# ---------- 上架与刷新 ----------

## 重新掷出商品并重建货架：上方 3 张兵员卡 + 下方 3 格随机文物/军令
func _restock() -> void:
	if _card_row == null:
		return
	_sold.clear()
	_stock_cards = RoguelikeManager.roll_reward_choices_tier(_max_tier)
	_stock_mix.clear()
	for i in range(MIX_STOCK):
		var item: Dictionary = _roll_mix_item()
		if not item.is_empty():
			_stock_mix.append(item)
	_rebuild_shelves()

## 随机掷出一格下方商品：50% 文物 / 50% 军令；所选类别池耗尽时退回另一类
func _roll_mix_item() -> Dictionary:
	var want_artifact: bool = randf() < 0.5
	if want_artifact:
		var arts := ItemDatabase.roll_artifacts(1, RoguelikeManager.owned_artifacts)
		if not arts.is_empty():
			return {"kind": "artifact", "data": arts[0]}
		var orders := ItemDatabase.roll_orders(1)
		if not orders.is_empty():
			return {"kind": "order", "data": orders[0]}
	else:
		var orders := ItemDatabase.roll_orders(1)
		if not orders.is_empty():
			return {"kind": "order", "data": orders[0]}
		var arts := ItemDatabase.roll_artifacts(1, RoguelikeManager.owned_artifacts)
		if not arts.is_empty():
			return {"kind": "artifact", "data": arts[0]}
	return {}

## 按当前库存与售出状态重建上下两排商品按钮
func _rebuild_shelves() -> void:
	_clear_row(_card_row)
	_clear_row(_mix_row)

	for i in range(mini(CARD_STOCK, _stock_cards.size())):
		var res := UnitDatabase.get_unit(_stock_cards[i]) as UnitResource
		if res == null:
			continue
		var price: int = RoguelikeManager.get_shop_price(maxi(res.cost, 20))
		var key: String = "card:%s:%d" % [res.unit_id, i]
		var card := _create_card(
			res.get_display_name(),
			"T%d · HP%d · ATK%d" % [res.tier, res.max_hp, res.damage],
			price,
			_tier_color(res.tier),
			key
		)
		card.pressed.connect(_on_buy_card.bind(res.unit_id, price, key))
		_card_row.add_child(card)

	for item in _stock_mix:
		var kind: String = item.get("kind", "")
		var key: String
		var price: int
		var card: Button
		if kind == "artifact":
			var art: ArtifactData = item["data"] as ArtifactData
			if art == null:
				continue
			key = "artifact:%s" % art.artifact_id
			price = RoguelikeManager.get_shop_price(art.cost)
			card = _create_card(
				"%s〔%s〕" % [art.display_name, art.get_rarity_name()],
				art.description,
				price,
				art.get_rarity_color(),
				key
			)
			card.pressed.connect(_on_buy_mix.bind("artifact", art.artifact_id, price, key))
		else:
			var od: MilitaryOrderData = item["data"] as MilitaryOrderData
			if od == null:
				continue
			key = "order:%s" % od.order_id
			price = RoguelikeManager.get_shop_price(od.cost)
			card = _create_card(
				"%s〔%s〕" % [od.display_name, od.get_rarity_name()],
				"%s（%s）" % [od.description, od.get_duration_text()],
				price,
				od.get_rarity_color(),
				key
			)
			card.pressed.connect(_on_buy_mix.bind("order", od.order_id, price, key))
		_mix_row.add_child(card)

	_refresh_gold()

## 清空一行容器内的所有商品卡（先摘出再延迟释放，避免本帧重影）
func _clear_row(row: HBoxContainer) -> void:
	if row == null:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()

## 创建一张商品卡按钮
func _create_card(title_text: String, sub_text: String, price: int, accent: Color, key: String) -> Button:
	var sold: bool = _sold.has(key)
	var affordable: bool = RoguelikeManager.can_afford(price)

	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.disabled = sold or not affordable
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.10, 0.96) if not sold else Color(0.08, 0.08, 0.08, 0.9)
	style.set_border_width_all(2)
	style.border_color = accent if not sold else Color(0.3, 0.3, 0.3, 1.0)
	style.set_corner_radius_all(6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		card.add_theme_stylebox_override(state, style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = title_text
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", accent if not sold else Color(0.45, 0.45, 0.45, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = sub_text
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.78, 0.76, 0.68, 1.0))
	sub_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_lbl)

	var price_lbl := Label.new()
	if sold:
		price_lbl.text = "—— 已售出 ——"
		price_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	else:
		price_lbl.text = "价格：%d 金币%s" % [price, "" if affordable else "（金币不足）"]
		price_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.36, 1.0) if affordable else Color(0.85, 0.42, 0.38, 1.0))
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.add_theme_font_size_override("font_size", 13)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(price_lbl)

	return card

## 刷新金币文案与刷新按钮状态
func _refresh_gold() -> void:
	var gold: int = RoguelikeManager.get_gold()
	_gold_label.text = "持有金币：%d" % gold
	_reroll_btn.text = "刷新商品（%d 金币）" % REROLL_COST
	_reroll_btn.disabled = not RoguelikeManager.can_afford(REROLL_COST)

## 各阶层兵员卡的描边颜色
func _tier_color(tier: int) -> Color:
	match clampi(tier, 1, 4):
		2:
			return Color(0.45, 0.85, 0.45, 1.0)
		3:
			return Color(0.42, 0.66, 1.0, 1.0)
		4:
			return Color(0.92, 0.62, 1.0, 1.0)
		_:
			return Color(0.78, 0.78, 0.78, 1.0)

# ---------- 购买回调 ----------

func _on_buy_card(unit_id: String, price: int, key: String) -> void:
	if _sold.has(key) or not RoguelikeManager.spend_gold(price):
		return
	RoguelikeManager.add_card(unit_id)
	_sold[key] = true
	_rebuild_shelves()

## 购买下方混排槽位中的文物或军令（item_kind: "artifact" / "order"）
func _on_buy_mix(item_kind: String, item_id: String, price: int, key: String) -> void:
	if _sold.has(key) or not RoguelikeManager.spend_gold(price):
		return
	if item_kind == "artifact":
		RoguelikeManager.add_artifact(item_id)
	else:
		RoguelikeManager.add_order(item_id)
	_sold[key] = true
	_rebuild_shelves()

func _on_reroll_pressed() -> void:
	if not RoguelikeManager.spend_gold(REROLL_COST):
		return
	_restock()

func _on_leave_pressed() -> void:
	shop_closed.emit()
	queue_free()
