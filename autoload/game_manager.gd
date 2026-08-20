extends Node  ## 继承自 Node 节点类
## 游戏管理器（全局单例）
## 负责管理整个游戏的流程状态，包括主菜单、战斗、游戏结束等状态的切换

## 游戏流程状态枚举，定义游戏可能处于的三种状态
enum GameState {
	MAIN_MENU,  ## 主菜单状态
	BATTLE,     ## 战斗进行状态
	GAME_OVER,  ## 游戏结束状态
	ROGUELIKE_MAP,  ## 肉鸽模式地图 hub 状态
	BATTLEFIELD_MODE,  ## 战场模式（RTS 沙盒：无敌人/无胜负，自由放置与指挥兵种）
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
## 是否为战场模式（RTS 沙盒：无敌人/无胜负，左右两列兵种都出我方的兵），默认 false
var is_battlefield_mode: bool = false
## 当前选中的战役关卡编号
var selected_campaign_level: int = 1

## 加载进度遮罩（运行时挂载，见 _ready）
const LOADING_OVERLAY_SCRIPT := preload("res://scenes/ui/loading_overlay.gd")
var loading_overlay: CanvasLayer = null

func _ready() -> void:
	## 挂载加载遮罩（autoload 场景之外，保证任何场景切换都存在）
	loading_overlay = LOADING_OVERLAY_SCRIPT.new()
	add_child(loading_overlay)

## 带加载遮罩的场景切换：显示随机提示词+兵种动画，异步加载完成后切换
## 2026-08-18 新增（用户拍板：需要长时间加载的地方都用）
func change_scene_with_loading(scene_path: String) -> void:
	if loading_overlay != null and loading_overlay.has_method("show_loading"):
		loading_overlay.show_loading(scene_path)
	else:
		get_tree().change_scene_to_file(scene_path)  ## 兜底：无遮罩直接切

## 切换游戏状态的方法
## new_state: 要切换到的目标状态（GameState 枚举值）
## skip_loading: 是否跳过加载提示框（true 时直接切场景）。
##   2026-08-19 新增（用户拍板：玩家启动游戏进主菜单时只要开屏动画，不要加载框）；
##   仅 main.gd 开屏结束的那一次传 true，其余入口保持弹框。
func change_state(new_state: GameState, skip_loading: bool = false) -> void:
	current_state = new_state  ## 更新当前状态变量
	## 离开战斗类场景时清空对象池：池中休眠单位释放纹理/碰撞体等 RID 内存，
	## 避免旧电脑多局累积卡死（2026-08-18 性能优化）
	if new_state == GameState.MAIN_MENU or new_state == GameState.ROGUELIKE_MAP:
		BattleManager.clear_unit_pool()
	## 使用 match 语句根据新状态执行不同的场景切换逻辑
	match current_state:
		GameState.MAIN_MENU:  ## 切换到主菜单状态
			## 加载主菜单场景文件（skip_loading 时不弹加载框，仅开屏结束那一次）
			if skip_loading:
				get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
			else:
				change_scene_with_loading("res://scenes/ui/main_menu.tscn")
		GameState.BATTLE:  ## 切换到战斗状态
			## 加载战斗根场景文件（带进度遮罩）
			change_scene_with_loading("res://scenes/battle/battle_root.tscn")
		GameState.GAME_OVER:  ## 切换到游戏结束状态
			## 游戏结束画面作为叠加层显示，不切换场景
			pass
		GameState.ROGUELIKE_MAP:  ## 切换到肉鸽模式地图 hub
			## 加载肉鸽地图总控台场景（带进度遮罩）
			change_scene_with_loading("res://scenes/ui/roguelike_meta.tscn")
		GameState.BATTLEFIELD_MODE:  ## 切换到竞技场模式（原战场模式）
			## 加载竞技场模式场景（带进度遮罩）
			change_scene_with_loading("res://scenes/battle/battlefield_mode.tscn")

## 开始新游戏的方法
## difficulty: 选择的游戏难度（入口不同语义不同——主菜单 0=简单/1=普通/2=困难；战役 0=普通/1=困难/2=地狱）
func start_game(difficulty: int = 1) -> void:
	current_difficulty = difficulty  ## 保存当前选择的难度
	winner = -1  ## 重置胜者为无
	is_battlefield_mode = false  ## 进入常规战斗，关闭战场模式标志
	change_state(GameState.BATTLE)  ## 切换到战斗状态

## 进入战场模式（RTS 沙盒）：无敌人、无胜负、无经济，纯放置与指挥
func start_battlefield() -> void:
	winner = -1  ## 重置胜者
	is_battlefield_mode = true  ## 打开战场模式标志（HUD 布局 / 出兵路由都据此分流）
	change_state(GameState.BATTLEFIELD_MODE)  ## 切换到战场模式场景

## 返回主菜单的方法
func return_to_menu() -> void:
	is_battlefield_mode = false  ## 离开战场模式，恢复常规标志
	change_state(GameState.MAIN_MENU)  ## 切换到主菜单状态

## 进入肉鸽模式地图 hub（战役地图「肉鸽模式」在 start_run() 后调用）
func enter_roguelike_map() -> void:
	change_state(GameState.ROGUELIKE_MAP)  ## 切换到肉鸽地图 hub 状态

## 游戏结束的方法
## winner_team: 获胜方的阵营编号（0=红方, 1=蓝方）
func end_game(winner_team: int) -> void:
	winner = winner_team  ## 记录获胜方
	change_state(GameState.GAME_OVER)  ## 切换到游戏结束状态
