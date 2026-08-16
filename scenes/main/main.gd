extends Node  ## 继承 Node，作为场景根节点
## 入口场景脚本
## 游戏启动后的第一个场景，负责跳转到主菜单

## 节点就绪时自动调用
func _ready() -> void:
	## 直接切换到主菜单状态
	## GameManager 会处理具体的场景加载
	GameManager.change_state.call_deferred(GameManager.GameState.MAIN_MENU)  ## 延迟调用游戏管理器切换到主菜单状态
