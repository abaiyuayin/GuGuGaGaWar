extends UnitState  ## 继承单位状态基类
## 死亡状态
## 单位死亡后的处理状态
## 优先播放兵种专属死亡动画（death_frames.tres，#9），无则回退到跳起掉出屏幕的 tween

## 死亡动画计时器
var death_timer: float = 0.0  ## 死亡动画计时器
## 死亡动画持续时间（秒）
var death_duration: float = 0.5  ## 死亡动画持续时间

## 进入死亡状态时调用
func enter() -> void:  ## 重写进入状态方法
	## 标记单位已死亡并禁用碰撞/检测
	unit.is_dead = true  ## 标记为已死亡
	unit.set_collision_layer_value(1, false)  ## 禁用碰撞层 1（红方近战）
	unit.set_collision_layer_value(2, false)  ## 禁用碰撞层 2（蓝方近战）
	## #9 拆层后远程单位在第 5/6 层，死亡时同样要下线，否则尸体仍会阻挡己方远程
	unit.set_collision_layer_value(5, false)  ## 禁用碰撞层 5（红方远程）
	unit.set_collision_layer_value(6, false)  ## 禁用碰撞层 6（蓝方远程）
	var detection = unit.get_node_or_null("DetectionArea")  ## 获取检测区域节点
	if detection:  ## 如果检测区域存在
		detection.monitoring = false  ## 关闭检测区域监控

	## #闪退修复（2026-08-21）：单位可能已脱离场景树（上一局的 2s 兜底回收定时器把
	## 复用单位中途拽回池 / 场景切换竞态），此时 get_tree() 返回 null，
	## 直接 create_timer 会报「Cannot call method 'create_timer' on a null value」并闪退。
	## 树外单位无需死亡演出，直接回收（recycle_unit 幂等：已在池中会被跳过）。
	if not unit.is_inside_tree():
		BattleManager.recycle_unit(unit)
		return

	## #9：优先播放兵种专属死亡动画（死亡使者 Death_1~10：站立→弯腰→下跪→躺平）
	## 播完停在最后一帧（躺平），配合下方淡出与强制回收完成销毁。
	## 其他兵种没有 death_frames → 回退到旧的「跳起+掉出屏幕」tween（优雅降级）。
	if unit.anim_death_frames != null and unit.unit_sprite != null:
		_play_death_anim()
	else:
		_play_legacy_fall_tween()

	## #8 兜底：本应靠 update() 里的死亡计时器兜底销毁，但 unit_base._physics_process 在
	## is_dead 时提前 return，state_die.update() 实际已不可达；一旦上方死亡补间被打断
	##（场景切回 / 节点被移出树等），单位就会卡成「已死亡 + 精灵透明」的僵尸（变虚卡死）。
	## 这里用挂在场景树上的定时器做与物理帧无关的强制回收：无论补间是否完成、单位是否仍在树中，
	## 超时后只要实例仍有效且尚未入销毁队列就回收进对象池（2026-08-18 性能优化：替代 queue_free）。
	var cleanup_timer := unit.get_tree().create_timer(2.0)
	cleanup_timer.timeout.connect(func() -> void:
		## #闪退修复（2026-08-21）：加 is_dead 防护——单位若在 2s 内被对象池复用
		##（setup() 会复位 is_dead=false 并重新入列 player_units/enemy_units），
		## 该陈旧定时器若照旧回收，会把正在战斗的复用单位中途拽回池：单位凭空消失、
		## 且仍残留在 BattleManager 列表里成为「树外幽灵」，后续 freeze_units()
		## 的 change_state("idle") 会再次触树外 create_timer 闪退。
		if is_instance_valid(unit) and unit.is_dead and not unit.is_queued_for_deletion():
			BattleManager.recycle_unit(unit)
	)

## 播放兵种专属死亡动画（#9）
## 切换 sprite_frames 到 death 帧、按 death_display 适配缩放、不循环播一遍，
## 动画后半段开始淡出（10 帧 @10fps = 1s，delay 0.6s 后 0.4s 淡完）。
func _play_death_anim() -> void:  ## 播放死亡动画
	unit.unit_sprite.sprite_frames = unit.anim_death_frames  ## 切换到死亡帧
	unit.unit_sprite.play("death")  ## 播放死亡动画（loop=false，播完停最后一帧）
	unit.unit_sprite.speed_scale = 1.0  ## 按 SpriteFrames 自带速度播放（10fps）
	unit._apply_anim_scale(unit.anim_death_frames, "death")  ## 按 death_display 适配显示尺寸
	## 动画后半段淡出（#9：死亡演出末端渐隐，避免尸体闪烁后突然消失）
	var fade := unit.create_tween()  ## 创建淡出动画
	fade.tween_property(unit.unit_sprite, "modulate:a", 0.0, 0.4).set_delay(0.6)  ## 延迟 0.6s 后 0.4s 淡完

## 旧死亡演出回退：先向上跳一下，再向下掉出屏幕（无 death 帧的兵种）
func _play_legacy_fall_tween() -> void:  ## 旧跳落补间
	var start_y = unit.position.y  ## 记录起始 Y 坐标
	var tween = unit.create_tween()  ## 创建补间动画
	tween.tween_property(unit, "position:y", start_y - 40.0, 0.2)  ## 先向上跳 40 像素
	tween.tween_property(unit, "position:y", start_y + 900.0, 0.6)  ## 再向下掉出屏幕
	tween.tween_callback(func() -> void:
		## 回收到对象池（2026-08-18 性能优化：替代 queue_free）
		## #闪退修复（2026-08-21）：is_dead 防护同 2s 兜底定时器——单位在 0.8s 内被
		## 对象池复用（is_dead 已被 setup 复位）时，本补间不得把它中途拽回池。
		if is_instance_valid(unit) and unit.is_dead and not unit.is_queued_for_deletion():
			BattleManager.recycle_unit(unit)
	)

	## 兼容旧的淡出效果（如有 Sprite2D）
	var sprite = unit.get_node_or_null("Sprite2D")  ## 获取精灵节点
	if sprite:  ## 如果精灵节点存在
		var fade = unit.create_tween()  ## 创建淡出动画
		fade.tween_property(sprite, "modulate:a", 0.0, death_duration)  ## 透明度渐变为 0

## 死亡状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(delta: float) -> void:  ## 重写每帧更新方法
	## 单位已被释放或已在释放队列中时，避免重复调用 queue_free
	if unit == null or not is_instance_valid(unit) or unit.is_queued_for_deletion():
		return
	## 累加死亡计时器
	death_timer += delta  ## 计时器累加
	## 如果死亡动画播放完毕
	if death_timer >= death_duration:  ## 如果达到持续时间
		## #对象池（2026-08-20）：原先此处 queue_free 会绕过对象池把实例销毁掉。
		## 该分支当前实际不可达（unit_base._physics_process 在 is_dead 时提前 return，
		## update 不会被调用，回收由本文件的 tween 回调与 2s 兜底 timer 负责），
		## 但留着 queue_free 是隐患——一旦有人放开那个早退，池就会被这里悄悄抽干。
		BattleManager.recycle_unit(unit)  ## 回收到对象池（与另两条回收路径保持一致）
