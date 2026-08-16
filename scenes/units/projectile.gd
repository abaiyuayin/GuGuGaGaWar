class_name Projectile  ## 定义全局类名 Projectile
extends Area2D  ## 继承 Area2D 区域节点
## 远程投射物脚本
## 直线飞行（无追踪），命中敌方单位后造成伤害
## 飞出战场范围或超时后自动销毁

## 飞行速度（像素/秒）
var speed: float = 600.0  ## 投射物飞行速度
## 投射物造成的伤害值
var damage: int = 0  ## 投射物伤害值
## 所属阵营编号（0=红方, 1=蓝方）
var team: int = 0  ## 阵营编号
## 目标单位引用（仅用于初始化方向，不追踪）
var target: Unit = null  ## 目标单位
## 攻击者单位引用（用于伤害计算和信号传递）
var attacker: Unit = null  ## 攻击者单位
## 是否已命中的标志，防止重复命中
var has_hit: bool = false  ## 已命中标志
## 飞行方向向量（发射时确定，之后不变）
var fly_direction: Vector2 = Vector2.ZERO  ## 飞行方向
## 生存计时器，超时后销毁
var lifetime: float = 0.0  ## 已存活时间
## 最大生存时间（秒），超过后销毁
const MAX_LIFETIME: float = 3.0  ## 最大生存时间
## 飞行物有效距离（像素），飞过此距离后销毁
var max_distance: float = 0.0  ## 有效距离，0 表示不限制
## 已飞行距离（像素）
var traveled_distance: float = 0.0  ## 已飞行距离
## 自定义飞行物贴图（可选，null 时使用默认方块）
var custom_texture: Texture2D = null  ## 自定义贴图
## 自定义贴图缩放倍率（0.1 = 缩小到 1/10；水晶发射的弹道 0.2 = 体积 ×2，由发射方设置）
var custom_scale: float = 0.1  ## 自定义贴图缩放
## 投射物携带的伤害列表（命中时按类型分别施加）
## 格式: [{"type": int, "value": int}, ...]
var carried_damage_entries: Array = []  ## 携带的伤害列表
## 投射物携带的词条列表（从攻击者复制，命中时施加给目标）
var carried_affixes: Array = []  ## 携带的词条列表
## 范围攻击半径（像素，0 表示无范围伤害）；>0 时命中后向四周敌人溅射同额伤害
var aoe_radius: float = 0.0  ## 范围攻击半径
## 是否为发光亮团外观（仅 F1 元素使启用，白色径向发光；所有投射物均直线飞行不追踪）
var is_glow_orb: bool = false  ## 发光亮团标志
## #15 自旋速度（度/秒），>0 时飞行途中持续旋转（D5 飞斧的翻滚效果）
var spin_speed: float = 0.0  ## 自旋速度
## #15 贴图朝向补偿（度），在「朝向飞行方向」的基础上再叠加（G5 标枪需 180°）
var rotation_offset_deg: float = 0.0  ## 朝向补偿角度

## 共享的纯色方块贴图（白色，通过 modulate 着色为红/蓝）
static var _crystal_texture: Texture2D = _create_crystal_texture()  ## 静态共享贴图
## 共享的白色径向渐变贴图（用于 F1 发光亮团）
static var _glow_texture: Texture2D = _create_glow_texture()  ## 静态发光贴图

## 创建纯色方块贴图（16x16 白色，运行时通过 modulate 着色）
static func _create_crystal_texture() -> Texture2D:  ## 定义创建贴图的静态方法
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)  ## 创建 16x16 图像
	img.fill(Color(1, 1, 1, 1))  ## 填充为纯白色
	var tex := ImageTexture.create_from_image(img)  ## 从图像创建贴图
	return tex  ## 返回创建的贴图

## 创建白色径向渐变贴图（用于 F1 发光亮团，中心亮白边缘透明）
static func _create_glow_texture() -> Texture2D:  ## 定义创建发光贴图的静态方法
	var size := 32  ## 贴图尺寸
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)  ## 创建图像
	var center := float(size) * 0.5  ## 中心坐标
	var radius := center  ## 半径
	img.fill(Color(0, 0, 0, 0))  ## 先填充透明
	for y in range(size):  ## 遍历像素
		for x in range(size):
			var dx := float(x) - center  ## X 偏移
			var dy := float(y) - center  ## Y 偏移
			var d := sqrt(dx * dx + dy * dy) / radius  ## 归一化距离
			if d <= 1.0:  ## 在圆内
				## 中心纯白，边缘渐变透明，使用 (1-d)^1.5 使光晕更集中
				var a: float = pow(1.0 - d, 1.5)  ## 透明度衰减
				img.set_pixel(x, y, Color(1, 1, 1, a))  ## 白色径向渐变
	var tex := ImageTexture.create_from_image(img)  ## 从图像创建贴图
	return tex  ## 返回贴图

## 初始化投射物
## dmg: 伤害值
## team_id: 所属阵营
## target_unit: 目标单位（仅用于确定初始飞行方向）
## attacker_unit: 攻击者单位
func setup(dmg: int, team_id: int, target_unit: Unit, attacker_unit: Unit) -> void:  ## 定义初始化方法
	damage = dmg  ## 保存伤害值
	team = team_id  ## 保存阵营
	target = target_unit  ## 保存目标（仅用于初始方向）
	attacker = attacker_unit  ## 保存攻击者
	_apply_texture()  ## 应用贴图

func _ready() -> void:  ## 重写 _ready 方法
	_apply_texture()  ## 应用贴图和颜色
	## #10（2026-08-08）：投射物掩码强制 = 常规命中层 + 水晶专属层。
	## 旧掩码 51（双方近战+远程）不含水晶层，而水晶 collision_layer=0 且 shape disabled，
	## 弹道物理上永远碰不到水晶 → 远程对水晶伤害路径完全断裂（箭射出去就完事）。
	## 现在水晶挂在 MASK_CRYSTAL（第 7 层），弹道掩码含该层后 body_entered 能检测到水晶，
	## 命中后走 projectile._hit_target → _damage_base_via_battlefield 正常结算。
	collision_mask = Constants.MASK_PROJECTILE_HIT | Constants.MASK_CRYSTAL
	## 连接碰撞信号：当投射物碰到物理体（CharacterBody2D 单位）时触发
	if not body_entered.is_connected(_on_body_entered):  ## 如果信号未连接
		body_entered.connect(_on_body_entered)  ## 连接碰撞信号
	## 注意：飞行方向不在此处计算，因为 add_child 后 global_position 尚未设置
	## 由 _spawn_projectile 在设置好位置后调用 init_direction() 计算

## 初始化飞行方向（在 add_child 并设置 global_position 之后调用）
func init_direction() -> void:  ## 定义初始化方向的方法
	## 此时 global_position 已是攻击单位的当前位置，计算朝向目标的方向
	if target != null and is_instance_valid(target):  ## 如果目标有效
		fly_direction = (target.global_position - global_position).normalized()  ## 朝向目标当前位置
	else:  ## 目标无效
		## 默认方向：红方向右，蓝方向左
		fly_direction = Vector2(1.0 if team == 0 else -1.0, 0.0)  ## 默认方向
	_apply_rotation()  ## 根据飞行方向旋转贴图

func _apply_texture() -> void:  ## 定义应用贴图的方法
	## 根据是否有自定义贴图选择贴图，并应用阵营颜色
	var sprite = get_node_or_null("Sprite2D")  ## 获取精灵节点
	if sprite == null:  ## 如果精灵节点不存在
		return  ## 直接返回
	if is_glow_orb:  ## F1 元素使：白色发光亮团
		sprite.texture = _glow_texture  ## 使用白色径向渐变贴图
		sprite.scale = Vector2(0.9, 0.9)  ## 光晕尺寸
		sprite.modulate = Color(1, 1, 1, 1)  ## 纯白色
		## 添加 PointLight2D 增强发光效果（仅添加一次）
		## Godot 4 的 PointLight2D 用 texture_scale 控制光照范围（无 range 属性）
		if get_node_or_null("GlowLight") == null:
			var light := PointLight2D.new()
			light.name = "GlowLight"
			light.texture = _glow_texture  ## 复用渐变贴图作为光纹理
			light.color = Color(1, 1, 1, 1)  ## 白色光
			light.energy = 1.2  ## 光能量
			light.texture_scale = 1.2  ## 光照范围缩放（替代 Godot 3 的 range）
			add_child(light)
		return  ## 发光亮团不染色不旋转
	if custom_texture != null:  ## 如果有自定义贴图（如箭矢/水晶缩小版）
		sprite.texture = custom_texture  ## 使用自定义贴图
		sprite.scale = Vector2(custom_scale, custom_scale)  ## 按发射方设定的缩放（水晶弹道 0.2 = 体积 ×2）
		sprite.modulate = Color(1, 1, 1, 1)  ## 保持原色不染色
	else:  ## 否则使用默认方块贴图
		sprite.texture = _crystal_texture  ## 设置共享纯色方块贴图
		sprite.scale = Vector2(1.2, 1.2)  ## 设置缩放，使方块更醒目
		if team == 0:  ## 如果是红方阵营
			sprite.modulate = Color(1.0, 0.2, 0.2)  ## 红方：鲜红色方块
		else:  ## 否则是蓝方阵营
			sprite.modulate = Color(0.2, 0.4, 1.0)  ## 蓝方：鲜蓝色方块

## 根据飞行方向旋转贴图（自定义贴图如箭矢需要朝向飞行方向）
func _apply_rotation() -> void:  ## 定义应用旋转的方法
	if custom_texture == null:  ## 默认方块无需旋转
		return  ## 直接返回
	var sprite = get_node_or_null("Sprite2D")  ## 获取精灵节点
	if sprite == null:  ## 如果精灵节点不存在
		return  ## 直接返回
	## 贴图默认朝上（-Y 方向，箭头在顶部），计算与飞行方向的夹角并旋转
	if fly_direction.length() > 0.01:  ## 如果方向有效
		## 贴图默认角度为 -90°（朝上），目标角度为飞行方向的角度
		var target_angle: float = fly_direction.angle()  ## 获取飞行方向角度（弧度）
		## #15：叠加朝向补偿（G5 标枪需 180°，让箭头朝后，飞行体朝前）
		sprite.rotation = target_angle + PI / 2.0 + deg_to_rad(rotation_offset_deg)  ## 加 90° 补偿贴图默认朝上 + 补偿角

## 物理帧处理，每帧按直线更新投射物位置
## delta: 上一帧到当前帧的时间间隔（秒）
func _physics_process(delta: float) -> void:  ## 重写物理帧方法
	## 如果已经命中，停止处理
	if has_hit:  ## 如果已命中
		return  ## 直接返回

	## 生存计时，超时销毁
	lifetime += delta  ## 累加生存时间
	if lifetime > MAX_LIFETIME:  ## 如果超过最大生存时间
		queue_free()  ## 销毁投射物
		return  ## 直接返回

	## 飞行逻辑：所有投射物均按发射时确定的方向（init_direction）直线飞行，不追踪目标
	if fly_direction.length() > 0.01:  ## 如果方向有效
		var move_vec: Vector2 = fly_direction * speed * delta  ## 本帧位移
		global_position += move_vec  ## 移动
		traveled_distance += move_vec.length()  ## 累加已飞行距离
		## #15：飞行途中持续自旋（D5 飞斧翻滚效果），自旋叠加在基础朝向上
		if spin_speed > 0.0:  ## 仅当配置了自旋速度时旋转
			var spin_sprite = get_node_or_null("Sprite2D")  ## 获取精灵节点
			if spin_sprite != null:  ## 精灵存在时累加旋转
				spin_sprite.rotation += deg_to_rad(spin_speed) * delta
		## 飞行物有效距离检查：超过有效距离后销毁
		if max_distance > 0.0 and traveled_distance >= max_distance:  ## 超过有效距离
			queue_free()  ## 销毁投射物
			return  ## 直接返回

## 命中目标的处理方法（私有）
func _hit_target(hit_unit: Unit) -> void:  ## 定义命中目标的方法
	## 如果已经命中，避免重复处理
	if has_hit:  ## 如果已命中
		return  ## 直接返回
	has_hit = true  ## 标记为已命中

	## 攻击者可能已被释放（如开发工具「清空对面兵种」freed 了发射单位），
	## 此时把 freed 引用传入 take_damage_typed 会触发
	## "argument 3 (previously freed) not subclass of expected argument class" 报错（#139）。
	## 用有效性校验保护：freed 时降级为 null，伤害照常结算，仅丢失击杀归属来源。
	var valid_attacker: Unit = attacker if (attacker != null and is_instance_valid(attacker)) else null

	## 如果命中的单位有效且存活，造成伤害
	if hit_unit != null and is_instance_valid(hit_unit) and not hit_unit.is_dead:  ## 如果命中单位有效且存活
		## #7：命中基地/水晶时必须经 battlefield.damage_base 结算。
		## 直接 take_damage_typed 会绕过 red/blue_base_hp 同步与 base_damaged/base_hp_changed 信号，
		## 导致 HUD 水晶血量与实际耐久脱节（表现为「掉血数字对不上」）。
		if hit_unit.is_base_unit and _damage_base_via_battlefield(hit_unit, valid_attacker):
			_play_hit_fx()
			return
		## 按伤害列表分别施加（支持多伤害类型）
		if not carried_damage_entries.is_empty():
			for entry in carried_damage_entries:
				hit_unit.take_damage_typed(int(entry["value"]), int(entry["type"]), valid_attacker)
		else:
			## 兼容旧接口：无伤害列表时用单一伤害（默认挥砍）
			hit_unit.take_damage(damage, valid_attacker)
		## 施加投射物携带的词条效果（如流血）
		if not carried_affixes.is_empty():
			for affix in carried_affixes:
				if affix != null and affix.trigger_timing == AffixResource.TriggerTiming.ON_ATTACK:
					hit_unit.apply_affix(affix, valid_attacker)
		## 范围攻击：向命中点周围敌人溅射同额伤害（不含主目标）
		if aoe_radius > 0.0 and valid_attacker != null and valid_attacker.has_method("_apply_aoe"):
			valid_attacker._apply_aoe(global_position, hit_unit, carried_damage_entries)

	_play_hit_fx()  ## 播放命中消失动画并销毁

## 命中基地/水晶时，把伤害交给 battlefield.damage_base 结算
## 返回 true 表示已成功走基地结算通道（调用方不应再走常规单位伤害）
func _damage_base_via_battlefield(base_unit: Unit, valid_attacker: Unit) -> bool:
	var battlefield: Node = base_unit.get_parent()  ## 基地单位挂在 UnitContainer 下
	if battlefield != null:
		battlefield = battlefield.get_parent()  ## 再上一层才是 Battlefield
	if battlefield == null or not battlefield.has_method("damage_base"):
		return false  ## 找不到战场则退回常规伤害逻辑
	## 汇总本次携带的全部伤害（基地只有单一耐久池，不区分伤害类型）
	var total: int = 0
	for entry in carried_damage_entries:
		total += int(entry["value"])
	if total <= 0:
		total = damage  ## 兼容旧接口：无伤害列表时用单一伤害
	if total <= 0:
		return false
	## #13：中远程兵种（is_ranged_override=1）对水晶伤害减半
	if valid_attacker != null and valid_attacker.unit_resource != null and valid_attacker.unit_resource.is_ranged_override == 1:
		total = maxi(1, total / 2)
	battlefield.damage_base(base_unit.team, total, valid_attacker)
	return true

## 播放命中消失动画（0.1 秒缩放归零后销毁）
func _play_hit_fx() -> void:
	var sprite = get_node_or_null("Sprite2D")  ## 获取精灵节点
	if sprite:  ## 如果精灵节点存在
		var tween = create_tween()  ## 创建补间动画
		tween.tween_property(sprite, "scale", Vector2(0, 0), 0.1)  ## 缩放为 0
		## 动画完成后销毁投射物
		tween.tween_callback(queue_free)  ## 动画结束后销毁
	else:  ## 否则没有精灵节点
		queue_free()  ## 直接销毁

## 碰撞检测回调
## 当投射物碰到物理体（单位 CharacterBody2D）时调用
## body: 碰撞到的物理体节点
func _on_body_entered(body: Node2D) -> void:  ## 定义碰撞回调方法
	## 如果已经命中，不再处理碰撞
	if has_hit:  ## 如果已命中
		return  ## 直接返回
	## 如果是敌方且存活的单位，命中
	if body is Unit and body.team != team and not body.is_dead:  ## 如果是敌方存活单位
		_hit_target(body)  ## 命中目标
