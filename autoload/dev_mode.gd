extends Node
## 开发者模式开关 —— 全局单例
##
## 生命周期：随游戏启动常驻。开启后，图鉴进入可编辑描述状态，
##   文物/军令/事件图鉴、开发工具按钮等开发者专属 UI 可见。
## 持久化：状态写入 user://dev_mode.cfg，下次启动自动恢复，
##   关闭后所有开发者专属 UI 一律隐藏；F12 局内按钮栏显隐标志同样持久化（2026-08-15）。
## 开关方式：图鉴 G1 页 abay 秘技 / 图鉴 G1 待机按钮连按 7 次 / 主菜单「控制台」按钮。
## （F11 快捷键已于 2026-08-23 隐藏，不再用于开关开发者模式。）

## 开发者模式开关状态变化时发出
signal dev_mode_changed(enabled: bool)
## 局内上方按钮整排（TopCenterButtons）显隐状态变化时发出（hidden=true 表示已隐藏）
signal hide_in_battle_top_buttons_changed(hidden: bool)

const SAVE_PATH: String = "user://dev_mode.cfg"  ## 状态持久化文件

var enabled: bool = false  ## 当前是否处于开发者模式
## 开发者无限金币（#需求2）：敌我购买兵种与升级人口/收入都不扣金币。
## 仅本次运行内保留（不持久化）；F11 关开发者模式不重置本开关。
var infinite_gold: bool = false
## 开发者出兵限制（#11）：开启后玩家方每次出兵严格只出 1 个（AI 不受影响）。
## 仅本次运行内保留（不持久化）；与 infinite_gold 一致。
var single_spawn: bool = false
## 开发者模式 F12 快捷键目标：是否隐藏局内上方按钮整排（TopCenterButtons）。
## 全局生效——在主菜单按 F12 也能预隐藏，进入战斗后自动套用；主菜单自身按钮不受影响。
## 持久化：与 enabled 一并写入 user://dev_mode.cfg（2026-08-15 修正：关闭重开窗口不重置按钮状态）。
var _hide_in_battle_top_buttons: bool = false
var hide_in_battle_top_buttons: bool:
	get:
		return _hide_in_battle_top_buttons
	set(v):
		if _hide_in_battle_top_buttons == v:
			return
		_hide_in_battle_top_buttons = v
		_save_state()
		hide_in_battle_top_buttons_changed.emit(v)

func _ready() -> void:
	_load_state()

## 设置开发者模式开关，状态变化才写盘并发信号
func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	_save_state()
	dev_mode_changed.emit(enabled)
	## #16（2026-08-11）：开启开发者模式自动解锁隐藏成就「上帝模式」
	## （unlock 内部去重，重复开启不会重复发星/弹窗）
	if enabled:
		Achievements._try_unlock("god_mode")

## 翻转当前开关
func toggle() -> void:
	set_enabled(not enabled)

## 设置开发者无限金币开关（#需求2），切换时打印提示；状态仅本次运行内保留
func set_infinite_gold(value: bool) -> void:
	if infinite_gold == value:
		return
	infinite_gold = value
	print("[调试] 无限金币（敌我购买/升级免费）: ", "开" if infinite_gold else "关")

## 设置开发者出兵限制开关（#11），切换时打印提示；状态仅本次运行内保留
## 开启后玩家方（player_id 0 / 双人模式双方）批量出兵强制每次只出 1 个，AI 不受影响
func set_single_spawn(value: bool) -> void:
	if single_spawn == value:
		return
	single_spawn = value
	print("[调试] 出兵限制（玩家每次只出1个）: ", "开" if single_spawn else "关")

## 全局快捷键 F11（开发者模式切换）已隐藏（2026-08-23 用户要求）：
## F11 不再开关开发者模式，避免玩家误触。仍保留 图鉴 G1 页 abay 秘技 /
## G1 待机按钮连按 7 次 / 主菜单「控制台」按钮 作为补充入口。
# func _unhandled_input(event: InputEvent) -> void:
# 	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
# 		get_viewport().set_input_as_handled()
# 		toggle()

func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		enabled = bool(cfg.get_value("dev", "enabled", false))
		_hide_in_battle_top_buttons = bool(cfg.get_value("dev", "hide_in_battle_top_buttons", false))

func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("dev", "enabled", enabled)
	cfg.set_value("dev", "hide_in_battle_top_buttons", _hide_in_battle_top_buttons)
	if cfg.save(SAVE_PATH) != OK:
		push_error("DevMode: 无法写入 %s。" % SAVE_PATH)
