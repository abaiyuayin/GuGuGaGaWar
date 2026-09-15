extends RefCounted
## 肉鸽结算战绩面板的构建器（胜利 / 失败界面共用）
##
## 刻意不声明 class_name：新增全局类名要等编辑器重扫 global_script_class_cache 才可用，
## 无头编译自检会直接报「未声明」。两个结算界面统一用 preload 常量引用本脚本。
##
## 只做一件事：把 RoguelikeManager.run_stats（本局战绩）与 best_records（历史最佳）
## 排成左右两列返回给调用方，由调用方塞进自己的 VBox。
## 不持有节点、不连信号 —— 纯 UI 拼装，胜负两个界面各自释放自己的子树。
##
## 调用时机要求：必须在 RoguelikeManager.archive_run() 之后调用。
## 本局数据取 last_run_stats 快照，因此不受 end_run() 清空 run_stats 的影响
## （battle_root 弹失败界面前就调了 end_run）。

## 左列（本局战绩）行定义：[统计键, 显示名, 单位后缀]
const RUN_ROWS: Array[Array] = [
	["max_floor", "最深层数", " 层"],
	["nodes_cleared", "通过节点", " 个"],
	["kills", "击杀敌军", " 名"],
	["gold_earned", "累计金币", ""],
	["cards_played", "打出兵种卡", " 张"],
	["orders_played", "下达军令", " 次"],
	["crystal_damage", "水晶承伤", ""],
]
## 右列（历史最佳）行定义：[记录键, 显示名, 单位后缀]
const BEST_ROWS: Array[Array] = [
	["best_floor", "最深层数", " 层"],
	["best_kills", "最高击杀", " 名"],
	["best_gold", "最高金币", ""],
	["best_ascension", "最高进阶", " 级"],
	["wins", "通关次数", " 次"],
	["runs", "总局数", " 局"],
]

const TITLE_COLOR: Color = Color(0.42, 0.16, 0.10, 1.0)
const KEY_COLOR: Color = Color(0.36, 0.28, 0.18, 1.0)
const VALUE_COLOR: Color = Color(0.20, 0.14, 0.08, 1.0)

## 构建「本局战绩 | 历史最佳」左右并排面板
static func build() -> Control:
	var wrap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	## 羊皮纸底色上再压一层更深的米色，和外层面板拉开层次
	style.bg_color = Color(0.87, 0.79, 0.62, 1.0)
	style.border_color = Color(0.52, 0.38, 0.20, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	wrap.add_theme_stylebox_override("panel", style)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	wrap.add_child(cols)

	cols.add_child(_build_column("本 局 战 绩", _run_rows()))
	cols.add_child(_build_column("历 史 最 佳", _best_rows()))
	return wrap

## 本局战绩行（读 archive_run 落下的快照，不受 end_run 清空影响）
static func _run_rows() -> Array:
	var rows: Array = []
	for row in RUN_ROWS:
		rows.append([String(row[1]), "%d%s" % [RoguelikeManager.get_last_stat(String(row[0])), String(row[2])]])
	rows.append(["本局用时", _format_duration(RoguelikeManager.get_last_stat("elapsed_sec"))])
	return rows

## 历史最佳行（无记录时显示 0；best_records 由 archive_run 写入 user://）
static func _best_rows() -> Array:
	var rows: Array = []
	var best: Dictionary = RoguelikeManager.best_records
	for row in BEST_ROWS:
		rows.append([String(row[1]), "%d%s" % [int(best.get(String(row[0]), 0)), String(row[2])]])
	return rows

## 单列：标题 + 若干「名称 —— 数值」行
static func _build_column(title_text: String, rows: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	col.add_child(title)

	for row in rows:
		col.add_child(_build_row(String(row[0]), String(row[1])))
	return col

## 一行统计：左侧名称、右侧数值，中间由 EXPAND 撑开
static func _build_row(key_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var key := Label.new()
	key.text = key_text
	key.add_theme_font_size_override("font_size", 14)
	key.add_theme_color_override("font_color", KEY_COLOR)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(96, 0)
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", VALUE_COLOR)
	row.add_child(value)
	return row

## 秒数格式化为「M 分 S 秒」；不足一分钟只显示秒
static func _format_duration(total_sec: int) -> String:
	var sec: int = maxi(total_sec, 0)
	if sec < 60:
		return "%d 秒" % sec
	return "%d 分 %d 秒" % [sec / 60, sec % 60]
