class_name Constants  ## 声明类名为 Constants
## 全局常量类
## 集中定义游戏中使用的所有常量，便于统一管理和修改

extends RefCounted  ## 继承 RefCounted 引用计数类
## 继承 RefCounted，表示这是一个引用计数类，不需要手动释放

## 战场总宽度（标准单位），双方基地之间的距离为 60 个标准单位
const BATTLEFIELD_WIDTH: float = 60.0
## 红方基地的 X 坐标（标准单位），位于战场最左侧
const RED_BASE_X: float = 0.0
## 蓝方基地的 X 坐标（标准单位），位于战场最右侧
const BLUE_BASE_X: float = 60.0
## 中场线的 X 坐标（标准单位），位于战场正中间
const MID_FIELD_X: float = 30.0
## 单位标准体型半径（标准单位），所有单位的碰撞体大小统一
const UNIT_SIZE: float = 0.25
## 每标准单位对应的像素数，用于将游戏逻辑单位转换为屏幕像素
const UNIT_TO_PIXELS: float = 32.0
## 基地的最大生命值（HP）
## 历史：原值 5000 -> #109 减半为 2500 -> #150 在原已减半基础上再下调一半 = 1250
## #12（2026-08-09 用户拍板）：1250 -> 1000（双方水晶最大血量改 1000）
const BASE_HP: int = 1000
## 常规模式双方水晶每秒自动恢复量（#13 用户拍板：血量不满时每秒恢复 5 点）
const BASE_REGEN_PER_SEC: int = 5
## 水晶/基地回血脱战延迟（秒）：受到实际伤害后需等该时长才开始回血（#8 2026-08-15：原 0/无延迟改 3s）
const BASE_REGEN_OUT_OF_COMBAT_SEC: float = 3.0

## ── 肉鸽模式水晶（#209）─────────────────────────────────────────
## 仅肉鸽模式生效：玩家侧放置区正中心的红色方块水晶，被敌方摧毁即本局失败。
## 水晶耐久为固定常量，不吃文物/军令的血量加成（在 battlefield 生成时强制覆盖）。
## #7：由 3000 下调到 400，使水晶成为需要重点保护的目标而非无敌墙。
## #23（2026-08-09）：由 400 上调到 1000，并配套每秒恢复 5 点（见 ROGUELIKE_CRYSTAL_REGEN_PER_SEC）。
const ROGUELIKE_CRYSTAL_HP: int = 1000
## 肉鸽水晶每秒自动恢复量（#23：1000 血 + 每秒 +5，持续战斗的续航手段）
const ROGUELIKE_CRYSTAL_REGEN_PER_SEC: int = 5
## 水晶世界坐标：肉鸽模式放在地图正中央（#7：原 -320 偏左，现居中，敌人从两侧合围）
const ROGUELIKE_CRYSTAL_POS: Vector2 = Vector2(0.0, 30.0)
## 水晶红色方块的显示边长（像素）
const ROGUELIKE_CRYSTAL_SIZE: float = 72.0
## 水晶方块颜色（红色）
const ROGUELIKE_CRYSTAL_COLOR: Color = Color(0.9, 0.16, 0.16, 1.0)
## 游戏开始时双方玩家获得的初始金币数
const INITIAL_GOLD: int = 200
## 前 10 回合的固定倒计时时间（秒）
const EARLY_ROUND_TIME: float = 5.0
## 第 11 回合起每回合递增的时间增量（秒）
const ROUND_TIME_INCREMENT: float = 1.0
## 第 40 回合及以后的固定倒计时时间（秒）
const LATE_ROUND_TIME: float = 40.0
## 游戏的最大回合数限制
const MAX_ROUND: int = 200
## 每方阵营在战场上同时存在的最大单位数量（默认人口上限，仅正常模式生效）
## #9（2026-08-08）：默认人口上限 20 → 10（用户拍板）
const MAX_UNITS_PER_SIDE: int = 10
## 人口升级后的人口上限封顶（#138：默认 10 + 升级加成，最高 45）
const MAX_POPULATION_CAP: int = 45
## 肉鸽模式单位部署上限（独立于正常模式人口；肉鸽无人口/收入概念，上限由玩家拍板=100）
const ROGUELIKE_MAX_UNITS_PER_SIDE: int = 100
## 克制关系中的伤害倍率（克制时伤害乘以 1.5）
const COUNTER_MULTIPLIER: float = 1.5
## 被克制关系中的伤害倍率（被克制时伤害乘以 0.6）
const WEAK_MULTIPLIER: float = 0.6
## 普通攻击（无克制关系）的伤害倍率
const NORMAL_MULTIPLIER: float = 1.0
## 远程攻击的距离阈值（标准单位），攻击距离大于此值视为远程单位
## 设为 2.0 以区分长柄近战武器（attack_range=1.5，如长戟/关刀/巨镰）和真正的远程单位
const RANGED_THRESHOLD: float = 2.0

## 单位生成 Y 坐标范围：限定在战场区域内
## 中心 y=30，生成范围 ±40，即 y∈-10~70（向下偏移，靠近战场中央）
const SPAWN_Y_CENTER: float = 30.0  ## 刷兵区域中心 Y（向下偏移）
const SPAWN_Y_RANGE: float = 40.0  ## 生成 Y 范围半径

## 单位活动边界（像素，battlefield 全局坐标）
## 单位互相碰撞挤压 + 直接位移（追击/后退）会累积偏移，无边界时会漂出屏幕
## X 略超基地中心（±576）让单位能贴到水晶；Y 给出生阵线上下各留约 100px 缓冲
const FIELD_X_MIN: float = -600.0  ## 单位可到达的最左 X
const FIELD_X_MAX: float = 600.0  ## 单位可到达的最右 X
## #13：空气墙 —— Y 收紧到出兵区域（SPAWN_Y_CENTER ± SPAWN_Y_RANGE = -10~70），
## 单位只能在「地图中心直线出兵区域」内移动，上下被空气墙挡住，不再漂到屏幕边缘。
## #7（2026-08-08）：战场整体上下活动范围扩大（用户拍板），-10~70 → -30~90
const FIELD_Y_MIN: float = -30.0  ## 单位可到达的最上 Y（出兵区域上界）
const FIELD_Y_MAX: float = 90.0  ## 单位可到达的最下 Y（出兵区域下界）
## 被挤出出生阵线后每秒拉回的像素速度（仅在移动状态生效，避免与追击抢控制权）
const LANE_RETURN_SPEED: float = 24.0  ## 阵线回归速度（像素/秒）
## 远程单位被近战贴脸时的后退触发距离（像素）
const MELEE_RETREAT_THRESHOLD: float = 55.0  ## 贴脸后退阈值
## 远程后退时的速度系数（相对自身移动速度）
const RETREAT_SPEED_RATIO: float = 0.9  ## 后退速度系数
## #4（2026-08-08）：中远程「安全距离」——只有被敌方兵种贴近到 3 格（3×32px）以内才会后撤。
## 取代旧逻辑「与射程挂钩的风筝距离」：远程不再隔老远就后退，贴近 3 格才拉开身位。
const RETREAT_SAFE_DISTANCE_PX: float = 96.0  ## 3 格 × 32px/格
## #5（2026-08-08）：攻击状态下朝向滞回死区（像素）。
## 目标在自身水平 ±24px 以内时不翻转朝向，杜绝「攻击循环 + 后撤」期间的左右疯狂抽搐。
const ATTACK_FACING_DEADBAND_PX: float = 24.0
## #5（2026-08-09）：中远程兵种攻击后的硬后摇时长（秒）。
## 攻击周期（前摇+命中+后摇）结束后再锁定 0.5s：不可移动、不可后撤、可转身，锁定结束才进入风筝恢复期。
const RANGED_ATTACK_RECOVERY_TIME: float = 0.5
## #6（2026-08-09）：远程攻击状态「超射程防抖」时长（秒）。
## 目标在射程边缘振荡时，攻击状态累计超射程达此时长才切回默认状态，杜绝 move↔attack↔idle 每帧循环导致的抽搐不攻击。
const RANGED_ATTACK_LOSE_TIMER: float = 0.3

## ── 寻敌 / 肉鸽守卫 AI（#210）─────────────────────────────────
## 常规模式的最小寻敌半径（像素）：近战攻击距离短，靠这个保底提前发现敌人
const DEFAULT_DETECTION_RADIUS: float = 150.0
## 肉鸽模式统一寻敌 / 追击半径默认值（像素）
## 所有兵种共用同一个值（与自身攻击距离解耦），运行时值见 RoguelikeManager.chase_range_px
const ROGUELIKE_CHASE_RANGE: float = 280.0
## 肉鸽追击牵引半径默认值（像素）：守卫单位离水晶超过此距离即放弃追击回防，
## 保证「以保护水晶为主」而不会被敌人牵着满地图跑。
## #9：需求改为守卫单位无限追击（不被牵引拉回），故置极大值使其实际永不触发牵引。
const ROGUELIKE_CHASE_LEASH: float = 99999.0
## 近战驻守点：水晶正前方的随机距离区间（像素）
## 每个单位在 setup 时抽一次并固定，避免所有近战叠在同一个像素点上
const GUARD_MELEE_FRONT_MIN: float = 48.0
const GUARD_MELEE_FRONT_MAX: float = 176.0
## 远程驻守点：后撤距离 = 自身射程像素 × 该比例，再夹到 [MIN, MAX]
## 射程越远站得越靠后，但始终保证火力能覆盖水晶正前方
const GUARD_RANGED_BACK_RATIO: float = 0.35
const GUARD_RANGED_BACK_MIN: float = 24.0
const GUARD_RANGED_BACK_MAX: float = 120.0
## 到达驻守点的判定容差（像素），小于此距离即视为就位并停下
const GUARD_ARRIVE_TOLERANCE: float = 12.0
## 远程跟随己方近战前压时，与该近战保持的身位区间（像素）
const GUARD_ESCORT_STANDOFF_MIN: float = 64.0
const GUARD_ESCORT_STANDOFF_MAX: float = 200.0

## ============================================================
## 伤害类型机制系数
## 伤害类型编号：0=挥砍 1=穿刺 2=钝击 3=魔法
## 设计原则：每种类型的「总输出」都以 damage 为基准，只改变护甲与血量的分配方式，
## 不允许出现护甲吃全额、血量再额外吃一份的双重结算（那会让实际输出远超面板数值）。
## ============================================================
## 穿刺：无视护甲、直接进血的伤害占比，其余部分走正常护甲流程
## #8（2026-08-08）：0.2 → 0.3，且「只有打中护盾才触发穿刺」——见 unit_base.take_damage_typed：
## 目标当前护甲 > 0 时按 30% 无视护甲穿刺；打无护盾的肉不触发（按普通挥砍结算）
const PIERCE_ARMOR_IGNORE_RATIO: float = 0.3  ## 穿刺无视护甲占比
## 钝击：对护甲的伤害倍率（破甲专精）
## #6：由 2.0 调整为 1.3 ——「打甲额外 30%」（原来 200% 破甲过于夸张，等于对护甲翻倍）
const BLUNT_ARMOR_MULTIPLIER: float = 1.3  ## 钝击破甲倍率
## 钝击：护甲被打穿后，溢出的破甲量折算回血量伤害的系数（与破甲倍率互为倒数）
const BLUNT_OVERFLOW_TO_HP_RATIO: float = 0.5  ## 钝击溢出折算系数
## 魔法：无视护甲直接进血的占比（1.0 = 完全无视护甲）
const MAGIC_ARMOR_IGNORE_RATIO: float = 1.0  ## 魔法无视护甲占比

## ============================================================
## 击退累计晕眩（#需求6）
## 兵种被击退效果击中时累计 1 层晕眩值；满 STUN_REQUIRED_STACKS 层 → 陷入
## STUN_DURATION 秒「不可移动不可攻击」晕眩状态；晕眩结束后 STUN_IMMUNE_DURATION
## 秒内不会被叠加晕眩值（免疫期结束重新从 0 累计）。
## ============================================================
const STUN_REQUIRED_STACKS: int = 2  ## 击退累计满 2 层触发晕眩
const STUN_DURATION: float = 2.0  ## 晕眩持续时间（秒）
const STUN_IMMUNE_DURATION: float = 5.0  ## 晕眩结束后的免疫期（秒）

## ============================================================
## 伤害飘字配色（按伤害类型与持续伤害来源区分）
## ============================================================
const DMG_COLOR_SLASH: Color = Color(1.0, 1.0, 1.0, 1.0)  ## 挥砍：白
const DMG_COLOR_PIERCE: Color = Color(1.0, 0.9, 0.25, 1.0)  ## 穿刺：黄
const DMG_COLOR_BLUNT: Color = Color(1.0, 0.6, 0.2, 1.0)  ## 钝击：橙
const DMG_COLOR_MAGIC: Color = Color(0.75, 0.45, 1.0, 1.0)  ## 魔法：紫
const DMG_COLOR_BLEED: Color = Color(1.0, 0.25, 0.25, 1.0)  ## 流血：红
const DMG_COLOR_POISON: Color = Color(0.35, 1.0, 0.4, 1.0)  ## 中毒：绿

## ============================================================
## 投射物
## ============================================================
## 投射物有效飞行距离相对攻击射程的余量倍率
## 命中判定在攻击动画中段触发，此时目标可能已挪到射程边缘外，
## 若有效距离恰好等于射程，箭矢会在半途凭空消失
const PROJECTILE_RANGE_MARGIN: float = 1.6  ## 投射物射程余量倍率
## 投射物飞出战场边界多远后销毁（像素）
const PROJECTILE_DESPAWN_MARGIN: float = 80.0  ## 出界销毁余量

## 2D 物理碰撞层定义（用于区分不同类型的碰撞体）
## 第 1 层：玩家单位（红方）
const COLLISION_PLAYER_UNITS: int = 1
## 第 2 层：敌方单位（蓝方/AI）
const COLLISION_ENEMY_UNITS: int = 2
## 第 3 层：建筑（基地等）
const COLLISION_BUILDINGS: int = 3
## 第 4 层：投射物（远程攻击的飞行物）
const COLLISION_PROJECTILES: int = 4
## 第 5 层：玩家远程单位（红方远程）
const COLLISION_PLAYER_RANGED: int = 5
## 第 6 层：敌方远程单位（蓝方远程）
const COLLISION_ENEMY_RANGED: int = 6

## ---- 碰撞位掩码（#9：近战与中远程之间取消碰撞体积）----
## 设计：近战与远程分处不同物理层，各自只碰撞「同类」，
## 于是远程排成一排也不会挡住己方近战推进，近战也不会被敌方远程卡住。
## 位值：bit1=1 红近战, bit2=2 蓝近战, bit3=4 建筑, bit4=8 投射物,
##       bit5=16 红远程, bit6=32 蓝远程
const MASK_RED_MELEE: int = 1  ## 红方近战层位值
const MASK_BLUE_MELEE: int = 2  ## 蓝方近战层位值
const MASK_BUILDINGS: int = 4  ## 建筑层位值
const MASK_RED_RANGED: int = 16  ## 红方远程层位值
const MASK_BLUE_RANGED: int = 32  ## 蓝方远程层位值
## 近战单位的碰撞掩码：仅与双方近战 + 建筑碰撞（不含远程层）
## 注意：此常量已废弃（保留供对照）。#10 起近战按阵营区分，见下方 MASK_MELEE_BODY_RED / _BLUE。
const MASK_MELEE_BODY: int = MASK_RED_MELEE | MASK_BLUE_MELEE | MASK_BUILDINGS  ## 3+4=7
## 近战碰撞掩码（#10 修复「被己方前排堵成空气墙」）：
## 拆成红/蓝两套，各自排除本方阵营层，使友军近战互相穿透（仍由 _compute_ally_separation 柔性散开），
## 但保留与敌方近战的碰撞（近战互砍手感不变）与建筑碰撞。
const MASK_MELEE_BODY_RED: int = MASK_BLUE_MELEE | MASK_BUILDINGS  ## 2+4=6（红方近战：只撞蓝近战+建筑）
const MASK_MELEE_BODY_BLUE: int = MASK_RED_MELEE | MASK_BUILDINGS  ## 1+4=5（蓝方近战：只撞红近战+建筑）
## 远程单位的碰撞掩码：仅与双方远程 + 建筑碰撞（不含近战层）
## #6（2026-08-08）：拆分红/蓝两套，各自排除本方远程层——
## 与近战掩码同理，使同阵营远程互相穿透（仍由 _compute_ally_separation 柔性散开），
## 保留与敌方远程的碰撞（远程互射交战手感不变）与建筑碰撞。
const MASK_RANGED_BODY: int = MASK_RED_RANGED | MASK_BLUE_RANGED | MASK_BUILDINGS  ## 48+4=52（旧值，保留对照）
const MASK_RANGED_BODY_RED: int = MASK_BLUE_RANGED | MASK_BUILDINGS  ## 32+4=36（红方远程：只撞蓝远程+建筑，不撞己方红远程）
const MASK_RANGED_BODY_BLUE: int = MASK_RED_RANGED | MASK_BUILDINGS  ## 16+4=20（蓝方远程：只撞红远程+建筑，不撞己方蓝远程）
## 水晶专属碰撞层（#10 2026-08-08）：位值 64 = 第 7 层，此前所有掩码最多用到 52（第 6 层），不冲突。
## 水晶 collision_layer=64、collision_mask=0 → 兵种（掩码不含 64）不碰水晶，只有投射物掩码含 64 能命中它。
const MASK_CRYSTAL: int = 64  ## 水晶/基地专属层位值
## 红方检测区掩码：蓝方近战 + 蓝方远程 + 建筑
const MASK_DETECT_FOR_RED: int = MASK_BLUE_MELEE | MASK_BLUE_RANGED | MASK_BUILDINGS  ## 2+32+4=38
## 蓝方检测区掩码：红方近战 + 红方远程 + 建筑
const MASK_DETECT_FOR_BLUE: int = MASK_RED_MELEE | MASK_RED_RANGED | MASK_BUILDINGS  ## 1+16+4=21
## 投射物掩码：能命中所有单位层（近战 + 远程，双方）
const MASK_PROJECTILE_HIT: int = MASK_RED_MELEE | MASK_BLUE_MELEE | MASK_RED_RANGED | MASK_BLUE_RANGED  ## 51
