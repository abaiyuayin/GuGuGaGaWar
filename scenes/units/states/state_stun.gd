extends UnitState  ## 继承单位状态基类
## 晕眩状态（#需求6）
## 由击退效果累计触发：兵种被击退命中时累计 1 层晕眩值，满 3 层进入本状态。
## 持续 Constants.STUN_DURATION（2 秒），期间不可移动、不可攻击：
##   - velocity 恒为 0，仅保留 move_and_slide 以维持被推挤时的物理碰撞表现
##   - 不执行任何索敌 / 追击 / 攻击逻辑（状态机单例，切到 stun 后只有本状态 update 运行）
##   - 晕眩中再被击退命中不产生位移、不累计层数（见 unit_base.apply_affix）
## 结束后进入 Constants.STUN_IMMUNE_DURATION（5 秒）免疫期（由 unit_base 物理帧递减），
## 免疫期结束后重新从 0 累计晕眩值。

## 进入晕眩状态时调用
func enter() -> void:  ## 重写进入状态方法
	## 播放待机动画（无 idle 用 move 兜底，避免动画卡在攻击帧）
	if unit.anim_idle_frames != null:
		unit.play_anim("idle")
	else:
		unit.play_anim("move")
	unit.velocity = Vector2.ZERO  ## 速度归零
	## 打断残留的击退位移：晕眩中不应再被推走
	unit._knockback_velocity = Vector2.ZERO
	unit._knockback_timer = 0.0

## 晕眩状态的每帧更新
## delta: 上一帧到当前帧的时间间隔（秒）
func update(delta: float) -> void:  ## 重写每帧更新方法
	if unit == null or not is_instance_valid(unit):  ## 宿主已失效
		return
	if unit.is_dead:  ## 已死亡（由 die() 切走状态）
		return
	unit.stun_timer -= delta  ## 递减晕眩剩余时间
	unit.velocity = Vector2.ZERO  ## 保持静止
	unit.move_and_slide()  ## 仍走一次碰撞系统，保持被推挤时的物理表现
	if unit.stun_timer <= 0.0:  ## 晕眩结束
		unit.stun_timer = 0.0  ## 归零（递减可能越过 0，归零保证「>0=晕眩中」不变量一致）
		unit.stun_immune_timer = Constants.STUN_IMMUNE_DURATION  ## 进入免疫期
		unit.change_state(unit.get_idle_state_name())  ## 回到默认状态（move 推进 / guard 护晶）
