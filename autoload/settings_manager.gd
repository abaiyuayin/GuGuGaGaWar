extends Node  ## 继承 Node，作为全局单例节点存在
## 设置管理器（全局单例）
## 管理游戏设置：窗口模式、语言、音频等

signal settings_changed  ## 设置变更信号，当任意设置被修改时发出

const WINDOW_MODE_WINDOWED = 0  ## 窗口模式常量：普通窗口模式
const WINDOW_MODE_FULLSCREEN = 1  ## 窗口模式常量：全屏模式
const WINDOW_MODE_BORDERLESS = 2  ## 窗口模式常量：无边框窗口模式

## BGM 名称到资源路径的映射表（"默认"表示使用游戏自带默认 BGM，"无"表示不播放）
const BGM_PATHS: Dictionary = {
	"默认": "",
	"Medieval Vol.2": "res://assets/audio/bgm/medieval2.mp3",
	"Falling Apart": "res://assets/audio/bgm/falling_apart.mp3",
	"Decisive Battle": "res://assets/audio/bgm/decisive_battle.mp3",
	"The Calm Before The Storm": "res://assets/audio/bgm/calm_before_storm.mp3",
	"Victory!": "res://assets/audio/bgm/victory.wav",
}

var window_mode: int = WINDOW_MODE_WINDOWED  ## 当前窗口模式，默认为普通窗口
var language: String = "zh"  ## 当前语言，默认为中文
var master_volume: float = 0.8  ## 主音量（0.0~1.0），默认 0.8
var music_volume: float = 0.7  ## 音乐音量（0.0~1.0），默认 0.7
var sfx_volume: float = 0.5  ## 音效音量（0.0~1.0），默认 0.5（设置界面显示为 50）
var show_damage_numbers: bool = true  ## 是否显示伤害量文本，默认开启
var show_hp_armor_bar: bool = false  ## #16：是否在血条居中显示血量/护盾数值，默认关闭（玩家可在设置中打开；2026-08-18 用户拍板）
var touch_controls: bool = false  ## 移动端触屏输入层开关：安卓/iOS 导出时由 OS.has_feature("mobile") 自动启用，桌面可手动开以便测试
var audio_throttle: bool = false  ## #4：音频节流开关（默认关闭）。开启=现在的并发限制播放方式；关闭=以前的触发即播、无限制（2026-08-18 用户拍板默认关闭）

## #17：单条音效文件音量表（res:// 音频路径 -> 0.0~1.0，缺省按 1.0 满音量）
## 由音效配置页「调整」视图的每个音效拖动条维护，播放时叠乘到 SFX 总线音量之上
var sound_volumes: Dictionary = {}

## 背景音乐设置
var menu_bgm: String = "默认"  ## 主菜单BGM名称
var battle_bgm: String = "默认"  ## 战斗BGM名称
var victory_bgm: String = "默认"  ## 胜利BGM名称（"无"=不播放）
var defeat_bgm: String = "默认"  ## 失败BGM名称（"无"=不播放）

## 兵种音效配置
## 结构：{ "G1": { "click_sound": "res://path", "spawn_sound": "res://path", "spawn_rules": [{ "type": 0, "count": 1 }, ...] }, ... }
## spawn_rules: 出兵音效规则列表，可同时配置多条，每条独立判断触发
##   type: 0=每次出兵都播放, 1=同时出N兵时播放, 2=累计出N兵时播放
##   count: 规则N值（同时出N兵或累计出N兵的N）
var unit_sound_configs: Dictionary = {}

## 音效归属类型：音频路径 -> "shared" / "G" / "D" / "F" / "N"
## 用于"音效专享"：被标记为某阵营专属的音效，仅该阵营兵种的下拉可选（编辑功能见 #101）
var sound_attribution: Dictionary = {}

## 音效库排序：控制台"音效管理"面板中用户手动拖动排序后的音频路径顺序
## 仅记录顺序，不代表文件是否存在；扫描时以实际文件为准，本表用于排序优先级
var sound_library_order: Array[String] = []

var _initialized: bool = false  ## 是否已初始化完成标志
var _windowed_size: Vector2i = Vector2i(1280, 720)  ## 窗口模式下记录的窗口尺寸，用于切换时恢复

func _ready() -> void:  ## 节点就绪时自动调用
	_load_settings()  ## 从配置文件加载设置
	## 启动时若处于窗口模式，记录当前窗口尺寸，便于后续切换恢复
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		_windowed_size = DisplayServer.window_get_size()
	_apply_settings()  ## 应用所有设置
	_initialized = true  ## 标记初始化完成

func _load_settings() -> void:  ## 从配置文件加载设置（私有方法）
	var cfg = ConfigFile.new()  ## 创建配置文件对象
	var err = cfg.load("user://settings.cfg")  ## 加载用户目录下的设置文件
	if err != OK:  ## 如果加载失败（如文件不存在）
		return  ## 直接返回，使用默认值

	if cfg.has_section_key("window", "mode"):  ## 如果配置中存在窗口模式键
		window_mode = cfg.get_value("window", "mode")  ## 读取窗口模式
	if cfg.has_section_key("language", "current"):  ## 如果配置中存在语言键
		language = cfg.get_value("language", "current")  ## 读取语言
		## #9（2026-08-09）：删除美式/英式英语后统一为「英语」，旧存档的 en_GB 归一化到 en
		if language == "en_GB":
			language = "en"
	if cfg.has_section_key("audio", "master"):  ## 如果配置中存在主音量键
		master_volume = cfg.get_value("audio", "master")  ## 读取主音量
	if cfg.has_section_key("audio", "music"):  ## 如果配置中存在音乐音量键
		music_volume = cfg.get_value("audio", "music")  ## 读取音乐音量
	if cfg.has_section_key("audio", "sfx"):  ## 如果配置中存在音效音量键
		sfx_volume = cfg.get_value("audio", "sfx")  ## 读取音效音量
	if cfg.has_section_key("combat", "show_damage_numbers"):  ## 如果配置中存在伤害显示键
		show_damage_numbers = cfg.get_value("combat", "show_damage_numbers")  ## 读取伤害显示开关
	if cfg.has_section_key("combat", "show_hp_armor_bar"):  ## #16：读取血条数值显示开关
		show_hp_armor_bar = cfg.get_value("combat", "show_hp_armor_bar")
	if cfg.has_section_key("input", "touch_controls"):  ## 移动端触屏输入层开关
		touch_controls = bool(cfg.get_value("input", "touch_controls"))
	if cfg.has_section_key("audio", "throttle"):  ## #4：音频节流开关
		audio_throttle = bool(cfg.get_value("audio", "throttle"))
	if cfg.has_section_key("bgm", "menu"):  ## 如果配置中存在主菜单BGM键
		menu_bgm = cfg.get_value("bgm", "menu")  ## 读取主菜单BGM名称
	if cfg.has_section_key("bgm", "battle"):  ## 如果配置中存在战斗BGM键
		battle_bgm = cfg.get_value("bgm", "battle")  ## 读取战斗BGM名称
	if cfg.has_section_key("bgm", "victory"):  ## 如果配置中存在胜利BGM键
		victory_bgm = cfg.get_value("bgm", "victory")  ## 读取胜利BGM名称
	if cfg.has_section_key("bgm", "defeat"):  ## 如果配置中存在失败BGM键
		defeat_bgm = cfg.get_value("bgm", "defeat")  ## 读取失败BGM名称
	## 读取音效库自定义排序
	if cfg.has_section_key("sound_library", "order"):
		var raw_order = cfg.get_value("sound_library", "order", [])
		sound_library_order.clear()
		if raw_order is Array:
			for item in raw_order:
				sound_library_order.append(str(item))

	## 加载兵种音效配置
	## 注意：不可硬编码兵种白名单（旧版只列 G/D/F/N 共 22 个）。英雄单位（Hero1 爱弥斯 / Hero2 Doro勇士）
	## 等同样有音效配置卡片，若被白名单漏掉，其配置虽已写盘（_save_settings 遍历 unit_sound_configs 全部），
	## 重开后却读不回来，表现为「每次打开窗口都要重新配置」。改为从磁盘 section 的实际 key 反推 unit_id，
	## 确保所有配置过的兵种都能正确加载。
	if cfg.has_section("unit_sounds"):
		var _saved_sound_keys: PackedStringArray = cfg.get_section_keys("unit_sounds")
		var _loaded_unit_ids: Array = []
		for _k in _saved_sound_keys:
			var _uid: String = str(_k)
			for _suffix in ["_click", "_spawn", "_attack", "_rules", "_rule_type", "_rule_count"]:
				if _uid.ends_with(_suffix):
					_uid = _uid.left(_uid.length() - _suffix.length())
					break
			if not _loaded_unit_ids.has(_uid):
				_loaded_unit_ids.append(_uid)
		for unit_id in _loaded_unit_ids:
			var config := _get_default_unit_sound_config()
			if cfg.has_section_key("unit_sounds", unit_id + "_click"):
				config["click_sound"] = cfg.get_value("unit_sounds", unit_id + "_click")
			if cfg.has_section_key("unit_sounds", unit_id + "_spawn"):
				config["spawn_sound"] = cfg.get_value("unit_sounds", unit_id + "_spawn")
			if cfg.has_section_key("unit_sounds", unit_id + "_attack"):
				config["attack_sound"] = cfg.get_value("unit_sounds", unit_id + "_attack")
				## 优先读取新版多条规则配置（JSON 字符串）
				if cfg.has_section_key("unit_sounds", unit_id + "_rules"):
					var rules_json: String = cfg.get_value("unit_sounds", unit_id + "_rules", "")
					if rules_json != "":
						var parsed = JSON.parse_string(rules_json)
						if parsed is Array:
							config["spawn_rules"] = _normalize_spawn_rules(parsed)
				## 兼容旧版单条规则配置：若 spawn_rules 仍为空，则从旧字段迁移
				if config["spawn_rules"].is_empty():
					var old_type: int = 0
					var old_count: int = 1
					var has_old: bool = false
					if cfg.has_section_key("unit_sounds", unit_id + "_rule_type"):
						old_type = int(cfg.get_value("unit_sounds", unit_id + "_rule_type"))
						has_old = true
					if cfg.has_section_key("unit_sounds", unit_id + "_rule_count"):
						old_count = int(cfg.get_value("unit_sounds", unit_id + "_rule_count"))
						has_old = true
					if has_old:
						config["spawn_rules"] = [{"type": old_type, "count": max(1, old_count)}]
			unit_sound_configs[unit_id] = config

	## 加载音效归属类型（音频路径 -> 阵营标签）
	if cfg.has_section("sound_attribution"):
		for key in cfg.get_section_keys("sound_attribution"):
			sound_attribution[key] = str(cfg.get_value("sound_attribution", key))

	## #17：加载单条音效文件音量表
	if cfg.has_section("sound_volumes"):
		for key in cfg.get_section_keys("sound_volumes"):
			sound_volumes[key] = clampf(float(cfg.get_value("sound_volumes", key)), 0.0, 2.0)

func _save_settings() -> void:  ## 保存设置到配置文件（私有方法）
	var cfg = ConfigFile.new()  ## 创建配置文件对象
	cfg.set_value("window", "mode", window_mode)  ## 写入窗口模式
	cfg.set_value("language", "current", language)  ## 写入语言
	cfg.set_value("audio", "master", master_volume)  ## 写入主音量
	cfg.set_value("audio", "music", music_volume)  ## 写入音乐音量
	cfg.set_value("audio", "sfx", sfx_volume)  ## 写入音效音量
	cfg.set_value("audio", "throttle", audio_throttle)  ## #4：写入音频节流开关
	cfg.set_value("combat", "show_damage_numbers", show_damage_numbers)  ## 写入伤害显示开关
	cfg.set_value("combat", "show_hp_armor_bar", show_hp_armor_bar)  ## #16：写入血条数值显示开关
	cfg.set_value("input", "touch_controls", touch_controls)  ## 写入移动端触屏输入层开关
	cfg.set_value("bgm", "menu", menu_bgm)  ## 写入主菜单BGM名称
	cfg.set_value("bgm", "battle", battle_bgm)  ## 写入战斗BGM名称
	cfg.set_value("bgm", "victory", victory_bgm)  ## 写入胜利BGM名称
	cfg.set_value("bgm", "defeat", defeat_bgm)  ## 写入失败BGM名称
	cfg.set_value("sound_library", "order", sound_library_order)  ## 写入音效库自定义排序
	## 保存音效归属类型
	for key in sound_attribution:
		cfg.set_value("sound_attribution", key, sound_attribution[key])
	## #17：保存单条音效文件音量表
	for key in sound_volumes:
		cfg.set_value("sound_volumes", key, clampf(float(sound_volumes[key]), 0.0, 2.0))
	## 保存兵种音效配置（遍历所有已配置的兵种）
	for unit_id in unit_sound_configs:
		var config: Dictionary = unit_sound_configs[unit_id]
		cfg.set_value("unit_sounds", unit_id + "_click", config.get("click_sound", ""))
		cfg.set_value("unit_sounds", unit_id + "_spawn", config.get("spawn_sound", ""))
		cfg.set_value("unit_sounds", unit_id + "_attack", config.get("attack_sound", ""))
		## spawn_rules 序列化为 JSON 字符串保存（ConfigFile 不支持嵌套 Dictionary 数组）
		var rules: Array = config.get("spawn_rules", [])
		rules = _normalize_spawn_rules(rules)
		cfg.set_value("unit_sounds", unit_id + "_rules", JSON.stringify(rules))
	cfg.save("user://settings.cfg")  ## 保存到用户目录下的设置文件

func _apply_settings() -> void:  ## 应用所有设置（私有方法）
	TranslationServer.set_locale(language)  ## 设置翻译语言区域
	_apply_window_mode()  ## 应用窗口模式
	_apply_audio_settings()  ## 应用音频设置

func _apply_window_mode() -> void:  ## 应用窗口模式（私有方法）
	## 使用 Window API（推荐）：直接操作游戏主窗口，比裸 DisplayServer 调用更稳定可靠
	var win := get_window()  ## 获取游戏主窗口
	if win == null:  ## 极少数情况下窗口尚未就绪，下个 idle 再试一次
		call_deferred("_apply_window_mode")
		return
	match window_mode:  ## 根据设置的窗口模式进行匹配
		WINDOW_MODE_WINDOWED:  ## 普通窗口模式
			win.borderless = false  ## 关闭无边框
			win.mode = Window.MODE_WINDOWED  ## 切换到窗口模式
			if _windowed_size.x > 0 and _windowed_size.y > 0:  ## 如果记录的窗口尺寸有效
				win.size = _windowed_size  ## 恢复窗口尺寸
		WINDOW_MODE_FULLSCREEN:  ## 全屏模式
			win.borderless = false  ## 关闭无边框
			win.mode = Window.MODE_FULLSCREEN  ## 切换到全屏模式
			## Android：额外隐藏系统状态栏/导航栏，避免顶部/底部出现黑边
			if OS.has_feature("android"):
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		WINDOW_MODE_BORDERLESS:  ## 无边框窗口模式
			win.mode = Window.MODE_WINDOWED  ## 先切回窗口模式（无边框必须基于窗口模式）
			var screen_size := DisplayServer.screen_get_size()  ## 获取屏幕尺寸
			win.size = screen_size  ## 窗口铺满屏幕
			win.position = Vector2i.ZERO  ## 定位到屏幕左上角
			win.borderless = true  ## 开启无边框标志

func _apply_audio_settings() -> void:  ## 应用音频设置（私有方法）
	AudioManager.set_master_volume(master_volume)  ## 设置主音量
	AudioManager.set_music_volume(music_volume)  ## 设置音乐音量
	AudioManager.set_sfx_volume(sfx_volume)  ## 设置音效音量

func set_window_mode(mode: int) -> void:  ## 设置窗口模式（公开方法）
	## 离开窗口模式前记录当前窗口尺寸，便于切回时恢复
	if window_mode == WINDOW_MODE_WINDOWED and mode != WINDOW_MODE_WINDOWED:
		_windowed_size = DisplayServer.window_get_size()
	window_mode = mode  ## 更新窗口模式
	## 延迟到当前帧输入处理完成后再切换窗口模式，避免 viewport 输入推送报错
	call_deferred("_apply_window_mode")
	call_deferred("_save_settings")  ## 延迟保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_language(lang: String) -> void:  ## 设置语言（公开方法）
	language = lang  ## 更新语言
	TranslationServer.set_locale(lang)  ## 立即应用语言区域
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_master_volume(vol: float) -> void:  ## 设置主音量（公开方法）
	master_volume = clampf(vol, 0.0, 2.0)  ## 钳制音量到 0.0~2.0 范围（#1：上限调至 200%）
	_apply_audio_settings()  ## 应用音频设置
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_music_volume(vol: float) -> void:  ## 设置音乐音量（公开方法）
	music_volume = clampf(vol, 0.0, 2.0)  ## 钳制音量到 0.0~2.0 范围（#1：上限调至 200%）
	_apply_audio_settings()  ## 应用音频设置
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_sfx_volume(vol: float) -> void:  ## 设置音效音量（公开方法）
	sfx_volume = clampf(vol, 0.0, 2.0)  ## 钳制音量到 0.0~2.0 范围（#1：上限调至 200%）
	_apply_audio_settings()  ## 应用音频设置
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_show_damage_numbers(show: bool) -> void:  ## 设置伤害量文本显示开关（公开方法）
	show_damage_numbers = show  ## 更新开关
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_show_hp_armor_bar(show: bool) -> void:  ## #16：设置血条数值显示开关（公开方法）
	show_hp_armor_bar = show  ## 更新开关
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

## 移动端触屏输入层：是否在触屏模式下运行（安卓/iOS 导出自动 true，桌面可手动开）
func is_touch_input() -> bool:
	return OS.has_feature("mobile") or touch_controls

## 设置触屏输入层开关并保存（设置界面/调试用）
func set_touch_controls(enabled: bool) -> void:
	touch_controls = enabled
	_save_settings()
	settings_changed.emit()

## #4：设置音频节流开关并保存（设置界面调用）
## 开启=现在的并发限制播放方式（攻击/点击音效同一时刻受限）；
## 关闭=以前的播放方式（触发即播放、不做并发限制）
func set_audio_throttle(enabled: bool) -> void:
	audio_throttle = enabled
	_save_settings()
	settings_changed.emit()

## #17：获取单条音效文件的音量（0.0~2.0），未单独设置过返回满音量 1.0
func get_sound_volume(path: String) -> float:
	if path == "":
		return 1.0
	return clampf(float(sound_volumes.get(path, 1.0)), 0.0, 2.0)

## #17：设置单条音效文件的音量并立即保存（音效配置页「调整」视图的拖动条调用）
func set_sound_volume(path: String, volume: float) -> void:
	if path == "":
		return
	sound_volumes[path] = clampf(volume, 0.0, 2.0)
	_save_settings()

func set_menu_bgm(bgm_name: String) -> void:  ## 设置主菜单BGM（公开方法）
	menu_bgm = bgm_name  ## 更新主菜单BGM名称
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_battle_bgm(bgm_name: String) -> void:  ## 设置战斗BGM（公开方法）
	battle_bgm = bgm_name  ## 更新战斗BGM名称
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_victory_bgm(bgm_name: String) -> void:  ## 设置胜利BGM（公开方法）
	victory_bgm = bgm_name  ## 更新胜利BGM名称
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

func set_defeat_bgm(bgm_name: String) -> void:  ## 设置失败BGM（公开方法）
	defeat_bgm = bgm_name  ## 更新失败BGM名称
	_save_settings()  ## 保存设置
	settings_changed.emit()  ## 发出设置变更信号

## 兵种音效配置的默认值
func _get_default_unit_sound_config() -> Dictionary:
	return {
		"click_sound": "",
		"attack_sound": "",
		"spawn_sound": "",
		"spawn_rules": [],  ## 出兵音效规则列表，可同时配置多条
	}

## 规范化出兵音效规则列表：校验每条规则的 type/count 字段，过滤无效项
## rules: 原始规则数组（元素可为 Dictionary）
## 返回：规范化的规则数组 [{ "type": int, "count": int }, ...]
func _normalize_spawn_rules(rules: Array) -> Array:
	var result: Array = []
	for entry in rules:
		if entry is Dictionary:
			var t: int = int(entry.get("type", 0))
			var c: int = int(entry.get("count", 1))
			if t < 0 or t > 2:
				t = 0
			if c < 1:
				c = 1
			## #规则音效（2026-08-14 修复）：必须保留 sound 字段，否则规则出兵音效在存盘/读盘时被剥掉
			var snd: String = str(entry.get("sound", ""))
			result.append({"type": t, "count": c, "sound": snd})
	return result

## 获取指定兵种的音效配置（不存在则用默认值填充并缓存）
func get_unit_sound_config(unit_id: String) -> Dictionary:
	if not unit_sound_configs.has(unit_id):
		unit_sound_configs[unit_id] = _get_default_unit_sound_config()
	return unit_sound_configs[unit_id]

## 设置指定兵种的音效配置并立即保存
func set_unit_sound_config(unit_id: String, config: Dictionary) -> void:
	unit_sound_configs[unit_id] = config
	_save_settings()

## 获取音频的归属类型（"shared"/"G"/"D"/"F"/"N"），未设置返回空串
func get_sound_attribution(path: String) -> String:
	if sound_attribution.has(path):
		return sound_attribution[path]
	return ""

## 设置音频的归属类型并立即保存（音效管理面板的"归属类型"下拉使用）
func set_sound_attribution(path: String, att_type: String) -> void:
	if path == "":
		return
	sound_attribution[path] = att_type
	_save_settings()

## 保存音效库的自定义排序（控制台"音效管理"面板拖动排序后调用）
## order: 按用户期望顺序排列的音频 res:// 路径数组
func set_sound_library_order(order: Array[String]) -> void:
	sound_library_order = order.duplicate()
	_save_settings()

## 将某个音效路径在所有兵种配置中的引用替换为新路径（重命名时同步）
## 传入空的 new_path 表示删除该引用（音频被删除时调用）
## old_path: 原路径；new_path: 新路径（空串=清除引用）
func replace_sound_path(old_path: String, new_path: String) -> void:
	if old_path == "":
		return
	for unit_id in unit_sound_configs:
		var config: Dictionary = unit_sound_configs[unit_id]
		## click_sound 支持单路径（String）或多配置（Array[String]），两者都要迁移
		var click: Variant = config.get("click_sound", "")
		if click is Array:
			var click_arr: Array = click
			for i in range(click_arr.size()):
				if str(click_arr[i]) == old_path:
					click_arr[i] = new_path
			if new_path == "":
				click_arr = click_arr.filter(func(p) -> bool: return str(p) != "")
			config["click_sound"] = click_arr
		elif str(click) == old_path:
			config["click_sound"] = new_path
		if config.get("spawn_sound", "") == old_path:
			config["spawn_sound"] = new_path
		var rules: Array = config.get("spawn_rules", [])
		for rule in rules:
			if rule is Dictionary and rule.get("sound", "") == old_path:
				rule["sound"] = new_path
	## 同步归属类型表的键
	if sound_attribution.has(old_path):
		var v: String = sound_attribution[old_path]
		sound_attribution.erase(old_path)
		if new_path != "":
			sound_attribution[new_path] = v
	## 同步排序表中的路径
	var idx: int = sound_library_order.find(old_path)
	if idx >= 0:
		if new_path == "":
			sound_library_order.remove_at(idx)
		else:
			sound_library_order[idx] = new_path
	_save_settings()
