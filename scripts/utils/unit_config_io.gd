class_name UnitConfigIO
## 兵种配置 导出/导入/重置配置 共用工具
## 范围：控制台「动画调整」+「数值调整」两个页面的全部可调字段
## 不包含：帧图调整（attack_frames.tres 等帧配置）、音效配置（路径引用在对方电脑可能失效）

## ── 字段清单（与 debug_units.gd 两个调整页一一对应）──────────────────

## 动画调整页（Tab1 尺寸调试）可调字段
const ANIM_FIELDS: Array[String] = [
	"display_width", "display_height",
	"move_display_width", "move_display_height",
	"walk_display_width", "walk_display_height",
	"attack_display_width", "attack_display_height",
	"sprint_display_width", "sprint_display_height",
	"idle_display_width", "idle_display_height",
	## 播放速度倍率（#4）
	"move_anim_speed", "attack_anim_speed", "sprint_anim_speed", "idle_anim_speed",
	"attack_anim_sync_interval",
	## 独立翻转
	"move_flip_override", "walk_flip_override", "attack_flip_override", "idle_flip_override", "sprint_flip_override",
	## 近战/远程覆盖 + 默认朝向
	"is_ranged_override", "default_facing",
]

## 数值调整页（Tab2 数值调试）可调字段
const STATS_FIELDS: Array[String] = [
	"cost", "max_hp", "armor_value", "move_speed", "attack_range",
	"attack_range_h", "attack_range_v", "attack_speed",
	"aoe_radius", "attack_recovery_time",
	## 连击配置
	"attack_count", "attack_hit_types", "damage", "damage_type", "damage_by_type",
	"damage_by_hit",  ## 每击独立伤害（Array[Dictionary]，高级配置）
	## #5：远程技能配置（Y1 死亡使者独有三件套）
	"ranged_skill_cooldown", "ranged_skill_damage", "ranged_skill_range",
]

## 词条资源目录（按 affix_id 查找 .tres）
const AFFIX_DIR := "res://resources/affixes"

## 导出文件格式版本（破坏性变更时 +1，导入时校验）
const FORMAT_VERSION: int = 1

## ── 收集 / 应用 ──────────────────────────────────────────────

## 收集单个兵种的可导出数据
## res: 兵种资源
## 返回值: {"unit_id", "anim": {...}, "stats": {...}}，词条以 affix_id 数组保存
static func collect_unit_data(res: UnitResource) -> Dictionary:
	var data := {}
	data["unit_id"] = res.unit_id
	var anim := {}
	for f in ANIM_FIELDS:
		anim[f] = res.get(f)
	var stats := {}
	for f in STATS_FIELDS:
		stats[f] = res.get(f)
	## 词条：存 affix_id 列表，导入方按 id 从本地 resources/affixes 重新加载
	var affix_ids: Array[String] = []
	for a in res.affixes:
		if a != null and a.affix_id != "":
			affix_ids.append(a.affix_id)
	stats["affix_ids"] = affix_ids
	data["anim"] = anim
	data["stats"] = stats
	return data

## 把导出的数据覆盖应用到兵种资源
## res: 目标兵种资源（就地修改，由调用方负责保存 .tres）
## data: collect_unit_data 的输出
## 返回值: 是否应用成功
static func apply_unit_data(res: UnitResource, data: Dictionary) -> bool:
	if res == null or not data.has("unit_id"):
		return false
	var anim: Dictionary = data.get("anim", {})
	for f in ANIM_FIELDS:
		if anim.has(f):
			res.set(f, anim[f])
	var stats: Dictionary = data.get("stats", {})
	for f in STATS_FIELDS:
		if stats.has(f):
			res.set(f, stats[f])
	## damage_by_type 的键是伤害类型 int，JSON 读回后是 String 键，需转回 int
	if stats.has("damage_by_type") and stats["damage_by_type"] is Dictionary:
		var raw_dbt: Dictionary = stats["damage_by_type"]
		var dbt: Dictionary = {}
		for k in raw_dbt:
			dbt[int(k)] = int(raw_dbt[k])
		res.damage_by_type = dbt
	## 词条：按 affix_id 重新加载本地资源（对方电脑的文件名/结构可能不同，只认 id）
	if stats.has("affix_ids") and stats["affix_ids"] is Array:
		var new_affixes: Array[AffixResource] = []
		for aid in stats["affix_ids"]:
			var a: AffixResource = load_affix_by_id(str(aid))
			if a != null:
				new_affixes.append(a)
		res.affixes = new_affixes
	return true

## 按 affix_id 加载词条资源
## affix_id: 词条唯一标识（如 "bleed"/"poison"/"knockback"）
## 返回值: 词条资源，未找到返回 null
static func load_affix_by_id(affix_id: String) -> AffixResource:
	if affix_id == "":
		return null
	var path := "%s/%s.tres" % [AFFIX_DIR, affix_id]
	if ResourceLoader.exists(path):
		var r: Variant = load(path)
		if r is AffixResource:
			return r
	return null

## ── 整包序列化 ──────────────────────────────────────────────

## 把兵种列表序列化为 JSON 文本（含格式版本号）
## unit_ids: 兵种 ID 列表（按此顺序）
## resolver: Callable(unit_id) -> UnitResource，取兵种资源
## 返回值: 完整 JSON 文本
static func serialize_units(unit_ids: Array[String], resolver: Callable) -> String:
	var units: Array = []
	for uid in unit_ids:
		var res: UnitResource = resolver.call(uid)
		if res == null:
			continue
		units.append(collect_unit_data(res))
	return JSON.stringify({"version": FORMAT_VERSION, "units": units}, "\t")

## 解析 JSON 文本并应用（导入 / 恢复出厂共用）
## json_text: serialize_units 的输出（或同构手写配置）
## resolver: Callable(unit_id) -> UnitResource，取兵种资源（不存在返回 null 则跳过）
## 返回值: {"ok": bool, "applied": int, "skipped": int, "message": String}
static func apply_serialized(json_text: String, resolver: Callable) -> Dictionary:
	var result := {"ok": false, "applied": 0, "skipped": 0, "message": ""}
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		result["message"] = "文件不是有效的 JSON"
		return result
	var root: Dictionary = parsed
	if not root.has("units") or not (root["units"] is Array):
		result["message"] = "缺少 units 列表"
		return result
	## 版本校验：只接受 1（未来版本可做兼容迁移）
	var ver: int = int(root.get("version", 0))
	if ver != FORMAT_VERSION:
		result["message"] = "配置版本不兼容（文件 v%d，当前支持 v%d）" % [ver, FORMAT_VERSION]
		return result
	var applied: int = 0
	var skipped: int = 0
	for unit_data in root["units"]:
		if not (unit_data is Dictionary):
			skipped += 1
			continue
		var uid: String = str(unit_data.get("unit_id", ""))
		if uid == "":
			skipped += 1
			continue
		var res: UnitResource = resolver.call(uid)
		if res == null:
			skipped += 1
			continue
		if apply_unit_data(res, unit_data):
			applied += 1
		else:
			skipped += 1
	result["applied"] = applied
	result["skipped"] = skipped
	result["ok"] = true
	return result
