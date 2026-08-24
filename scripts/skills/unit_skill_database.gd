class_name UnitSkillDatabase
extends RefCounted
## 兵种技能数据表（标准模式：战役 / 全面战争 / 双人）
##
## 设计原则（来自与用户的需求确认）：
##   1. 技能绑定「兵种」而非「玩家/AI」——红蓝双方部署同一英雄，技能行为完全一致。
##   2. 自动释放：CD 就绪 且 触发半径内有敌人，即由单位自行释放，无需玩家操作。
##   3. 冷却以「秒」计（标准模式没有波次概念，与肉鸽 HeroSkillManager 的波次 CD 完全无关）。
##   4. 纯数据驱动：新增技能只改本表 + 在 SkillEffects 加一个分支，不散落各处。
##
## 与肉鸽的关系：本表只服务标准模式，不读写 RoguelikeManager，
## 也不影响 autoload/hero_skill_manager.gd（那套是肉鸽专用的波次 CD 技能）。
##
## 技能定义字段说明：
##   id            唯一标识（效果分发的 key）
##   unit_id       所属兵种（与 UnitResource.unit_id 对应）
##   name          显示名
##   desc          描述文本
##   cd            冷却时间（秒）
##   cast_time     前摇时长（秒）：蓄力 / 吟唱阶段，期间锁定移动与普攻
##   recover_time  后摇时长（秒）：结算后的僵直
##   trigger_range 触发半径（像素）：该范围内有敌人才释放
##   anim          前摇播放的动画名（"attack" = 复用现有攻击动画降速播放；
##                 "skill" = 使用 resources/units/<unit_id>/skill_frames.tres）
##   anim_speed    前摇动画播放速度倍率（<1 = 放慢，营造蓄力感）
##   effect        效果参数字典，由 SkillEffects 按 id 解读

## 技能定义表
## Hero1（爱弥斯）：标准模式暂不配技能（用户拍板；其肉鸽技能见 HeroSkillManager）。
## Hero4（咕咕嘎嘎）/ Hero5（糯糯）：单位尚未建资源与动画，先留数据位，
##   等 .tres 与动画就位后把 enabled 改为 true 即自动生效，无需改代码。
const SKILL_DEFS: Array[Dictionary] = [
	{
		"id": "hero2_greatsword_slam",
		"unit_id": "Hero2",
		"name": "巨剑下砸",
		"desc": "短暂蓄力后大剑下砸，对周围造成一片圆形钝击伤害，并将敌人击退、减速 5 秒",
		"enabled": true,
		"cd": 12.0,
		"cast_time": 0.6,
		"recover_time": 0.4,
		"trigger_range": 110.0,
		"anim": "attack",
		"anim_speed": 0.5,
		"effect": {
			"kind": "slam",
			"radius": 120.0,
			"damage": 180,
			"damage_type": 2,
			"knockback_px": 55.0,
			"slow_percent": 0.4,
			"slow_duration": 5.0,
		},
	},
	{
		"id": "hero3_light_pillar",
		"unit_id": "Hero3",
		"name": "圣光降临",
		"desc": "短暂吟唱后在目标位置降下一道光柱，造成大量魔法伤害",
		"enabled": true,
		"cd": 14.0,
		"cast_time": 0.8,
		"recover_time": 0.5,
		"trigger_range": 260.0,
		"anim": "skill",
		"anim_speed": 1.0,
		"effect": {
			"kind": "pillar",
			"radius": 70.0,
			"damage": 260,
			"damage_type": 3,
			"cast_range": 260.0,
		},
	},
	{
		"id": "hero4_dash_strike",
		"unit_id": "Hero4",
		"name": "破阵突袭",
		"desc": "举剑蓄力后向前方位移 500px，位移结束后对身后 500px 范围造成 5 段伤害",
		"enabled": false,
		"cd": 15.0,
		"cast_time": 1.0,
		"recover_time": 0.5,
		"trigger_range": 300.0,
		"anim": "attack",
		"anim_speed": 0.5,
		"effect": {
			"kind": "dash_strike",
			"dash_px": 500.0,
			"dash_time": 0.35,
			"trail_width": 90.0,
			"hit_count": 5,
			"damage": 60,
			"damage_type": 0,
		},
	},
	{
		"id": "hero5_horse_archery",
		"unit_id": "Hero5",
		"name": "骑射",
		"desc": "进入 5 秒骑射状态，期间取消攻击后摇",
		"enabled": false,
		"cd": 18.0,
		"cast_time": 0.3,
		"recover_time": 0.0,
		"trigger_range": 320.0,
		"anim": "attack",
		"anim_speed": 1.0,
		"effect": {
			"kind": "no_recovery_buff",
			"duration": 5.0,
		},
	},
]

## unit_id → 技能定义 的查找缓存（首次查询时惰性构建）
static var _by_unit: Dictionary = {}
static var _built: bool = false

## ============================================================
## 标准模式兵种技能系统总开关（2026-08-21 用户要求「先停用」）
## ============================================================
## false = 停用：has_skill() 恒返回 false、get_skill_for_unit() 恒返回空字典。
## 于是 unit_base._setup_skill_component() 直接不挂组件，
## 已挂载的 UnitSkillComponent 也会在 _ready 查表拿到空字典后自我 queue_free。
## 单位不会再切入 "skill" 状态，SkillEffects 也不会被调用。
##
## 为什么在这里加而不是把各技能的 enabled 改成 false：
##   1. 单点可逆——恢复时只改这一行，不必逐条回滚数据、不会漏项或改错值；
##   2. 各技能自己的 enabled 语义保持原样（表示「这条技能本身做完了没」），
##      与「整个系统要不要开」是两件事，混在一起以后会分不清是谁关的。
##
## 注意：本开关**只管标准模式**（战役 / 全面战争 / 双人）。
## 肉鸽模式的英雄技能走 autoload/hero_skill_manager.gd，与本表完全无关，不受影响。
## 另外 _built 是 static var，缓存只构建一次，改动本开关需重启才生效。
const SYSTEM_ENABLED: bool = false

## 构建查找表：只收录 enabled == true 的技能
static func _build() -> void:
	if _built:
		return
	_built = true
	## 总开关关闭时留空表，等价于「所有兵种都没有技能」
	if not SYSTEM_ENABLED:
		return
	for d in SKILL_DEFS:
		if not bool(d.get("enabled", false)):
			continue
		_by_unit[String(d["unit_id"])] = d

## 取某兵种的技能定义；无技能返回空字典
## 绝大多数兵种（30+ 个普通兵）都会返回空字典，调用方据此跳过，零额外开销
static func get_skill_for_unit(unit_id: String) -> Dictionary:
	_build()
	return _by_unit.get(unit_id, {})

## 某兵种是否拥有已启用的技能
static func has_skill(unit_id: String) -> bool:
	_build()
	return _by_unit.has(unit_id)
