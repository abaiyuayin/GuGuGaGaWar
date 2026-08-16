extends Node  ## 继承自 Node 节点类
## 游戏管理器（全局单例）
## 负责管理整个游戏的流程状态，包括主菜单、战斗、游戏结束等状态的切换

## 游戏流程状态枚举，定义游戏可能处于的三种状态
enum GameState {
	MAIN_MENU,  ## 主菜单状态
	BATTLE,     ## 战斗进行状态
	GAME_OVER,  ## 游戏结束状态
	ROGUELIKE_MAP,  ## 肉鸽模式地图 hub 状态
}

## 当前游戏状态变量，初始值为 MAIN_MENU（主菜单）
var current_state: GameState = GameState.MAIN_MENU
## 当前游戏难度变量，默认普通。
## 注意：难度语义随入口不同——主菜单自由模式 0=简单/1=普通/2=困难；
## 战役模式 0=普通/1=困难/2=地狱（campaign_map 直接透传）。AI 策略与成就判定均已按入口分流。
var current_difficulty: int = 1
## 当前游戏胜者变量（0=红方/玩家, 1=蓝方/AI, -1=无/未结束），初始无胜者
var winner: int = -1
## 是否为战役模式（开始游戏按钮进入），默认 false
var is_campaign_mode: bool = false
## 当前选中的战役关卡编号
var selected_campaign_level: int = 1

## 切换游戏状态的方法
## new_state: 要切换到的目标状态（GameState 枚举值）
func change_state(new_state: GameState) -> void:
	current_state = new_state  ## 更新当前状态变量
	## 使用 match 语句根据新状态执行不同的场景切换逻辑
	match current_state:
		GameState.MAIN_MENU:  ## 切换到主菜单状态
			## 加载主菜单场景文件
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		GameState.BATTLE:  ## 切换到战斗状态
			## 加载战斗根场景文件
			get_tree().change_scene_to_file("res://scenes/battle/battle_root.tscn")
		GameState.GAME_OVER:  ## 切换到游戏结束状态
			## 游戏结束画面作为叠加层显示，不切换场景
			pass
		GameState.ROGUELIKE_MAP:  ## 切换到肉鸽模式地图 hub
			## 加载肉鸽地图总控台场景
			get_tree().change_scene_to_file("res://scenes/ui/roguelike_meta.tscn")

## 开始新游戏的方法
## difficulty: 选择的游戏难度（入口不同语义不同——主菜单 0=简单/1=普通/2=困难；战役 0=普通/1=困难/2=地狱）
func start_game(difficulty: int = 1) -> void:
	current_difficulty = difficulty  ## 保存当前选择的难度
	winner = -1  ## 重置胜者为无
	change_state(GameState.BATTLE)  ## 切换到战斗状态

## 返回主菜单的方法
func return_to_menu() -> void:
	change_state(GameState.MAIN_MENU)  ## 切换到主菜单状态

## 进入肉鸽模式地图 hub（战役地图「肉鸽模式」在 start_run() 后调用）
func enter_roguelike_map() -> void:
	change_state(GameState.ROGUELIKE_MAP)  ## 切换到肉鸽地图 hub 状态

## 游戏结束的方法
## winner_team: 获胜方的阵营编号（0=红方, 1=蓝方）
func end_game(winner_team: int) -> void:
	winner = winner_team  ## 记录获胜方
	change_state(GameState.GAME_OVER)  ## 切换到游戏结束状态
