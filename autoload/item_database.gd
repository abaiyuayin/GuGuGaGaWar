extends Node
## 文物 / 军令数据库 —— Autoload 单例
##
## 生命周期：随游戏启动常驻，不随场景切换重建。
## 职责边界：只负责「静态道具数据」的加载 / 查询 / 文本覆盖，
##   不持有任何 run 内的拥有状态（那属于 RoguelikeManager）。
##
## 数据源：
##   res://data/artifacts.json        —— 20 条文物，规范数据，永不被程序改写
##   res://data/military_orders.json  —— 20 条军令，同上
##   codex_overrides.json             —— 开发者模式改写的文本，独立存放，删掉即还原

## 数据重新加载完成时发出（图鉴等界面据此刷新）
signal items_reloaded
## 某条目的文本被开发者模式改写时发出
## [param kind] 为 "unit" / "artifact" / "order"，[param item_id] 为对应 ID
signal item_text_changed(kind: String, item_id: String)

const ARTIFACT_JSON_PATH: String = "res://data/artifacts.json"
const ORDER_JSON_PATH: String = "res://data/military_orders.json"
const CHEST_EVENT_JSON_PATH: String = "res://data/chest_events.json"
## 允许开发者模式改写的文本字段白名单（只放文本，杜绝改到数值字段）
const EDITABLE_FIELDS: Array[String] = ["description", "appearance", "flavor"]

## 文物字典：artifact_id -> ArtifactData
var artifacts: Dictionary = {}
## 文物列表：按 JSON 顺序
var artifact_list: Array[ArtifactData] = []
## 军令字典：order_id -> MilitaryOrderData
var orders: Dictionary = {}
## 军令列表：按 JSON 顺序
var order_list: Array[MilitaryOrderData] = []
## 宝箱奇遇事件列表：按 JSON 顺序
var chest_event_list: Array[ChestEventData] = []

## 开发者模式文本覆盖：{ "units": {...}, "artifacts": {...}, "orders": {...} }
var _overrides: Dictionary = {"units": {}, "artifacts": {}, "orders": {}, "help": {}}

func _ready() -> void:
	load_all()

## 加载全部道具数据与文本覆盖
func load_all() -> void:
	artifacts.clear()
	artifact_list.clear()
	orders.clear()
	order_list.clear()
	chest_event_list.clear()
	_load_overrides()

	var artifact_root: Dictionary = _read_json(ARTIFACT_JSON_PATH)
	for entry in artifact_root.get("artifacts", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var art := ArtifactData.new()
		art.from_dict(entry as Dictionary)
		if art.artifact_id.is_empty():
			continue
		_apply_override(art, "artifacts", art.artifact_id)
		artifacts[art.artifact_id] = art
		artifact_list.append(art)

	var order_root: Dictionary = _read_json(ORDER_JSON_PATH)
	for entry in order_root.get("orders", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var od := MilitaryOrderData.new()
		od.from_dict(entry as Dictionary)
		if od.order_id.is_empty():
			continue
		_apply_override(od, "orders", od.order_id)
		orders[od.order_id] = od
		order_list.append(od)

	var event_root: Dictionary = _read_json(CHEST_EVENT_JSON_PATH)
	for entry in event_root.get("events", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ev := ChestEventData.new()
		ev.from_dict(entry as Dictionary)
		if ev.event_id.is_empty():
			continue
		chest_event_list.append(ev)

	if artifact_list.is_empty():
		push_error("ItemDatabase: 未能加载任何文物，检查 %s。" % ARTIFACT_JSON_PATH)
	if order_list.is_empty():
		push_error("ItemDatabase: 未能加载任何军令，检查 %s。" % ORDER_JSON_PATH)
	items_reloaded.emit()

## 按 ID 取文物，不存在返回 null
func get_artifact(artifact_id: String) -> ArtifactData:
	return artifacts.get(artifact_id, null) as ArtifactData

## 按 ID 取军令，不存在返回 null
func get_order(order_id: String) -> MilitaryOrderData:
	return orders.get(order_id, null) as MilitaryOrderData

## 随机抽取 [param count] 件互不重复的文物，可用 [param exclude_ids] 排除已拥有的
func roll_artifacts(count: int, exclude_ids: Array[String] = []) -> Array[ArtifactData]:
	var pool: Array[ArtifactData] = []
	for art in artifact_list:
		if not (art.artifact_id in exclude_ids):
			pool.append(art)
	pool.shuffle()
	return pool.slice(0, maxi(count, 0))

## 随机抽取 [param count] 张互不重复的军令
func roll_orders(count: int, exclude_ids: Array[String] = []) -> Array[MilitaryOrderData]:
	var pool: Array[MilitaryOrderData] = []
	for od in order_list:
		if not (od.order_id in exclude_ids):
			pool.append(od)
	pool.shuffle()
	return pool.slice(0, maxi(count, 0))

## 随机抽取一个宝箱奇遇事件；事件池为空返回 null（调用方做空状态兜底）
func roll_chest_event() -> ChestEventData:
	if chest_event_list.is_empty():
		return null
	return chest_event_list[randi() % chest_event_list.size()]

## 取兵种描述（优先返回开发者模式覆盖文本）
func get_unit_description(res: UnitResource) -> String:
	if res == null:
		return ""
	var patch: Dictionary = (_overrides.get("units", {}) as Dictionary).get(res.unit_id, {})
	var text: String = String(patch.get("description", ""))
	return text if not text.is_empty() else res.get_description()

## 覆盖某条目的文本字段（开发者模式专用），成功写盘返回 true
## [param kind] 取 "unit" / "artifact" / "order"；[param field] 取 "description" / "appearance"
func set_text_override(kind: String, item_id: String, field: String, text: String) -> bool:
	var bucket_key: String = {"unit": "units", "artifact": "artifacts", "order": "orders"}.get(kind, "")
	if bucket_key.is_empty() or item_id.is_empty():
		push_error("ItemDatabase: 非法的覆盖目标 kind=%s id=%s。" % [kind, item_id])
		return false
	if not (field in EDITABLE_FIELDS):
		push_error("ItemDatabase: 字段 %s 不在可编辑白名单内。" % field)
		return false
	var bucket: Dictionary = _overrides.get(bucket_key, {})
	var patch: Dictionary = bucket.get(item_id, {})
	patch[field] = text
	bucket[item_id] = patch
	_overrides[bucket_key] = bucket
	## 立即回写到内存对象，界面无需重载即可看到效果
	if kind == "artifact":
		var art := get_artifact(item_id)
		if art != null:
			art.set(field, text)
	elif kind == "order":
		var od := get_order(item_id)
		if od != null:
			od.set(field, text)
	item_text_changed.emit(kind, item_id)
	return _save_overrides()

## 取帮助窗口正文（优先返回开发者模式覆盖文本，无覆盖回退到 localization.csv 的 HELP_TEXT）
func get_help_text() -> String:
	var patch: Dictionary = (_overrides.get("help", {}) as Dictionary)
	var text: String = String(patch.get("body", ""))
	return text if not text.is_empty() else tr("HELP_TEXT")

## 覆盖帮助窗口正文（开发者模式专用），成功写盘返回 true
## 覆盖与图鉴文本覆盖同源：存进 codex_overrides.json 的 "help" 桶，删文件即还原
func set_help_text_override(text: String) -> bool:
	var bucket: Dictionary = _overrides.get("help", {})
	bucket["body"] = text
	_overrides["help"] = bucket
	return _save_overrides()

## 清空全部文本覆盖并重新加载规范数据
func clear_overrides() -> void:
	_overrides = {"units": {}, "artifacts": {}, "orders": {}}
	_save_overrides()
	load_all()

## 覆盖文件路径：编辑器内写进项目，导出版写进用户目录
func _overrides_path() -> String:
	if OS.has_feature("editor"):
		return "res://data/codex_overrides.json"
	return "user://codex_overrides.json"

## 把覆盖字典中的字段套用到资源对象上
func _apply_override(target: Resource, bucket_key: String, item_id: String) -> void:
	var bucket: Dictionary = _overrides.get(bucket_key, {})
	var patch: Dictionary = bucket.get(item_id, {})
	for field in patch.keys():
		var key := String(field)
		if key in EDITABLE_FIELDS:
			target.set(key, String(patch[field]))

## 读取 JSON 文件为字典，失败返回空字典
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ItemDatabase: 找不到数据文件 %s。" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ItemDatabase: 无法打开 %s（错误码 %d）。" % [path, FileAccess.get_open_error()])
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemDatabase: %s 不是合法的 JSON 对象。" % path)
		return {}
	return parsed as Dictionary

## 载入文本覆盖文件（不存在视为无覆盖）
func _load_overrides() -> void:
	_overrides = {"units": {}, "artifacts": {}, "orders": {}}
	var path: String = _overrides_path()
	if not FileAccess.file_exists(path):
		return
	var loaded: Dictionary = _read_json(path)
	for key in ["units", "artifacts", "orders", "help"]:
		if loaded.has(key) and typeof(loaded[key]) == TYPE_DICTIONARY:
			_overrides[key] = loaded[key]

## 把文本覆盖写盘
func _save_overrides() -> bool:
	var path: String = _overrides_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ItemDatabase: 无法写入 %s（错误码 %d）。" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(_overrides, "\t"))
	file.close()
	return true
