class_name UnitResource extends Resource  ## 声明类名为 UnitResource，继承自 Resource
## 兵种资源基类
## 定义了兵种的所有属性数据，作为 Godot Resource 可在编辑器中配置
## 每种兵种对应一个 .tres 文件，存储该兵种的具体数值

## 兵种的唯一标识符（英文小写），用于程序中识别兵种
@export var unit_id: String = ""
## 兵种的显示名称（中文），用于 UI 界面显示
@export var display_name: String = ""
## 兵种的描述文本，用于工具提示和说明
@export var description: String = ""
## 兵种阶层（1=一阶, 2=二阶, 3=三阶, 4=四阶），决定兵种的强度和造价
@export var tier: int = 1
## 人口占用数，高阶兵种占用更多人口
@export var supply_cost: int = 1
## 兵种造价（金币），购买该兵种需要消耗的金币
@export var cost: int = 0
## 每张卡默认召唤的兵数量（0 = 按阶层自动：tier>=2 高级兵 2 个，其余 3 个）
## 设为 >0 可强制覆盖，做到出兵数量数据驱动、不写死
@export var units_per_card: int = 0
## 每回合收入，拥有该兵种后每回合额外获得的金币
@export var income: int = 0
## 最大生命值（HP），单位的血量上限
@export var max_hp: int = 100
## 护甲值（独立护盾血量），受到伤害时先扣护甲再扣 HP
@export var armor_value: int = 10
## 移动速度（标准单位/秒），决定单位在战场上的移动快慢
@export var move_speed: float = 2.0
## 攻击伤害（统一伤害值，不再区分轻甲/重甲）
@export var damage: int = 10
## 伤害类型（0=挥砍, 1=穿刺, 2=钝击, 3=魔法）
## 用于克制关系和护甲减伤计算（旧字段，保留兼容，新代码请用 damage_types）
@export var damage_type: int = 0
## 多选伤害类型列表（可同时具有多种伤害类型）
## 例如 [0, 3] 表示同时具有挥砍和魔法伤害
@export var damage_types: Array[int] = []
## 各伤害类型对应的伤害值字典（key=伤害类型编号, value=伤害值）
## 多选伤害类型时，每种类型可设置独立伤害值
## 例如 {0: 10, 3: 5} 表示挥砍伤害10 + 魔法伤害5
@export var damage_by_type: Dictionary = {}
## 攻击距离（标准单位），大于 RANGED_THRESHOLD（2.0）视为远程单位
@export var attack_range: float = 1.0
## #3：横向攻击半径（标准单位）。0 表示「沿用 attack_range」，>0 时启用椭圆/矩形判定
##   蓝女巫（S1）攻击纵向一条线：h 小、v 大；D6 大锤手攻击横向宽范围：h 大、v 小
@export var attack_range_h: float = 0.0
## #3：纵向攻击半径（标准单位）。0 表示「沿用 attack_range」，>0 时启用椭圆/矩形判定
@export var attack_range_v: float = 0.0
## 远程/近战覆盖设置（-1=自动根据 attack_range 判断，0=强制近战，1=强制远程）
## 在调试界面可手动切换，用于测试不同兵种类型的行为
@export var is_ranged_override: int = -1
## 攻击速度（秒/次），值越小攻击频率越高
@export var attack_speed: float = 1.5
## 单次攻击周期内的攻击次数（1=单次攻击，2=二连击如G6）
## 在一个 attack_speed 周期内均匀分布多次命中
@export var attack_count: int = 1
## 每次命中对应的伤害类型列表（与 attack_count 对应）
## 留空则所有命中使用 damage_types；设置了则第 i 次命中使用 attack_hit_types[i] 的类型
## 例如二连击第一击挥砍第二击钝击：attack_hit_types = [0, 2]
## 每个元素是该次命中的主伤害类型（0=挥砍,1=穿刺,2=钝击,3=魔法）
@export var attack_hit_types: Array[int] = []
## 每次命中独立的伤害值配置（与 attack_count / attack_hit_types 对应）
## 留空则所有命中共用 damage_by_type；设置了则第 i 次命中使用 damage_by_hit[i] 的伤害字典
## 例如二连击第一击 10 挥砍+5 魔法、第二击 20 钝击：damage_by_hit = [{0:10, 3:5}, {2:20}]
## 每个元素是 Dictionary（同 damage_by_type 格式：{type_int: value_int}）
@export var damage_by_hit: Array = []
## 攻击音效播放时机（0.0~1.0，相对于 attack_speed 的比例）
## 0.0=周期开始即播放，1.0=周期结束播放，默认 0.95（与近战命中点一致）
## 可在调试界面调整并永久保存到 .tres
@export var attack_sound_timing: float = 0.95
## 攻击动画中的命中帧索引（0 开始），-1 表示不通过动画帧触发伤害
## 配置后，state_attack 会在动画播放到该帧时执行 perform_attack()
@export var attack_hit_frame: int = -1
## 攻击判定起始帧（0 开始，-1 表示不启用范围命中）
## 配置后优先于 attack_hit_frame 生效，进入 [start, end] 范围的第一帧触发 perform_attack()
@export var attack_hit_frame_start: int = -1
## 备用攻击动画（attack_alt_frames，凑企鹅 Y2 双攻击轮流）的独立命中帧
## 两套动画帧数/挥击时机不同，命中帧必须各自配置：-1 = 未配置时沿用攻击一的命中帧
@export var attack_hit_frame_start_alt: int = -1
## 攻击判定结束帧（0 开始，-1 表示与 start 相同=单帧命中）
## 配合 attack_hit_frame_start 使用，标记判定窗口的最后一帧
@export var attack_hit_frame_end: int = -1
## 攻击音效播放帧（0 开始，-1 表示使用 attack_sound_timing 比例）
## 配置后，动画播放到该帧时播放音效（优先于 attack_sound_timing 生效）
@export var attack_sound_frame: int = -1
## 备用攻击动画（attack_alt_frames）的独立音效帧：-1 = 未配置时沿用攻击一的音效帧
@export var attack_sound_frame_alt: int = -1
## 多段连击的判定帧列表（与 attack_count 对应）
## 每个元素为该次命中的判定帧索引（0 开始）
## 空数组 []：使用 attack_hit_frame_start 单帧判定逻辑
## [5]：单次命中在第5帧触发
## [5, 15]：二连击，第一击在第5帧，第二击在第15帧触发
## 配置后优先于 attack_hit_frame_start 生效
@export var attack_hit_frames: Array[int] = []
## 素材默认朝向（1=默认朝右，-1=默认朝左）
## 根据素材实际朝向设置，用于正确翻转精灵图
@export var default_facing: int = -1
## 精灵在局内的显示高度（像素），0 表示使用全局默认值（40）
## 调试界面可调整，永久保存到 .tres
@export var display_height: float = 40.0
## 精灵在局内的显示宽度（像素），0 表示与高度相同
## 调试界面可调整，永久保存到 .tres
@export var display_width: float = 40.0
## 移动动画的独立显示高度（像素），0 表示使用 display_height
@export var move_display_height: float = 0.0
## 移动动画的独立显示宽度（像素），0 表示使用 display_width
@export var move_display_width: float = 0.0
## 行走动画的独立显示高度（像素），0 表示使用 display_height
@export var walk_display_height: float = 0.0
## 行走动画的独立显示宽度（像素），0 表示使用 display_width
@export var walk_display_width: float = 0.0
## 攻击动画的独立显示高度（像素），0 表示使用 display_height
@export var attack_display_height: float = 0.0
## 攻击动画的独立显示宽度（像素），0 表示使用 display_width
@export var attack_display_width: float = 0.0
## 冲刺动画的独立显示高度（像素），0 表示使用 display_height
@export var sprint_display_height: float = 0.0
## 冲刺动画的独立显示宽度（像素），0 表示使用 display_width
@export var sprint_display_width: float = 0.0
## 待机动画的独立显示高度（像素），0 表示使用 display_height
@export var idle_display_height: float = 0.0
## 待机动画的独立显示宽度（像素），0 表示使用 display_width
@export var idle_display_width: float = 0.0
## 出场动画的独立显示高度（像素），0 表示使用 display_height
@export var charge_display_height: float = 0.0
## 出场动画的独立显示宽度（像素），0 表示使用 display_width
@export var charge_display_width: float = 0.0
## 死亡动画的独立显示高度（像素），0 表示使用 display_height
@export var death_display_height: float = 0.0
## 死亡动画的独立显示宽度（像素），0 表示使用 display_width
@export var death_display_width: float = 0.0
## 远程技能冷却（秒），>0 表示该单位拥有定时释放的远程技能（用 sprint 动画槽位）
@export var ranged_skill_cooldown: float = 0.0
## 远程技能伤害
@export var ranged_skill_damage: int = 0
## 远程技能射程（格子）
@export var ranged_skill_range: float = 0.0

## ── 动画播放速度（#4）────────────────────────────────────────
## 与 attack_speed（攻击间隔秒数）是两个完全独立的概念：
## attack_speed 决定「多久打一次」，下面这些倍率只决定「一次动画播多快」。
## 1.0 = 按 SpriteFrames 里配置的原始 FPS 播放。
## 移动动画播放速度倍率
@export var move_anim_speed: float = 1.0
## 攻击动画播放速度倍率
@export var attack_anim_speed: float = 1.0
## 第二套攻击动画帧文件名（可选，如 "attack2_frames.tres"）：凑企鹅等双攻击兵种，
## 每攻击周期轮流使用 attack 与 attack_alt（先攻击1、再攻击2）。空 = 单攻击动画。
@export var attack_alt_frames: String = ""
## #攻击特效（2026-08-15 / #14 补丁）：命中后是否等待攻击动画完整播完才进入后摇。
## 默认 true = 所有兵种攻击动画完整播放（#14 用户拍板）。
## false = 命中已出即进后摇（唯一例外 H2：其攻击动画 frame 14 后帧内容尺寸暴涨
## 403→619px，完整播放会视觉膨胀偏移，故 H2 保持 #12「命中即后摇」不完整播放）。
@export var attack_wait_anim_end: bool = true
## #突进（2026-08-15）：命中帧朝目标方向突进位移（像素）。0 = 不突进。
## 凑企鹅（Y2）等打击感兵种使用。位移曲线：前 90% 距离快速、后 10% 减速，总时长 1 秒。
@export var attack_dash_px: float = 0.0
## 冲刺动画播放速度倍率
@export var sprint_anim_speed: float = 1.0
## 待机动画播放速度倍率
@export var idle_anim_speed: float = 1.0
## 攻击动画是否拉伸到与攻击间隔等长（true=一次攻击刚好播完一遍动画，攻速加成会同步影响动画；
## false=攻击动画只按 attack_anim_speed 播放，与攻速彻底解耦）
## 2026-08-14：默认由 true 改为 false——原默认开启会把「播放速度」倍率淹没在「拉伸到攻击间隔」里，
## 导致控制台调了攻击动画速度、局内看着像没生效。改为默认关闭后，「播放速度」直接、明显地控制局内攻击动画快慢。
@export var attack_anim_sync_interval: bool = false

## 攻击硬后摇时长（秒）：攻击周期结束后的固定僵直锁定（不可移动/不可后撤，可转身）
## -1 = 跟随兵种类型默认（远程 0.5s / 近战 0s）；显式设置 >=0 时优先用该值
## 可在调试界面「数值调整」中调校并永久保存到 .tres（中远程兵种默认 0.5 秒后摇）
@export var attack_recovery_time: float = -1.0

## 移动动画是否独立翻转（null=跟随 default_facing，true=强制翻转，false=强制不翻转）
@export var move_flip_override: int = 0
## 行走动画是否独立翻转（null=跟随 default_facing，1=强制翻转，0=跟随默认）
@export var walk_flip_override: int = 0
## 攻击动画是否独立翻转（0=跟随 default_facing，1=强制翻转）
@export var attack_flip_override: int = 0
## 待机动画是否独立翻转（0=跟随 default_facing，1=强制翻转）
@export var idle_flip_override: int = 0
## 冲刺动画是否独立翻转（0=跟随 default_facing，1=强制翻转）
@export var sprint_flip_override: int = 0
## 远程单位飞行物贴图（可选，null 时使用默认方块）
@export var projectile_texture: Texture2D = null
## 飞行物自旋速度（度/秒）。>0 时飞行途中持续旋转，用于飞斧这类翻滚投掷物（D5）
## 0 表示不自旋，贴图始终朝向飞行方向
@export var projectile_spin_speed: float = 0.0
## 飞行物贴图朝向补偿（度）。在「朝向飞行方向」基础上再叠加的固定旋转，
## 用于素材本身朝向不对的情况（如 G5 标枪需要额外转 180°）
@export var projectile_rotation_offset: float = 0.0
## 飞行物发射位置的 Y 轴偏移（像素）。正值下移、负值上移（Godot 坐标系 Y 轴向下）。
## 用于个别骑乘/持弓兵种的弹道从更高处（如弓弦）发射，默认 0 从单位原点发射。
@export var projectile_spawn_offset_y: float = 0.0
## 是否远程单位（只读属性）
## 优先使用 is_ranged_override（-1=自动, 0=近战, 1=远程），否则根据 attack_range 自动判断
var is_ranged: bool:
	get:
		if is_ranged_override == 1:
			return true
		elif is_ranged_override == 0:
			return false
		return attack_range > Constants.RANGED_THRESHOLD  ## 自动判断：攻击距离大于远程阈值则视为远程单位
## #3：是否使用横/纵分开的椭圆/矩形攻击判定（attack_range_h 或 attack_range_v 任一 > 0 即为 true）
var use_elliptical_range: bool:
	get:
		return attack_range_h > 0.0 or attack_range_v > 0.0
## #3：横向攻击半径像素值（默认沿用 attack_range）
func get_attack_range_h_px() -> float:
	if attack_range_h > 0.0:
		return attack_range_h * Constants.UNIT_TO_PIXELS
	return attack_range * Constants.UNIT_TO_PIXELS
## #3：纵向攻击半径像素值（默认沿用 attack_range）
func get_attack_range_v_px() -> float:
	if attack_range_v > 0.0:
		return attack_range_v * Constants.UNIT_TO_PIXELS
	return attack_range * Constants.UNIT_TO_PIXELS
## 红方单位的占位颜色（用于没有精灵图时的颜色区分）
@export var color_red: Color = Color(1, 0.3, 0.3)
## 蓝方单位的占位颜色（用于没有精灵图时的颜色区分）
@export var color_blue: Color = Color(0.3, 0.3, 1)
## 单位精灵图（可选，优先于颜色方块显示）
@export var sprite_texture: Texture2D = null
## 精灵图在 spritesheet 中的区域（如果整张图就是单个精灵则留空）
@export var sprite_region: Rect2 = Rect2(0, 0, 0, 0)
## 克制关系表（字典）
## 键：被克制的兵种 ID，值：伤害倍率（如 1.5 表示克制时伤害增加 50%）
@export var counter_table: Dictionary = {}
## 被克制关系表（字典）
## 键：克制自己的兵种 ID，值：伤害倍率（如 0.6 表示被克制时伤害减少 40%）
@export var weakness_table: Dictionary = {}
## 受击框宽度（像素，蓝色框），单位被击中的判定区域宽度
@export var hitbox_width: float = 40.0
## 受击框高度（像素，蓝色框），单位被击中的判定区域高度
@export var hitbox_height: float = 40.0
## 攻击判定框宽度（像素，红色框），单位攻击的判定区域宽度
## 红框代表攻击判定范围，与敌方蓝框（受击框）重叠时判定攻击命中
@export var attack_box_width: float = 40.0
## 攻击判定框高度（像素，红色框），单位攻击的判定区域高度
@export var attack_box_height: float = 40.0
## 攻击判定框 X 偏移（像素，正值=朝右，负值=朝左）
## 默认 0 表示以单位原点为中心，按需调整到面朝方向前方
@export var attack_box_offset_x: float = 0.0
## 攻击判定框 Y 偏移（像素，正值=朝下，负值=朝上）
## 默认 0 表示以单位原点为中心
@export var attack_box_offset_y: float = 0.0
## 范围攻击半径（像素，0 表示无范围伤害/单体攻击）
## > 0 时，命中主目标的同时对半径内所有敌方单位造成与主目标同额的伤害（范围输出兵种用）
@export var aoe_radius: float = 0.0

## 该兵种自带的词条列表（攻击命中时施加给目标）
## 例如 N1 持矛勇士带流血词条：攻击时给目标施加流血效果
@export var affixes: Array[AffixResource] = []

## 取指定动画的播放速度倍率（#4）
## anim_name: move / walk / attack / sprint / idle
## 返回值: 倍率，非法值一律回落到 1.0
func get_anim_speed(anim_name: String) -> float:
	var v: float = 1.0
	match anim_name:
		"move", "walk":
			v = move_anim_speed
		"attack":
			v = attack_anim_speed
		"sprint":
			v = sprint_anim_speed
		"idle":
			v = idle_anim_speed
	return v if v > 0.0 else 1.0

## 设置指定动画的播放速度倍率（#4，控制台调校用）
func set_anim_speed(anim_name: String, value: float) -> void:
	var v: float = value if value > 0.0 else 1.0
	match anim_name:
		"move", "walk":
			move_anim_speed = v
		"attack":
			attack_anim_speed = v
		"sprint":
			sprint_anim_speed = v
		"idle":
			idle_anim_speed = v

## 获取攻击硬后摇时长（秒）
## -1（未显式配置）时跟随兵种类型默认（#需求21 用户拍板强制落地）：近战 0.5s / 中远程 1s
func get_attack_recovery_time() -> float:
	if attack_recovery_time >= 0.0:
		return attack_recovery_time
	return 1.0 if is_ranged else 0.5

## 获取当前语言下的显示名称
func get_display_name() -> String:
	var key = "UNIT_%s_NAME" % unit_id.to_upper()  ## 构造翻译键名（大写）
	var translated = tr(key)  ## 查询翻译文本
	if translated == key:  ## 如果翻译结果等于键名（即未找到翻译）
		return display_name  ## 返回默认显示名称
	return translated  ## 返回翻译后的名称

## 获取当前语言下的描述文本
func get_description() -> String:
	var key = "UNIT_%s_DESC" % unit_id.to_upper()  ## 构造翻译键名（大写）
	var translated = tr(key)  ## 查询翻译文本
	if translated == key:  ## 如果翻译结果等于键名（即未找到翻译）
		return description  ## 返回默认描述文本
	return translated  ## 返回翻译后的描述
