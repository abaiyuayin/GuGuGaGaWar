class_name RoguelikeMap
extends CanvasLayer
## 杀戮尖塔式分支地图 UI：羊皮卷背景、图标节点、虚线路径。
## 玩家只能点击当前「可达」节点；选中后发出 node_chosen(index)。

signal node_chosen(index: int)

const TYPE_LABELS: Array[String] = ["战", "强", "休", "?", "商", "宝", "决战"]
const TYPE_COLORS: Array[Color] = [
	Color(0.95, 0.55, 0.42),  # 0 战斗 橙红
	Color(0.88, 0.25, 0.25),  # 1 精英 深红
	Color(0.38, 0.78, 0.48),  # 2 休息 绿
	Color(0.55, 0.58, 0.92),  # 3 事件 蓝紫
	Color(0.95, 0.82, 0.32),  # 4 商店 金
	Color(0.98, 0.90, 0.48),  # 5 宝箱 浅金
	Color(0.72, 0.32, 0.78),  # 6 Boss 紫
]

const NODE_SIZE: Vector2 = Vector2(54, 54)
const BOSS_SIZE: Vector2 = Vector2(76, 76)

@onready var map_root: Control = $MapRoot
@onready var line_drawer: Control = $MapRoot/LineDrawer

var _node_buttons: Array[Button] = []
var _node_positions: Dictionary = {}

func _ready() -> void:
	line_drawer.draw.connect(_on_line_drawer_draw)
	map_root.resized.connect(_on_resized)
	if map_root.size.x <= 0.0 or map_root.size.y <= 0.0:
		await get_tree().process_frame
	_build_map()

## 外部（roguelike_meta）在节点推进后调用，重建节点按钮与连线
func refresh() -> void:
	_build_map()

func _on_resized() -> void:
	_build_map()

func _build_map() -> void:
	for b in _node_buttons:
		b.queue_free()
	_node_buttons.clear()
	_node_positions.clear()
	if RoguelikeManager.map_nodes.is_empty():
		return
	_compute_positions()
	_create_buttons()
	line_drawer.queue_redraw()

func _compute_positions() -> void:
	var area_size: Vector2 = map_root.size
	var pad_x: float = 100.0
	var pad_y: float = 80.0
	var usable_w: float = maxf(area_size.x - pad_x * 2.0, 1.0)
	var usable_h: float = maxf(area_size.y - pad_y * 2.0, 1.0)
	for i in range(RoguelikeManager.map_nodes.size()):
		var node: RoguelikeMapNode = RoguelikeManager.map_nodes[i]
		var x: float = pad_x + node.x_ratio * usable_w
		# 第 0 层在最底部，Boss 层在最顶部
		var y_norm: float = 1.0 - (float(node.floor_index) + 0.5) / float(RoguelikeManager.MAP_FLOORS)
		var y: float = pad_y + y_norm * usable_h
		_node_positions[i] = Vector2(x, y)

func _create_buttons() -> void:
	var reachable: Array[int] = RoguelikeManager.get_reachable_node_indices()
	for i in range(RoguelikeManager.map_nodes.size()):
		var node: RoguelikeMapNode = RoguelikeManager.map_nodes[i]
		var is_boss: bool = node.node_type == RoguelikeManager.NodeType.BOSS
		var size: Vector2 = BOSS_SIZE if is_boss else NODE_SIZE
		var btn := Button.new()
		btn.custom_minimum_size = size
		btn.size = size
		var pos: Vector2 = _node_positions.get(i, Vector2.ZERO)
		btn.position = pos - size * 0.5
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		var style := _make_node_style(node.node_type, size.x * 0.5)
		btn.add_theme_stylebox_override("normal", style)

		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = hover.bg_color.lightened(0.15)
		hover.border_color = Color(0.95, 0.95, 1.0, 1.0)
		btn.add_theme_stylebox_override("hover", hover)

		var disabled := style.duplicate() as StyleBoxFlat
		disabled.bg_color = disabled.bg_color * 0.35
		btn.add_theme_stylebox_override("disabled", disabled)

		var icon := Label.new()
		icon.text = TYPE_LABELS[node.node_type] if node.node_type < TYPE_LABELS.size() else "?"
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.add_theme_font_size_override("font_size", 14 if is_boss else 20)
		icon.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06, 1.0))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)

		var is_reachable: bool = i in reachable
		btn.disabled = not is_reachable or node.visited
		if node.visited:
			btn.modulate = Color(0.55, 0.55, 0.55, 0.7)
		elif is_reachable:
			btn.modulate = Color(1.15, 1.15, 1.15, 1.0)

		btn.pressed.connect(_on_node_pressed.bind(i))
		map_root.add_child(btn)
		_node_buttons.append(btn)

func _make_node_style(node_type: int, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TYPE_COLORS[node_type] if node_type < TYPE_COLORS.size() else Color.WHITE
	style.border_color = Color(0.12, 0.1, 0.08, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(radius))
	return style

func _on_node_pressed(index: int) -> void:
	if not (index in RoguelikeManager.get_reachable_node_indices()):
		return
	node_chosen.emit(index)

func _on_line_drawer_draw() -> void:
	## 画出所有相邻层之间的连边，分支/汇聚路径统一亮度
	for i in range(RoguelikeManager.map_nodes.size()):
		var node: RoguelikeMapNode = RoguelikeManager.map_nodes[i]
		var from: Vector2 = _node_positions.get(i, Vector2.ZERO)
		for nxt in node.next:
			var to: Vector2 = _node_positions.get(nxt, Vector2.ZERO)
			_draw_dotted_line(from, to, Color(0.45, 0.33, 0.20, 0.85), 3.0, 7.0, 6.0)

func _draw_dotted_line(from: Vector2, to: Vector2, color: Color, width: float, dot_len: float, gap_len: float) -> void:
	var dir: Vector2 = (to - from).normalized()
	var total: float = from.distance_to(to)
	if total <= 0.0:
		return
	var pos: float = 0.0
	while pos < total:
		var a: Vector2 = from + dir * pos
		var b: Vector2 = from + dir * minf(pos + dot_len, total)
		line_drawer.draw_line(a, b, color, width)
		pos += dot_len + gap_len
