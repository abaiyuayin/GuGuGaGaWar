extends Node2D
## 通用绘制代理层
## 把实际绘制逻辑委托给外部 Callable，便于把「网格」画在战场背景之上/单位之下，
## 把「框选矩形 / 选中椭圆」画在战场之上（不同 z 层级），而无需为每个层单独写脚本。

## 绘制回调：由战场控制器在 _ready 中赋值（传入自身的方法引用）
var draw_func: Callable = Callable()

func _draw() -> void:
	if draw_func.is_valid():
		draw_func.call()
