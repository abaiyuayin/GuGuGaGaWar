class_name Unit  ## 定义全局类名 Unit，便于其他脚本引用
extends CharacterBody2D  ## 继承 CharacterBody2D 物理角色节点

## 战场模式多阵营配色：阵营1红 / 2蓝 / 3绿 / 4橙（HUD 阵容按钮、脚下光圈、血条一致）
## 2026-08-18 用户确认：阵营1=红（默认阵营），阵营2=蓝，阵营3=绿，阵营4=橙
static var TEAM_COLORS: Array[Color] = [
	Color("#D93025"),  # 阵营1 红
	Color("#1A73E8"),  # 阵营2 蓝
	Color("#34A853"),  # 阵营3 绿
	Color("#F29900"),  # 阵营4 橙
]
static func team_color(t: int) -> Color:
	if t >= 0 and t < TEAM_COLORS.size():
		return TEAM_COLORS[t]
	return Color("#D93025")
## 单位基础脚本
## 管理单位的属性、状态机、攻击和死亡
## 所有战斗单位都基于此脚本，通过 setup() 方法初始化不同兵种

## 信号：单位死亡时发出
## unit: 死亡的单位自身
## killer_team: 击杀方的阵营编号（0=红方, 1=蓝方）
signal unit_died(unit: Unit, killer_team: int, killer_unit_id: String)  ## 定义单位死亡信号（#13：第三参为击杀者兵种 ID，供剑术大师等成就判定）
## 信号：单位受到伤害时发出
## unit: 受击的单位
## damage: 受到的伤害值
signal unit_damaged(unit: Unit, damage: int)  ## 定义单位受伤信号
## 信号：攻击动画播放到配置的命中帧时发出
## 由 state_attack 接收并在该时机执行实际伤害
signal attack_animation_hit(hit_index: int)  ## 定义攻击动画命中帧信号（hit_index 用于二连击不同伤害类型）

## 兵种资源引用，包含该单位的所有属性数据
var unit_resource: UnitResource  ## 存储兵种资源对象
## 所属阵营编号（0=红方/玩家, 1=蓝方/AI）
var team: int = 0  ## 阵营编号，默认为红方
## 当前生命值（HP）
var current_hp: int  ## 当前 HP 值
## 当前状态机状态实例
var current_state: UnitState  ## 当前所处的状态机状态
## 攻击计时器，用于控制攻击间隔
var attack_timer: float = 0.0  ## 攻击间隔计时器
## 当前攻击目标单位引用
var target: Unit = null  ## 当前攻击目标
## 单位是否已死亡的标志
var is_dead: bool = false  ## 死亡标志位

## 节点引用：血条显示节点
var health_bar: ProgressBar  ## 血条节点引用
## 节点引用：护甲条显示节点（位于血条上方，白灰色）
var armor_bar: ProgressBar  ## 护甲条节点引用
## 当前护甲值（独立护盾血量，受到伤害时先于 HP 扣减）
var current_armor: int = 0  ## 当前护甲值

## ---- 肉鸽文物/军令加成快照（在 setup() 时从 RunModifiers 取一次，之后不再变）----
## 只对玩家方（team==0）的生命/护甲/伤害/移速/攻速生效，敌方走 enemy_* 通道。
## 快照而非每帧查询：单位一旦出场，其数值就固定，避免中途拿到文物导致场上单位数值跳变。
## 本单位的最大生命（已含 unit_hp_pct 加成），非肉鸽模式等于 unit_resource.max_hp
var buff_max_hp: int = 1
## 伤害倍率（全局 unit_damage_pct / 敌方 enemy_damage_pct）
var buff_damage_mult: float = 1.0
## 移动速度倍率
var buff_move_mult: float = 1.0
## 攻击间隔倍率（<1 更快）
var buff_attack_interval_mult: float = 1.0
## 是否按远程通道吃加成（由 attack_range 判定，setup 时确定）
var buff_is_ranged: bool = false
## 节点引用：检测区域（用于发现敌人）
var detection_area: Area2D  ## 检测区域节点引用
## 节点引用：单位主精灵（若启用动画则使用 AnimatedSprite2D）
var unit_sprite: AnimatedSprite2D = null  ## 单位动画精灵引用
## 单位动画状态名称
var current_anim_state: String = "idle"  ## 当前动画状态，默认空闲
## 单位面朝方向，1=向右，-1=向左
var facing_dir: int = 1  ## 朝向，默认向右
## 动画配置：是否存在移动/攻击动画
var has_animations: bool = false  ## 是否有动画的标志
## 动画帧资源
var anim_move_frames: SpriteFrames = null  ## 移动动画帧资源
var anim_attack_frames: SpriteFrames = null  ## 攻击动画帧资源
var anim_attack_frames_alt: SpriteFrames = null  ## 备用攻击动画帧资源（#双攻击：凑企鹅等每周期轮流）
var attack_anim_toggle: bool = false  ## 双攻击动画轮流开关（state_attack 每攻击周期翻转）
## #突进（2026-08-15）：命中帧朝目标突进（unit_resource.attack_dash_px > 0 的兵种，如凑企鹅 Y2）
var _attack_dash_dir: Vector2 = Vector2.ZERO  ## 突进方向（朝目标）
var _attack_dash_time: float = -1.0  ## 突进已进行时间（秒），<0 表示未激活
var _attack_dash_triggered: bool = false  ## #18-2：本攻击周期是否已预触发突进（命中帧前一帧）
var anim_sprint_frames: SpriteFrames = null  ## 冲刺动画帧资源
var anim_idle_frames: SpriteFrames = null  ## 待机动画帧资源
var anim_charge_frames: SpriteFrames = null  ## 出场动画帧资源（charge，蓝女巫等）
var anim_death_frames: SpriteFrames = null  ## 死亡动画帧资源
var anim_skill_frames: SpriteFrames = null  ## 技能动画帧资源（#技能系统：吟唱/蓄力专属动画，null 时回退攻击动画）
## S1 蓝女巫攻击逐帧偏移补偿（#S1attack-drift）
## 切片工具给每帧加了不等边距，角色在 104x46 画布里位置逐帧不同 → 整画布居中后角色漂移。
## 仅在 unit_id=="S1" 的攻击动画上，把每帧角色内容中心钉到画布中心，消除漂移，不动任何图片。
var _s1_attack_offsets: Array[Vector2] = []  ## 每帧「画布中心-内容中心」偏移（纹理像素）
var _s1_attack_compensate: bool = false  ## S1 攻击是否启用补偿
var _frame_signal_connected: bool = false  ## frame_changed 是否已连接
## 攻击动画身体锚点补偿（#G2-offset 2026-08-14）：move 与 attack 画布尺寸/角色居中不一致时，
## 切换动画会让单位整块横移（G2 attack 703x470 角色偏右 ~129px，move 400x400 居中）。
## 计算「攻击首帧角色内容中心」相对「move 首帧角色内容中心」的常量偏移（已折算两套动画缩放比），
## 攻击态施加为 sprite.offset，使攻击第 0 帧身体对齐移动姿态；攻击内前冲/挥砍保留，且不逐帧漂移。
## 角色已居中的兵种（含 S1 现版居中导出）该值≈0，零影响。
var _attack_anchor_offset: Vector2 = Vector2.ZERO  ## 攻击态常量偏移（纹理px，已含缩放比折算；X 受 flip_h 翻转）
## 远程技能自动施放定时器（死亡使者等异象兵种，5秒冷却远程攻击）
var _ranged_skill_timer: Timer = null
## 远程技能冷却中标志
var _ranged_skill_on_cooldown: bool = false
## 攻击动画上一帧索引，用于检测动画循环并允许下一次命中判定
var _prev_attack_frame: int = -1  ## 上一攻击动画帧索引
## 当前攻击动画周期内是否已经触发过命中伤害
var _attack_hit_emitted: bool = false  ## 本周期是否已触发命中标志
## 当前攻击动画周期内是否已经通过帧触发过音效（attack_sound_frame 配置时生效）
var _attack_sound_frame_played: bool = false  ## 本周期是否已通过帧播放音效标志
## 当前攻击周期内已执行的命中次数（用于连击和不同命中的伤害类型）
var _attack_hit_index: int = 0  ## 当前周期已执行命中次数
## 基准动画显示高度（基于 move 动画第一帧高度 × 基础 scale），用于统一各动画显示尺寸
var _base_anim_display_height: float = 0.0  ## 基准动画显示高度
## 精灵显示半宽（move 动画目标宽度的一半），setup 时缓存用于边界钳制扣半宽
## 取 move 宽而非 attack 宽（attack 最大 137px 会导致钳制过保守、切动画抖动）
var _sprite_half_width: float = 12.0  ## 精灵半宽，默认与碰撞半径同量级，setup 后更新
## _finalize_setup 是否已执行（防止 setup 与 _ready 重复调用导致 scale 被重置）
var _setup_finalized: bool = false
## 选中属性面板（被选中时显示在单位身旁，包含名字/血量/护盾/伤害/攻速等属性）
var _info_panel: Panel = null
## 信息面板所在的 CanvasLayer（使面板不受摄像机 zoom 影响，避免文字模糊）
var _info_canvas_layer: CanvasLayer = null
## 属性面板中的动态标签（血量、护盾）
var _info_hp_label: Label = null
var _info_armor_label: Label = null
## 属性面板中的静态属性标签
var _info_static_label: Label = null
## 是否被选中（选中时显示属性面板）
var _is_selected: bool = false
## 血条/护盾数值 Label 引用（用于 zoom 放大同步字号防模糊）
var _hp_value_label: Label = null
var _armor_value_label: Label = null
## 上次应用的相机 zoom（避免每帧重复设置）
var _last_hp_label_zoom: float = -1.0
## 基础动画缩放比例
const ANIM_BASE_SCALE: float = 0.05  ## 基础动画缩放（调小一半）
## 统一显示高度（像素），所有兵种（动画/静态精灵）都按此高度缩放
const UNIFIED_DISPLAY_HEIGHT: float = 40.0  ## 统一显示高度

## 动画资源路径
const ANIM_ROOT_DIR := "res://resources/units"  ## 动画资源根目录
const ANIM_MOVE_FILE := "move_frames.tres"  ## 移动动画帧文件名
const ANIM_ATTACK_FILE := "attack_frames.tres"  ## 攻击动画帧文件名
const ANIM_SPRINT_FILE := "sprint_frames.tres"  ## 冲刺动画帧文件名
const ANIM_IDLE_FILE := "idle_frames.tres"  ## 待机动画帧文件名
const ANIM_CHARGE_FILE := "charge_frames.tres"  ## 出场动画帧文件名（蓝女巫等特殊兵种）
const ANIM_DEATH_FILE := "death_frames.tres"  ## 死亡动画帧文件名（#9：死亡使者等有独立死亡演出的兵种）
const ANIM_SKILL_FILE := "skill_frames.tres"  ## 技能动画帧文件名（#技能系统：吟唱/蓄力等技能专属动画，缺失则回退攻击动画）

## #技能系统：显式 preload 技能数据表与组件脚本
## 不依赖 class_name 全局类缓存（新脚本需重开编辑器才注册），preload 在任何情况下都能解析
const SKILL_DB := preload("res://scripts/skills/unit_skill_database.gd")
const SKILL_COMPONENT_SCRIPT := preload("res://scripts/skills/unit_skill_component.gd")

## 玩家方单位阵亡时对周围敌人的爆炸半径（军令「断后令」death_explosion_damage 用）
const DEATH_EXPLOSION_RADIUS: float = 120.0

## 友军分离（拥挤规避）：防止单位在密集人堆里互相推挤位移/卡死
## 作用域仅限同阵营、存活、在 SEPARATION_RADIUS 内的友军，越远权重越低
## #BugB：半径略大于碰撞直径（远程碰撞半径≈显示尺寸/6≈20px）才能在物理互撞前先软推开；
## 强度 80≈中速兵 0.8x 移速——保留物理碰撞且无新增绕步时，分离力是唯一散开手段，必须够强
const SEPARATION_RADIUS: float = 40.0  ## 分离感知半径（像素，略大于碰撞直径，柔和防挤）
const SEPARATION_STRENGTH: float = 80.0  ## 分离推力强度（像素/秒）
## 卡住绕步（自动侧向寻路）：前进持续受阻时向侧方绕步，绕开后继续进攻
const STUCK_THRESHOLD: float = 0.35  ## 连续前进受阻超过该秒数判定为卡住
const DODGE_DURATION: float = 0.7  ## 单次绕步持续时间（秒）
const DODGE_FORWARD_FACTOR: float = 0.7  ## 绕步时保留的前进速度比例

## 全局缓存：(unit_id + anim_name) → 帧纹理最大尺寸 Vector2(max_w, max_h)
## 避免每次切动画都重新扫描纹理尺寸，大幅提升性能
static var _anim_content_size_cache: Dictionary = {}

## 调试开关：是否显示红蓝判定框（由 battle_root.gd 的 F3 切换）
## 红框=攻击判定框，蓝框=受击框
static var show_hitboxes: bool = false
## #15：是否显示兵种攻击距离圆圈（由开发工具菜单的「显示兵种攻击距离」切换，默认关闭）
static var show_attack_ranges: bool = false

var state_map: Dictionary = {  ## 状态映射字典
	"idle": preload("res://scenes/units/states/state_idle.gd"),   ## 空闲状态
	"move": preload("res://scenes/units/states/state_move.gd"),   ## 移动状态
	"attack": preload("res://scenes/units/states/state_attack.gd"), ## 攻击状态
	"attack_base": preload("res://scenes/units/states/state_attack_base.gd"), ## 攻击基地状态
	"base_defense": preload("res://scenes/units/states/state_base_defense.gd"), ## 基地防御状态（G5/D3 替代水晶）
	"guard": preload("res://scenes/units/states/state_guard.gd"), ## 守卫状态（肉鸽护晶，#210）
	"stun": preload("res://scenes/units/states/state_stun.gd"), ## 晕眩状态（#需求6：击退累计满 3 层触发）
	"skill": preload("res://scenes/units/states/state_skill.gd"), ## 技能状态（#技能系统：标准模式英雄技能前摇/结算/后摇）
	"die": preload("res://scenes/units/states/state_die.gd")      ## 死亡状态
}
## 待应用的检测掩码（在进入场景树后应用）
var pending_detection_mask: int = -1  ## 待应用的检测掩码

## 是否为基地单位（G5/D3 替代水晶，原地不动防御，HP=BASE_HP，死亡时触发基地摧毁）
var is_base_unit: bool = false  ## 基地单位标志
## 战场模式（RTS 沙盒）玩家指挥字段：
## order_pos：玩家右键下达的移动令目标点（Vector2.INF 表示无移动令）
## hold_position：站定待命——不出移动令时原地站住，不向敌方基地推进
## 两者由 battlefield_mode.gd 写入、state_move 消费；常规模式永不为真，零影响
var order_pos: Vector2 = Vector2.INF  ## 玩家移动令目标（世界坐标）
var hold_position: bool = false  ## 是否站定待命（战场模式专用）
var combat_enabled: bool = true  ## 战场模式：是否允许交战（和平/停战=false → 完全不攻击）
## #竞技场（2026-08-24 需求3）：朝移动令目标推进时的「被卡住计时」，见 state_move._advance_to_order
var _order_stuck_timer: float = 0.0
## AI 禁用标志（用于调试模拟，true 时单位不自动切换状态）
var ai_disabled: bool = false
## 出生阵线 Y 坐标（在 _ready 时记录），单位被碰撞挤压后会缓慢回归这条阵线
var lane_y: float = 0.0  ## 出生阵线 Y
## 肉鸽守卫驻守偏移（像素）：近战单位驻守在水晶正前方的距离
## 在 setup 时随机抽一次并固定，避免所有近战叠在同一个点上（#210）
var guard_front_offset: float = 0.0  ## 近战驻守前压距离

## 卡住绕步状态（单位级，跨状态保持，进入移动/攻击状态时清空）
var _stuck_timer: float = 0.0  ## 连续前进受阻累计时间
var _dodge_timer: float = 0.0  ## 当前绕步剩余时间
var _dodge_dir: float = 0.0  ## 当前绕步方向（±1，沿 Y 轴）
var _dodge_toggle: float = 1.0  ## 绕步方向交替开关（无明确侧向空间时兜底用）

## 活跃词条效果列表（当前施加在该单位上的词条实例）
## 每个元素为字典：{ "affix": AffixResource, "remaining": float(剩余秒), "stacks": int(层数), "source": Unit(施加者) }
var _active_affixes: Array = []
var _dot_timer: float = 0.0  ## 持续伤害每秒结算计时器（跨过 1 秒统一结算一次）

## #6：冰霜词条 — 受击时攻速降低 30%（攻击间隔 × 1/0.7 ≈ ×1.4286）持续 1 秒
## 不可叠加，重复施加刷新计时；死亡时清零
var _frost_timer: float = 0.0  ## 冰霜剩余秒（>0 表示被减速中）

## #技能系统：技能减速（独立于冰霜词条，避免污染现有词条逻辑）
## 与冰霜的区别：冰霜固定 -30% 攻速持续 1s；技能减速的幅度与时长由技能定义给出，
## 且同时作用于「移速」与「攻速」。重复施加取「幅度更大者」并刷新计时。
var skill_slow_percent: float = 0.0  ## 技能减速幅度（0.4 = 移速/攻速各 -40%）
var skill_slow_timer: float = 0.0  ## 技能减速剩余秒（>0 表示生效中）

## #技能系统：骑射类技能的「取消攻击后摇」计时（>0 期间攻击后摇为 0）
var skill_no_recovery_timer: float = 0.0

## #技能系统：待释放的技能定义（由 UnitSkillComponent 写入，state_skill 读取后清空）
var pending_skill_def: Dictionary = {}

## #6：侵蚀词条 — 受击时伤害 -10%/层，最多 3 层（共 -30%）
## 持续到兵种死亡（不走 _active_affixes 的计时，独立 stack 计数）
var erosion_stacks: int = 0  ## 当前侵蚀层数（0~3，3 为上限）

## #14 击退状态（由 KNOCKBACK 词条触发，在物理帧末尾叠加位移）
const KNOCKBACK_DURATION: float = 0.12  ## 击退位移的完成时长（秒）
var _knockback_velocity: Vector2 = Vector2.ZERO  ## 击退速度（像素/秒）
var _knockback_timer: float = 0.0  ## 击退剩余时长（秒）

## #需求6 击退累计晕眩：被击退命中时累计晕眩值，满 3 层进入晕眩状态
var stun_timer: float = 0.0  ## 晕眩剩余秒（>0 表示处于晕眩状态，由 state_stun 管理递减）
var stun_stacks: int = 0  ## 当前累计晕眩值（0~2，满 STUN_REQUIRED_STACKS 触发后清零）
var stun_immune_timer: float = 0.0  ## 晕眩免疫剩余秒（晕眩结束后进入，期间击退不累计层数）

## 全局 SpriteFrames 资源缓存：(unit_id + anim_name) → SpriteFrames
## 避免每次出兵都重新 load .tres 文件，大幅减少卡顿
static var _sprite_frames_cache: Dictionary = {}

## 节点就绪时自动调用，初始化节点引用和信号连接
func _ready() -> void:  ## 重写 _ready 生命周期方法
	## 初始化节点引用
	health_bar = get_node_or_null("HealthBar")  ## 获取血条节点
	armor_bar = get_node_or_null("ArmorBar")  ## 获取护甲条节点
	detection_area = get_node_or_null("DetectionArea")  ## 获取检测区域节点
	unit_sprite = get_node_or_null("VisualBox/UnitSprite") as AnimatedSprite2D  ## 获取单位精灵节点
	if unit_sprite != null:  ## 如果精灵节点存在
		has_animations = true  ## 标记有动画

	## 记录出生阵线 Y，后续被碰撞挤压偏离后可缓慢回归，避免长期累积漂出战场
	lane_y = global_position.y  ## 记录出生阵线

	## 应用待设置的检测掩码
	if pending_detection_mask >= 0 and detection_area:  ## 如果有待应用的掩码
		detection_area.collision_mask = pending_detection_mask  ## 应用掩码
		pending_detection_mask = -1  ## 重置待应用掩码

	## 连接检测区域的进入和离开信号
	## 当有单位进入/离开检测范围时触发回调
	if detection_area:  ## 如果检测区域存在
		detection_area.body_entered.connect(_on_detection_body_entered)  ## 连接进入信号
		detection_area.body_exited.connect(_on_detection_body_exited)  ## 连接离开信号

	## 完成初始化
	call_deferred("_finalize_setup")  ## 延迟调用完成初始化方法

## 初始化单位的方法
## 在实例化后调用此方法设置单位的兵种和阵营
## res: 兵种资源对象
## team_id: 阵营编号（0=红方, 1=蓝方）
func setup(res: UnitResource, team_id: int) -> void:  ## 定义初始化单位的方法
	## ── 对象池复用复位（2026-08-18）：新实例这些字段本就是初值，幂等无副作用 ──
	_setup_finalized = false  ## 允许 _finalize_setup 重新执行（血条/精灵/缩放重配）
	is_dead = false  ## 重置死亡标志
	current_state = null  ## 清空状态机，_physics_process 走 _fallback_move 兜底直到状态就绪
	_clear_pool_residue()  ## 清理对象池残留（tween/词条/定时器/可见性）
	## #26：肉鸽模式复制兵种资源并应用控制台覆盖层，只影响肉鸽单位不污染全局 .tres
	if RoguelikeManager.is_active and not is_base_unit and res != null:
		var dup: UnitResource = res.duplicate(true)
		RoguelikeManager.apply_unit_override(dup)
		unit_resource = dup
	else:
		unit_resource = res  ## 保存兵种资源
	team = team_id  ## 保存阵营
	## 先快照肉鸽加成，再据此设置血量/护甲（顺序不能反）
	_snapshot_run_modifiers()  ## 计算本单位的文物/军令加成
	current_hp = buff_max_hp  ## 设置当前 HP 为（含加成的）最大值
	current_armor = RunModifiers.player_armor(res.armor_value) if team == 0 else res.armor_value  ## 设置当前护甲
	is_dead = false  ## 重置死亡标志
	target = null  ## 清空攻击目标
	attack_timer = 0.0  ## 重置攻击计时器
	current_anim_state = "idle"  ## 重置动画状态为空闲
	facing_dir = 1 if team == 0 else -1  ## 根据阵营设置初始朝向
	## 无论 unit_sprite 是否已就绪都先加载动画帧资源
	load_animation_frames()  ## 加载动画帧资源
	if unit_sprite != null:  ## 如果精灵节点存在
		unit_sprite.visible = anim_move_frames != null or anim_attack_frames != null  ## 根据是否有动画帧设置可见性
		## 立即应用朝向翻转，避免出兵瞬间显示反方向再回正
		set_facing_direction(float(facing_dir))
	call_deferred("_finalize_setup")  ## 延迟调用完成初始化方法

	## 远程技能自动施放定时器（异象兵种，如死亡使者5秒冷却）
	if unit_resource != null and unit_resource.ranged_skill_cooldown > 0.0:
		_ranged_skill_timer = Timer.new()
		_ranged_skill_timer.wait_time = unit_resource.ranged_skill_cooldown
		_ranged_skill_timer.one_shot = false
		_ranged_skill_timer.autostart = false
		add_child(_ranged_skill_timer)
		_ranged_skill_timer.timeout.connect(_on_ranged_skill_tick)
		## 5秒后首次触发（必须等加入场景树后才可用 create_timer）
		if is_inside_tree():
			await get_tree().create_timer(unit_resource.ranged_skill_cooldown).timeout
			if is_instance_valid(_ranged_skill_timer):
				_ranged_skill_timer.start()
		else:
			## 尚未挂载到场景树时（如 spawn_unit 先 setup 再 add_child），
			## 用 call_deferred 延迟到首帧后再启动定时器
			_start_ranged_skill_deferred.call_deferred()

	## 设置碰撞层与碰撞掩码
	## #9：近战与中远程分处不同物理层，各自只与「同类」碰撞。
	## 这样一排远程兵不会用身位堵死己方近战的推进路线，近战也不会被敌方远程卡住。
	## 层位：红近战=bit1 / 蓝近战=bit2 / 建筑=bit3 / 投射物=bit4 / 红远程=bit5 / 蓝远程=bit6
	var ranged: bool = unit_resource != null and unit_resource.is_ranged  ## 本单位是否为中远程
	if team == 0:  ## 如果是红方阵营
		collision_layer = Constants.MASK_RED_RANGED if ranged else Constants.MASK_RED_MELEE  ## 红方远程/近战层
		pending_detection_mask = Constants.MASK_DETECT_FOR_RED  ## 检测蓝方近战 + 蓝方远程 + 基地
	else:  ## 否则为蓝方阵营
		collision_layer = Constants.MASK_BLUE_RANGED if ranged else Constants.MASK_BLUE_MELEE  ## 蓝方远程/近战层
		pending_detection_mask = Constants.MASK_DETECT_FOR_BLUE  ## 检测红方近战 + 红方远程 + 基地
	## 物理掩码（#6 2026-08-08：己方兵种之间一律无碰撞体积）：
	## 近战只撞「敌方近战 + 建筑」；远程只撞「敌方远程 + 建筑」——双方掩码都排除本方阵营层，
	## 因此己方近战与中远程互相穿透不堵路（仍由 _compute_ally_separation 柔性散开），
	## 敌我之间保留同类碰撞（近战互砍 / 远程互射的物理手感不变）。
	collision_mask = (
		(Constants.MASK_RANGED_BODY_RED if team == 0 else Constants.MASK_RANGED_BODY_BLUE) if ranged
		else (Constants.MASK_MELEE_BODY_RED if team == 0 else Constants.MASK_MELEE_BODY_BLUE))
	## setup() 常在 add_child（_ready 已跑完）之后调用，此时 pending 掩码不会再被 _ready 消费。
	## 拆层后检测区必须覆盖新增的远程层，否则远程兵互相「看不见」，这里立即落盘。
	if detection_area != null:  ## 检测区已就绪
		detection_area.collision_mask = pending_detection_mask  ## 立即应用检测掩码
		pending_detection_mask = -1  ## 标记已应用，避免 _ready 重复设置

## 快照本单位的肉鸽文物/军令加成（只在 setup 调用一次）
## 玩家方（team==0）吃 player_* 通道，敌方吃 enemy_* 通道；非肉鸽模式全部为中性值。
func _snapshot_run_modifiers() -> void:
	if unit_resource == null:
		return
	buff_is_ranged = RunModifiers.is_ranged_unit(unit_resource.attack_range)
	if team == 0:
		buff_max_hp = maxi(int(round(float(unit_resource.max_hp) * RunModifiers.player_hp_mult())), 1)
		buff_damage_mult = RunModifiers.player_damage_mult()
		buff_move_mult = RunModifiers.player_move_mult()
		buff_attack_interval_mult = RunModifiers.player_attack_interval_mult()
	else:
		buff_max_hp = maxi(unit_resource.max_hp, 1)
		buff_damage_mult = RunModifiers.enemy_damage_mult()
		buff_move_mult = 1.0
		buff_attack_interval_mult = RunModifiers.enemy_attack_interval_mult()

## 本单位的最大生命（含文物加成）。所有血条 / 面板 / 百分比结算都必须走这里，
## 不要再直接读 unit_resource.max_hp —— 那是不含加成的兵种基础值。
func get_max_hp() -> int:
	return maxi(buff_max_hp, 1)

## 本单位的实际移动速度（像素/秒，含文物与军令加成）
func get_move_speed_px() -> float:
	if unit_resource == null:
		return 0.0
	## #技能系统：技能减速期间移速按 (1 - skill_slow_percent) 折算
	var slow_mult: float = (1.0 - skill_slow_percent) if skill_slow_timer > 0.0 else 1.0
	return unit_resource.move_speed * Constants.UNIT_TO_PIXELS * buff_move_mult * maxf(slow_mult, 0.1)

## 把合成后的移动速度限幅到该单位的真实移速上限（方向不变，只削大小）
## 背景：友军分离推力 _compute_ally_separation() 与绕步侧向速度都是「叠加量」，
## 直接与 dir * speed_px 相加会让合速度模长超过 move_speed，
## 表现就是「转弯 / 卡住重新寻路的那一瞬间突然窜一下」。
## 统一走此函数后，任何状态下的移动速度都不会超过兵种设定的移速。
func clamp_move_velocity(v: Vector2, speed_px: float) -> Vector2:
	if speed_px <= 0.0:
		return Vector2.ZERO
	if v.length() > speed_px:
		return v.normalized() * speed_px
	return v

## 本单位的实际攻击周期（秒，含攻速加成；值越小攻击越快）
func get_attack_interval() -> float:
	if unit_resource == null:
		return 1.0
	## #6：冰霜词条期间攻速 -30% → 攻击间隔 × 1/0.7 ≈ ×1.4286（其他加成不变）
	var frost_mult: float = 1.0 / (1.0 - _frost_mult()) if _frost_timer > 0.0 else 1.0
	## #技能系统：技能减速期间攻击间隔同样放大（与冰霜相乘叠加）
	var slow_mult: float = 1.0
	if skill_slow_timer > 0.0 and skill_slow_percent > 0.0:
		slow_mult = 1.0 / maxf(1.0 - skill_slow_percent, 0.1)
	return maxf(unit_resource.attack_speed * buff_attack_interval_mult * frost_mult * slow_mult, 0.05)

## #6：当前冰霜减攻速乘数（基础 0.3；非冰霜期返回 0 表示无效果）
## 单位是「value_percent」：FROST .value_percent=0.3 表示攻速 -30%
func _frost_mult() -> float:
	if _frost_timer <= 0.0:
		return 0.0
	## 取出当前 FROST 词条的 value_percent（取首个匹配；非叠加词条理论上只有一个）
	for entry in _active_affixes:
		var a: AffixResource = entry.get("affix", null)
		if a != null and a.affix_type == AffixResource.AffixType.FROST:
			return a.value_percent
	return 0.0

## 读取动画资源（带缓存，避免每次出兵都 load .tres 导致卡顿）
func load_animation_frames() -> void:  ## 定义加载动画帧的方法
	if unit_resource == null:  ## 如果没有兵种资源
		return  ## 直接返回
	var unit_id: String = unit_resource.unit_id  ## 兵种 ID
	## 从全局缓存加载各动画帧，缓存未命中时才 load .tres 并写入缓存
	anim_move_frames = _load_cached_frames(unit_id, "move")  ## 加载移动动画帧
	anim_attack_frames = _load_cached_frames(unit_id, "attack")  ## 加载攻击动画帧
	## #双攻击（凑企鹅 Y4 等）：attack_alt_frames 指定第二套攻击动画，攻击动画每周期轮流播放
	anim_attack_frames_alt = _load_cached_frames(unit_id, "attack_alt")  ## 加载备用攻击动画帧
	anim_sprint_frames = _load_cached_frames(unit_id, "sprint")  ## 加载冲刺动画帧
	anim_idle_frames = _load_cached_frames(unit_id, "idle")  ## 加载待机动画帧
	anim_charge_frames = _load_cached_frames(unit_id, "charge")  ## 加载出场动画帧
	anim_death_frames = _load_cached_frames(unit_id, "death")  ## 加载死亡动画帧（#9）
	anim_skill_frames = _load_cached_frames(unit_id, "skill")  ## 加载技能动画帧（#技能系统，无此文件则为 null 并回退攻击动画）
	_compute_attack_anchor_offset()  ## 计算攻击态身体锚点常量偏移（解决 move/attack 画布居中不一致导致的横移）
	if unit_sprite:  ## 如果精灵节点存在
		## 有出场动画先播放出场（charge 播完后切 idle 或 move）
		if anim_charge_frames:
			unit_sprite.sprite_frames = anim_charge_frames
			unit_sprite.play("charge")
			unit_sprite.animation_finished.connect(_on_charge_finished, CONNECT_ONE_SHOT)
			_apply_anim_scale(anim_charge_frames, "charge")
			return
		if anim_move_frames:  ## 如果有移动动画帧
			unit_sprite.sprite_frames = anim_move_frames  ## 设置移动动画帧
			unit_sprite.play("move")  ## 播放移动动画
		elif anim_attack_frames:  ## 否则如果有攻击动画帧
			unit_sprite.sprite_frames = anim_attack_frames  ## 设置攻击动画帧
			unit_sprite.play("attack")  ## 播放攻击动画
			_apply_attack_anchor_offset()  ## 攻击态立即定位（偏移≈0 时为安全 no-op）
		else:  ## 否则没有动画帧
			unit_sprite.stop()  ## 停止动画

## S1 攻击逐帧偏移补偿（#S1attack-drift）：切片给每帧加不等边距，角色在 104x46 画布内位置逐帧不同，
## 整画布居中后角色漂移、循环回第 1 帧时瞬跳回 → 用户所述「一帧震往后退」。
## 仅在 unit_id=="S1" 的攻击动画把每帧角色内容中心钉到画布中心（不动任何图片）。其它兵种/动画零影响。
func _compute_s1_attack_offsets() -> void:
	_s1_attack_offsets.clear()
	_s1_attack_compensate = false
	if unit_resource == null or unit_resource.unit_id != "S1":
		return
	if anim_attack_frames == null or anim_attack_frames.get_frame_count("attack") <= 0:
		return
	var n: int = anim_attack_frames.get_frame_count("attack")
	for i in range(n):
		var tex: Texture2D = anim_attack_frames.get_frame_texture("attack", i)
		_s1_attack_offsets.append(_texture_content_center_offset(tex))
	_s1_attack_compensate = (_s1_attack_offsets.size() == n)

## 求单帧纹理「画布中心 - 内容中心」偏移（纹理像素）；无内容时返回零向量
## 同时处理 AtlasTexture：取 region 子图扫描（对 AtlasTexture 直接 get_image() 返回 null，会漏算导致偏移恒为 0）
func _texture_content_center_offset(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var img: Image = null
	if tex is AtlasTexture:
		var atlas: AtlasTexture = tex as AtlasTexture
		if atlas.atlas == null:
			return Vector2.ZERO
		var full_img: Image = atlas.atlas.get_image()
		if full_img == null:
			return Vector2.ZERO
		var region: Rect2 = atlas.region
		img = full_img.get_region(Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)))
	else:
		img = tex.get_image()
	if img == null:
		return Vector2.ZERO
	var w: int = img.get_width()
	var h: int = img.get_height()
	var minx: int = w; var maxx: int = -1; var miny: int = h; var maxy: int = -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.01:
				if x < minx: minx = x
				if x > maxx: maxx = x
				if y < miny: miny = y
				if y > maxy: maxy = y
	if maxx < 0:
		return Vector2.ZERO
	var ccx: float = float(minx + maxx) / 2.0
	var ccy: float = float(miny + maxy) / 2.0
	return Vector2(float(w) / 2.0 - ccx, float(h) / 2.0 - ccy)

## 计算攻击态身体锚点常量偏移（#G2-offset 2026-08-14）
## 取 move 首帧与 attack 首帧的「画布中心-内容中心」偏移，按两套动画缩放比折算，
## 得到攻击态应施加的 sprite.offset（纹理px），使攻击第 0 帧身体对齐移动姿态。
## 角色已居中的兵种该值≈0，零影响；不影响 S1（其现版居中导出）。
func _compute_attack_anchor_offset() -> void:
	_attack_anchor_offset = Vector2.ZERO
	if anim_move_frames == null or anim_attack_frames == null:
		return
	if anim_move_frames.get_frame_count("move") <= 0 or anim_attack_frames.get_frame_count("attack") <= 0:
		return
	var m: Vector2 = _texture_content_center_offset(anim_move_frames.get_frame_texture("move", 0))
	var a: Vector2 = _texture_content_center_offset(anim_attack_frames.get_frame_texture("attack", 0))
	var s_m: float = _compute_anim_scale(anim_move_frames, "move")
	var s_a: float = _compute_anim_scale(anim_attack_frames, "attack")
	if s_a <= 0.0:
		return
	var ratio: float = s_m / s_a  ## move 相对 attack 的缩放比
	_attack_anchor_offset = Vector2(a.x - m.x * ratio, a.y - m.y * ratio)

## #G2-offset（2026-08-14）：攻击态身体锚点常量偏移
## 把攻击首帧角色内容中心对齐到移动首帧，消除 move↔attack 切换时单位整块横移。
## 角色已居中的兵种（含 S1 现版居中导出）_attack_anchor_offset≈0 → 直接清零，零影响。
## X 分量受 flip_h 影响（镜像后偏移方向取反）。常量偏移、不逐帧变化 → 不会像 S1 旧补偿那样漂移。
func _apply_attack_anchor_offset() -> void:
	if unit_sprite == null:
		return
	## #G2-offset（2026-08-14）：攻击态身体锚点常量偏移
	## 把攻击首帧角色内容中心对齐到移动首帧，消除 move↔attack 切换时单位整块横移。
	## 角色已居中的兵种（含 S1 现版居中导出）_attack_anchor_offset≈0 → 直接清零，零影响。
	## X 分量受 flip_h 影响（镜像后偏移方向取反）。常量偏移、不逐帧变化 → 不会像 S1 旧补偿那样漂移。
	if _attack_anchor_offset == Vector2.ZERO:
		unit_sprite.offset = Vector2.ZERO
		return
	var fx: float = -1.0 if unit_sprite.flip_h else 1.0
	unit_sprite.offset = Vector2(_attack_anchor_offset.x * fx, _attack_anchor_offset.y)

## frame_changed 回调：逐帧刷新攻击偏移（S1 旧逐帧补偿未连接信号，此处保留入口）
func _on_sprite_frame_changed() -> void:
	_apply_attack_anchor_offset()

## 从全局缓存加载 SpriteFrames，缓存未命中时 load .tres 并写入缓存
## unit_id: 兵种 ID
## anim_name: 动画名（move/attack/sprint/idle）
## 返回值: SpriteFrames 资源，无则 null
func _load_cached_frames(unit_id: String, anim_name: String) -> SpriteFrames:  ## 定义缓存加载方法
	var cache_key: String = unit_id + "_" + anim_name  ## 缓存键
	if _sprite_frames_cache.has(cache_key):  ## 命中缓存
		return _sprite_frames_cache[cache_key]  ## 直接返回缓存的资源
	## 未命中缓存，加载 .tres 文件
	var file_map: Dictionary = {  ## 动画名到文件名的映射
		"move": ANIM_MOVE_FILE,
		"attack": ANIM_ATTACK_FILE,
		"attack_alt": "",  ## 备用攻击动画：文件名取 unit_resource.attack_alt_frames
		"sprint": ANIM_SPRINT_FILE,
		"idle": ANIM_IDLE_FILE,
		"charge": ANIM_CHARGE_FILE,
		"death": ANIM_DEATH_FILE,
		"skill": ANIM_SKILL_FILE,
	}
	var file_name: String = file_map.get(anim_name, "")  ## 获取文件名
	if anim_name == "attack_alt":
		file_name = unit_resource.attack_alt_frames if unit_resource != null else ""  ## 备用攻击动画文件名来自资源字段
	if file_name.is_empty():  ## 文件名无效
		return null  ## 返回 null
	var path := "%s/%s/%s" % [ANIM_ROOT_DIR, unit_id, file_name]  ## 拼接路径
	if not ResourceLoader.exists(path):  ## 文件不存在
		return null  ## 返回 null
	var frames: SpriteFrames = load(path)  ## 加载资源
	if frames != null:  ## 加载成功
		_sprite_frames_cache[cache_key] = frames  ## 写入缓存
	return frames  ## 返回资源

## charge 出场动画播完后切 idle（无 idle 则切 move）
func _on_charge_finished() -> void:
	if unit_sprite == null:
		return
	if anim_idle_frames:
		unit_sprite.sprite_frames = anim_idle_frames
		unit_sprite.play("idle")
		_apply_anim_scale(anim_idle_frames, "idle")
	elif anim_move_frames:
		unit_sprite.sprite_frames = anim_move_frames
		unit_sprite.play("move")
		_apply_anim_scale(anim_move_frames, "move")

func play_anim(anim_name: String, force: bool = false) -> void:  ## 定义播放动画的方法
	if unit_sprite == null:  ## 如果精灵节点不存在
		return  ## 直接返回
	if anim_name == current_anim_state and not force:  ## 如果动画相同且不强制重播
		return  ## 直接返回
	current_anim_state = anim_name  ## 更新当前动画状态
	if anim_name != "attack":  ## 非攻击：复位偏移，避免 S1 攻击补偿污染其它动画
		unit_sprite.offset = Vector2.ZERO
	match anim_name:  ## 根据动画名称匹配
		"move":  ## 移动动画
			unit_sprite.speed_scale = _get_anim_speed("move")  ## #4：应用该动画自己的播放倍率（同时清掉攻击倍速残留）
			if anim_move_frames:  ## 如果有移动动画帧
				unit_sprite.sprite_frames = anim_move_frames  ## 设置移动动画帧
				_apply_anim_scale(anim_move_frames, "move")  ## 按基准高度统一显示尺寸
				unit_sprite.play("move")  ## 播放移动动画
			else:  ## 否则
				unit_sprite.stop()  ## 停止动画
		"attack":  ## 攻击动画
			## #双攻击（凑企鹅 Y4 等）：attack_anim_toggle 为 true 且存在备用攻击动画时，播备用攻击动画
			var _frames: SpriteFrames = anim_attack_frames_alt if (attack_anim_toggle and anim_attack_frames_alt != null) else anim_attack_frames
			if _frames:  ## 如果有攻击动画帧
				unit_sprite.sprite_frames = _frames  ## 设置攻击动画帧
				_apply_anim_scale(_frames, "attack")  ## 按基准高度统一显示尺寸
				_apply_attack_speed_scale()  ## 应用攻击动画速度
				## 单次攻击不自动循环：彻底消除「多连挥」，攻击时长与攻击周期解耦，
				## 控制台 attack_anim_speed 倍率原样生效（#回归修复 2026-08-15）
				_frames.set_animation_loop("attack", false)
				unit_sprite.play("attack")  ## 播放攻击动画（单次）
				_apply_attack_anchor_offset()  ## 攻击态立即对第 0 帧定位（信号未必在起始帧触发）
			elif anim_move_frames:  ## 否则如果有移动动画帧（远程单位无攻击动画），复用移动动画避免视觉卡死
				unit_sprite.speed_scale = _get_anim_speed("move")  ## #4：按移动动画的倍率播放
				unit_sprite.sprite_frames = anim_move_frames  ## 设置移动动画帧
				_apply_anim_scale(anim_move_frames, "move")  ## 按基准高度统一显示尺寸
				unit_sprite.play("move")  ## 播放移动动画作为攻击姿态
			else:  ## 否则
				unit_sprite.stop()  ## 停止动画
		"idle":  ## 空闲动画
			unit_sprite.speed_scale = _get_anim_speed("idle" if anim_idle_frames else "move")  ## #4：按实际播放的动画取倍率
			if anim_idle_frames:  ## 如果有待机动画帧，优先使用
				unit_sprite.sprite_frames = anim_idle_frames  ## 设置待机动画帧
				_apply_anim_scale(anim_idle_frames, "idle")  ## 按基准高度统一显示尺寸
				unit_sprite.play("idle")  ## 播放待机动画
			elif anim_move_frames:  ## 否则如果有移动动画帧，复用作为空闲动画
				unit_sprite.sprite_frames = anim_move_frames  ## 设置移动动画帧
				_apply_anim_scale(anim_move_frames, "move")  ## 按基准高度统一显示尺寸
				unit_sprite.play("move")  ## 播放移动动画
			elif anim_attack_frames:  ## 否则如果有攻击动画帧
				unit_sprite.sprite_frames = anim_attack_frames  ## 设置攻击动画帧
				_apply_anim_scale(anim_attack_frames, "attack")  ## 按基准高度统一显示尺寸
				unit_sprite.play("attack")  ## 播放攻击动画
				_apply_attack_anchor_offset()  ## 攻击态立即对第 0 帧定位
			else:  ## 否则
				unit_sprite.stop()  ## 停止动画
		"sprint":  ## 冲刺动画
			unit_sprite.speed_scale = _get_anim_speed("sprint" if anim_sprint_frames else "move")  ## #4：按实际播放的动画取倍率
			if anim_sprint_frames:  ## 如果有冲刺动画帧
				unit_sprite.sprite_frames = anim_sprint_frames  ## 设置冲刺动画帧
				_apply_anim_scale(anim_sprint_frames, "sprint")  ## 按基准高度统一显示尺寸
				unit_sprite.play("sprint")  ## 播放冲刺动画
			elif anim_move_frames:  ## 否则回退到移动动画
				unit_sprite.sprite_frames = anim_move_frames  ## 设置移动动画帧
				_apply_anim_scale(anim_move_frames, "move")  ## 按基准高度统一显示尺寸
				unit_sprite.play("move")  ## 播放移动动画
			else:  ## 否则
				unit_sprite.stop()  ## 停止动画
		_:  ## 其他情况
			unit_sprite.stop()  ## 停止动画
	## #Bug5（2026-08-12）：切换动画后必须重新应用翻转——
	## 不同动画有独立的 flip_override（如 N3 attack_flip_override=1），不重新应用会继承上一动画的 flip_h，
	## 导致红方攻击时朝左（倒着攻击）。move→attack 切换时尤其明显。
	_apply_anim_flip()

## 后摇站定动画（2026-08-21 用户拍板）：后摇站定时段（近战范围内站定 / 远程原地不动）按优先级切换：
##   1. 有待机动画 → 播待机
##   2. 无待机动画 → 播奔跑
func play_backswing_stand() -> void:
	if unit_sprite == null:
		return
	if anim_idle_frames != null:
		play_anim("idle")  ## 有待机动画播放待机
		return
	play_anim("move")  ## 无待机动画播放奔跑

## 竞技场站定定格（#竞技场 2026-08-24 用户拍板）
## 和平模式站着不动 / 战争模式无目标站着不动时，一律定格在行走动画第一帧；
## 没有行走动画则定格在攻击动画第一帧。不播待机动画、不循环播放。
func play_arena_stand() -> void:
	if unit_sprite == null:
		return
	var frames: SpriteFrames = anim_move_frames
	var anim_key: String = "move"
	if frames == null:
		frames = anim_attack_frames
		anim_key = "attack"
	if frames == null:
		unit_sprite.stop()
		return
	if current_anim_state == "arena_stand" and unit_sprite.sprite_frames == frames:
		return  ## 已定格，避免每帧重设导致抖动
	current_anim_state = "arena_stand"
	unit_sprite.offset = Vector2.ZERO
	unit_sprite.sprite_frames = frames
	_apply_anim_scale(frames, anim_key)
	unit_sprite.animation = anim_key
	unit_sprite.frame = 0
	unit_sprite.stop()  ## 定格第一帧
	_apply_anim_flip()

## 清空动画缩放缓存（控制台修改显示尺寸后调用，使新尺寸立即生效）
static func clear_anim_scale_cache() -> void:  ## 定义清空缩放缓存的方法
	_anim_content_size_cache.clear()  ## 清空缓存字典

## 清空 SpriteFrames 资源缓存（控制台保存帧图/动画帧后调用，使新帧数据立即生效）
## 帧图调整保存的是新 SpriteFrames 对象并写盘 .tres，但本进程内 ResourceLoader 缓存
## 仍指向旧实例（编辑器同进程运行），不清缓存则战斗中 load 到旧帧 → 调整不生效（#6）
static func clear_sprite_frames_cache() -> void:
	_sprite_frames_cache.clear()

## 预热指定兵种的 SpriteFrames 缓存（2026-08-19 对象池改造）
## 进入局内前把该兵种各动画的 .tres 预先 load 进 _sprite_frames_cache，
## 使首次出兵时 _load_cached_frames 直接命中缓存，消除首次出兵卡顿。
## 与实例方法 _load_cached_frames 共用同一份静态缓存与键格式（unit_id + "_" + anim_name）。
## unit_id: 兵种 ID
## attack_alt_file: 该兵种的备用攻击动画文件名（来自 UnitResource.attack_alt_frames，无则空串）
## 返回值: 本次新加载（未命中缓存）的动画数量，供调用方统计预热进度
static func prewarm_sprite_frames(unit_id: String, attack_alt_file: String = "") -> int:
	var file_map: Dictionary = {
		"move": ANIM_MOVE_FILE,
		"attack": ANIM_ATTACK_FILE,
		"sprint": ANIM_SPRINT_FILE,
		"idle": ANIM_IDLE_FILE,
		"charge": ANIM_CHARGE_FILE,
		"death": ANIM_DEATH_FILE,
	}
	if not attack_alt_file.is_empty():
		file_map["attack_alt"] = attack_alt_file
	var loaded: int = 0
	for anim_name in file_map:
		var cache_key: String = unit_id + "_" + anim_name
		if _sprite_frames_cache.has(cache_key):
			continue
		var file_name: String = file_map[anim_name]
		if file_name.is_empty():
			continue
		var path := "%s/%s/%s" % [ANIM_ROOT_DIR, unit_id, file_name]
		if not ResourceLoader.exists(path):
			continue
		var frames: SpriteFrames = load(path)
		if frames != null:
			_sprite_frames_cache[cache_key] = frames
			loaded += 1
	return loaded

## 根据纹理尺寸，动态计算并设置当前动画的 scale
## 完全复刻控制台（debug_units.gd::_apply_preview_scale）的算法：
##   s = min(目标宽 / 帧纹理宽, 目标高 / 帧纹理高)
## 与控制台用同一缩放基准（整帧纹理尺寸，而非内容边界框），
## 使得在控制台动画调整页调好的每个兵种显示尺寸，在战场上 1:1 还原。
func _apply_anim_scale(frames: SpriteFrames, anim_name: String) -> void:  ## 定义应用动画缩放的方法
	if frames == null or unit_sprite == null:  ## 如果缺少必要资源
		return  ## 直接返回
	var scale_factor: float = _compute_anim_scale(frames, anim_name)  ## 该动画自身的缩放系数
	if scale_factor <= 0.0:  ## 计算失败，回退到基础缩放
		scale_factor = ANIM_BASE_SCALE
	unit_sprite.scale = Vector2(scale_factor, scale_factor)  ## 设置缩放
	## 基地单位额外放大 3 倍（替代水晶的视觉存在感）
	if is_base_unit:
		unit_sprite.scale *= 3.0

## 计算指定动画的缩放系数，与控制台预览完全一致
## 取首帧纹理尺寸，按「目标宽/高」双向约束取较小值，保证画面不超出配置框
## frames: 该动画的 SpriteFrames
## anim_name: 动画名（move/walk/attack/sprint/idle）
## 返回值: 缩放系数（>0），失败返回 0.0
func _compute_anim_scale(frames: SpriteFrames, anim_name: String) -> float:  ## 定义计算单动画缩放的方法
	if frames == null:  ## 无纹理资源
		return 0.0
	## 缓存键：兵种 ID + 动画名，避免每次切动画重复扫描纹理
	var cache_key: String = (unit_resource.unit_id + "_" + anim_name) if unit_resource != null else ""
	if cache_key != "" and _anim_content_size_cache.has(cache_key):
		return float(_anim_content_size_cache[cache_key].x)
	## 动画名兜底：资源里没有同名动画时退化为第一个可用动画
	var ref_anim: String = anim_name if frames.has_animation(anim_name) else (frames.get_animation_names()[0] if frames.get_animation_names().size() > 0 else "")
	if ref_anim == "":  ## 无动画名
		return 0.0
	if frames.get_frame_count(ref_anim) <= 0:  ## 无帧
		return 0.0
	var frame_tex: Texture2D = frames.get_frame_texture(ref_anim, 0)  ## 首帧纹理（与控制台一致）
	if frame_tex == null:  ## 纹理缺失
		return 0.0
	## 与控制台 debug_units.gd::_apply_preview_scale 完全一致：用整帧纹理尺寸（get_width/Height）
	## 计算缩放，使「在控制台动画调整页调好的每个精灵图大小」在战场上 1:1 还原。
	## 刻意不使用 #Bug6 的内容边界框（_get_frame_content_size）：内容框会让「透明边距大小
	## 不一的各兵种」在 minf 约束下缩放差异被放大，反而导致兵种之间显示大小不统一。
	## 控制台预览用纹理尺寸，局内必须同基准才能 1:1 还原用户在控制台看到的效果。
	var fw: float = float(frame_tex.get_width())
	var fh: float = float(frame_tex.get_height())
	if fw <= 0.0 or fh <= 0.0:  ## 无有效尺寸
		return 0.0
	var target_w: float = _get_anim_target_width(anim_name)  ## 该动画的目标显示宽度
	if target_w <= 0.0:
		target_w = UNIFIED_DISPLAY_HEIGHT
	var target_h: float = _get_anim_target_height(anim_name)  ## 该动画的目标显示高度
	if target_h <= 0.0:
		target_h = UNIFIED_DISPLAY_HEIGHT
	var scale_factor: float = minf(target_w / fw, target_h / fh)  ## 宽高双向约束取较小值
	if cache_key != "":  ## 写入缓存
		_anim_content_size_cache[cache_key] = Vector2(scale_factor, scale_factor)
	return scale_factor

## 获取纹理中非透明像素的内容边界框尺寸（宽×高）
## #Bug6：用于替代帧纹理尺寸计算缩放，使角色跨动画视觉大小一致
## tex: 帧纹理
## 返回值: Vector2(内容宽, 内容高)，检测失败返回 Vector2.ZERO
func _get_frame_content_size(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var img: Image = null
	if tex is AtlasTexture:
		## AtlasTexture 取实际 region 内的图像
		var atlas: AtlasTexture = tex as AtlasTexture
		if atlas.atlas == null:
			return Vector2.ZERO
		var full_img: Image = atlas.atlas.get_image()
		if full_img == null:
			return Vector2.ZERO
		var region: Rect2 = atlas.region
		## 取 region 子图用于扫描
		img = full_img.get_region(Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)))
	else:
		img = tex.get_image()
	if img == null:
		return Vector2.ZERO
	var min_x: int = img.get_width()
	var max_x: int = -1
	var min_y: int = img.get_height()
	var max_y: int = -1
	## 扫描非透明像素，找出内容边界框
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel: Color = img.get_pixel(x, y)
			if pixel.a > 0.01:  ## 非透明
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y
	if max_x < 0 or max_y < 0:  ## 全透明
		return Vector2.ZERO
	return Vector2(float(max_x - min_x + 1), float(max_y - min_y + 1))

## 获取指定动画的目标显示高度
## 优先级：动画独立值（move/walk/attack/sprint/idle_display_height） > 兵种通用 display_height > 全局默认
## anim_name: 动画名
## 返回值: 目标显示高度（像素）
func _get_anim_target_height(anim_name: String) -> float:  ## 定义获取动画目标高度的方法
	if unit_resource == null:  ## 无兵种资源
		return UNIFIED_DISPLAY_HEIGHT
	var per_anim: float = 0.0  ## 动画独立高度
	match anim_name:
		"move":
			per_anim = unit_resource.move_display_height
		"walk":
			per_anim = unit_resource.walk_display_height
		"attack":
			per_anim = unit_resource.attack_display_height
		"sprint":
			per_anim = unit_resource.sprint_display_height
		"idle":
			per_anim = unit_resource.idle_display_height
		"charge":
			per_anim = unit_resource.charge_display_height
		"death":
			per_anim = unit_resource.death_display_height
	if per_anim > 0.0:  ## 有动画独立配置
		return per_anim
	return unit_resource.display_height if unit_resource.display_height > 0.0 else UNIFIED_DISPLAY_HEIGHT

## 获取指定动画的目标显示宽度
## 优先级：动画独立值（move/walk/attack/sprint/idle_display_width） > 兵种通用 display_width > 全局默认
## anim_name: 动画名
## 返回值: 目标显示宽度（像素）
func _get_anim_target_width(anim_name: String) -> float:  ## 定义获取动画目标宽度的方法
	if unit_resource == null:  ## 无兵种资源
		return UNIFIED_DISPLAY_HEIGHT
	var per_anim: float = 0.0  ## 动画独立宽度
	match anim_name:
		"move":
			per_anim = unit_resource.move_display_width
		"walk":
			per_anim = unit_resource.walk_display_width
		"attack":
			per_anim = unit_resource.attack_display_width
		"sprint":
			per_anim = unit_resource.sprint_display_width
		"idle":
			per_anim = unit_resource.idle_display_width
		"charge":
			per_anim = unit_resource.charge_display_width
		"death":
			per_anim = unit_resource.death_display_width
	if per_anim > 0.0:  ## 有动画独立配置
		return per_anim
	return unit_resource.display_width if unit_resource.display_width > 0.0 else UNIFIED_DISPLAY_HEIGHT

## 取指定动画在控制台里配置的播放速度倍率（#4）
## 与攻速（attack_speed，攻击间隔秒数）无关，只影响「一次动画播多快」
func _get_anim_speed(anim_name: String) -> float:
	if unit_resource == null:
		return 1.0
	return unit_resource.get_anim_speed(anim_name)

## 应用攻击动画的播放速度（#4）
## - attack_anim_sync_interval = true：动画拉伸到与攻击间隔等长（攻速加成同步影响动画，
##   避免「攻速加成生效但挥砍动画还是原速」的表里不一，B-攻速一致性），再乘控制台倍率
## - false：与攻速彻底解耦，只按控制台配置的 attack_anim_speed 播放
func _apply_attack_speed_scale() -> void:  ## 定义应用攻击速度的方法
	if unit_resource == null or unit_sprite == null:  ## 如果缺少必要资源
		return  ## 直接返回
	var _cur_frames: SpriteFrames = anim_attack_frames_alt if (attack_anim_toggle and anim_attack_frames_alt != null) else anim_attack_frames
	if _cur_frames == null:  ## 当前攻击动画帧缺失
		return  ## 直接返回
	var user_scale: float = _get_anim_speed("attack")  ## 控制台配置的播放倍率
	if not unit_resource.attack_anim_sync_interval:  ## 不跟随攻速：纯播放倍率
		unit_sprite.speed_scale = user_scale
		return
	var frame_count: int = _cur_frames.get_frame_count("attack")  ## 获取攻击动画总帧数
	var anim_speed: float = _cur_frames.get_animation_speed("attack")  ## 获取动画原始 FPS
	var interval: float = get_attack_interval()  ## 实际攻击周期（秒，含加成）
	if frame_count <= 0 or anim_speed <= 0.0 or interval <= 0.0:  ## 如果参数无效
		unit_sprite.speed_scale = user_scale  ## 回落到纯播放倍率
		return  ## 直接返回
	var anim_duration: float = frame_count / anim_speed  ## 计算动画原始时长
	unit_sprite.speed_scale = (anim_duration / interval) * user_scale  ## 拉伸到攻击间隔后再乘播放倍率

func set_facing_direction(direction: float) -> void:  ## 定义设置朝向的方法
	if direction > 0.0:  ## 如果方向为正（向右）
		facing_dir = 1  ## 设置朝向为右
	elif direction < 0.0:  ## 如果方向为负（向左）
		facing_dir = -1  ## 设置朝向为左
	if unit_sprite:  ## 如果精灵节点存在
		## 根据当前播放的动画类型和 default_facing 决定是否翻转
		_apply_anim_flip()

## 带滞回死区的朝向设置（#BugB：杜绝「原地疯狂左右转头」）
## 单位被友军卡死时，按实际位移翻转会让 facing 在 dx 抖动中每帧翻转。
## 本函数按「意图方向」（velocity.x / 目标方向）设朝向，|target_x| < deadband 时保持当前朝向不翻转。
## target_x: 意图方向 X 分量
## deadband: 死区宽度（像素/秒），速度足够且方向明确才翻转
func set_facing_hysteresis(target_x: float, deadband: float) -> void:  ## 定义带滞回的朝向设置方法
	## 复用纯函数（与单元测试同一份实现）
	var want: int = resolve_facing_hysteresis(facing_dir, target_x, deadband)  ## 滞回判定结果
	if want != 0:  ## 需要翻转
		set_facing_direction(float(want))  ## 设置朝向

## 根据当前动画类型应用独立的翻转逻辑
## 每个动画可通过 xxx_flip_override 独立控制翻转（0=跟随 default_facing，1=强制翻转）
func _apply_anim_flip() -> void:
	if unit_sprite == null or unit_resource == null:
		return
	var default_facing: int = unit_resource.default_facing
	## 基础翻转：朝向与默认朝向不一致时翻转
	var base_flip: bool = facing_dir != default_facing
	## 读取当前动画的独立翻转覆盖设置
	var anim_name: String = unit_sprite.animation
	var override: int = 0
	match anim_name:
		"move":
			override = unit_resource.move_flip_override
		"walk":
			override = unit_resource.walk_flip_override
		"attack":
			override = unit_resource.attack_flip_override
		"idle":
			override = unit_resource.idle_flip_override
		"sprint":
			override = unit_resource.sprint_flip_override
		_:
			override = 0
	## override=1 时强制翻转（与基础翻转取反），override=0 时跟随基础翻转
	if override == 1:
		unit_sprite.flip_h = not base_flip
	else:
		unit_sprite.flip_h = base_flip
	## #G2-offset：flip_h 变更后立即刷新攻击态锚点偏移（offset.x 依赖 flip_h 方向），
	## 否则 play_anim 里先设 offset、后应用 flip，攻击首帧偏移方向会短暂错误
	if unit_sprite.animation == "attack":
		_apply_attack_anchor_offset()

## 设置护甲条的灰色样式（背景深灰，填充灰色）
## 护盾条位于血条上方，max_value 统一为 100 让不同护甲值显示不同比例
func _setup_armor_bar_style() -> void:  ## 定义应用护甲条样式的方法
	if armor_bar == null:  ## 如果护甲条节点不存在
		return  ## 直接返回
	var bg_style = StyleBoxFlat.new()  ## 创建背景样式
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)  ## 深灰色半透明背景
	bg_style.corner_radius_top_left = 1  ## 圆角
	bg_style.corner_radius_top_right = 1  ## 圆角
	bg_style.corner_radius_bottom_left = 1  ## 圆角
	bg_style.corner_radius_bottom_right = 1  ## 圆角
	var fill_style = StyleBoxFlat.new()  ## 创建填充样式
	fill_style.bg_color = Color(0.6, 0.6, 0.6, 1.0)  ## 灰色不透明填充
	fill_style.corner_radius_top_left = 1  ## 圆角
	fill_style.corner_radius_top_right = 1  ## 圆角
	fill_style.corner_radius_bottom_left = 1  ## 圆角
	fill_style.corner_radius_bottom_right = 1  ## 圆角
	armor_bar.add_theme_stylebox_override("background", bg_style)  ## 应用背景样式
	armor_bar.add_theme_stylebox_override("fill", fill_style)  ## 应用填充样式

## 设置血条的阵营色样式（背景深灰，红方红填充 / 蓝方蓝填充）
## 血条位于护盾条下方
## #战场模式（2026-08-17 用户拍板全局生效）：纯白填充改为按阵营着色，
## 红方（team=0）#D93025 / 蓝方（team=1）#1A73E8，与 HUD 水晶条配色一致
func _setup_health_bar_style() -> void:  ## 定义应用血条样式的方法
	if health_bar == null:  ## 如果血条节点不存在
		return  ## 直接返回
	var bg_style = StyleBoxFlat.new()  ## 创建背景样式
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)  ## 深灰色半透明背景
	bg_style.corner_radius_top_left = 1  ## 圆角
	bg_style.corner_radius_top_right = 1  ## 圆角
	bg_style.corner_radius_bottom_left = 1  ## 圆角
	bg_style.corner_radius_bottom_right = 1  ## 圆角
	var fill_style = StyleBoxFlat.new()  ## 创建填充样式
	fill_style.bg_color = Unit.team_color(team) if GameManager.is_battlefield_mode else (Color("#D93025") if team == 0 else Color("#1A73E8"))  ## 红方红 / 蓝方蓝
	fill_style.corner_radius_top_left = 1  ## 圆角
	fill_style.corner_radius_top_right = 1  ## 圆角
	fill_style.corner_radius_bottom_left = 1  ## 圆角
	fill_style.corner_radius_bottom_right = 1  ## 圆角
	health_bar.add_theme_stylebox_override("background", bg_style)  ## 应用背景样式
	health_bar.add_theme_stylebox_override("fill", fill_style)  ## 应用填充样式

## #16（2026-08-09 拆分）：血条上居中显示血量数值、护盾条上居中显示护盾数值（两条独立 Label）。
## 显隐由 SettingsManager.show_hp_armor_bar 控制，且支持运行时实时切换（#4：set_hp_armor_value_labels_visible）。
func _setup_hp_bar_value_label() -> void:
	if health_bar == null or health_bar.has_meta("hp_value_label_created"):
		return
	health_bar.set_meta("hp_value_label_created", true)
	## #16：#1（2026-08-09）血条数值 Label 优化：
	## ① 字号 10→8 缩小（避免挤占血条）；
	## ② 字体强制用引擎默认字体（ThemeDB.fallback_font）——全局 gui/theme/custom_font 是书法体
	##   （猫啃忘形圆），小字号下书法体渲染发虚，数字看起来「糊」；系统字体小字号也清晰锐利；
	## ③ 整体 offset 上移 3px，贴合血条上部，不与护盾数值/血条底部重叠。
	var lbl := Label.new()
	lbl.name = "HpValueLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	## 竞技场模式相机可非整数缩放（0.9~4.0），8px 小字号放大后模糊 → 字号提至 12（光栅化更精细）
	lbl.add_theme_font_size_override("font_size", 12 if GameManager.is_battlefield_mode else 8)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible = SettingsManager.show_hp_armor_bar
	health_bar.add_child(lbl)
	## 2026-08-18 修复：add_child 后再设 FULL_RECT + 垂直居中（此前 add_child 前设 anchors 可能不生效），
	## 并保留 1px 上下内缩，使数值严格居中于血条内（不偏上）
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_top = 1
	lbl.offset_bottom = -1
	_hp_value_label = lbl
	## 护盾条独立数值 Label（仅当护盾条节点存在时创建）
	if armor_bar != null:
		var armor_lbl := Label.new()
		armor_lbl.name = "ArmorValueLabel"
		armor_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		armor_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		armor_lbl.add_theme_font_override("font", ThemeDB.fallback_font)
		armor_lbl.add_theme_font_size_override("font_size", 12 if GameManager.is_battlefield_mode else 8)
		armor_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
		armor_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		armor_lbl.add_theme_constant_override("shadow_offset_x", 1)
		armor_lbl.add_theme_constant_override("shadow_offset_y", 1)
		armor_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		armor_lbl.visible = SettingsManager.show_hp_armor_bar
		armor_bar.add_child(armor_lbl)
		## 2026-08-18 修复：add_child 后设 FULL_RECT + 1px 内缩居中
		armor_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		armor_lbl.offset_top = 1
		armor_lbl.offset_bottom = -1
		_armor_value_label = armor_lbl
	## 血条数值变化时自动刷新文本；护甲变化不一定伴随血量变化，受击结算末尾会再补刷一次
	health_bar.value_changed.connect(_update_hp_bar_value_label)
	_update_hp_bar_value_label()

## #16：刷新血条/护盾条居中数值文本（血量归血条、护盾归护盾条），由 value_changed 与受击结算调用
func _update_hp_bar_value_label(_v: float = 0.0) -> void:
	if health_bar == null or not health_bar.has_meta("hp_value_label_created"):
		return
	## 优先用缓存引用；兜底按节点名查找（兼容旧存档场景）
	var lbl: Label = _hp_value_label
	if lbl == null or not is_instance_valid(lbl):
		lbl = health_bar.get_node_or_null("HpValueLabel") as Label
		_hp_value_label = lbl
	if lbl != null:
		lbl.text = "%d/%d" % [current_hp, get_max_hp()]
	var armor_lbl: Label = _armor_value_label
	if armor_lbl == null or not is_instance_valid(armor_lbl):
		armor_lbl = armor_bar.get_node_or_null("ArmorValueLabel") as Label if armor_bar != null else null
		_armor_value_label = armor_lbl
	if armor_lbl != null:
		armor_lbl.text = str(current_armor)

## 2026-08-18：血条/护盾数值 Label 随相机 zoom 同步放大（文字跟随血条变大且保持清晰）
## 原理：zoom 放大时字号同步 ×zoom（光栅化分辨率同步提高 → 不模糊），
## 同时 scale = 1/zoom 抵消节点自身的场景缩放（血条仍在场景空间被相机放大，
## 但文字通过字号放大 + 反向缩放达到「屏幕上同比例变大且 1:1 光栅化」）。
## pivot 居中使缩放围绕文字中心，位置不偏移。
func _update_hp_label_zoom() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var z: float = cam.zoom.x
	if z <= 0.0 or is_equal_approx(z, _last_hp_label_zoom):
		return
	_last_hp_label_zoom = z
	## 基准字号（与 _setup_hp_bar_value_label 创建时一致）
	var base_size: int = 12 if GameManager.is_battlefield_mode else 8
	## 目标屏幕字号 = 基准 × zoom（clamp 防过大过小）
	var target: int = clampi(int(round(base_size * z)), 6, 48)
	for lbl in [_hp_value_label, _armor_value_label]:
		if lbl != null and is_instance_valid(lbl) and lbl.is_inside_tree():
			lbl.add_theme_font_size_override("font_size", target)
			lbl.pivot_offset = lbl.size / 2.0
			lbl.scale = Vector2(1.0 / z, 1.0 / z)

## #1（2026-08-09）：血条/护盾数值 Label 字号固定，不随镜头 zoom 放大（放大遮挡视野）。
## 血条数值 Label 保持创建时的固定字号，由 _setup_hp_bar_value_label 统一设置。

## #4（2026-08-09）：运行时实时切换血条/护盾条数值 Label 显隐（设置面板开关改动后由 battle_root 遍历单位调用）
func set_hp_armor_value_labels_visible(show: bool) -> void:
	if health_bar != null and health_bar.has_meta("hp_value_label_created"):
		var lbl: Label = health_bar.get_node_or_null("HpValueLabel")
		if lbl != null:
			lbl.visible = show
	if armor_bar != null:
		var armor_lbl: Label = armor_bar.get_node_or_null("ArmorValueLabel")
		if armor_lbl != null:
			armor_lbl.visible = show

## 完成初始化（在 _ready 中调用）
func _finalize_setup() -> void:  ## 定义完成初始化的方法
	if not is_node_ready():  ## 如果节点未就绪
		return  ## 直接返回
	if not unit_resource:  ## 如果没有兵种资源
		return  ## 直接返回
	## 防止重复执行：setup() 和 _ready() 都会 call_deferred 本方法，
	## 重复执行会把 scale 重置为 ANIM_BASE_SCALE 后因动画状态未变而无法纠正，导致单位显示极小
	if _setup_finalized:
		return
	_setup_finalized = true
	## 设置视觉框颜色和兵种名字（统一阵营颜色）
	var visual_box = get_node_or_null("VisualBox")  ## 获取视觉框节点
	var unit_sprite_node = get_node_or_null("VisualBox/UnitSprite")  ## 获取精灵节点
	if visual_box:  ## 如果视觉框存在
		if unit_sprite != null and (anim_move_frames != null or anim_attack_frames != null):  ## 如果有动画精灵且有动画帧
			## 保持父节点可见，否则子节点 AnimatedSprite2D 也会被隐藏；
			## 用 color.a = 0 隐藏 ColorRect 占位方块本身。
			visual_box.visible = true  ## 设置视觉框可见
			visual_box.color = Color(visual_box.color.r, visual_box.color.g, visual_box.color.b, 0.0)  ## 设置透明度为 0 隐藏占位方块
			unit_sprite.visible = true  ## 设置精灵可见
			unit_sprite.position = Vector2(20, 20)  ## 设置精灵位置（VisualBox 中心，40×40）
			unit_sprite.centered = true  ## 设置精灵居中
			unit_sprite.offset = Vector2.ZERO  ## 设置偏移为零
			unit_sprite.scale = Vector2(ANIM_BASE_SCALE, ANIM_BASE_SCALE)  ## 设置缩放比例（调大单位体型）
		## #5（2026-08-14）：旧 S1 逐帧偏移补偿已弃用（补偿即漂移源）。现由 _apply_attack_anchor_offset 取而代之：
		## 常量偏移对齐攻击首帧身体到移动姿态，角色居中的兵种（含 S1 现版）偏移≈0、零影响且不漂移。
			## 以 move 动画第一帧高度为基准，记录显示高度，用于统一其他动画的显示尺寸
			if anim_move_frames != null and anim_move_frames.get_frame_count("move") > 0:
				var move_frame_tex = anim_move_frames.get_frame_texture("move", 0)
				if move_frame_tex != null:
					_base_anim_display_height = unit_resource.display_height if (unit_resource != null and unit_resource.display_height > 0.0) else UNIFIED_DISPLAY_HEIGHT
			## #BugA：缓存精灵显示半宽，供 _clamp_to_field 边界钳制扣半宽使用。
			## move 动画目标宽度（40~60px 的一半 = 20~30px），比攻击动画宽（最大 137px）小得多，
			## 避免用攻击宽钳制导致阵线被过度压缩。
			_sprite_half_width = maxf(_get_anim_target_width("move") / 2.0, 12.0)
	## 如果配置了精灵图，则完全使用精灵显示，隐藏方块
		elif unit_resource.sprite_texture and unit_sprite_node:  ## 如果有静态精灵贴图
			visual_box.visible = false  ## 隐藏视觉框
			(unit_sprite_node as Sprite2D).texture = unit_resource.sprite_texture  ## 设置精灵贴图
			if unit_resource.sprite_region.size.x > 0 and unit_resource.sprite_region.size.y > 0:  ## 如果有区域设置
				(unit_sprite_node as Sprite2D).region_enabled = true  ## 启用区域裁剪
				(unit_sprite_node as Sprite2D).region_rect = unit_resource.sprite_region  ## 设置裁剪区域
			## 按 40x40 的区域缩放精灵，保持宽高比
			var tex_size = unit_resource.sprite_texture.get_size()  ## 获取贴图尺寸
			if unit_resource.sprite_region.size.x > 0:  ## 如果有区域设置
				tex_size = unit_resource.sprite_region.size  ## 使用区域尺寸
			if tex_size.x > 0 and tex_size.y > 0:  ## 如果尺寸有效
				var s = UNIFIED_DISPLAY_HEIGHT / tex_size.y  ## 按统一高度缩放
				(unit_sprite_node as Sprite2D).scale = Vector2(s, s)  ## 设置缩放
			## 将精灵居中到 VisualBox 的区域
			(unit_sprite_node as Sprite2D).position = Vector2(20, 20)  ## 设置精灵位置（VisualBox 中心，40×40）
			unit_sprite_node.visible = true  ## 设置精灵可见
	else:  ## 否则无精灵图
		## 无精灵图时隐藏占位方块（保持节点存在，仅设为透明）
		visual_box.visible = true  ## 保持节点可见（子节点需要父节点可见）
		visual_box.color = Color(0.5, 0.5, 0.5, 0.0)  ## 设置透明度为 0 隐藏占位方块
		if unit_sprite_node:  ## 如果有精灵节点
			unit_sprite_node.visible = false  ## 隐藏精灵节点
		## [B#12 修复] 不再显示白色兵种名标签：无精灵图时也保持 NameLabel 隐藏，
		## 避免战斗中镜头居中时一批白色兵种名簇在屏幕中央（视觉噪音/误以为调试残留）
	## 设置血条（纯白色样式，位于护盾条下方）
	if health_bar:  ## 如果血条节点存在
		health_bar.max_value = get_max_hp()  ## 设置血条最大值（含文物加成）
		health_bar.value = current_hp  ## 设置血条当前值
		_setup_health_bar_style()  ## 应用纯白色样式
		_setup_hp_bar_value_label()  ## #16：血条居中数值 Label（开关控制显隐）
	## 设置护甲条（灰色样式，位于血条上方）
	## max_value 统一为 100，让不同护甲值的单位显示不同比例（避免都显示满）
	if armor_bar:  ## 如果护甲条节点存在
		armor_bar.max_value = 100.0  ## 统一上限 100
		armor_bar.value = current_armor  ## 设置护甲条当前值（10/20/30/50 会显示不同比例）
		_setup_armor_bar_style()  ## 应用灰色样式
	## #16 修复：凑企鹅（Y2）血条/护盾整体上移 30px——其攻击/移动动画画布内容偏上（锚点
	## offset.y≈-70），血条（默认 -26px）落在角色身上遮挡本体。仅 Y2 特调，其余兵种不受影响。
	if unit_resource != null and unit_resource.unit_id == "Y2":
		var _hb := get_node_or_null("HealthBar") as Control
		if _hb != null:
			_hb.offset_top -= 30.0
			_hb.offset_bottom -= 30.0
		var _ab := get_node_or_null("ArmorBar") as Control
		if _ab != null:
			_ab.offset_top -= 30.0
			_ab.offset_bottom -= 30.0
	## 设置检测范围：统一走 get_chase_range_px()
	## 常规模式按兵种攻击距离推算（远程 ×1.5，近战保底 DEFAULT_DETECTION_RADIUS）；
	## 肉鸽模式所有兵种共用 RoguelikeManager.chase_range_px（#210：寻敌范围一致）
	if detection_area:  ## 如果检测区域存在
		var shape_node = detection_area.get_node_or_null("DetectionShape")  ## 获取碰撞形状节点
		if shape_node is CollisionShape2D:  ## 如果是碰撞形状节点
			var shape = shape_node.shape  ## 获取形状
			if shape is CircleShape2D:  ## 如果是圆形形状
				shape.radius = get_chase_range_px()  ## 设置圆形半径
	## 立即应用朝向翻转，避免出兵瞬间显示反方向再回正
	## （setup() 在 _ready() 之前调用时 unit_sprite 为 null，set_facing_direction 被跳过）
	if unit_sprite != null:
		set_facing_direction(float(facing_dir))
	## 设置碰撞体为精灵图显示尺寸的 1/3，居中放置
	## 这样每个兵种最多各自 1/3 的身体重叠，避免全部挤在一起
	if not is_base_unit:
		_setup_collision_body()
	## 守卫模式：为本单位抽定一个固定的驻守前压距离，避免所有近战叠在同一个点（#210）
	if is_guard_mode():
		guard_front_offset = randf_range(Constants.GUARD_MELEE_FRONT_MIN, Constants.GUARD_MELEE_FRONT_MAX)
	## 初始进入状态：基地单位进入 base_defense，普通单位进入 move / guard
	## AI 禁用时（调试模拟）进入 idle 状态，不自动移动
	if ai_disabled:
		change_state("idle")
	elif is_base_unit:  ## 如果是基地单位
		change_state("base_defense")  ## 切换到基地防御状态（原地不动）
	else:  ## 普通单位
		change_state(get_idle_state_name())  ## 肉鸽玩家单位进 guard 护晶，其余进 move 推进
	## #技能系统：挂载兵种技能组件（标准模式）
	## 组件内部会查表，无技能的兵种立即自我移除，因此 30+ 普通兵种无额外开销
	_setup_skill_component()

## #技能系统：为拥有技能的兵种挂载技能组件
## 只在非肉鸽模式、非基地单位、且该兵种在 UnitSkillDatabase 中有启用技能时才挂载。
## 技能绑定兵种而非玩家/AI，故红蓝双方同一兵种都会挂载，行为一致。
func _setup_skill_component() -> void:
	if is_base_unit:
		return
	if RoguelikeManager.is_active:
		return  ## 肉鸽模式走 HeroSkillManager 的波次技能，不启用本系统
	if unit_resource == null:
		return
	if not SKILL_DB.has_skill(unit_resource.unit_id):
		return
	if get_node_or_null("UnitSkillComponent") != null:
		return  ## 避免重复挂载
	var comp := Node.new()
	comp.name = "UnitSkillComponent"
	comp.set_script(SKILL_COMPONENT_SCRIPT)
	add_child(comp)

## 设置碰撞体为精灵图显示尺寸的 1/3，居中放置
## 精灵图显示尺寸 = 纹理帧尺寸 × scale，碰撞体直径 = 显示尺寸 / 3
## 碰撞体放在精灵图正中心（即 Unit 节点原点）
func _setup_collision_body() -> void:
	if unit_sprite == null:
		return
	var col = get_node_or_null("CollisionShape2D")
	if col == null:
		return
	## 获取精灵图当前显示尺寸（纹理帧尺寸 × scale）
	## sprite_frames 或 animation 可能为空，用安全方式获取纹理
	var display_size: float = 40.0  ## 默认显示尺寸
	if unit_sprite.sprite_frames != null:
		var anim_name: String = unit_sprite.animation
		if unit_sprite.sprite_frames.has_animation(anim_name) and unit_sprite.sprite_frames.get_frame_count(anim_name) > 0:
			var tex: Texture2D = unit_sprite.sprite_frames.get_frame_texture(anim_name, 0)
			if tex != null:
				var tex_size: Vector2 = tex.get_size()
				display_size = max(tex_size.x, tex_size.y) * unit_sprite.scale.x
	## 碰撞体直径 = 显示尺寸 / 3，半径 = 显示尺寸 / 6
	var collision_radius: float = display_size / 6.0
	## 最小半径限制，防止过小导致无法碰撞
	collision_radius = max(collision_radius, 5.0)
	## 复制 shape 避免影响其他单位（资源共享）
	if col.shape is CircleShape2D:
		var new_shape = (col.shape as CircleShape2D).duplicate()
		new_shape.radius = collision_radius
		col.shape = new_shape
	## 碰撞体居中（Unit 节点原点即为精灵图中心，无需额外偏移）
	col.position = Vector2.ZERO

## 普通帧处理，用于检测攻击动画命中帧
func _process(delta: float) -> void:  ## 重写 _process 方法
	_check_attack_hit_frame()  ## 检查攻击动画命中帧
	## 血条/护盾数值 Label：放大时同步字号 + 反向缩放（文字跟随变大且保持清晰，2026-08-18）
	_update_hp_label_zoom()
	## #1（2026-08-09）：血条/护盾数值 Label 字号固定，不再随镜头 zoom 变化（避免放大遮挡视野）
	## 选中时每帧更新属性面板（血量、护盾动态变化）和位置
	if _is_selected and _info_panel != null:
		_update_info_panel_dynamic()
		_update_info_panel_position()
		## #17：仅当鼠标悬停在单位附近时才显示信息面板（已选中 + 悬停 双条件）
		var _mouse_dist: float = get_global_mouse_position().distance_to(global_position)
		_info_panel.visible = _mouse_dist < 90.0
	## 远程单位每帧请求重绘以显示射程圆圈
	if unit_resource != null and unit_resource.is_ranged:
		queue_redraw()
	## 红蓝判定框开启时每帧重绘，确保判定框始终跟随单位
	## （避免被碰撞挤压或切换状态时，判定框残留在旧位置不更新）
	if show_hitboxes:
		queue_redraw()
	## 更新活跃词条效果（流血扣血、持续时间递减）
	## 战斗结束后冻结（不结算 DoT），避免胜负已分后仍在持续掉血
	if BattleManager.is_battle_active:
		_update_active_affixes(delta)
	## 更新信息面板位置（CanvasLayer 中需手动将世界坐标转换为屏幕坐标）
## #1（2026-08-09）：面板在屏幕上保持固定大小（scale=1、字号/尺寸固定），不随镜头 zoom 缩放
## 红方（team=0）面板显示在单位左侧，蓝方（team=1）显示在单位右侧
func _update_info_panel_position() -> void:
	if _info_panel == null:
		return
	## 获取单位在屏幕上的位置（包含摄像机变换）
	var screen_pos: Vector2 = get_global_transform_with_canvas().origin
	## 固定屏幕大小：不设置 scale（保持 1），字号与尺寸维持 _create_info_panel 的初始值
	_info_panel.scale = Vector2.ONE
	## 根据阵营决定面板水平偏移方向：红方(左)面板在单位左侧，蓝方(右)面板在单位右侧
	var panel_w: float = _info_panel.size.x
	var offset_x: float = 25.0 if team == 1 else -25.0 - panel_w
	var offset_y: float = -90.0
	_info_panel.position = screen_pos + Vector2(offset_x, offset_y)

## 设置选中状态（被镜头锁定选中时调用）
## selected: true=显示属性面板，false=隐藏
func set_selected(selected: bool) -> void:
	_is_selected = selected
	if selected:
		if _info_panel == null:
			_create_info_panel()
		if _info_panel != null:
			## #17：选中后不立即显示面板，可见性由 _process 的鼠标悬停距离检测决定
			_info_panel.visible = false
			_update_info_panel_full()
			## 展开信息面板时播放对应兵种的点击音效
			if unit_resource != null:
				AudioManager.play_unit_click_sound(unit_resource.unit_id)
	else:
		if _info_panel != null:
			_info_panel.visible = false

## 基地单位放大 2 倍（在 _finalize_setup 后调用，避免被覆盖）
## 仅放大精灵，不参与物理碰撞（防止被其他单位推走）
## 隐藏基地单位身上的血条/护甲条（水晶血条由 HUD 顶部显示）
func _apply_base_unit_scale() -> void:
	if not is_base_unit:
		return
	## 只放大精灵，不影响血条/护甲条/信息面板
	if unit_sprite != null:
		unit_sprite.scale *= 3.0
	## 基地单位禁用物理碰撞（collision_layer=0, collision_mask=0）
	## 这样其他单位的 move_and_slide 不会碰到基地单位，也不会推动它
	## 基地单位不需要被碰撞检测（攻击通过 state_attack_base 的距离判定处理）
	collision_layer = 0
	collision_mask = 0
	## 禁用 CollisionShape2D 的物理形状（双重保险，确保不被推动）
	var col = get_node_or_null("CollisionShape2D")
	if col != null:
		col.disabled = true
	## 隐藏基地单位身上的血条和护甲条（水晶血条由 HUD 顶部显示）
	if health_bar != null:
		health_bar.visible = false
	if armor_bar != null:
		armor_bar.visible = false

## 套用肉鸽水晶外观（#209）：红色方块 + 加宽血条 + 禁用物理碰撞
## 必须在 _finalize_setup 之后调用（用 call_deferred），否则 VisualBox 会被 finalize 重置为透明。
## box_size: 方块边长（像素）
## box_color: 方块填充色
func apply_crystal_look(box_size: float, box_color: Color) -> void:
	var half: float = box_size * 0.5
	var visual_box := get_node_or_null("VisualBox") as ColorRect
	if visual_box != null:
		visual_box.visible = true
		## 改为透明底（贴图会覆盖其上，保留 ColorRect 用于碰撞调试可见）
		visual_box.color = Color(1, 1, 1, 0)
		visual_box.offset_left = -half
		visual_box.offset_top = -half
		visual_box.offset_right = half
		visual_box.offset_bottom = half
	## 加载水晶贴图（红方=曲奇饼干，蓝方=橘子）并显示为精灵
	var tex_path: String = "res://assets/crystal_red.png" if team == 0 else "res://assets/crystal_blue.png"
	if ResourceLoader.exists(tex_path):
		var crystal_tex: Texture2D = load(tex_path)
		## 复用或创建一个静态精灵节点显示水晶贴图
		var crystal_sprite := get_node_or_null("CrystalSprite") as Sprite2D
		if crystal_sprite == null:
			crystal_sprite = Sprite2D.new()
			crystal_sprite.name = "CrystalSprite"
			## 挂到 VisualBox 同级（直接挂在 unit 下），确保在 VisualBox 之上
			add_child(crystal_sprite)
		crystal_sprite.texture = crystal_tex
		crystal_sprite.visible = true
		crystal_sprite.centered = true
		## 等比缩放贴图适应 box_size（取较小边避免溢出）
		if crystal_tex != null and crystal_tex.get_width() > 0 and crystal_tex.get_height() > 0:
			var scale_val: float = box_size / maxf(float(crystal_tex.get_width()), float(crystal_tex.get_height()))
			crystal_sprite.scale = Vector2(scale_val, scale_val)
		else:
			crystal_sprite.scale = Vector2(1.0, 1.0)
	else:
		## 贴图不存在时回退到纯色方块
		if visual_box != null:
			visual_box.color = box_color
	## 水晶没有兵种精灵，隐藏避免残留占位
	if unit_sprite != null:
		unit_sprite.visible = false
	## 血条加宽到方块同宽，置于方块正上方（HUD 顶部另有一条总览血条）
	if health_bar != null:
		health_bar.visible = true
		health_bar.max_value = float(get_max_hp())
		health_bar.value = float(current_hp)
		health_bar.offset_left = -half
		health_bar.offset_right = half
		health_bar.offset_top = -half - 14.0
		health_bar.offset_bottom = -half - 6.0
	## 水晶无护甲，隐藏护甲条
	if armor_bar != null:
		armor_bar.visible = false
	## #10（2026-08-08）：修复「远程投射物打不到水晶」。
	## 旧实现碰撞全禁用（layer=0 / mask=0 / shape disabled），弹道（mask 51）物理上永远碰不到水晶，
	## 远程对水晶的伤害路径实际是断的（箭射出去就完事了，水晶不掉血）。
	## 现在给水晶启用一个专属碰撞层（MASK_CRYSTAL=64，第 7 层）：
	##  - collision_layer=64：水晶自己挂在第 7 层，只有掩码含 64 的物体能检测到它；
	##  - collision_mask=0：水晶不主动撞任何东西，兵种（掩码不含 64）照旧穿行、不会挡住推进；
	##  - 只有投射物掩码（MASK_PROJECTILE_HIT | MASK_CRYSTAL）能命中水晶 → 命中后走
	##    projectile._damage_base_via_battlefield → battlefield.damage_base 正常结算。
	collision_layer = Constants.MASK_CRYSTAL
	collision_mask = 0
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		## 碰撞体半径放大到方块半宽（36px），与 72×72 的视觉方块一致，弹道打在方块上即命中
		if col.shape is CircleShape2D:
			var new_shape: CircleShape2D = (col.shape as CircleShape2D).duplicate()
			new_shape.radius = box_size * 0.5
			col.shape = new_shape
		col.disabled = false
	## #1/#2（2026-08-11）：红方水晶曲奇饼干缓慢旋转、蓝方水晶橘子缓慢上下浮动
	## 动画绑定在 CrystalSprite 节点上（apply_crystal_look 中创建的贴图精灵）。
	## 注意 apply_crystal_look 通过 call_deferred 调用，首次调用时节点已在场景树中。
	var crystal_sprite_final := get_node_or_null("CrystalSprite") as Sprite2D
	if crystal_sprite_final != null:
		## #Bug11（2026-08-12）：水晶旋转偶尔停止——两处根因：
		## ① tween_property 用绝对值 TAU 作目标，首圈 0→TAU 正常，后续循环 TAU→TAU 无变化（视觉停止）；
		## ② apply_crystal_look 被多次调用时旧 tween 未杀掉，多个 tween 竞争同属性。
		## 修复：杀掉旧 tween；红方旋转改 as_relative()，每圈 +TAU 实现持续旋转。
		var old_tween: Variant = crystal_sprite_final.get_meta("crystal_tween", null)
		if old_tween is Tween and (old_tween as Tween).is_valid():
			(old_tween as Tween).kill()
		var crystal_tween := create_tween().set_loops()
		crystal_sprite_final.set_meta("crystal_tween", crystal_tween)
		if team == 0:
			## 红方曲奇饼干：缓慢旋转，360°/12 秒（relative 每圈叠加 TAU，永不停止）
			crystal_tween.tween_property(crystal_sprite_final, "rotation", TAU, 12.0) \
				.as_relative() \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		else:
			## 蓝方橘子：垂直浮动，幅度 8px，周期 2 秒（正弦来回）
			crystal_tween.tween_property(crystal_sprite_final, "position:y", -8.0, 1.0) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			crystal_tween.tween_property(crystal_sprite_final, "position:y", 8.0, 1.0) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

## 应用信息面板样式（solid=true 凝实不透明，solid=false 半透明）
func _apply_info_panel_style(solid: bool) -> void:
	if _info_panel == null:
		return
	var style = StyleBoxFlat.new()
	## 凝实状态：深色背景 0.9 透明度；半透明状态：0.35 透明度
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9 if solid else 0.35)
	style.border_color = Color(1, 0.8, 0.2, 1.0 if solid else 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	## 增加左边距，减少右边距（宽度减半后更紧凑）
	style.content_margin_left = 10
	style.content_margin_right = 4
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_info_panel.add_theme_stylebox_override("panel", style)

## 创建属性面板（显示在单位身旁，包含名字/血量/护盾/伤害/攻速等）
## 使用 CanvasLayer 使面板不受摄像机 zoom 影响，避免文字模糊
## 默认半透明，鼠标悬停时凝实（不透明）
func _create_info_panel() -> void:
	if unit_resource == null:
		return
	## 创建独立 CanvasLayer，使面板不受摄像机 zoom 影响
	_info_canvas_layer = CanvasLayer.new()
	_info_canvas_layer.layer = 1  ## 在世界空间之上，HUD 之下不影响交互
	add_child(_info_canvas_layer)
	_info_panel = Panel.new()
	_info_panel.custom_minimum_size = Vector2(110, 210)
	_info_panel.size = Vector2(110, 210)
	## 允许鼠标交互以检测悬停（STOP 拦截事件，但不影响其他控件）
	_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	## 默认半透明状态（凝实状态由悬停切换）
	_apply_info_panel_style(false)
	_info_canvas_layer.add_child(_info_panel)
	## 鼠标悬停时切换为凝实状态
	_info_panel.mouse_entered.connect(func() -> void:
		_apply_info_panel_style(true)
	)
	_info_panel.mouse_exited.connect(func() -> void:
		_apply_info_panel_style(false)
	)
	## 使用 VBoxContainer 自动布局
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	## 设置内容边距：左边留 8px 间距，避免文字紧贴边框；顶部留 22px 给关闭按钮
	vbox.offset_left = 8
	vbox.offset_right = -4
	vbox.offset_top = 22
	vbox.offset_bottom = -4
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER  ## 垂直居中
	_info_panel.add_child(vbox)
	## 右上角关闭按钮
	var btn_close := Button.new()
	btn_close.text = "×"
	btn_close.custom_minimum_size = Vector2(24, 24)
	btn_close.add_theme_font_size_override("font_size", 16)
	btn_close.position = Vector2(_info_panel.size.x - 26, 2)  ## 右上角内缩2px（面板宽100，按钮24）
	btn_close.size = Vector2(24, 24)
	btn_close.tooltip_text = tr("UNIT_INFO_CLOSE")
	btn_close.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_panel.add_child(btn_close)
	## 点击关闭按钮：取消选中并隐藏面板
	btn_close.pressed.connect(func() -> void:
		set_selected(false)
		## 通知战场解除镜头锁定
		var battlefield_node = get_parent().get_parent()
		if battlefield_node and battlefield_node.get_parent() and battlefield_node.get_parent().has_method("_unlock_camera"):
			battlefield_node.get_parent()._unlock_camera()
	)
	## 静态属性标签（名字、伤害、攻速、移速、射程、造价）
	var info_text = tr("UNIT_INFO_STATS") % [
		unit_resource.get_display_name(), unit_resource.damage, unit_resource.attack_speed,
		unit_resource.move_speed, unit_resource.attack_range, unit_resource.cost]
	var static_label = Label.new()
	static_label.text = info_text
	static_label.add_theme_font_size_override("font_size", 12)
	static_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	static_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	static_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(static_label)
	_info_static_label = static_label  ## #2：存引用，zoom 放大时同步字号
	## 动态属性标签：血量、护盾（每帧更新）
	_info_hp_label = Label.new()
	_info_hp_label.text = "HP: %d/%d" % [current_hp, get_max_hp()]
	_info_hp_label.add_theme_font_size_override("font_size", 12)
	_info_hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_info_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_info_hp_label)
	_info_armor_label = Label.new()
	_info_armor_label.text = tr("UNIT_INFO_SHIELD") % [current_armor, unit_resource.armor_value]
	_info_armor_label.add_theme_font_size_override("font_size", 12)
	_info_armor_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_info_armor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_armor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_info_armor_label)

## 完整更新属性面板（选中时立即调用一次）
func _update_info_panel_full() -> void:
	if _info_hp_label != null and unit_resource != null:
		_info_hp_label.text = "HP: %d/%d" % [current_hp, get_max_hp()]
	if _info_armor_label != null and unit_resource != null:
		_info_armor_label.text = tr("UNIT_INFO_SHIELD") % [current_armor, unit_resource.armor_value]

## 动态更新属性面板的血量和护盾（每帧调用）
func _update_info_panel_dynamic() -> void:
	if _info_hp_label != null and unit_resource != null:
		_info_hp_label.text = "HP: %d/%d" % [current_hp, get_max_hp()]
	if _info_armor_label != null and unit_resource != null:
		_info_armor_label.text = tr("UNIT_INFO_SHIELD") % [current_armor, unit_resource.armor_value]

## 绘制攻击范围（红色）：由开发工具「显示兵种攻击距离」开关控制，默认不显示
## - 仅 h（横向）：正前方矩形区域
## - 仅 v（纵向）：身前半圆区域
## - h+v 同时配置：矩形+半圆组合
## - 均未配置：圆形（基于 attack_range）
func _draw() -> void:  ## 重写 _draw 方法
	if unit_resource == null:  ## 缺少资源时直接返回
		return
	if not show_attack_ranges:
		return
	var red_color: Color = Color(1.0, 0.15, 0.15, 0.45)  ## 红色半透明
	var h_px: float = unit_resource.get_attack_range_h_px()
	var v_px: float = unit_resource.get_attack_range_v_px()
	var use_special: bool = h_px > 0.0 or v_px > 0.0
	if use_special:
		var dir: float = float(facing_dir)
		## 横向矩形：正前方，长=h_px，宽=20px
		if h_px > 0.0:
			var rect_w: float = h_px
			var rect_h: float = 20.0
			var rect_x: float = 0.0 if dir > 0 else -rect_w
			var rect := Rect2(rect_x, -rect_h * 0.5, rect_w, rect_h)
			draw_rect(rect, red_color, false, 1.5)
		## 纵向半圆：身前 180°
		if v_px > 0.0:
			var start_angle: float = -PI * 0.5 if dir > 0 else PI * 0.5
			var end_angle: float = PI * 0.5 if dir > 0 else PI * 1.5
			draw_arc(Vector2.ZERO, v_px, start_angle, end_angle, 32, red_color, 1.5)
	else:
		## 默认圆形范围（基于 attack_range）
		var range_px: float = unit_resource.attack_range * Constants.UNIT_TO_PIXELS
		if range_px > 0.0:
			draw_arc(Vector2.ZERO, range_px, 0.0, TAU, 64, red_color, 1.0)
	## 调试模式：绘制红蓝判定框（F3 开关控制）
	if show_hitboxes:
		## 蓝框：受击框（以单位中心为中心）
		var hitbox_w: float = unit_resource.hitbox_width
		var hitbox_h: float = unit_resource.hitbox_height
		var hitbox_rect := Rect2(-hitbox_w * 0.5, -hitbox_h * 0.5, hitbox_w, hitbox_h)
		draw_rect(hitbox_rect, Color(0.3, 0.5, 1.0, 0.8), false, 1.5)
		## 红框：攻击判定框（定位由 attack_box_offset_x/y 控制，用户可在调试界面调整）
		## 红框代表单位攻击判定的范围区域，与敌方蓝框（受击框）重叠时判定攻击命中
		## 红框中心位置 = attack_box_offset_x/y，正 X 值=朝面朝方向前方
		var atk_w: float = unit_resource.attack_box_width
		var atk_h: float = unit_resource.attack_box_height
		var atk_offset_x: float = unit_resource.attack_box_offset_x * facing_dir  ## 根据朝向翻转
		var atk_offset_y: float = unit_resource.attack_box_offset_y
		var atk_rect := Rect2(atk_offset_x - atk_w * 0.5, atk_offset_y - atk_h * 0.5, atk_w, atk_h)
		draw_rect(atk_rect, Color(1.0, 0.2, 0.2, 0.8), false, 1.5)

## 检测攻击动画是否到达配置的命中帧，到达则发出 attack_animation_hit 信号
## 支持两种模式：
##   1. 多段连击模式（attack_hit_frames 非空）：每帧检查是否到达某次连击的判定帧
##   2. 单帧命中模式（attack_hit_frame_start >= 0）：动画到达指定帧时触发一次伤害
## 同时检测 attack_sound_frame（帧音效触发，优先于 state_attack 的时间比例音效）
func _check_attack_hit_frame() -> void:  ## 定义检查命中帧的方法
	if unit_sprite == null or unit_resource == null:  ## 如果缺少必要资源
		return  ## 直接返回
	## AI 禁用时不检查命中帧（用于调试模拟，停止按钮后不再触发攻击命中）
	if ai_disabled:
		return
	## 任何命中帧机制都仅在攻击动画中生效
	if current_anim_state != "attack":  ## 离开攻击动画即重置命中/音效标志
		_prev_attack_frame = -1  ## 重置上一帧索引
		_attack_hit_emitted = false  ## 重置命中标志
		_attack_sound_frame_played = false  ## 重置帧音效标志
		_attack_hit_index = 0  ## 重置连击命中索引
		_attack_dash_triggered = false  ## #18-2：离开攻击态重置突进预触发标志（新周期重新预触发）
		return  ## 直接返回
	## 判断使用哪种命中模式
	var using_alt: bool = anim_attack_frames_alt != null and unit_sprite.sprite_frames == anim_attack_frames_alt  ## 当前播放的是否备用攻击动画
	var has_multi_hit: bool = not unit_resource.attack_hit_frames.is_empty()
	var has_frame_hit: bool = unit_resource.attack_hit_frame_start >= 0 or (using_alt and unit_resource.attack_hit_frame_start_alt >= 0)
	var has_frame_sound: bool = unit_resource.attack_sound_frame >= 0 or (using_alt and unit_resource.attack_sound_frame_alt >= 0)
	if not has_multi_hit and not has_frame_hit and not has_frame_sound:
		return
	var frame: int = unit_sprite.frame  ## 获取当前动画帧
	## 帧号回退表示动画进入下一个周期（循环 / 被打断重播）
	## 单帧命中标志 _attack_hit_emitted 不在此处重置——它只在「攻击周期边界」
	## （state_attack 周期结束时调用 reset_attack_frame_flags）清零，确保一个攻击周期
	## 内只结算一次单帧命中。旧逻辑在这里重置它，会导致「攻击动画比攻击周期短、周期内
	## 循环多次」的兵种（如 F3/N4）每次循环都重复触发一次伤害 → 实际连击数被动画长度绑架，
	## 与 damage_by_hit 的条数（=1）冲突，DPS 被放大约 3 倍。
	## 多段连击（attack_hit_frames）的 _attack_hit_index 仍随回绕归零，保留其「每循环各段重触发」
	## 的既有行为（#181 G6/N5 不受影响）。
	if frame < _prev_attack_frame:  ## 如果帧号回退（动画循环 / 被打断重播）
		_attack_hit_index = 0  ## 重置连击命中索引（多段兵种保留循环重触发）
		## 攻击音效标志 _attack_sound_frame_played 不在回退时重置：它只在「攻击周期边界」
		## （reset_attack_frame_flags）清，确保一个攻击周期只播一次音效，避免动画循环 /
		## 重播导致音效连播两遍（#3 修复）
	_prev_attack_frame = frame  ## 更新上一帧索引
	## 多段连击命中判定：遍历所有连击判定帧，到达则触发对应索引的命中
	if has_multi_hit:
		var hit_frames: Array = unit_resource.attack_hit_frames
		for i in range(hit_frames.size()):
			var hit_frame: int = int(hit_frames[i])
			## 用 >= 而非 ==：掉帧时动画可能从 9 直接跳到 12，精确相等会整段命中丢失。
			## 配合 _attack_hit_index 递增守卫，每段最多触发一次，不会重复计伤。
			if frame >= hit_frame and _attack_hit_index <= i:
				_attack_hit_index = i + 1  ## 更新已执行命中次数
				attack_animation_hit.emit(i)  ## 发出命中信号，传递连击索引
	## 单帧命中判定：动画播放到指定帧时触发伤害
	elif has_frame_hit and not _attack_hit_emitted:
		## #18-4（2026-08-15）：两套攻击动画（attack1/attack2）判定帧独立。
		## 播放备用动画（attack_alt_frames）时取 attack_hit_frame_start_alt，否则用主动画的
		## attack_hit_frame_start——此前共用一值，改攻击一的判定帧会连攻击二一起改。
		var hit_frame: int = unit_resource.attack_hit_frame_start_alt if (using_alt and unit_resource.attack_hit_frame_start_alt >= 0) else unit_resource.attack_hit_frame_start  ## 命中帧（单帧，按当前动画取）
		## #18-2（2026-08-15）：突进位移在攻击判定帧的前一帧开始（frame >= hit_frame - 1）。
		## 原实现命中帧（frame >= hit_frame）才触发 dash，视觉是「先出伤害、人才飞」；
		## 改为前一帧就启动位移，命中帧正好冲到敌人面前（突进攻击的打击感）。
		## _attack_dash_triggered 防重：本周期只预触发一次；掉帧跳过 27 直达 28 时，命中帧兜底触发。
		## 仅 attack_dash_px > 0 的兵种生效（Y2），其它兵种短路无影响。
		if not _attack_dash_triggered and frame >= hit_frame - 1 and unit_resource.attack_dash_px > 0.0:
			_attack_dash_triggered = true  ## 标记已预触发（防重）
			start_attack_dash()  ## 提前一帧启动突进（命中帧前的位移）
		## #12（2026-08-15）：用 >= 而非 ==（与多段连击判定一致）——掉帧/动画跳帧时帧号可能
		## 从 13 直接跳到 15，精确相等会整帧错过命中 → hit_done 永不满足 → 只能靠攻击周期
		## 兜底结束 → 动画整段（含第二段挥击）播完才进后摇 = 视觉「连打两下」（D3 根因）。
		## _attack_hit_emitted 防止 >= 后每帧重复触发，一个周期仍只结算一次。
		if frame >= hit_frame:  ## 到达命中帧（含跳帧越过）
			_attack_hit_emitted = true  ## 标记已触发命中
			attack_animation_hit.emit(0)  ## 发出命中信号（单帧命中模式：默认第 0 段）
	## 帧音效触发
	## #1 修复（2026-08-14）：一个攻击动画播放周期内只响一次。
	## 旧逻辑依赖攻击「周期边界」复位 _attack_sound_frame_played，而帧音效按动画帧播放——
	## 当攻击动画比攻击周期长、周期结束后动画仍停在音效帧上时，标志被复位 → 立刻又触发 → 连播两遍。
	## 现改为自管理：frame 到达音效帧且未播 → 播放并置位；frame 回绕到音效帧之前（或回到第 0 帧）→ 重新武装，下一轮再播一次。
	if has_frame_sound:
		## #18-4（2026-08-15）：备用攻击动画音效帧独立（attack_sound_frame_alt），
		## 与命中帧同理——两套动画帧数不同，音效帧各自配置。
		var _sf: int = unit_resource.attack_sound_frame_alt if (using_alt and unit_resource.attack_sound_frame_alt >= 0) else unit_resource.attack_sound_frame
		if frame >= _sf and not _attack_sound_frame_played:
			_attack_sound_frame_played = true  ## 标记已播放
			AudioManager.play_attack_sound(unit_resource.unit_id)  ## 播放攻击音效
		elif frame < _sf or frame == 0:
			_attack_sound_frame_played = false  ## 动画回绕/新一轮 → 重新武装（下一轮播一次）

## 重置攻击动画的帧判定与帧音效标志（供 state_attack 在攻击周期结束时调用）
func reset_attack_frame_flags() -> void:  ## 重置帧判定标志
	_attack_hit_emitted = false  ## 重置命中标志
	_attack_dash_triggered = false  ## #18-2：新攻击周期重新预触发突进
	## #1（2026-08-14）：不再复位 _attack_sound_frame_played。帧音效改由 _check_attack_hit_frame
	## 按「frame 回绕到音效帧之前/回到第 0 帧」自行重新武装，避免攻击周期边界误触发连播两遍。

## 物理帧处理，每帧调用当前状态的 update 方法
## delta: 上一帧到当前帧的时间间隔（秒）
## 远程技能自动施放回调（死亡使者等异象兵种）
## 延迟启动：setup() 被调用时单位可能尚未加入场景树（spawn_unit 先 setup 再 add_child），
## 此时 get_tree()=null 无法 create_timer。此函数由 call_deferred 延迟到首帧执行。
func _start_ranged_skill_deferred() -> void:
	if not is_instance_valid(_ranged_skill_timer):
		return
	if is_inside_tree() and unit_resource != null:
		await get_tree().create_timer(unit_resource.ranged_skill_cooldown).timeout
		if is_instance_valid(_ranged_skill_timer):
			_ranged_skill_timer.start()

## 远程技能自动施放回调（死亡使者等异象兵种）
func _on_ranged_skill_tick() -> void:
	if is_dead or unit_resource == null or unit_resource.ranged_skill_damage <= 0:
		return
	## 找最近敌方单位
	var nearest: Node2D = null
	var nearest_dist: float = unit_resource.ranged_skill_range * 32.0 + 10.0
	var enemies: Array = BattleManager.get_enemy_units(team)
	for e in enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	if nearest == null:
		return  ## 无射程内敌方目标，跳过
	## 播放 sprint 动画（远程技能动画）
	if anim_sprint_frames:
		unit_sprite.sprite_frames = anim_sprint_frames
		unit_sprite.play("sprint")
		_apply_anim_scale(anim_sprint_frames, "sprint")
		## 动画播完后切回 move/idle
		unit_sprite.animation_finished.connect(_on_ranged_anim_finished, CONNECT_ONE_SHOT)
	## 造成远程技能伤害
	var dmg: int = unit_resource.ranged_skill_damage
	if nearest.is_base_unit:
		## 对基地伤害走 damage_base 通道
		var bf: Node = get_parent()
		if bf and bf.has_method("damage_base"):
			bf.damage_base(nearest.team, dmg)
	else:
		nearest.take_damage_typed(dmg, unit_resource.damage_type)
	## 飘字
	_spawn_damage_number(dmg, Constants.DMG_COLOR_MAGIC, "", 0.0)
	print("[Y1] 远程技能发射 → %s，伤害 %d" % ["基地" if nearest.is_base_unit else nearest.unit_resource.unit_id if nearest.unit_resource else "?", dmg])

## 远程技能动画播完切回当前动画
func _on_ranged_anim_finished() -> void:
	if is_dead or unit_sprite == null:
		return
	if anim_move_frames:
		unit_sprite.sprite_frames = anim_move_frames
		unit_sprite.play("move")
		_apply_anim_scale(anim_move_frames, "move")
	elif anim_idle_frames:
		unit_sprite.sprite_frames = anim_idle_frames
		unit_sprite.play("idle")
		_apply_anim_scale(anim_idle_frames, "idle")

func _physics_process(delta: float) -> void:  ## 重写 _physics_process 方法
	## 如果单位已死亡，停止处理
	if is_dead:  ## 如果单位已死亡
		return  ## 直接返回
	## 战斗已结束（胜负已分）时冻结所有单位，停止一切移动与攻击
	if not BattleManager.is_battle_active:
		return
	## #索敌卡顿（2026-08-20）：索敌节流计时器改为在此处每帧推进且仅推进一次。
	## 旧实现把 `+= delta` 写在 _pathfind_ready() 内，而该函数同一帧会被多个调用点各调一次，
	## 计时器实际按「调用次数」而非「时间」走，且先调用者会消费掉放行配额。
	## 放到这里后节流窗口才真正等于 PATHFIND_INTERVAL 秒，与调用次数/顺序完全无关。
	_pathfind_accum += delta
	## 如果当前状态有效，调用当前状态的每帧更新
	if current_state:  ## 如果当前状态有效
		current_state.update(delta)  ## 调用状态的更新方法
	else:  ## 否则没有状态
		## 备用：如果没有状态，直接朝敌方基地移动
		_fallback_move(delta)  ## 调用备用移动方法
	## #需求6 晕眩免疫计时递减（每物理帧；晕眩自身计时由 state_stun 管理递减）
	if stun_immune_timer > 0.0:
		stun_immune_timer = maxf(stun_immune_timer - delta, 0.0)
	## #14 击退位移：在状态机之后叠加，避免与 move_and_slide 抢控制权
	_apply_knockback_step(delta)  ## 消耗本帧的击退位移
	## #突进（2026-08-15）：命中帧朝目标突进位移（攻击周期内 velocity 为零，直接改 position 不冲突）
	_process_attack_dash(delta)
	## #16 修复：突进（dash）期间跳过战场钳制——dash 是强制位移（飞踢穿人），
	## 真实战场的水晶间钳制会把冲过敌方水晶的位移拉回（用户反馈「攻击时被阻挡卡在原地」）。
	## dash 结束（_attack_dash_time 回 -1）后下一帧恢复钳制。
	if _attack_dash_time < 0.0:
		## 状态更新后统一钳制到战场范围内，兜底所有位移来源（碰撞挤压/追击/后退/击退）
		_clamp_to_field()  ## 限制在战场活动范围内

## 纯逻辑：水晶间 X 钳制（#BugA 核心算法，static 供单元测试复用）
## x: 待钳制 X；home_x: 己方水晶 X；enemy_x: 敌方水晶 X；hw: 精灵半宽；team: 0=红 1=蓝
## 红方（team0）从左往右推 → X ∈ [home_x+hw, enemy_x−hw]；蓝方镜像。
## 钳制后单位永远停在两水晶之间（含精灵边缘不越界），不可能被顶到任何水晶后方。
static func clamp_field_x(x: float, home_x: float, enemy_x: float, hw: float, team: int) -> float:  ## 定义水晶间钳制纯函数
	if team == 0:  ## 红方
		return clampf(x, home_x + hw, enemy_x - hw)  ## 区间 [己方+半宽, 敌方−半宽]
	return clampf(x, enemy_x + hw, home_x - hw)  ## 蓝方镜像

## 纯逻辑：单友军的分离推力（#BugB 核心算法，static 供单元测试复用）
## offset: 自身相对友军的偏移向量；d: 距离；radius: 分离半径；strength: 满强度
## 按 (radius−d)/radius 线性分级，越近推得越强；d<=0 或 d>=radius 返回零。
static func compute_separation_push(offset: Vector2, d: float, radius: float, strength: float) -> Vector2:  ## 定义分离推力纯函数
	if d <= 0.0 or d >= radius:  ## 无效距离或超出半径
		return Vector2.ZERO  ## 无推力
	var weight: float = (radius - d) / radius  ## 距离权重（0~1）
	return offset.normalized() * weight * strength  ## 方向 × 权重 × 强度

## 纯逻辑：朝向滞回判定（#BugB，static 供单元测试复用）
## current: 当前朝向（1/-1）；target_x: 意图方向 X；deadband: 死区
## 返回 0=保持当前朝向（在死区内或方向未变），1/-1=应翻转到的朝向
static func resolve_facing_hysteresis(current: int, target_x: float, deadband: float) -> int:  ## 定义朝向滞回纯函数
	if absf(target_x) < deadband:  ## 意图方向在死区内（速度太弱或方向不明确）
		return 0  ## 保持
	var want: int = 1 if target_x > 0.0 else -1  ## 期望朝向
	return want if want != current else 0  ## 方向变了才翻转，否则保持

## 将单位限制在战场活动范围内
## 追击（state_attack._move_towards_target）与后退都是直接改 position，不经过碰撞系统；
## 加上 move_and_slide 在密集人堆里的挤压滑移，位移会持续累积并把单位推出屏幕。
## 这里作为唯一兜底，任何位移来源都会在物理帧末被拉回场内。
func _clamp_to_field() -> void:  ## 定义战场边界钳制方法
	if not is_instance_valid(self):  ## 单位可能已被释放（如肉鸽战败清场），直接返回避免 Nil 访问
		return  ## 直接返回
	if is_base_unit:  ## 基地单位（水晶）位置固定，不参与钳制
		return  ## 直接返回
	## 基础兜底：FIELD 边界（防止极端异常位移直接飞出战场）
	global_position.x = clampf(global_position.x, Constants.FIELD_X_MIN, Constants.FIELD_X_MAX)  ## 钳制 X
	global_position.y = clampf(global_position.y, Constants.FIELD_Y_MIN, Constants.FIELD_Y_MAX)  ## 钳制 Y
	## #BugA：水晶间钳制 + 扣精灵半宽（仅敌方有基地时生效）。
	## 旧实现只封「不越过敌方水晶」，己方水晶背后留了 24px 漏网（FIELD ±600 vs 水晶 ±576），
	## 单位被敌方近战顶推 / 远程后撤时会滑到己方水晶后方，视觉上像被挤出地图。
	## 新逻辑：X 限制在 [己方水晶+半宽, 敌方水晶−半宽] 区间，单位到不了任何水晶后方。
	## 肉鸽无敌方基地（has_base(1)=false）时不额外钳制，只保留 FIELD ±600 兜底——
	## 红方守卫的驻守锚点在水晶后方（_guard_anchor 可到 -440），加下限会把守卫卡死在水晶前方原地打转。
	var unit_container: Node = get_parent()  ## 单位容器节点
	var battlefield: Node = unit_container.get_parent() if unit_container != null else null  ## 战场节点
	if battlefield != null and battlefield.has_method("has_base") and battlefield.has_method("get_base_position") \
			and battlefield.has_base(1 - team):  ## 敌方有基地才做水晶间钳制
		var home_x: float = battlefield.get_base_position(team).x  ## 己方水晶 X
		var enemy_x: float = battlefield.get_base_position(1 - team).x  ## 敌方水晶 X
		## 复用纯函数（与单元测试同一份实现）
		global_position.x = clamp_field_x(global_position.x, home_x, enemy_x, _sprite_half_width, team)  ## 水晶间钳制

func _fallback_move(delta: float) -> void:  ## 定义备用移动方法
	if unit_resource == null:  ## 如果没有兵种资源
		return  ## 直接返回
	var direction: float = 1.0 if team == 0 else -1.0  ## 根据阵营设置移动方向
	var speed_px: float = get_move_speed_px()  ## 计算像素速度（含文物/军令加成）
	position.x += direction * speed_px * delta  ## 更新 X 坐标
	## Y 坐标保持不变，维持各自阵线位置

## 计算来自同阵营友军的柔和分离推力（防止人堆互相挤压位移）
## 仅作用于同阵营、存活、在 SEPARATION_RADIUS 内的单位；越近推力越强
## #BugB：旧实现遍历 detection_area.get_overlapping_bodies()，但 DetectionArea 的 collision_mask
## 只覆盖敌方层（MASK_DETECT_FOR_RED/BLUE），友军永远不会出现在结果里 → 推力恒为 ZERO，是死代码。
## 改为遍历 get_parent()（UnitContainer）兄弟节点——项目既定模式，与 get_children 寻敌一致。
func _compute_ally_separation() -> Vector2:  ## 定义友军分离计算方法
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return Vector2.ZERO  ## 直接返回零向量
	## 分离推力节流（2026-08-18）：与索敌共用 0.1s 窗口，中间帧返回缓存推力。
	## 分离是软性防重叠（物理碰撞仍每帧兜底），0.1s 推力滞后在密集阵型下无感知差异，
	## 但能把「每帧全扫友军 O(N)」降到 10 次/秒，大量单位时显著降 CPU。
	if not _pathfind_ready():
		return _cached_separation  ## 返回缓存推力
	var container: Node = get_parent()  ## 单位容器（同阵营单位互为兄弟节点）
	if container == null:  ## 容器不存在（未入树/已被移除）
		_cached_separation = Vector2.ZERO
		return _cached_separation  ## 直接返回零向量
	var push := Vector2.ZERO  ## 累计推力（带距离权重，未归一化）
	for body in container.get_children():  ## 遍历同容器兄弟节点
		## 跳过自身、非单位、已销毁、已死亡、非同阵营的单位
		if body == self or not (body is Unit) or not is_instance_valid(body) or body.is_dead or body.team != team:  ## 过滤无效/异阵营单位
			continue
		var offset: Vector2 = global_position - body.global_position  ## 自身相对友军的偏移
		var d: float = offset.length()  ## 与友军距离
		## 复用纯函数（与单元测试同一份实现）：按 (R−d)/R 线性分级，越近推得越强
		push += compute_separation_push(offset, d, SEPARATION_RADIUS, 1.0)  ## 单友军推力（强度先归一，末尾统一限幅）
	if push.length() > 0.0:  ## 有推力时归一化并按权重强度限幅（不超单倍强度，防分离力把合速度顶飞）
		## 单侧较远友军（weight 小）→ 推力小；多侧近距围堵 → 封顶 SEPARATION_STRENGTH
		push = push.normalized() * minf(SEPARATION_STRENGTH, push.length() * SEPARATION_STRENGTH)  ## 限幅
	_cached_separation = push  ## 缓存本次推力（节流窗口内复用）
	return push  ## 返回分离推力向量

## 缓慢将单位拉回出生阵线（抵消 move_and_slide 在密集人堆里的 Y 轴挤压漂移）
## delta: 上一帧到当前帧的时间间隔（秒）
func _return_to_lane(delta: float) -> void:  ## 定义阵线回归方法
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return  ## 直接返回
	if is_base_unit:  ## 基地单位位置固定，不参与回归
		return  ## 直接返回
	## #竞技场（2026-08-24）：沙盒是自由摆阵，敌人可能在任意方位。
	## 阵线回归每帧把单位往出生 Y 拉回，会抵消追击的纵向位移 →
	## 表现为「纵向离得远的兵一直贴着自己那条线走，永远追不上敌人」。
	if GameManager.is_battlefield_mode:
		return
	var lane_dy: float = lane_y - global_position.y  ## 与出生阵线的 Y 偏差
	if absf(lane_dy) > 2.0:  ## 偏差超过容差才回拉
		var step_len: float = minf(absf(lane_dy), Constants.LANE_RETURN_SPEED * delta)  ## 本帧回拉步长
		global_position.y += signf(lane_dy) * step_len  ## 缓慢拉回阵线

## 清空卡住绕步状态（进入移动/攻击状态时调用，避免遗留上一状态的绕步）
func _reset_dodge_state() -> void:  ## 定义绕步状态重置方法
	_stuck_timer = 0.0  ## 清空卡住计时
	_dodge_timer = 0.0  ## 清空绕步计时
	_dodge_dir = 0.0  ## 清空绕步方向

## 是否处于「守卫水晶」AI 模式（#210）
## 只有肉鸽模式下的玩家单位才护晶；敌方单位必须保留推进逻辑，否则没人来打水晶。
## 水晶本体（is_base_unit）走 base_defense，不参与守卫调度。
## 返回值: true 表示该单位无目标时应回到 guard 而不是 move
func is_guard_mode() -> bool:  ## 定义守卫模式判定方法
	return RoguelikeManager.is_active and team == 0 and not is_base_unit

## 当前统一寻敌 / 追击半径（像素）
## 肉鸽模式：所有兵种共用 RoguelikeManager.chase_range_px（控制台可调，#210/#212）
## 常规模式：按兵种攻击距离推算，远程 ×1.5，并以 DEFAULT_DETECTION_RADIUS 保底
## 返回值: 检测半径（像素）
func get_chase_range_px() -> float:  ## 定义寻敌半径计算方法
	if RoguelikeManager.is_active:  ## 肉鸽模式统一半径
		return maxf(RoguelikeManager.chase_range_px, 1.0)
	if unit_resource == null:  ## 无资源时兜底
		return Constants.DEFAULT_DETECTION_RADIUS
	var radius: float = unit_resource.attack_range * Constants.UNIT_TO_PIXELS  ## 按攻击距离换算
	if unit_resource.is_ranged:  ## 远程单位提前发现敌人
		radius *= 1.5
	return maxf(radius, Constants.DEFAULT_DETECTION_RADIUS)  ## 近战保底半径

## 追击牵引半径（像素）：守卫单位离己方水晶超过此距离即放弃追击返回驻守
## 返回值: 牵引半径（像素）
func get_chase_leash_px() -> float:  ## 定义追击牵引半径方法
	return maxf(RoguelikeManager.chase_leash_px, get_chase_range_px())

## 无目标时应回到的默认状态名
## 返回值: "guard"（肉鸽护晶）或 "move"（常规推进）
func get_idle_state_name() -> String:  ## 定义默认空闲状态名方法
	return "guard" if is_guard_mode() else "move"

## 切换单位状态
## state_name: 目标状态名称（"idle"/"move"/"guard"/"attack"/"die"）
func change_state(state_name: String) -> void:  ## 定义切换状态的方法
	## 如果当前状态有效，先调用退出方法
	if current_state:  ## 如果当前状态有效
		current_state.exit()  ## 调用退出方法

	## 如果状态映射中有目标状态，创建新状态实例
	if state_map.has(state_name):  ## 如果状态映射中有目标状态
		current_state = state_map[state_name].new(self)  ## 创建新状态实例
		current_state.enter()  ## 调用新状态的进入方法

## 查找最近的敌方单位（索敌统一入口）
## #210：肉鸽模式下索敌被限制在统一寻敌半径 get_chase_range_px() 内 ——
##   「所有兵种的寻敌范围一致，范围内有敌人才追击」这条规则必须在索敌源头生效，
##   否则守卫单位会锁定地图另一头的敌人冲出去、再被牵引半径拉回，来回抖动。
##   常规（战役 / 双人）模式保持原有的全场索敌行为，不受影响。
## 返回值: 最近的敌方单位，如果没有则返回 null
func find_nearest_enemy() -> Unit:  ## 定义查找最近敌人的方法
	return find_nearest_enemy_in_range(get_chase_range_px() if RoguelikeManager.is_active else INF)

## #3：判定目标位置是否在本单位攻击范围内
##   默认（attack_range_h == attack_range_v == 0）使用圆形 distance_to 判定；
##   设置了 attack_range_h 或 attack_range_v 后启用椭圆判定（dx²/h² + dy²/v² ≤ 1）
##   蓝女巫（纵向一条线）：h 小、v 大；大锤手（横向宽范围）：h 大、v 小
##   tolerance_px 由调用方传入（默认 0，攻击状态用 10 滞回带）
func is_target_in_attack_range(target_pos: Vector2, tolerance_px: float = 0.0) -> bool:
	if unit_resource == null:
		return false
	var dx: float = target_pos.x - global_position.x
	var dy: float = target_pos.y - global_position.y
	if unit_resource.use_elliptical_range:
		var h: float = unit_resource.get_attack_range_h_px() + tolerance_px
		var v: float = unit_resource.get_attack_range_v_px() + tolerance_px
		if h <= 0.0 or v <= 0.0:
			return false
		return (dx * dx) / (h * h) + (dy * dy) / (v * v) <= 1.0
	var r: float = unit_resource.attack_range * Constants.UNIT_TO_PIXELS + tolerance_px
	return dx * dx + dy * dy <= r * r

## 判定目标位置是否**超出**攻击范围（is_target_in_attack_range 的取反）
## 供 state_attack 攻击周期结束后的退出判定使用（+10px 滞回容差）
func is_target_out_of_attack_range(target_pos: Vector2, tolerance_px: float = 0.0) -> bool:
	return not is_target_in_attack_range(target_pos, tolerance_px)

## 索敌节流间隔（秒）：奔跑/后摇期间每 0.1s 最多真正扫描一次敌方列表（2026-08-18 用户拍板 0.1s）
const PATHFIND_INTERVAL: float = 0.1
## 索敌节流累计计时器
var _pathfind_accum: float = 0.0
## 索敌节流「本帧结论」缓存（2026-08-20）：记录上次算出放行结论的物理帧序号与结论值。
## 作用是让同一物理帧内的多个调用点（索敌 / 平分锁敌 / 友军分离）共享同一判定，
## 避免先调用者消费掉配额导致后调用者被迫用旧缓存 —— 那正是「进射程前突然卡一下」的根因。
var _pathfind_gate_frame: int = -1
var _pathfind_gate_value: bool = false
## 友军分离推力缓存（节流窗口内复用，2026-08-18）
var _cached_separation: Vector2 = Vector2.ZERO

## 索敌节流判定：物理帧累计达 PATHFIND_INTERVAL 才放行一次真实扫描
## 攻击动画周期（_attack_started 段）不索敌，由 state_attack 不调用本函数保证；
## 这里统一节流，覆盖所有索敌调用点（move / attack 后摇 / 守卫等）。
##
## #索敌卡顿（2026-08-20 用户反馈「远程兵进入射程前几步会突然卡一下」）：
## 旧实现每次调用都 `_pathfind_accum += delta` 并在达标时清零，而本函数在**同一物理帧内
## 会被多个调用点各调一次**（state_move 里 find_best_distributed_target → 未命中则
## find_nearest_enemy → 再 _compute_ally_separation，最多 3 次）。后果有两个：
##   ① 计时器按「调用次数」而非「时间」推进，节流窗口被压缩到不确定的长度；
##   ② 更严重的是**互相抢配额**——先调用者消费掉放行额度并清零，同帧后续调用者必然
##      拿到 false。远程兵接近敌人时正好从「射程外只调 1~2 次」跳变为「射程边缘调 3 次」，
##      分离推力那一路被挤掉配额 → _compute_ally_separation 连续多帧返回旧缓存推力，
##      合速度方向突变，表现就是「进入射程前几步突然卡/顿一下」。
## 修法：计时推进移到 _physics_process 统一做（每帧且仅一帧一次），本函数只做**只读判定**，
## 并用物理帧序号让同一帧内的所有调用者拿到一致答案 —— 谁先调都不再影响别人。
func _pathfind_ready() -> bool:
	var frame: int = Engine.get_physics_frames()
	## 同帧内重复调用：直接复用本帧已算出的结论，不再消费/改写任何计时状态
	if _pathfind_gate_frame == frame:
		return _pathfind_gate_value
	_pathfind_gate_frame = frame
	_pathfind_gate_value = _pathfind_accum >= PATHFIND_INTERVAL
	if _pathfind_gate_value:
		_pathfind_accum = 0.0  ## 本帧放行，重新开始累计（一帧只清零一次）
	return _pathfind_gate_value

## 在指定半径内查找最近的敌方单位
## 直接扫描 UnitContainer 中的所有单位，不依赖 Area2D 物理检测（更可靠）
## 使用 2D 真实距离（等视角多线战场需要考虑 Y 轴）
## max_range_px: 索敌半径上限（像素），传 INF 表示全场索敌
## 返回值: 半径内最近的敌方单位，如果没有则返回 null
## 2026-08-18 性能优化：索敌节流 —— 每 PATHFIND_INTERVAL 秒最多真正扫描一次，
## 节流窗口内返回上次扫描结果（target 缓存），避免大量单位每帧 O(N) 遍历。
func find_nearest_enemy_in_range(max_range_px: float) -> Unit:  ## 定义限定半径索敌的方法
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return null  ## 返回 null
	## 索敌节流：窗口内返回缓存目标（仍有效则用，否则返回 null 让调用方走兜底推进）
	if not _pathfind_ready():
		return target if (target != null and is_instance_valid(target) and not target.is_dead) else null
	## 获取战场节点（单位在 UnitContainer 下，UnitContainer 在 Battlefield 下）
	var unit_container = get_parent()  ## 获取父节点（UnitContainer）
	if unit_container == null:  ## 如果父节点不存在
		return null  ## 返回 null
	var nearest: Unit = null  ## 最近敌方单位
	var nearest_dist: float = INF  ## 最近距离初始为无穷大

	## 遍历 UnitContainer 中的所有单位
	for body in unit_container.get_children():  ## 遍历所有子节点
		## 跳过自身、非单位类型、已销毁、已死亡的单位
		## is_instance_valid 防止访问已 queue_free 的单位导致 previously freed 错误
		if body == self or not (body is Unit) or not is_instance_valid(body) or body.is_dead or body.is_base_unit:  ## 跳过自身、非单位、已销毁、已死亡、基地单位
			continue
		## 跳过同阵营单位
		if body.team == team:  ## 跳过同阵营
			continue
		## 计算 2D 真实距离（等视角战场需要考虑 Y 轴阵线差异）
		var dist = global_position.distance_to(body.global_position)  ## 计算 2D 距离
		if dist > max_range_px:  ## 超出索敌半径（肉鸽统一寻敌范围）
			continue
		## 如果距离更近，更新最近目标
		if dist < nearest_dist:  ## 如果距离更近
			nearest_dist = dist  ## 更新最近距离
			nearest = body  ## 更新最近单位

	return nearest  ## 返回找到的最近敌方单位

## 射程内平分锁敌（#25）
## 远程单位索敌用：统计射程内每个敌人当前被多少己方远程单位锁定（target == 该敌人），
## 选被锁最少的敌人 —— 多个敌人同时入射程时自动分散火力：
##   1 敌人 → 所有远程集火它；2 敌人 → 2:1 分配；3 敌人 → 各打各的（按被锁数最少，平局取最近）
## attack_range_px: 射程上限（像素）
## 返回值: 应锁定的敌方单位，射程内无敌人返回 null
func find_best_distributed_target(attack_range_px: float) -> Unit:  ## 定义射程内平分索敌方法
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return null
	## 索敌节流（2026-08-18）：与 find_nearest_enemy_in_range 共用同一节流窗口，
	## 避免 move 状态内两种索敌在同一物理帧各扫一遍。
	if not _pathfind_ready():
		return target if (target != null and is_instance_valid(target) and not target.is_dead) else null
	## 获取战场节点（单位在 UnitContainer 下）
	var unit_container = get_parent()  ## 获取父节点（UnitContainer）
	if unit_container == null:  ## 如果父节点不存在
		return null
	## 收集射程内的敌方单位
	var in_range: Array[Unit] = []  ## 射程内敌方列表
	for body in unit_container.get_children():  ## 遍历所有子节点
		if body == self or not (body is Unit) or not is_instance_valid(body) or body.is_dead or body.is_base_unit:  ## 跳过自身、非单位、已销毁、已死亡、基地单位
			continue
		if body.team == team:  ## 跳过同阵营
			continue
		if global_position.distance_to(body.global_position) > attack_range_px:  ## 超出射程
			continue
		in_range.append(body)  ## 加入射程内列表
	if in_range.is_empty():  ## 射程内无敌人
		return null  ## 返回 null
	if in_range.size() == 1:  ## 只有一个敌人：所有远程集火它
		return in_range[0]  ## 返回唯一敌人
	## 多个敌人：统计每个敌人被多少己方远程单位锁定，选被锁最少的（平局取最近）
	var best: Unit = null  ## 最优目标
	var best_lock_count: int = 999999  ## 最优目标的被锁数
	var best_dist: float = INF  ## 最优目标的距离
	for enemy in in_range:  ## 遍历射程内每个敌人
		var lock_count: int = 0  ## 该敌人被己方远程锁定的数量
		for ally in unit_container.get_children():  ## 遍历所有单位统计锁定
			if ally == self or not (ally is Unit) or not is_instance_valid(ally) or ally.is_dead:  ## 跳过自身与无效单位
				continue
			if ally.team != team:  ## 跳过敌方
				continue
			if ally.unit_resource == null or not ally.unit_resource.is_ranged:  ## 只统计己方远程单位
				continue
			if ally.target == enemy:  ## 该远程已锁定此敌人
				## #25修复：只统计「真正够得着该敌人」的己方远程（自己射程×32 + 10 内）。
				## 旧逻辑统计所有 target==enemy 的远程——move 状态残留的射程外 target
				## （state_attack 周期结束超射程切回 move 时不清空）与 #19 分配器写入的
				## 幻影 target 都虚增锁定数，让射程内的远程平分失真（10v3 只有部分开火）。
				var ally_effective: float = ally.unit_resource.attack_range * Constants.UNIT_TO_PIXELS + 10.0
				if ally.global_position.distance_to(enemy.global_position) <= ally_effective:
					lock_count += 1  ## 被锁数 +1
		var dist: float = global_position.distance_to(enemy.global_position)  ## 自身到该敌人的距离
		if lock_count < best_lock_count or (lock_count == best_lock_count and dist < best_dist):  ## 被锁更少或同锁更近
			best_lock_count = lock_count  ## 更新最优被锁数
			best_dist = dist  ## 更新最优距离
			best = enemy  ## 更新最优目标
	return best  ## 返回被锁最少（平局最近）的敌人

## 查找距离自身最近的敌方单位的距离（2D）
## 用于远程单位判断是否有敌人过于靠近，需要撤退
## 返回值: 最近敌方单位的 2D 距离，无敌人返回 INF
func get_nearest_enemy_distance() -> float:  ## 定义获取最近敌方距离的方法
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return INF  ## 返回无穷大
	if detection_area == null:  ## 如果检测区域不存在
		return INF  ## 返回无穷大
	var nearest_dist: float = INF  ## 最近距离初始为无穷大
	var bodies = detection_area.get_overlapping_bodies()  ## 获取所有重叠物理体
	for body in bodies:  ## 遍历每个物理体
		## is_instance_valid 防止访问已 queue_free 的单位导致 previously freed 错误
		if body == self or not (body is Unit) or not is_instance_valid(body) or body.is_dead:  ## 跳过自身、非单位、已销毁、已死亡
			continue
		if body.team == team:  ## 跳过同阵营
			continue
		var dist = global_position.distance_to(body.global_position)  ## 计算 2D 距离
		if dist < nearest_dist:  ## 如果距离更近
			nearest_dist = dist  ## 更新最近距离
	return nearest_dist  ## 返回最近敌方距离

## 查找身后（远离敌方基地方向）最近的同阵营友方单位
## 用于远程单位撤退时寻找掩护位置
## 返回值: 身后最近的友方单位，如果没有则返回 null
func find_rear_ally() -> Unit:  ## 定义查找身后友方的方法
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return null  ## 返回 null
	if detection_area == null:  ## 如果检测区域不存在
		return null  ## 返回 null
	## 后退方向：红方后退为向左（-1），蓝方后退为向右（+1）
	var retreat_dir: float = -1.0 if team == 0 else 1.0  ## 计算后退方向
	var nearest: Unit = null  ## 身后最近友方
	var nearest_dist: float = INF  ## 最近距离初始为无穷大
	var bodies = detection_area.get_overlapping_bodies()  ## 获取所有重叠物理体
	for body in bodies:  ## 遍历每个物理体
		## is_instance_valid 防止访问已 queue_free 的单位导致 previously freed 错误
		if body == self or not (body is Unit) or not is_instance_valid(body) or body.is_dead:  ## 跳过自身、非单位、已销毁、已死亡
			continue
		if body.team != team:  ## 跳过敌方
			continue
		## 判断友方是否在身后（X 轴方向符合后退方向）
		var offset_x: float = body.global_position.x - global_position.x  ## 友方相对自身的 X 偏移
		if retreat_dir > 0.0 and offset_x <= 0.0:  ## 蓝方后退向右，友方需在右侧
			continue
		if retreat_dir < 0.0 and offset_x >= 0.0:  ## 红方后退向左，友方需在左侧
			continue
		var dist = global_position.distance_to(body.global_position)  ## 计算 2D 距离
		if dist < nearest_dist:  ## 如果距离更近
			nearest_dist = dist  ## 更新最近距离
			nearest = body  ## 更新最近友方
	return nearest  ## 返回身后最近友方

## 执行攻击的方法
## 对当前目标造成伤害，或在没有目标时攻击基地
## hit_index: 当前攻击周期内的命中索引（0=第一次命中，1=第二次命中...），用于支持二连击不同伤害类型
func perform_attack(hit_index: int = 0) -> void:  ## 定义执行攻击的方法
	## 如果单位已死亡，停止攻击
	if is_dead:  ## 如果单位已死亡
		return  ## 直接返回
	## #13：一次攻击周期开始，重置本次攻击击杀计数（供「大力出奇迹」统计）
	_attack_kill_count = 0

	## 目标已失效（死亡/释放/为空）时的兜底：多段连击远程单位（attack_hit_frames 非空）
	## 朝默认方向空发一枚白球，保证连击段数发满（目标中途死亡不吞后续段）。
	if (target == null or not is_instance_valid(target) or target.is_dead) \
			and unit_resource.is_ranged and not unit_resource.attack_hit_frames.is_empty():
		_spawn_projectile_with_entries(_compute_damage_entries("", hit_index), null)
		return

	## 如果目标有效且存活
	if target != null and is_instance_valid(target) and not target.is_dead:  ## 如果目标有效且存活
		## 计算伤害列表：根据 damage_types 和 damage_by_type 生成 [(type, value), ...]
		## 支持二连击不同类型：若 attack_hit_types 配置了，第 hit_index 次命中只使用对应类型
		var damage_entries: Array = _compute_damage_entries(target.unit_resource.unit_id, hit_index)

		## 远程单位生成投射物（携带伤害列表）
		if unit_resource.is_ranged:  ## 如果是远程单位
			_spawn_projectile_with_entries(damage_entries, target)  ## 生成投射物
			## 远程伤害/范围/词条全部由投射物在 _hit_target 命中时结算（carried_* 已带齐）。
			## 此处必须 return：否则本帧会再走一遍下方的 take_damage_typed/_apply_aoe/apply_affix，
			## 造成「箭还在飞、血已经掉了」且伤害翻倍（#7 远程出伤异常）。
			return
		else:  ## 否则是近战单位
			## #9：近战命中结算时重新校验目标距离。
			## 攻击动画播放期间（前摇→命中帧）目标可能被击退/移出攻击范围，
			## 原实现直接造成伤害 → 表现为「隔空挥砍」。超出范围则本次命中落空。
			## 容差与 state_attack 进入攻击周期的判定一致（attack_range_px + 10.0）。
			var melee_range_px: float = unit_resource.attack_range * Constants.UNIT_TO_PIXELS
			if global_position.distance_to(target.global_position) > melee_range_px + 10.0:
				return  ## 目标已移出攻击范围，本次命中落空（不计 _attacks_done，周期兜底逻辑不受影响）
		## 近战单位直接对目标造成伤害（按伤害类型分别施加）
		for entry in damage_entries:
			target.take_damage_typed(int(entry["value"]), int(entry["type"]), self)
		## 结算后目标可能因致死触发撤退（enemy_retreat_pct）而被 queue_free 释放，
		## 此时 self.target 引用仍非空、但实例已销毁，后续访问其属性会崩。
		## 重新校验一次目标有效性，作为范围伤害与词条结算的前置闸门。
		if is_instance_valid(target) and not target.is_dead:
			## 范围攻击：对主目标周围半径内的敌人造成同额伤害
			_apply_aoe(target.global_position, target, damage_entries)
	## 施加攻击方词条效果给目标（如流血）
	if is_instance_valid(target) and not target.is_dead and not unit_resource.affixes.is_empty():
		for affix in unit_resource.affixes:
			if affix != null and affix.trigger_timing == AffixResource.TriggerTiming.ON_ATTACK:
				target.apply_affix(affix, self)

		## 不在攻击时闪烁精灵，避免攻击动画被打断的视觉错觉
	elif target == null:  ## 如果没有目标
		## 攻击周期内目标已阵亡/离场时不再补刀基地：
		## 否则在中场兵种互殴、目标中途阵亡的瞬间，同一攻击周期仍会触发本帧命中，
		## 把伤害错误结算到敌方水晶（#104）。基地攻击统一由 state_attack_base 状态机处理。
		return

## 范围伤害：对 center 半径 aoe_radius 内的敌方单位（不含主目标）施加与本次攻击同额的伤害
## center: 范围中心（世界坐标，通常为被命中的主目标位置）
## primary: 已被直接伤害的主目标（从范围命中中排除）
## damage_entries: 本次攻击的伤害列表 [{"type": int, "value": int}, ...]
func _apply_aoe(center: Vector2, primary: Unit, damage_entries: Array) -> void:
	if primary == null or not is_instance_valid(primary):  ## 主目标已释放则直接返回（防御性闸门）
		return
	if unit_resource.aoe_radius <= 0.0:  ## 未配置范围攻击则直接返回
		return
	if damage_entries.is_empty():
		return
	## 通过战场查询半径内的敌方单位（get_parent().get_parent() = Battlefield）
	var battlefield = get_parent().get_parent()
	if battlefield == null or not battlefield.has_method("get_units_in_radius"):
		return
	var enemies := battlefield.get_units_in_radius(center, unit_resource.aoe_radius, 1 - team) as Array[Unit]
	for e in enemies:
		if e == primary or not is_instance_valid(e) or e.is_dead:
			continue
		for entry in damage_entries:
			e.take_damage_typed(int(entry["value"]), int(entry["type"]), self)

## 生成远程投射物的方法（私有）
## damage: 投射物造成的伤害值
## target_unit: 投射物的目标单位
func _spawn_projectile(damage: int, target_unit: Unit) -> void:  ## 定义生成投射物的方法
	## 兼容旧接口：将单一伤害转为伤害列表（默认挥砍类型）
	var entries: Array = [{"type": 0, "value": damage}]
	_spawn_projectile_with_entries(entries, target_unit)

## 生成携带伤害列表的投射物
## damage_entries: 伤害列表 [{"type": int, "value": int}, ...]
## target_unit: 目标单位
## 返回生成的投射物实例（供调用方微调 max_distance 等参数），失败时返回 null
func _spawn_projectile_with_entries(damage_entries: Array, target_unit: Unit) -> Node:
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return null
	## 加载投射物场景
	var projectile_scene = load("res://scenes/units/projectile.tscn")
	var projectile = projectile_scene.instantiate()
	## F1 元素使 / Hero3 菲比Hero：投射物为白色发光亮团（直线飞行，取消追踪）
	if unit_resource.unit_id == "F1" or unit_resource.unit_id == "Hero3":
		projectile.is_glow_orb = true
	## 计算总伤害用于投射物显示（setup 仍用总伤害兼容旧逻辑）
	var total_damage: int = 0
	for entry in damage_entries:
		total_damage += int(entry["value"])
	projectile.setup(total_damage, team, target_unit, self)
	## #用户反馈（2026-08-11）：水晶（基地单位）发射的弹道体积 ×2（custom_scale 0.1→0.2）
	projectile.custom_scale = 0.2 if is_base_unit else 0.1
	## 设置飞行物有效距离 = 有效射程（attack_range×32 + 10px 容差），与 state_attack 进入攻击判定口径一致。
	## #用户反馈（2026-08-11）：旧逻辑 ×1.6 余量（PROJECTILE_RANGE_MARGIN）导致飞行物
	## 「飞出攻击距离还在飞」（锁定敌人时更明显）。现在飞过有效射程立即销毁，
	## 目标停在射程边缘 (range, range+10] 内开火时仍可命中，不会半途消失。
	projectile.max_distance = unit_resource.attack_range * Constants.UNIT_TO_PIXELS + 10.0
	## 传递自定义飞行物贴图
	projectile.custom_texture = unit_resource.projectile_texture
	## 传递伤害列表（命中时按类型分别施加）
	projectile.carried_damage_entries = damage_entries
	## 传递词条列表给投射物（命中时施加给目标）
	projectile.carried_affixes = unit_resource.affixes
	## 传递范围攻击半径（>0 时投射物命中后向四周溅射同额伤害）
	projectile.aoe_radius = unit_resource.aoe_radius
	## #15：传递飞行物自旋速度（D5 飞斧翻滚）与贴图朝向补偿（G5 标枪 180°）
	projectile.spin_speed = unit_resource.projectile_spin_speed
	projectile.rotation_offset_deg = unit_resource.projectile_rotation_offset

	## 将投射物添加到战场中
	var battlefield = get_parent()
	if battlefield:
		battlefield.add_child(projectile)
		projectile.global_position = global_position
		## 应用投射物发射位置 Y 轴偏移（如糯糯Hero 骑射从上身弓弦发射，负值上移）
		projectile.global_position.y += unit_resource.projectile_spawn_offset_y
		projectile.init_direction()
		return projectile
	return null

## 计算伤害列表（根据 damage_types 和 damage_by_type 生成）
## 兼容旧数据：若 damage_types 为空，使用 damage_type 和 damage
## target_id: 目标兵种 ID（用于克制关系修正）
## hit_index: 当前命中索引（用于二连击不同类型），-1 或越界时使用 damage_types
## 返回值: [{"type": int, "value": int}, ...]
func _compute_damage_entries(target_id: String, hit_index: int = -1) -> Array:
	var entries: Array = []
	## 每击独立伤害字典（damage_by_hit[hit_index]），可含多个伤害类型（同伤）
	## #用户反馈（2026-08-11）：旧逻辑在 attack_hit_types 非空时只用单一主类型，
	## damage_by_hit 里的多类型字典被丢弃 → 第一个同伤类型不生效（如 F4 {0:80, 3:40} 只打出魔法 40）。
	var per_hit_dmg_dict: Dictionary = {}
	if hit_index >= 0 and hit_index < unit_resource.damage_by_hit.size():
		var per_hit: Variant = unit_resource.damage_by_hit[hit_index]
		if per_hit is Dictionary:
			per_hit_dmg_dict = per_hit
	## 确定本次命中要施加的伤害类型：
	## ① damage_by_hit[hit_index] 配置了字典 → 遍历字典全部类型（同伤全部同时生效）
	## ② 否则 attack_hit_types[hit_index]（单主类型）
	## ③ 否则 damage_types 列表 / damage_type 单类型
	var types: Array[int] = []
	if not per_hit_dmg_dict.is_empty():
		for key in per_hit_dmg_dict.keys():
			if key is int:
				types.append(int(key))
	elif hit_index >= 0 and hit_index < unit_resource.attack_hit_types.size():
		## 仅配置 attack_hit_types：本次命中只使用该单一主类型
		types = [unit_resource.attack_hit_types[hit_index]]
	else:
		## 标准模式：使用 damage_types 列表（可多类型同伤）
		types = unit_resource.damage_types
		if types.is_empty():
			types = [unit_resource.damage_type]
	## 遍历每种伤害类型，计算对应伤害值
	for dt in types:
		var raw_dmg: int = unit_resource.damage
		## 优先级：damage_by_hit[hit_index][dt] > damage_by_type[dt] > damage（基础值）
		if per_hit_dmg_dict.has(dt):
			raw_dmg = int(per_hit_dmg_dict[dt])
		elif unit_resource.damage_by_type.has(dt):
			raw_dmg = int(unit_resource.damage_by_type[dt])
		## 应用克制关系修正
		if unit_resource.counter_table.has(target_id):
			raw_dmg = int(float(raw_dmg) * float(unit_resource.counter_table[target_id]))
		elif unit_resource.weakness_table.has(target_id):
			raw_dmg = int(float(raw_dmg) * float(unit_resource.weakness_table[target_id]))
		## 应用肉鸽加成：全局倍率（快照）× 伤害类型/远近程专属倍率（实时，军令可中途生效）
		##             × 残血激励倍率（实时，随当前血量变化）
		##             × 侵蚀减伤（#6：受击者身上侵蚀层数 0~3，每层 -10%）
		var erosion_mult: float = 1.0 - 0.1 * float(erosion_stacks)
		raw_dmg = int(round(float(raw_dmg) * buff_damage_mult * _damage_type_mult(int(dt)) * _low_hp_mult() * erosion_mult))
		## 确保最低伤害为 1
		raw_dmg = maxi(raw_dmg, 1)
		entries.append({"type": int(dt), "value": raw_dmg})
	return entries

## 该单位对指定伤害类型的额外倍率（仅玩家方吃「磨石/元素核心/菲比法典」等类型系文物）
func _damage_type_mult(damage_type: int) -> float:
	if team != 0:
		return 1.0
	return RunModifiers.damage_type_mult(damage_type, buff_is_ranged)

## 残血激励倍率（仅玩家方吃军令「死战令」），血量每次结算都会变，故不做快照
func _low_hp_mult() -> float:
	if team != 0:
		return 1.0
	return RunModifiers.low_hp_damage_mult(float(current_hp) / float(get_max_hp()))

## 攻击敌方基地的方法
## 当单位到达敌方基地时调用
func attack_base() -> void:  ## 定义攻击基地的方法
	## 如果单位已死亡，停止攻击
	if is_dead:  ## 如果单位已死亡
		return  ## 直接返回

	## 获取战场场景引用（单位在 UnitContainer 下，UnitContainer 在 Battlefield 下
	var battlefield = get_parent().get_parent()  ## 获取战场节点
	## 检查战场是否有 damage_base 方法
	if battlefield and battlefield.has_method("damage_base"):  ## 如果战场有 damage_base 方法
		## 计算敌方阵营编号（0 的敌方是 1，1 的敌方是 0）
		var enemy_team = 1 - team  ## 计算敌方阵营
		## #14（2026-08-11 修复）：对基地伤害用「本次攻击实际总伤害」而非 unit_resource.damage。
		## 旧逻辑取 damage 字段（英雄 Hero1/Hero2 只有 30），导致英雄打水晶固定 30 点，
		## 实际输出（damage_by_type/damage_by_hit 150~200）完全没生效。
		var entries: Array = _compute_damage_entries("base")
		## #13（2026-08-11 用户要求）：中远程兵种对水晶伤害减半（entries 与总值统一减半）
		if unit_resource != null and unit_resource.is_ranged:
			for i in range(entries.size()):
				entries[i]["value"] = maxi(1, int(round(int(entries[i]["value"]) * 0.5)))
		var damage: int = 0
		for e in entries:
			damage += maxi(int(e["value"]), 0)
		damage = maxi(damage, 1)
		## #7：远程兵种打基地/水晶时也必须走飞行物，命中瞬间才扣血。
		## 旧逻辑在命中帧直接 damage_base，表现为「箭还在半路，水晶血已经掉了」。
		if unit_resource.is_ranged:
			var base_unit: Unit = battlefield.get("red_base_unit") if enemy_team == 0 else battlefield.get("blue_base_unit")
			if base_unit != null and is_instance_valid(base_unit) and not base_unit.is_dead:
				var proj: Node = _spawn_projectile_with_entries(entries, base_unit)
				if proj != null:
					## 打基地时单位可能站在基地攻击范围（320px）内但超出自身射程余量，
					## 需把有效飞行距离拉到实际间距，避免箭矢半途消失导致永远打不掉水晶。
					var need_dist: float = global_position.distance_to(base_unit.global_position) + 64.0
					proj.max_distance = maxf(proj.max_distance, need_dist)
				return
		## 对敌方基地造成伤害（传入攻击者自身，战场触发 base_damaged 信号供 HUD 扣血日志条显示）
		battlefield.damage_base(enemy_team, damage, self)

## 受到伤害的方法（兼容旧接口，默认挥砍类型）
## #13（2026-08-09）：攻击方「本次攻击击杀计数」，供成就「大力出奇迹」（一次攻击击杀 ≥3）统计。
## 每次 perform_attack 开始时清零，击杀死者时（die()）按攻击方累加，跨 AOE 多目标累计。
var _attack_kill_count: int = 0

## damage: 受到的伤害值
## attacker: 攻击者单位（用于记录击杀信息）
func take_damage(damage: int, _attacker: Unit = null) -> void:  ## 定义受到伤害的方法
	## 默认按挥砍类型处理（先扣护甲再扣HP）
	take_damage_typed(damage, 0, _attacker)

## 受到带类型的伤害
## 四种类型的总输出都以 damage 为基准，只改变「护甲 / 血量」的分配方式：
##   挥砍(0): 先扣护甲，护甲耗尽后溢出扣 HP。对无甲目标 100% 进血。
##   穿刺(1): 其中 20%（PIERCE_ARMOR_IGNORE_RATIO）无视护甲直接进血，
##            剩余 80% 走护甲流程。对高甲目标输出稳定，对无甲目标与挥砍等价。
##   钝击(2): 对护甲伤害 ×1.3（打甲额外 30%）；打穿护甲后溢出的破甲量按 ×0.5 折回血量。
##            对无甲目标 100% 进血，对满甲目标全被护甲吃掉。
##   魔法(3): 护盾与血量同时全额扣除 —— 护盾按伤害扣（受当前护盾上限约束），血量扣全额伤害。
##            （用户拍板：100 魔法伤害 → 护盾 -100 且 血量 -100，护盾和血量各自吃全额）
## damage: 伤害值
## damage_type: 伤害类型（0=挥砍, 1=穿刺, 2=钝击, 3=魔法）
## attacker: 攻击者单位
func take_damage_typed(damage: int, damage_type: int = 0, attacker: Unit = null) -> void:
	## 如果单位已死亡，不再受伤
	if is_dead:
		return

	## #16（2026-08-11 用户要求）：中远程兵种（is_ranged）对英雄/特殊/异象类兵种伤害减半。
	## 原 #14 逻辑（is_ranged_override==1 且 tier>=4 减 1/3）已废弃：改用 is_ranged 全量判定 + 减半 + 目标仅限三类。
	var effective_damage: int = damage
	if attacker != null and attacker.unit_resource != null and attacker.unit_resource.is_ranged:
		if unit_resource != null:
			var uid: String = unit_resource.unit_id
			var is_hero: bool = uid.begins_with("Hero")
			var is_special: bool = uid.begins_with("S")
			var is_anomaly: bool = uid.begins_with("Y")
			if is_hero or is_special or is_anomaly:
				effective_damage = maxi(1, int(round(damage * 0.5)))

	var armor_before: int = current_armor  ## 受击前护甲（#6：钝击飘字是否橙色的判定基准）
	var hp_damage: int = 0      ## 本轮要扣的 HP
	var armor_damage: int = 0   ## 本轮要扣的护甲
	var blunt_bonus: int = 0    ## 钝击打盾额外伤害（#2 拍板：主伤白 + 额外飘橙）

	## 根据伤害类型计算护甲和HP的伤害分配
	match damage_type:
		1:  ## 穿刺（#8 2026-08-08 用户拍板）：只有打中护盾（当前有护甲）的目标才触发穿刺。
			## 打无护盾的「肉」不触发穿刺，按普通挥砍结算（护甲 0、全额进血）。
			## 有护盾时：PIERCE_ARMOR_IGNORE_RATIO（30%）无视护甲直接进血，其余部分走正常护甲流程。
			if current_armor > 0:  ## 目标当前有护盾才走穿刺
				var pierce_hp: int = int(float(effective_damage) * Constants.PIERCE_ARMOR_IGNORE_RATIO)  ## 穿透进血部分
				var remainder: int = maxi(effective_damage - pierce_hp, 0)  ## 需要过护甲的部分
				armor_damage = mini(current_armor, remainder)  ## 护甲吸收量
				hp_damage = pierce_hp + maxi(remainder - armor_damage, 0)  ## 穿透 + 护甲溢出
			else:  ## 无护盾目标：穿刺不生效，等同挥砍全额进血
				armor_damage = 0
				hp_damage = effective_damage
		2:  ## 钝击（#7 2026-08-11 用户要求）：打有护盾目标额外 +30% 伤害（BLUNT_ARMOR_MULTIPLIER=1.3）。
			## 旧实现（破甲潜力 ×1.3 + 溢出折半）只在满甲目标上多扣 30% 护甲、飘字仍显示原伤害，
			## 且低甲目标溢出折半后总输出反而不如挥砍 → 用户反馈「没奏效」。
			## 新实现：有盾目标伤害直接 ×1.3 再按先甲后血结算，飘字同步显示加成后数值。
			var blunt_dmg: int = effective_damage
			if armor_before > 0:
				blunt_dmg = maxi(1, int(round(float(effective_damage) * Constants.BLUNT_ARMOR_MULTIPLIER)))
				blunt_bonus = blunt_dmg - effective_damage  ## 打盾额外伤害（飘橙色）
			effective_damage = blunt_dmg
			armor_damage = mini(current_armor, effective_damage)  ## 先扣护甲
			hp_damage = maxi(effective_damage - armor_damage, 0)  ## 溢出进血
		3:  ## 魔法（#需求4）：护盾与血量同时全额扣除 —— 护盾按伤害扣（受当前护盾上限约束），血量扣全额
			armor_damage = mini(current_armor, effective_damage)  ## 护盾按伤害扣，受当前护盾上限约束
			hp_damage = effective_damage  ## 血量扣全额伤害
		_:  ## 挥砍及未知类型：先扣护甲，溢出扣 HP
			armor_damage = mini(current_armor, effective_damage)  ## 护甲吸收量
			hp_damage = maxi(effective_damage - armor_damage, 0)  ## 护甲溢出部分进血

	## 扣减护甲
	if armor_damage > 0:
		current_armor = maxi(current_armor - armor_damage, 0)
		if armor_bar:
			armor_bar.value = current_armor

	## 扣减 HP
	if hp_damage > 0:
		current_hp = maxi(current_hp - hp_damage, 0)
		if health_bar:
			health_bar.value = current_hp

	## #16：护甲吸收全部伤害时血量不变（value_changed 不触发），这里补刷一次血条数值
	_update_hp_bar_value_label()

	## 播放受击视觉反馈（精灵闪烁）
	_flash_sprite()

	## 显示伤害飘字（#2 2026-08-11 拍板）：
	## 主伤害一律白色（基础攻击色）；穿刺穿透进血附带伤害黄色（↳）；
	## 钝击打盾额外伤害（+30% 部分）橙色（+）；魔法保持紫色；流血红 / 中毒绿不变。
	match damage_type:
		1:  ## 穿刺：主伤害白色，有护盾时穿透进血部分独立飘黄色（↳ 前缀）
			_spawn_damage_number(effective_damage, Constants.DMG_COLOR_SLASH)
			if armor_before > 0:
				var pierce_hp: int = int(float(effective_damage) * Constants.PIERCE_ARMOR_IGNORE_RATIO)
				## 穿透独立飘字：仅当有穿透伤害且非零时显示
				## #5：整体右移 30px，与白色主伤害分列显示，避免两串数字重叠影响观察
				if pierce_hp > 0:
					_spawn_damage_number(pierce_hp, Constants.DMG_COLOR_PIERCE, "↳", 30.0)  ## ↳ 表示穿透进血
		2:  ## 钝击：主伤害白色（加成前），打盾额外伤害独立飘橙色（+ 前缀）
			_spawn_damage_number(effective_damage - blunt_bonus, Constants.DMG_COLOR_SLASH)
			if blunt_bonus > 0:
				_spawn_damage_number(blunt_bonus, Constants.DMG_COLOR_BLUNT, "+", 30.0)
		_:  ## 挥砍/魔法：按类型色（挥砍白、魔法紫）
			_spawn_damage_number(effective_damage, get_damage_type_color(damage_type))

	## 发出受击信号
	unit_damaged.emit(self, effective_damage)

	## 如果生命值归零，统一走 _on_lethal：敌军可能触发撤退，否则正常死亡
	if current_hp <= 0:
		_on_lethal(attacker)

## 治疗本单位，上限为含文物加成的最大生命。返回实际回复量
## 供军令「犒军」heal_all_pct、文物「龙涎香炉」regen_per_wave_pct 等调用
func heal(amount: int) -> int:
	if is_dead or amount <= 0:
		return 0
	var before: int = current_hp
	current_hp = mini(current_hp + amount, get_max_hp())
	if health_bar:
		health_bar.value = current_hp
	return current_hp - before

## 追加护盾（不受兵种基础护甲上限约束，用于军令 / 文物提供的临时护盾）
func add_shield(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	current_armor += amount
	if armor_bar:
		armor_bar.value = current_armor

## 生命归零时的统一处理：敌军（team==1）按概率触发撤退（军令「围三阙一令」），否则正常死亡
## 把三个致死入口（take_damage_typed / 流血 / 中毒）收拢到此处，避免撤退逻辑散落多处。
## attacker: 本次伤害的攻击者（传入 die() 用于击杀归属统计）
func _on_lethal(attacker: Unit = null) -> void:
	if team == 1 and not is_base_unit and randf() < RunModifiers.enemy_retreat_pct():
		_retreat()
		return
	die(attacker)

## 敌军撤退（军令「围三阙一令」enemy_retreat_pct）：受到伤害本应死亡时逃离战场。
## 不计击杀赏金，但会从敌方列表移除使波次可清空（走 BattleManager.retreat_unit）。
## #对象池（2026-08-20 用户反馈「连续出一百只兵还是会很卡」）：撤退原先直接 queue_free，
## 实例从对象池永久蒸发。撤退是每次敌方致死都可能触发的高频路径（军令「围三阙一令」），
## 打几分钟就把预热的 ~90 个实例抽干 → 此后每次 spawn_unit 都退化成 instantiate() +
## setup()，出兵瞬间卡顿。改为走 recycle_unit 回池（池满时它内部仍会 queue_free 兜底）。
func _retreat() -> void:
	is_dead = true
	if not is_base_unit:
		BattleManager.retreat_unit(self, team)
	BattleManager.recycle_unit(self)

## 死亡处理方法
## attacker: 击杀者单位（可为 null：环境伤害/词条来源缺失时无击杀归属）
func die(attacker: Unit = null) -> void:  ## 定义死亡处理方法
	## 如果已经死亡，避免重复处理
	if is_dead:  ## 如果已经死亡
		return  ## 直接返回
	is_dead = true  ## 标记为已死亡
	change_state("die")  ## 切换到死亡状态
	## 死亡时清除所有活跃词条效果
	clear_all_affixes()
	## #13（2026-08-09）：击杀归属统计 + 信号携带击杀者兵种 ID。
	## 汇集近战/投射物/AOE/词条全部致死路径，实时判定成就：
	##  - 大力出奇迹：己方攻击方一次攻击（本攻击周期内）击杀 ≥3 名敌方
	##  - 剑术大师：击杀者是 N2 兵种时按兵种累加击杀
	var killer_unit_id: String = ""
	if attacker != null and is_instance_valid(attacker) and attacker is Unit \
			and attacker.unit_resource != null:
		killer_unit_id = attacker.unit_resource.unit_id
		if attacker.team == 0:
			attacker._attack_kill_count += 1
			if attacker._attack_kill_count >= 3:
				Achievements.record_multi_kill()
			Achievements.record_unit_kill(killer_unit_id)
	## 发出死亡信号，通知击杀方
	unit_died.emit(self, 1 - team, killer_unit_id)  ## 发出死亡信号

	## 玩家方单位阵亡触发军令「断后令」的范围爆炸（team==0 且非基地单位）
	if team == 0 and not is_base_unit:
		_trigger_death_explosion()

	## 基地单位死亡时不从战斗管理器移除（不占人口），由 battlefield 处理基地摧毁
	if is_base_unit:  ## 如果是基地单位
		return  ## 直接返回，由 battlefield 通过 unit_died 信号处理
	## 通知战斗管理器从单位列表中移除
	BattleManager.remove_unit(self, team)  ## 从战斗管理器移除

## 玩家方单位阵亡时对周围敌人造成范围伤害（军令「断后令」death_explosion_damage）
## 仅在 team==0 的单位死亡时调用；爆炸造成的敌方阵亡仍会正常走 die()，计入击杀赏金。
func _trigger_death_explosion() -> void:
	if not is_instance_valid(self):  ## 单位可能已被释放，直接返回避免 Nil 访问
		return
	var dmg: int = RunModifiers.death_explosion_damage()
	if dmg <= 0:
		return
	## 战场节点：单位在 UnitContainer 下，UnitContainer 在 Battlefield 下
	var battlefield = get_parent().get_parent()
	if battlefield == null or not battlefield.has_method("get_units_in_radius"):
		return
	var enemies := battlefield.get_units_in_radius(global_position, DEATH_EXPLOSION_RADIUS, 1) as Array[Unit]
	for e in enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		e.take_damage_typed(dmg, RunModifiers.DMG_MAGIC, self)

## 精灵闪烁效果（私有）
## 用于攻击和受击时的视觉反馈
func _flash_sprite() -> void:  ## 定义精灵闪烁方法
	var visual = get_node_or_null("VisualBox")  ## 获取视觉框节点
	if visual == null:  ## 如果视觉框不存在
		return  ## 直接返回
	var tween = create_tween()  ## 创建补间动画
	tween.tween_property(visual, "modulate:v", 1.5, 0.05)  ## 提亮
	tween.tween_property(visual, "modulate:v", 1.0, 0.1)  ## 恢复正常亮度

## ============================================================
## 词条系统
## ============================================================

## 每帧更新活跃词条效果
## 流血：每秒扣 value_percent × 最大生命值 血量（直接扣HP，绕过护甲）
## 中毒：每秒扣 value_percent × 最大生命值 伤害（先扣护盾，再扣HP）
func _update_active_affixes(delta: float) -> void:
	if is_dead:
		return
	## #6 冰霜计时递减（独立于 _active_affixes，每帧减）
	if _frost_timer > 0.0:
		_frost_timer = maxf(_frost_timer - delta, 0.0)
	## #技能系统：技能减速与骑射计时递减（同样独立于 _active_affixes）
	if skill_slow_timer > 0.0:
		skill_slow_timer = maxf(skill_slow_timer - delta, 0.0)
		if skill_slow_timer <= 0.0:
			skill_slow_percent = 0.0  ## 减速结束即清空幅度，保证「timer>0 才有效」的不变量
	if skill_no_recovery_timer > 0.0:
		skill_no_recovery_timer = maxf(skill_no_recovery_timer - delta, 0.0)
	if _active_affixes.is_empty():
		return
	## AI 禁用时不处理词条效果（用于调试模拟，停止按钮后不再持续掉血）
	if ai_disabled:
		return
	## 基地单位（替代水晶）不接受持续伤害结算
	if is_base_unit:
		return
	## 每秒结算一次：累积计时器，跨过 1 秒时对所有活跃 DoT 词条统一结算一跳
	## 设计意图：流血/中毒均为“每秒扣一次固定百分比最大生命值”，而非逐帧点滴扣血
	_dot_timer += delta
	var tick_this_frame: bool = _dot_timer >= 1.0
	if tick_this_frame:
		_dot_timer -= 1.0
	var i: int = _active_affixes.size() - 1
	while i >= 0:
		var entry: Dictionary = _active_affixes[i]
		var affix: AffixResource = entry.get("affix", null)
		if affix == null or not is_instance_valid(affix):
			_active_affixes.remove_at(i)
			i -= 1
			continue
		## 递减剩余时间
		entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
		## 仅在每秒结算点触发一次伤害
		if tick_this_frame:
			var stacks: int = int(entry.get("stacks", 1))
			## 流血与中毒统一按最大生命值%计算（#需求5：流血不再按当前生命值，避免越扣越慢）
			## 描述：流血-每秒扣 value_percent × 最大生命值（直接扣HP绕过护甲）、中毒-每秒扣 value_percent × 最大生命值
			var base_hp: float = float(get_max_hp())
			var tick_damage: int = int(affix.value_percent * base_hp * float(stacks))
			if tick_damage > 0:
				if affix.affix_type == AffixResource.AffixType.BLEED:
					## 流血：直接扣 HP（绕过护甲），飘字红色
					_apply_direct_hp_damage(tick_damage)
					_spawn_damage_number(tick_damage, Constants.DMG_COLOR_BLEED)
					unit_damaged.emit(self, tick_damage)
				elif affix.affix_type == AffixResource.AffixType.POISON:
					## 中毒：先扣护盾再扣 HP，飘字绿色
					_apply_damage_with_armor(tick_damage)
					_spawn_damage_number(tick_damage, Constants.DMG_COLOR_POISON)
					unit_damaged.emit(self, tick_damage)
		## 时间耗尽，移除词条
		if float(entry.get("remaining", 0.0)) <= 0.0:
			_active_affixes.remove_at(i)
		i -= 1

## 直接扣减 HP（绕过护甲，用于流血等持续伤害）
## damage: 要扣减的 HP 数值
func _apply_direct_hp_damage(damage: int) -> void:
	if is_dead:
		return
	current_hp = maxi(current_hp - damage, 0)
	if health_bar:
		health_bar.value = current_hp
	if current_hp <= 0:
		_on_lethal()

## 先扣护盾再扣HP（用于中毒等持续伤害）
## damage: 要扣减的总伤害数值
func _apply_damage_with_armor(damage: int) -> void:
	if is_dead:
		return
	var armor_dmg: int = mini(current_armor, damage)
	current_armor = maxi(current_armor - armor_dmg, 0)
	var hp_dmg: int = maxi(damage - armor_dmg, 0)
	current_hp = maxi(current_hp - hp_dmg, 0)
	if armor_bar:
		armor_bar.value = current_armor
	if health_bar:
		health_bar.value = current_hp
	if current_hp <= 0:
		_on_lethal()

## 施加词条效果给目标单位
## affix: 要施加的词条资源
## source: 施加者单位（用于记录来源）
func apply_affix(affix: AffixResource, source: Unit = null) -> void:
	if is_dead or affix == null:
		return
	## 基地单位（替代水晶）不接受流血/中毒等持续词条，避免基地莫名持续掉血
	if is_base_unit:
		return
	## #14 击退：瞬时效果，命中即位移，不占用持续词条列表（否则会被当成 DoT 每秒结算）
	## #需求6 击退累计晕眩：晕眩中不再被推走且不累计；免疫期内正常击退位移但不累计层数
	if affix.affix_type == AffixResource.AffixType.KNOCKBACK:
		if stun_timer > 0.0:
			return  ## 晕眩中：不位移、不累计
		var origin: Vector2 = source.global_position if (source != null and is_instance_valid(source)) else global_position
		apply_knockback(origin, affix.knockback_distance * Constants.UNIT_TO_PIXELS)
		if stun_immune_timer <= 0.0:
			stun_stacks += 1  ## 免疫期外才累计晕眩值
			if stun_stacks >= Constants.STUN_REQUIRED_STACKS:
				stun_stacks = 0  ## 触发后清零，重新累计
				stun_timer = Constants.STUN_DURATION
				change_state("stun")  ## 进入晕眩状态
		return
	## #6 冰霜：受击时攻速降低 30% 持续 1 秒，不可叠加（重复施加仅刷新计时），走专用 _frost_timer
	if affix.affix_type == AffixResource.AffixType.FROST:
		_frost_timer = affix.duration  ## 直接刷新剩余秒
		return
	## #6 侵蚀：受击时伤害 -10%/层，最多 3 层持续到死亡，走专用 erosion_stacks
	if affix.affix_type == AffixResource.AffixType.EROSION:
		erosion_stacks = mini(erosion_stacks + 1, affix.max_stacks)
		return
	## 检查是否已有同类型词条
	var existing_idx: int = -1
	for i in range(_active_affixes.size()):
		var entry: Dictionary = _active_affixes[i]
		var e_affix: AffixResource = entry.get("affix", null)
		if e_affix != null and e_affix.affix_id == affix.affix_id:
			existing_idx = i
			break
	if existing_idx >= 0:
		## 已存在同类型词条
		var existing: Dictionary = _active_affixes[existing_idx]
		if affix.stackable:
			## 可叠加：增加层数（不超过 max_stacks），刷新持续时间
			var cur_stacks: int = int(existing.get("stacks", 1))
			existing["stacks"] = mini(cur_stacks + 1, affix.max_stacks)
			existing["remaining"] = affix.duration
		else:
			## 不可叠加：仅重置持续时间
			existing["remaining"] = affix.duration
	else:
		## 新词条，添加到列表
		_active_affixes.append({
			"affix": affix,
			"remaining": affix.duration,
			"stacks": 1,
			"source": source,
		})

## 清除所有活跃词条效果（死亡时调用）
## #需求6 顺带清空晕眩状态（晕眩计时/层数/免疫计时），保证死亡或重置后不残留
## #6：冰霜计时 + 侵蚀层数也一并清零
## #技能系统：技能减速/骑射计时与待释放技能定义同样清零 ——
##   本函数在「死亡」与「对象池复用前」（_clear_pool_residue）两处调用，
##   不清会导致复用实例带着上一局的减速幅度或残留技能定义出场。
func clear_all_affixes() -> void:
	_active_affixes.clear()
	stun_timer = 0.0
	stun_stacks = 0
	stun_immune_timer = 0.0
	_frost_timer = 0.0
	erosion_stacks = 0
	skill_slow_percent = 0.0
	skill_slow_timer = 0.0
	skill_no_recovery_timer = 0.0
	pending_skill_def = {}

## 对象池复用前的残留清理（2026-08-18）：清掉死亡/战斗遗留的 tween、词条、
## 远程技能定时器、击退/突进位移，恢复血条护盾条与精灵可见性。新实例调此函数为幂等空操作。
func _clear_pool_residue() -> void:
	clear_all_affixes()
	## 注：死亡 tween 由 state_die 创建，回池时机（死亡动画播完/2s 兜底）保证其已自然结束，
	## 无需在此枚举清理（Tween 是 RefCounted 非 Node，无法从 get_children 获取）。
	## 释放远程技能定时器（setup 会按需重建）
	if _ranged_skill_timer != null:
		if is_instance_valid(_ranged_skill_timer):
			_ranged_skill_timer.queue_free()
		_ranged_skill_timer = null
	## #技能系统：移除技能组件（setup 会按新兵种重新按需挂载）
	## 对象池是**无类型池**——同一实例可能上局是 Hero2、下局被复用为普通兵，
	## 不移除会让普通兵带着 Hero2 的技能出场。
	var old_skill_comp: Node = get_node_or_null("UnitSkillComponent")
	if old_skill_comp != null:
		old_skill_comp.queue_free()
		## 立即改名，避免 queue_free 生效前 setup 里的重名检查误判为「已挂载」
		old_skill_comp.name = "UnitSkillComponent_Freeing"
	## 复位战斗位移残留
	_knockback_velocity = Vector2.ZERO
	_knockback_timer = 0.0
	_attack_dash_time = -1.0
	_attack_dash_dir = Vector2.ZERO
	_attack_dash_triggered = false
	## 复位寻路节流缓存
	_pathfind_accum = 0.0
	_cached_separation = Vector2.ZERO
	## #索敌卡顿（2026-08-20）：本帧结论缓存也必须复位。物理帧序号是全局单调递增的，
	## 复用出来的实例若带着上一世写入的 _pathfind_gate_frame，虽不会等于当前帧（不会误判），
	## 但 _pathfind_gate_value 会残留上一世的放行结论；一旦复用发生在同一帧内（清场后立即刷兵
	## 就是这种时序），同帧调用会直接吃到旧结论。置为 -1 保证新一世的第一次调用必然重新计算。
	_pathfind_gate_frame = -1
	_pathfind_gate_value = false
	## 复位显示：精灵/血条/护盾条恢复可见（死亡时被隐藏或淡出）
	modulate = Color.WHITE
	if unit_sprite != null:
		unit_sprite.modulate = Color.WHITE
		unit_sprite.visible = true
	if health_bar != null:
		health_bar.visible = true
	if armor_bar != null:
		armor_bar.visible = true

## #技能系统：施加技能减速（移速与攻速同时按 percent 折减，持续 duration 秒）
## 与冰霜词条完全独立：冰霜只影响攻速且固定 -30%/1s，本函数的幅度与时长由技能定义给出。
## 重复施加时取「幅度更大者」并刷新计时，避免弱减速覆盖强减速。
## percent: 减速幅度（0.4 = -40%）
## duration: 持续秒数
func apply_skill_slow(percent: float, duration: float) -> void:
	if is_dead or is_base_unit or percent <= 0.0 or duration <= 0.0:
		return
	skill_slow_percent = maxf(skill_slow_percent, clampf(percent, 0.0, 0.9))
	skill_slow_timer = maxf(skill_slow_timer, duration)

## #技能系统：播放技能专属动画（skill_frames.tres）
## speed: 播放速度倍率（<1 放慢，营造吟唱/蓄力感）
func play_skill_anim(speed: float = 1.0) -> void:
	if unit_sprite == null or anim_skill_frames == null:
		return
	current_anim_state = "skill"
	unit_sprite.offset = Vector2.ZERO
	unit_sprite.sprite_frames = anim_skill_frames
	_apply_anim_scale(anim_skill_frames, "skill")
	unit_sprite.speed_scale = speed if speed > 0.0 else 1.0
	## 取该 SpriteFrames 内的第一个动画名播放（切片工具生成的动画名可能是 skill/attack 等）
	var names: PackedStringArray = anim_skill_frames.get_animation_names()
	if names.size() > 0:
		unit_sprite.play(names[0])

## #14 击退：把本单位沿「攻击者 → 自己」的方向推开一段距离
## 位移不是瞬移，而是在 KNOCKBACK_DURATION 秒内均匀完成，由 _apply_knockback_step 每物理帧消耗；
## 这样既不与状态机的 move_and_slide 抢控制权，也不会出现瞬间闪现的突兀感。
## from_position: 击退来源位置（通常是攻击者世界坐标）
## distance_px: 击退距离（像素）
func apply_knockback(from_position: Vector2, distance_px: float) -> void:
	if is_dead or is_base_unit or distance_px <= 0.0:  ## 死亡 / 基地 / 无效距离不生效
		return
	## #14 用户拍板：突进不可被阻挡——命中突进一旦触发必须往前走完，击退不打断 dash
	##（原 _attack_dash_time = -1.0 会让攻击中的单位被击退时突进中断）
	var dir: Vector2 = global_position - from_position  ## 由攻击者指向自己的方向
	if dir.length() < 0.01:  ## 完全重叠时退化为「推向自己后方」
		dir = Vector2(-1.0 if team == 0 else 1.0, 0.0)  ## 红方向左退，蓝方向右退
	## 换算为速度：总位移 / 持续时间，后续每帧按 delta 消耗
	_knockback_velocity = dir.normalized() * (distance_px / KNOCKBACK_DURATION)
	_knockback_timer = KNOCKBACK_DURATION  ## 启动击退计时
	## #1（2026-08-14）：击退打断攻击 —— 若本单位正处于攻击状态，按「是否已出伤害」分支打断
	if current_state != null and is_instance_valid(current_state) and current_state.get_script() == state_map.get("attack", null):
		current_state.on_knockback_interrupt()

## 消耗本帧的击退位移（在状态机更新之后、边界钳制之前调用）
## delta: 物理帧间隔（秒）
func _apply_knockback_step(delta: float) -> void:
	if _knockback_timer <= 0.0:  ## 没有待结算的击退
		return
	var step: float = minf(delta, _knockback_timer)  ## 本帧可消耗的时长（末帧不超发）
	global_position += _knockback_velocity * step  ## 应用位移
	_knockback_timer -= step  ## 扣减剩余时长
	if _knockback_timer <= 0.0:  ## 击退结束
		_knockback_velocity = Vector2.ZERO  ## 清空速度

## #突进（2026-08-15）：命中帧朝目标方向突进（unit_resource.attack_dash_px > 0 的兵种，如凑企鹅 Y2）
## 由 state_attack._on_frame_hit 在命中帧调用；方向取目标方向，目标失效时按面朝方向兜底
func start_attack_dash() -> void:
	if unit_resource == null or unit_resource.attack_dash_px <= 0.0:
		return
	if target == null or not is_instance_valid(target) or target.is_dead:
		return
	_start_attack_dash_impl(target.global_position)

## #突进（2026-08-15）：朝指定世界坐标方向突进（state_attack_base 攻击水晶时 target 为 null，
## 改向敌方基地位置；与 state_attack 命中突进共用同一套位移曲线）
func start_attack_dash_toward(point: Vector2) -> void:
	if unit_resource == null or unit_resource.attack_dash_px <= 0.0:
		return
	_start_attack_dash_impl(point)

## 突进启动内部实现：计算方向、激活计时、禁用碰撞（#15：突进不可阻挡，直接穿过面前敌人）
func _start_attack_dash_impl(point: Vector2) -> void:
	var dir: Vector2 = point - global_position
	if dir.length() < 0.01:  ## 与目标重叠时按面朝方向兜底
		dir = Vector2.RIGHT if facing_dir >= 0 else Vector2.LEFT
	else:
		dir = dir.normalized()
	_attack_dash_dir = dir
	## #18-3（2026-08-15）：突进动画朝向跟随位移方向。
	## 用户反馈「臭企鹅面向左时攻击右上方敌人，动画朝左却向右上位移飞过去」——
	## dash 是强制位移，动画朝向必须与位移方向同步，否则视觉倒退飞行。
	## 用带 flip_override 的 set_facing_direction（内部走 _apply_anim_flip），Y2 无 override 直接跟随。
	if absf(dir.x) > 0.01:
		set_facing_direction(dir.x)
	_attack_dash_time = 0.0  ## 激活突进（从 0 秒计时）
	_set_dash_collision(false)  ## #15：突进期间禁用碰撞体，位移不被面前敌人阻挡（飞踢穿人）

## #15：突进期间禁用/恢复碰撞体——直接改 position 的本体位移会被其他单位 move_and_slide
## 的碰撞重叠修正推回（用户反馈「被面前敌人阻挡无法位移」），禁用后 1 秒内直接穿人而过。
func _set_dash_collision(enabled: bool) -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null and col.disabled != (not enabled):
		col.disabled = not enabled

## #突进位移处理：在状态机更新之后、边界钳制之前调用
## 攻击周期内 velocity 为零（站定挥击），直接改 position 不与其他移动冲突
func _process_attack_dash(delta: float) -> void:
	if _attack_dash_time < 0.0 or unit_resource == null:
		return
	var total: float = unit_resource.attack_dash_px
	if total <= 0.0:
		_attack_dash_time = -1.0
		return
	var prev: float = _attack_dash_distance(_attack_dash_time)
	_attack_dash_time += delta
	var cur: float = _attack_dash_distance(_attack_dash_time)
	global_position += _attack_dash_dir * (cur - prev)  ## 应用本帧位移增量
	if _attack_dash_time >= 1.0:
		_attack_dash_time = -1.0  ## 突进完成（总时长 1 秒）
		_set_dash_collision(true)  ## #15：突进结束恢复碰撞体

## #突进距离进度曲线（t: 0→1 秒）——先快后慢：
## 前 90% 距离在 0.5s 内快速走完（快），后 10% 距离在 0.5s 内减速走完（慢），总位移 = attack_dash_px
func _attack_dash_distance(t: float) -> float:
	var total: float = unit_resource.attack_dash_px if unit_resource != null else 0.0
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return total
	if t < 0.5:
		return total * 0.9 * (t / 0.5)  ## 前 0.5s：快速走 90% 距离
	return total * 0.9 + total * 0.1 * ((t - 0.5) / 0.5)  ## 后 0.5s：减速走完剩余 10%

## 根据伤害类型返回对应的飘字颜色
## 白=挥砍(0) 黄=穿刺(1) 橙=钝击(2) 紫=魔法(3)
func get_damage_type_color(damage_type: int) -> Color:
	match damage_type:
		1: return Constants.DMG_COLOR_PIERCE
		2: return Constants.DMG_COLOR_BLUNT
		3: return Constants.DMG_COLOR_MAGIC
		_: return Constants.DMG_COLOR_SLASH

## 生成伤害飘字（根据设置开关决定是否显示）
## damage: 伤害数值
## color: 飘字颜色（按伤害类型/持续伤害来源区分，见 Constants.DMG_COLOR_*）
## prefix_text: 显示在伤害数字前的文本前缀（如"20%穿透"），为空则不显示
## x_offset: 额外的水平偏移（像素）。穿刺的白色穿透飘字用 +30 右移，
##           与黄色主伤害数字错开，避免两串数字叠在一起看不清（#5）
func _spawn_damage_number(damage: int, color: Color, prefix_text: String = "", x_offset: float = 0.0) -> void:
	## 检查设置开关，关闭时不显示飘字
	if not SettingsManager.show_damage_numbers:
		return
	## 创建伤害飘字实例
	var dmg_label = DamageNumber.new()
	## 有前缀文本时（如"20%穿透4"）直接拼接，否则仅显示数值
	if prefix_text != "":
		dmg_label.text = prefix_text + str(damage)
	else:
		dmg_label.text = str(damage)
	## 颜色即伤害类型：白=挥砍 黄=穿刺 橙=钝击 紫=魔法 红=流血 绿=中毒
	dmg_label.add_theme_color_override("font_color", color)
	## 飘字位置：单位头顶上方，随机 X 偏移避免重叠；x_offset 用于把并发的多条飘字分列显示
	## #3（2026-08-08）：水晶（is_base_unit）被攻击也显示伤害数字，位置上移到方块上方（血条之上），
	## 避免叠在 72×72 的方块和头顶血条上（旧逻辑直接跳过 base_unit，水晶受击无任何反馈）。
	var rand_x: float = randf_range(-10.0, 10.0)
	var float_y: float = -70.0 if is_base_unit else -30.0
	dmg_label.position = Vector2(rand_x + x_offset, float_y)
	add_child(dmg_label)

## 检测区域进入回调
## 当有单位进入检测范围时调用
## body: 进入检测区域的物理体节点
func _on_detection_body_entered(body: Node2D) -> void:  ## 定义检测区域进入回调
	## 如果单位已死亡，忽略
	if is_dead:  ## 如果单位已死亡
		return  ## 直接返回
	if body == null:  ## 如果进入的节点为空
		return  ## 直接返回
	## AI 禁用时不自动切换状态（用于调试模拟，防止自动开始战斗）
	if ai_disabled:
		return
	## #竞技场（2026-08-24）：和平模式/停战期间 combat_enabled=false，
	## 检测区回调不得抢过状态机把单位拽进 attack —— 那正是「和平模式下两个
	## 靠近的阵营互相冲上去打」的来源（hold_position 只拦 state_move，拦不住这里）。
	if not combat_enabled:
		return
	## 检查是否为敌方且存活的单位
	if body is Unit and body.team != team and not body.is_dead:  ## 如果是敌方且存活的单位
		## 如果当前没有目标，设置为目标
		if target == null:  ## 如果当前没有目标
			target = body  ## 设置为目标
			## 如果当前处于「无目标默认状态」（move 推进 / guard 护晶），切换到攻击状态
			if current_state and current_state.get_script() == state_map[get_idle_state_name()]:
				change_state("attack")  ## 切换到攻击状态

## 检测区域离开回调
## 当有单位离开检测范围时调用
## body: 离开检测区域的物理体节点
func _on_detection_body_exited(body: Node2D) -> void:  ## 定义检测区域离开回调
	if body == null:  ## 如果离开的节点为空
		return  ## 直接返回
	## 如果离开的是当前目标
	if body == target:  ## 如果离开的是当前目标
		## 若处于攻击周期内（前后摇未结束），不打断：保留目标直到本周期自然结束
		## （目标若已死亡，命中判定会因 is_dead 自然 no-op；周期结束后状态机会重新寻找目标）
		if current_state and current_state.get_script() == state_map["attack"] and current_state._attack_started:
			return  ## 攻击周期中，等待本周期播完后再由状态机处理
		target = null  ## 清空目标
		## 如果当前在攻击状态，切回默认状态（move 推进 / guard 护晶）
		if current_state and current_state.get_script() == state_map["attack"]:  ## 如果当前在攻击状态
			change_state(get_idle_state_name())  ## 切回默认状态
