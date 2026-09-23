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
##   trigger       触发方式（#2026-09-20 抽象，肉鸽 / 标准用不同触发方式）：
##                   {"kind": "cooldown"}               冷却时间触发（标准模式默认）
##                       —— 参数取顶层 cd（冷却秒数）与 trigger_range（触发半径像素）
##                   {"kind": "attack_count", "count": N} 攻击次数触发
##                       —— 累计完成 N 次普通攻击周期后，第 N+1 次攻击改为释放技能；
##                          由 state_attack 在「即将开始新攻击周期」时抢占，见 UnitSkillComponent
##                 后续肉鸽侧触发方式（波次 CD / 手动指令等）在此新增 kind 即可，
##                 触发判定全部收敛在 UnitSkillComponent，效果侧无需感知。
##   cd            冷却时间（秒）—— trigger.kind == "cooldown" 时生效
##   cast_time     前摇时长（秒）：蓄力 / 吟唱阶段，期间锁定移动与普攻
##   recover_time  后摇时长（秒）：结算后的僵直
##   trigger_range 触发半径（像素）：该范围内有敌人才释放 —— trigger.kind == "cooldown" 时生效
##   anim          前摇播放的动画名（"attack" = 复用现有攻击动画降速播放；
##                 "skill" = 使用 resources/units/<unit_id>/skill_frames.tres）
##   anim_speed    前摇动画播放速度倍率（<1 = 放慢，营造蓄力感）
##   effect        效果参数字典，由 SkillEffects 按 id 解读

## 技能定义表
## 五位英雄的标准模式技能全部按「攻击次数触发」统一（每打满 3 次普攻，第 4 次攻击触发）：
##   Hero1（爱弥斯）：标准模式暂不配技能（用户拍板；其肉鸽技能见 HeroSkillManager）。
##   Hero2（Doro勇士）：巨化重击（giant_strike，state_skill 专属流程）。
##   Hero3（菲比Hero）：充能光球（orb_charge_launch，state_skill 专属流程 + SkillOrb）。
##   Hero4（咕咕嘎嘎）：回身七连（frame_hold_backburst，state_skill 帧定格流程）。
##   Hero5（糯糯）：九箭齐射（multi_lock_volley，inline 效果，不切状态）。
## 全部技能期间自动获得霸体（state_skill.enter()/exit() 统一置位 skill_super_armor）。
const SKILL_DEFS: Array[Dictionary] = [
	{
		"id": "hero1_summon_heroes",
		"unit_id": "Hero1",
		"name": "四方英灵",
		"desc": "每 3 次普攻后的第 4 次攻击改为技能：召唤糯糯Hero、菲比Hero、咕咕嘎嘎Hero与Doro勇士各一名前来助战。召回的是缩水版援军——没有护盾、不能释放技能，生命上限与造成的伤害都只有本体的一半。",
		"enabled": true,
		"trigger": {"kind": "attack_count", "count": 3},
		"cd": 0.0,
		## 常规流程 A：吟唱 cast_time 秒（复用攻击动画降速播放），结束时结算召唤
		"cast_time": 0.8,
		"recover_time": 0.4,
		"trigger_range": 0.0,
		"anim": "attack",
		"anim_speed": 0.6,
		"effect": {
			"kind": "summon_heroes",
			## 召唤对象（顺序即环形落点顺序：正上方起顺时针）
			"hero_ids": ["Hero5", "Hero3", "Hero4", "Hero2"],
			## 环形分布半径（像素）：四个英雄在施法者周围均分一圈，避免叠在一格
			"spawn_radius": 70.0,
		},
	},
	{
		"id": "hero2_giant_strike",
		"unit_id": "Hero2",
		"name": "巨化重击",
		"desc": "每 3 次普攻后的第 4 次攻击改为技能：先用 1 秒平滑膨胀到 2 倍体型（过程播后摇动画，不出攻击动作），随后挥出强化一击造成 300 挥砍 + 300 钝击伤害，命中后再用 1 秒平滑缩回正常体型。巨化期间攻击面随体型放大（横向额外 ×1.3）。技能期间霸体。",
		"enabled": true,
		## 攻击次数触发：打满 3 次普通攻击后，第 4 次攻击由本技能接管
		"trigger": {"kind": "attack_count", "count": 3},
		"cd": 0.0,
		"cast_time": 0.0,
		"recover_time": 0.0,
		"trigger_range": 0.0,
		"anim": "attack",
		"anim_speed": 1.0,
		"effect": {
			"kind": "giant_strike",
			## 膨胀 / 缩回的时长（秒）与体型倍率；两段过程都播后摇动画，不播攻击动画
			"grow_time": 1.0,
			"grow_mult": 2.0,
			"shrink_time": 1.0,
			## 2026-09-22 需求：巨化期间**横向**攻击范围在「体型 ×2」之上再 ×1.3。
			## 即横向 = 1.2 格 ×32 ×2 ×1.3 ≈ 100px，纵向维持 ×2 = 38.4px。
			"grow_range_h_mult": 1.3,
			## 强化一击的伤害：伤害类型 → 数值（0=挥砍, 1=穿刺, 2=钝击, 3=魔法），同伤系统全部同时生效
			"hit_damage": {0: 300, 2: 300},
		},
	},
	{
		"id": "hero3_orb_charge",
		"unit_id": "Hero3",
		"name": "充能星屑",
		"desc": "每 3 次普攻后的第 4 次攻击改为技能：光球在头顶浮现并悬停，随攻击动画前三段依次「出现 → 变大两次」，第四段沿面朝方向发射；光球一路推进到自身攻击范围之外后爆炸（80px 内 100 魔法伤害）。推进途中每 0.5 秒判定一次：范围内敌人被吸附并受 20 魔法伤害，范围内友方恢复 20 生命（只回血量，不动护盾）。技能期间霸体。",
		"enabled": true,
		"trigger": {"kind": "attack_count", "count": 3},
		"cd": 0.0,
		"cast_time": 0.0,
		"recover_time": 0.0,
		"trigger_range": 0.0,
		"anim": "attack",
		"anim_speed": 1.0,
		"effect": {
			"kind": "orb_charge_launch",
			## 光球悬停点：施法者头顶偏移（负值向上）
			"orb_offset_y": -70.0,
			## 三次尺寸（直径像素）：第 1 段出现=60、第 2 段变大=90、第 3 段变大=130。
			## 判定半径恒等于光球当前半径（用户拍板「光球多大，判定范围就多大」）。
			"orb_diameters": [60.0, 90.0, 130.0],
			## 星云光套的缓慢旋转速度（度/秒）
			"spin_speed": 40.0,
			## 发射后的推进速度（像素/秒）与行程。
			## fly_distance = 0 表示「用自身 attack_range × 32」（菲比 8.0 → 256px），
			## 即用户拍板的「推到自身攻击范围之外时爆炸」。
			"fly_speed": 200.0,
			"fly_distance": 0.0,
			## 推进途中的周期判定：每 tick_interval 秒一次
			"tick_interval": 0.5,
			"pull_px": 30.0,
			"tick_damage": 20,
			"tick_damage_type": 3,
			"heal_amount": 20,
			## 行程终点的爆炸
			## 2026-09-22 需求：最后一段爆炸的范围与伤害各减半（160→80px、200→100）。
			"explode_radius": 80.0,
			"explode_damage": 100,
			"explode_damage_type": 3,
		},
	},
	{
		"id": "hero4_back_burst",
		"unit_id": "Hero4",
		"name": "一瞬千击",
		"desc": "每 3 次普攻后的第 4 次攻击改为技能：攻击动画在判定帧前两帧定格 1 秒蓄力，随后 0.2 秒冲刺 150px 并回身，10 道萌黄冲击特效在 1 秒的第二次停顿里用 0.6 秒自位移起点向终点一道道铺开，铺完后 0.4 秒内连续打出 7 段伤害；剩余攻击动画播完后整批特效 1 秒渐隐。技能期间霸体，不被击退打断",
		"enabled": true,
		## 攻击次数触发：打满 3 次普通攻击后，第 4 次攻击由本技能接管
		"trigger": {"kind": "attack_count", "count": 3},
		"cd": 0.0,
		"cast_time": 0.0,
		"recover_time": 0.0,
		"trigger_range": 0.0,
		"anim": "attack",
		"anim_speed": 1.0,
		"effect": {
			"kind": "frame_hold_backburst",
			## 定格帧 / 判定帧：Hero4 攻击动画共 23 帧，attack_hit_frame_start = 11，
			## hold_frame = 9 即「判定帧往前两帧」（2026-09-20 用户要求再往前移一帧，原为 10）
			"hold_frame": 9,
			"hold_time": 1.0,
			"hit_frame": 11,
			"hit_hold_time": 1.0,
			## 判定帧朝当前朝向冲刺的像素距离（0.2s 平滑冲刺，不是瞬移）
			"dash_px": 150.0,
			"dash_time": 0.2,
			## 判定走廊：沿身后方向 0 ~ back_length、横向 ±back_half_width
			## back_length 必须 >= dash_px，才能覆盖「位移起点 → 位移终点」整条路径
			"back_length": 150.0,
			"back_half_width": 50.0,
			## 判定时序（用户拍板）：第二次停顿共 hit_hold_time = 1.0 秒，
			## 先用 fx_spread_time = 0.6 秒把红光铺完，铺完后才在 damage_window = 0.4 秒内排队打完 hit_count 段。
			## 两者由同一条协程串行保证先后（见 SkillEffects.apply_hold_backburst），不额外配延迟参数。
			"hit_count": 7,
			"damage": 60,
			"damage_type": 0,
			"damage_window": 0.4,
			## 视觉：fx_count 道萌黄（S9）特效沿走廊均匀分布（0 = 位移起点，最后一道 = 位移终点），
			## 在 fx_spread_time 内自起点向终点一道道铺开；攻击动画播完后统一 fx_fade_time 渐隐
			"fx_count": 10,
			"fx_frames": "res://resources/units/S9/impact_frames.tres",
			"fx_height": 68.667,
			"fx_width": 86.667,
			"fx_spread_time": 0.6,
			"fx_fade_time": 1.0,
		},
	},
	{
		"id": "hero5_nine_arrow_volley",
		"unit_id": "Hero5",
		"name": "九箭齐射",
		"desc": "每 3 次普攻后的第 4 次攻击起进入九箭状态：同时锁定最多 3 名射程内敌人，共射出 9 支箭（每箭 100 伤害）；主目标走直线箭，第 2 / 3 目标的箭分别自上方、下方呈鱼钩状飞射而来。状态持续 2 次攻击。",
		"enabled": true,
		## 攻击次数触发：打满 3 次普通攻击后触发；本次普攻即为第一次九箭，之后还有 1 次
		"trigger": {"kind": "attack_count", "count": 3},
		"cd": 0.0,
		"cast_time": 0.0,
		"recover_time": 0.0,
		"trigger_range": 0.0,
		"anim": "attack",
		"anim_speed": 1.0,
		"effect": {
			## 本效果不改变动作流程，只叠加到普攻上（unit_skill_component 的 inline 分支处理）
			"kind": "multi_lock_volley",
			## 同时锁定的最大敌人数
			"max_targets": 3,
			## 状态持续的普攻次数（含触发的这一次）
			"charges": 3,
			## 总箭数与单箭伤害（总箭数按「近者多 1 支」分配：3 敌=3/3/3、2 敌=5/4、1 敌=9）
			"total_arrows": 9,
			"arrow_damage": 100,
			"arrow_damage_type": 0,
			## 鱼钩箭：起点上下偏移、钩形凸起幅度、整段飞行时长
			"hook_offset_y": 96.0,
			"hook_bulge": 70.0,
			"hook_fly_time": 0.55,
		},
	},
]

## unit_id → 技能定义 的查找缓存（首次查询时惰性构建）
static var _by_unit: Dictionary = {}
static var _built: bool = false

## ============================================================
## 标准模式兵种技能系统总开关
## ============================================================
## 2026-08-21 用户要求「先停用」→ 曾置 false；
## 2026-09-20 用户要求「总开关打开，但只启用 Hero4 这一条」→ 置 true，
## 同时把 Hero2 / Hero3 的 enabled 改回 false，二者配合后实际生效的只有 Hero4 回身七连。
##
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
const SYSTEM_ENABLED: bool = true

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
