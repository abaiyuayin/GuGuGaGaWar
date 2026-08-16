extends UnitState  ## 继承单位状态基类
## 空闲状态
## 单位刚生成或目标丢失时的短暂等待状态
## 等待一小段时间后自动切换到移动状态

## 计时器引用，退出 idle 状态时销毁，防止残留计时器在非 idle 状态下触发状态切换
var _idle_timer: SceneTreeTimer = null

## 进入空闲状态时调用
func enter() -> void:  ## 重写进入状态方法
	unit.play_anim("idle")  ## 播放空闲动画
	unit.velocity = Vector2.ZERO  ## 速度归零
	## AI 禁用时不自动切换状态（用于调试模拟）
	if unit.ai_disabled:
		return
	## 创建一个 0.1 秒的计时器
	_idle_timer = unit.get_tree().create_timer(0.1)  ## 创建一次性计时器
	## 计时器超时后，切换到移动状态
	## 使用匿名函数连接信号，避免创建额外的方法
	_idle_timer.timeout.connect(func(): 
		## 计时器期间可能被设为 ai_disabled，再次检查
		if unit != null and is_instance_valid(unit) and not unit.ai_disabled:
			## 战斗已结束则不再切换状态（防止胜负已分后单位恢复移动）
			if BattleManager.is_battle_active:
				unit.change_state("move")
	)  ## 超时后切换到移动状态

## 退出空闲状态时调用，销毁计时器防止残留
func exit() -> void:
	_idle_timer = null  ## 释放计时器引用，Godot 自动清理超时的 SceneTreeTimer

## 空闲状态的每帧更新（当前为空实现）
## _delta: 上一帧到当前帧的时间间隔（秒）
func update(_delta: float) -> void:  ## 重写每帧更新方法（空实现）
	pass  ## 空实现，不做任何事
