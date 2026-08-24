extends Node  ## 继承 Node，作为全局单例节点存在
## 音效管理器（全局单例）
## 负责管理游戏中的音效、背景音乐和总线音量同步

signal volumes_changed  ## 音量变更信号，当任意音量被修改时发出

## 主音量（0.0 ~ 1.0），控制所有音频的总音量
var master_volume: float = 1.0
## 音效音量（0.0 ~ 1.0），控制音效（SFX）的音量
var sfx_volume: float = 1.0
## 音乐音量（0.0 ~ 1.0），控制背景音乐的音量
var music_volume: float = 1.0

## 攻击音效同时播放上限（最多同时播放 10 个攻击音效）
const MAX_CONCURRENT_ATTACK_SFX: int = 10
## 全部兵种 ID（用于攻击音效预加载与状态自检，单一真相源，避免多处重复维护）
const UNIT_IDS: Array[String] = [
	"G1", "G2", "G3", "G4", "G5", "G6",
	"D1", "D2", "D3", "D4", "D5", "D6",
	"F1", "F2", "F3", "F4", "F5",
	"N1", "N2", "N3", "N4", "N5",
]
## 攻击音效资源缓存（unit_id -> AudioStream）
var _attack_sound_cache: Dictionary = {}
## 当前正在播放攻击音效的播放器列表
var _active_attack_players: Array[AudioStreamPlayer] = []
## 音效播放器对象池（复用避免频繁创建）
var _sfx_player_pool: Array[AudioStreamPlayer] = []
## #3 音频节流（2026-08-14 重构，本轮二次修正语义）：开启时「出兵音效」与「点击音效」共享单一并发锁
## （严格只播一条），且点击优先——点击音效始终抢占（打断在播的出兵/其它点击）、出兵音效在锁占用时被丢弃，
## 实现「点击与出兵同时触发时只播点击」。关闭时全部触发即播、不做任何限制与防抖：
## 出多少兵播放多少次出兵音效、点多少次按钮播放多少次点击音效。
var _throttle_sfx_lock: AudioStreamPlayer = null
## 点击压制窗口（秒）：点击音播放后的一小段时间内，出兵音一律不播放（点击优先，所有模式通用）。
## 解决「点击音仅 40ms、锁很快释放，出兵晚到就漏放导致两遍都响」——用时间窗口兜底，不依赖 40ms 的锁占用。
var _click_supremacy_until: float = 0.0
const CLICK_SUPREMACY_WINDOW: float = 0.2
## UI 点击音效（程序化生成，带缓存）
var _click_stream: AudioStreamWAV = null
## 兵种点击音效缓存（unit_id -> AudioStream）
var _unit_click_sound_cache: Dictionary = {}
## 兵种出兵音效缓存（unit_id -> AudioStream）
var _unit_spawn_sound_cache: Dictionary = {}
## 兵种出兵音效规则状态跟踪
## key: "unit_id|rule_index", value: { "count": int(当前计数), "last_time": float(上次出兵时间戳) }
## 用于"同时出N兵"窗口计数与"累计出N兵"累计计数，每条规则独立维护状态
var _unit_spawn_state: Dictionary = {}
## 同时出兵判定窗口（秒），略大于 SPAWN_INTERVAL(1.0s)，用于判定"同时出兵"
const SPAWN_SOUND_WINDOW: float = 1.2
## 优先播放攻击音效的兵种 ID（镜头锁定单位），其攻击音效必播放（不受上限限制）
var _priority_unit_id: String = ""
## BGM 播放器（独立于 SFX 对象池，常驻单实例）
var _music_player: AudioStreamPlayer = null
## BGM 资源缓存（name -> AudioStreamMP3）
var _music_stream_cache: Dictionary = {}
## 当前正在播放的 BGM 名称（用于判断"同一首不重启"）
var _current_music_name: String = ""
## 当前 BGM 上下文（"menu" / "battle"），由 play_menu_bgm / play_battle_bgm 设置。
## 用于监听 SettingsManager.settings_changed 后在 BGM 设置变化（随机播放等）时自动重播当前场景音乐。
var _bgm_context: String = "menu"
## 记录当前正在播放的 menu/battle BGM 设置名，用于设置变更时只重播“对应上下文真正变化”的那一路
## （避免在主菜单改战斗BGM时误重播主菜单BGM，见 #26）
var _last_menu_bgm: String = ""
var _last_battle_bgm: String = ""

func _ready() -> void:  ## 节点就绪时自动调用
	_apply_bus_volumes()  ## 应用音频总线音量
	## 初始化 BGM 播放器
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	## #21：BGM 播放器设为 ALWAYS，避免结算界面 get_tree().paused = true 时
	## 刚调用的 play_victory_bgm() 被树暂停冻结（继承模式会随树暂停）
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	## #25（2026-08-23）：监听设置变化，BGM 设置（随机播放等）改动后自动重播当前场景音乐。
	## AudioManager 在 autoload 顺序中位于 SettingsManager 之前，需用 call_deferred 连接，
	## 否则 SettingsManager 尚未就绪会报错。
	if not SettingsManager.settings_changed.is_connected(_on_settings_bgm_changed):
		SettingsManager.settings_changed.connect(_on_settings_bgm_changed)
	## 预加载所有兵种攻击音效，避免首次攻击时的 load() 卡顿造成音效延迟（#148）
	for uid in UNIT_IDS:
		_get_attack_sound(uid)
	## 打印各兵种音效状态，便于排查缺失情况
	## 注意：必须用 call_deferred —— AudioManager 在 autoload 顺序中位于 SettingsManager 之前，
	## 若同步调用，SettingsManager 尚未加载 settings.cfg，unit_sound_configs 为空，会误报“全部未配置”。
	## defer 到所有 autoload _ready 完成后再打印，才能读到用户已保存的攻击音效配置（2026-08-09 修复）
	## call_deferred 首参必须是方法名字符串（StringName），不能传 Callable
	call_deferred("_print_sound_status")

## 打印所有兵种的攻击音效状态到控制台
## 直接复用 _get_attack_sound 的判定结果，避免自检逻辑与真实加载逻辑不一致造成误报
## （旧实现只查 attack.mp3，导致 G1 的 .wav 与用户自定义配置被误报为"未配置"）
func _print_sound_status() -> void:
	print("========== 兵种音效状态 ==========")
	for uid in UNIT_IDS:
		if _get_attack_sound(uid) != null:
			print("[音效] %s: 攻击音效已配置" % uid)
		else:
			print("[音效] %s: 未配置攻击音效（将静音）" % uid)
	print("==================================")

## 播放指定名称的音效（占位实现）
## name: 音效资源名称
## TODO: 后续添加实际音频资源后完善此功能
func play_sfx(_name: String) -> void:  ## 播放音效方法（参数名前缀下划线表示暂未使用）
	## 占位：实际音效播放逻辑待实现
	pass  ## 空实现，待后续完善

## 播放 UI 点击音效（按钮按下时调用）
## 音效为程序化生成的短促衰减正弦波，无需外部音频文件
func play_ui_click() -> void:
	if _click_stream == null:
		_click_stream = _create_click_stream()
	## 点击优先：记录压制窗口（无论节流开关，点击后的窗口内出兵音不播）
	_click_supremacy_until = Time.get_ticks_msec() / 1000.0 + CLICK_SUPREMACY_WINDOW
	if SettingsManager.audio_throttle:
		## 开启节流：单一并发锁 + 点击优先（点击抢占，打断在播的非点击音效）
		if not _throttle_gate(true):
			return  ## 点击永远通过闸门（闸门内已处理抢占），此分支仅为防御
		var player: AudioStreamPlayer = _get_pooled_player()
		player.stream = _click_stream
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		player.play()
		_sfx_throttle_occupy(player)
		return
	## 关闭节流：触发即播，每次点击都立刻播放（无限制、无防抖）
	var player: AudioStreamPlayer = _get_pooled_player()
	player.stream = _click_stream
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.play()

## 程序化生成 UI 点击音效（40ms 衰减正弦波）
func _create_click_stream() -> AudioStreamWAV:
	var sample_rate := 44100
	var duration := 0.04  ## 40ms 短促音
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)  ## 16-bit 每样本 2 字节
	var freq := 1200.0  ## 点击音频率
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var env := 1.0 - float(i) / float(num_samples)  ## 线性衰减
		env = env * env  ## 二次衰减更短促
		var sample := sin(t * freq * TAU) * env * 0.45
		var s := int(clamp(sample, -1.0, 1.0) * 32767)
		data.encode_s16(i * 2, s)  ## little-endian 16-bit
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

## 播放指定兵种的攻击音效
## 最多同时播放 MAX_CONCURRENT_ATTACK_SFX 个攻击音效，超出则忽略
## 优先兵种（镜头锁定单位）的攻击音效不受上限限制，必播放
## unit_id: 兵种 ID（如 "G1"），用于加载对应的 attack.mp3
func play_attack_sound(unit_id: String) -> void:  ## 播放攻击音效方法
	## 清理已播放完成的播放器
	_cleanup_finished_players()
	## 判断是否为优先兵种（镜头锁定单位），优先兵种不受上限限制
	var is_priority: bool = (_priority_unit_id != "" and unit_id == _priority_unit_id)  ## 是否为优先兵种
	## #3 修正（2026-08-23）：节流（audio_throttle）只作用于「点击音效」与「出兵音效」，不作用于攻击音效。
	## 攻击音效始终走并发池，最多同时播放 MAX_CONCURRENT_ATTACK_SFX 个，超出则忽略；
	## 优先兵种（镜头锁定单位）不受上限限制，必播放。节流开关对攻击音效无任何影响。
	if not is_priority and _active_attack_players.size() >= MAX_CONCURRENT_ATTACK_SFX:
		return
	## 加载音效资源（带缓存）
	var stream: AudioStream = _get_attack_sound(unit_id)
	if stream == null:
		return
	## 从对象池取一个播放器
	var player: AudioStreamPlayer = _get_pooled_player()
	player.stream = stream
	## 优先使用 SFX 总线，不存在则回退到 Master
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	## #17：应用该音效文件的独立音量（未设置过 = 满音量）
	var attack_path: String = _get_attack_sound_path(unit_id)
	player.volume_db = linear_to_db(SettingsManager.get_sound_volume(attack_path))
	_active_attack_players.append(player)
	player.play()

## 设置优先播放攻击音效的兵种 ID（镜头锁定单位时调用）
## 优先兵种的攻击音效必播放，不受 10 个同时播放上限限制
## unit_id: 兵种 ID，传空字符串清除优先
func set_priority_unit_id(unit_id: String) -> void:  ## 设置优先兵种方法
	_priority_unit_id = unit_id  ## 保存优先兵种 ID

## 获取兵种攻击音效（带缓存）
## 优先使用音效配置页配置的"攻击音效"，未配置时回退到默认 attack.mp3
func _get_attack_sound(unit_id: String) -> AudioStream:
	if _attack_sound_cache.has(unit_id):
		return _attack_sound_cache[unit_id]
	var path: String = _get_attack_sound_path(unit_id)
	if path == "":
		## 不缓存 null：文件可能尚未被导入，下次攻击时重新检查（避免误缓存导致永久静音，#149）
		return null
	var stream = load(path)
	_attack_sound_cache[unit_id] = stream
	return stream

## 解析兵种攻击音效的最终路径（配置自定义 > 默认 attack.mp3 > attack.wav 兼容）
## 返回 "" 表示不存在可用音效；供 _get_attack_sound 与 #17 的 per-file 音量查询共用
func _get_attack_sound_path(unit_id: String) -> String:
	var config: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
	var custom_path: String = str(config.get("attack_sound", ""))
	if custom_path != "" and ResourceLoader.exists(custom_path):
		return custom_path
	var path := "res://assets/audio/units/%s/attack.mp3" % unit_id
	if not ResourceLoader.exists(path):
		## 兼容 .wav 命名的攻击音效（如 G1 的攻击音效为 shared 目录下的 wav）
		path = "res://assets/audio/units/%s/attack.wav" % unit_id
		if not ResourceLoader.exists(path):
			return ""
	return path

## 播放兵种点击音效（局内点击兵种按钮/展开信息面板时调用）
## unit_id: 兵种 ID（如 "G1"），从 SettingsManager 读取配置的音频路径
func play_unit_click_sound(unit_id: String) -> void:
	var config: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
	var click: Variant = config.get("click_sound", "")
	## 多配置（Array）：随机播放其中一个；单配置（String）：直接播放
	## is_click=true 标记这是"点击音效"，用于在播放期间压制出兵音效（#146）
	if click is Array:
		var arr: Array = click
		if arr.is_empty():
			return
		_play_one_shot(str(arr[randi() % arr.size()]), true)
	else:
		_play_one_shot(str(click), true)

## 直接按路径播放一段一次性音效（用于调试界面预览、规则语音试听等场景）
## path: res:// 音频路径；空或文件不存在则直接返回，不做任何操作
## force: 为 true 时跳过「同名防抖」（#4：试听场景每次点击立即重播）
func play_sound_path(path: String, force: bool = false) -> void:
	_play_one_shot(path, false, force)

## 播放兵种出兵音效（根据配置的规则列表决定是否播放）
## 规则类型：0=每次出兵都播放, 1=同时出N兵时播放(已废弃选项，仅保留兼容旧配置), 2=累计出N兵时播放
## 设计要点（对应策划要求）：
## - 每条规则可单独配置语音(rule["sound"])，未配置时使用顶层 spawn_sound 作为兜底
## - 每次出兵(type 0) 与 累计出兵(type 2) 同时触发时，仅播放 累计出兵 的音效（优先级更高）
## - 多个相同类型规则同时触发时，随机挑其中一条的语音播放（避免同音反复堆叠）
## unit_id: 兵种 ID（如 "G1"），从 SettingsManager 读取配置的音频路径与规则列表
func play_unit_spawn_sound(unit_id: String) -> void:
	## 点击优先（所有模式通用）：点击后的压制窗口内，出兵音一律不播放（只播点击）。
	## 与节流开关无关——即便关闭节流，点击也永远压过「同时」触发的出兵。
	if Time.get_ticks_msec() / 1000.0 < _click_supremacy_until:
		return
	var config: Dictionary = SettingsManager.get_unit_sound_config(unit_id)
	var rules: Array = config.get("spawn_rules", [])
	## 无规则时默认每次都播放（使用顶层 spawn_sound 作为语音）
	if rules.is_empty():
		rules = [{"type": 0, "count": 1, "sound": config.get("spawn_sound", "")}]
	## 按规则类型收集"本次触发"的语音候选
	var cands_by_type: Dictionary = {}
	for i in range(rules.size()):
		var rule: Dictionary = rules[i]
		var rule_type: int = int(rule.get("type", 0))
		var rule_count: int = maxi(int(rule.get("count", 1)), 1)
		var state_key: String = "%s|%d" % [unit_id, i]
		var triggered: bool = false
		match rule_type:
			1:
				## 同时出N兵：时间窗口内累计计数，达到N时触发（保留兼容旧配置）
				triggered = _eval_simultaneous(state_key, rule_count)
			2:
				## 累计出N兵：累计计数，达到N时触发并重置
				triggered = _eval_cumulative(state_key, rule_count)
			_:
				## 0=每次出兵都播放
				triggered = true
		var snd: String = ""
		if triggered:
			snd = rule.get("sound", "")
			if snd == "":
				snd = config.get("spawn_sound", "")
		if snd != "":
			var type_cands: Array[String] = []
			if cands_by_type.has(rule_type):
				type_cands = cands_by_type[rule_type]
			type_cands.append(snd)
			cands_by_type[rule_type] = type_cands
	## 优先级：累计出兵(2) > 每次出兵(0) > 同时出兵(1)
	## 相撞时只播放优先级更高的一类，符合"每次与累计相撞只放累计"的要求
	var chosen_type: int = -1
	if cands_by_type.has(2):
		chosen_type = 2
	elif cands_by_type.has(0):
		chosen_type = 0
	elif cands_by_type.has(1):
		chosen_type = 1
	if chosen_type < 0:
		return
	var cands: Array[String] = cands_by_type[chosen_type]
	## 多个相同规则同时触发 → 随机挑一个播放
	var chosen_sound: String = cands[randi() % cands.size()]
	_play_one_shot(chosen_sound)

## 累计出N兵判定：计数+1，达到阈值即触发并重置计数
## 返回 true 表示本次出兵触发了播放条件
func _eval_cumulative(state_key: String, rule_count: int) -> bool:
	var state: Dictionary = _unit_spawn_state.get(state_key, {"count": 0})
	state["count"] = int(state.get("count", 0)) + 1
	var triggered: bool = int(state.get("count", 0)) >= rule_count
	if triggered:
		state["count"] = 0
	_unit_spawn_state[state_key] = state
	return triggered

## 同时出N兵判定：时间窗口内累计计数，达到阈值即触发并重置
## 返回 true 表示本次出兵触发了播放条件
func _eval_simultaneous(state_key: String, rule_count: int) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var state: Dictionary = _unit_spawn_state.get(state_key, {"count": 0, "last_time": 0.0})
	## 超过窗口时间则重置计数（视为新一轮出兵）
	if now - float(state.get("last_time", 0.0)) > SPAWN_SOUND_WINDOW:
		state["count"] = 0
	state["count"] = int(state.get("count", 0)) + 1
	state["last_time"] = now
	var triggered: bool = int(state.get("count", 0)) >= rule_count
	if triggered:
		state["count"] = 0
	_unit_spawn_state[state_key] = state
	return triggered

## 按路径加载并播放一段一次性音效（对象池复用 AudioStreamPlayer）
## 兼容两类资源：
## 1. 已被 Godot 导入的音频（load 正常）
## 2. 运行时刚复制进项目、尚未被资源系统导入的上传音频 —— 直接从磁盘读字节解析 WAV
## 节流语义（#3）：
## - 关闭：force=true 或 audio_throttle=false → 触发即播、不做任何限制与防抖
##   （出多少兵播多少次、点多少次按钮播多少次）
## - 开启：单一并发锁 + 点击优先（见 _throttle_gate）；出兵在锁占用时被丢弃，点击抢占在播音效
func _play_one_shot(path: String, is_click: bool = false, force: bool = false) -> void:
	if path == "":
		return
	## 试听（force）或节流关闭 → 直接触发即播，跳过一切节流与防抖
	if force or not SettingsManager.audio_throttle:
		_play_oneshot_now(path, is_click)
		return
	## 节流开启：走点击优先的并发闸门
	if not _throttle_gate(is_click):
		return
	_play_oneshot_now(path, is_click)

## 实际播放一段一次性音效（不处理节流/防抖，由调用方决定）
func _play_oneshot_now(path: String, is_click: bool) -> void:
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	## 未导入 → 尝试直接读文件字节解析 WAV（拖动上传后尚未被编辑器重新导入的场景）
	if stream == null:
		stream = _load_raw_wav(path)
	if stream == null:
		return
	var player: AudioStreamPlayer = _get_pooled_player()
	player.stream = stream
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	## #17：应用该音效文件的独立音量（叠加在 SFX 总线音量之上）
	player.volume_db = linear_to_db(SettingsManager.get_sound_volume(path))
	## 节流开启时才占用并发锁（关闭时纯触发即播，不占锁）
	if is_click:  ## 点击优先：记录压制窗口，期间出兵音不播放（所有模式通用）
		_click_supremacy_until = Time.get_ticks_msec() / 1000.0 + CLICK_SUPREMACY_WINDOW
	if SettingsManager.audio_throttle:
		_sfx_throttle_occupy(player)
	player.play()

## 节流开启时的并发闸门（点击优先）。返回 true=允许本次播放，false=丢弃本次触发。
## is_click=true（点击音效）：始终抢占——若当前锁正播放（无论被出兵还是其它点击占用），
##   先 stop() 打断，再让点击立即播放，实现「点击与出兵同时触发只播点击」。
## is_click=false（出兵音效）：若锁正被占用则丢弃本次出兵（点击优先且不堆叠出兵）。
func _throttle_gate(is_click: bool) -> bool:
	if _throttle_sfx_lock != null and is_instance_valid(_throttle_sfx_lock) and _throttle_sfx_lock.playing:
		if is_click:
			_throttle_sfx_lock.stop()  ## 点击优先：打断在播音效
		else:
			return false  ## 出兵被占用锁挡住
	return true

## 从磁盘读取 WAV 文件字节并解析为 AudioStreamWAV（绕过 Godot 资源导入系统）
## 用于上传后尚未被编辑器重新导入的音频预览播放；非 WAV 或解析失败返回 null
func _load_raw_wav(path: String) -> AudioStreamWAV:
	var abs_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	if bytes == null or bytes.size() < 44:
		return null
	return _parse_wav_to_stream(bytes)

## 解析标准 RIFF/WAVE 字节为 AudioStreamWAV（支持 PCM fmt=1 与 EXTENSIBLE fmt=0xFFFE）
func _parse_wav_to_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 12:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var format_tag: int = 1
	var channels: int = 1
	var sample_rate: int = 44100
	var bits_per_sample: int = 16
	var pcm := PackedByteArray()
	var i: int = 12
	while i + 8 <= bytes.size():
		var chunk_id: String = bytes.slice(i, i + 4).get_string_from_ascii()
		var chunk_size: int = bytes.decode_u32(i + 4)
		var data_start: int = i + 8
		if chunk_id == "fmt ":
			if data_start + 16 <= bytes.size():
				format_tag = bytes.decode_u16(data_start)
				channels = maxi(bytes.decode_u16(data_start + 2), 1)
				sample_rate = maxi(bytes.decode_u32(data_start + 4), 8000)
				bits_per_sample = bytes.decode_u16(data_start + 14)
		elif chunk_id == "data":
			var end: int = mini(data_start + chunk_size, bytes.size())
			pcm = bytes.slice(data_start, end)
			break
		## 块大小为奇数时需按 2 字节对齐
		i = data_start + chunk_size + (1 if chunk_size % 2 == 1 else 0)
	if pcm.is_empty():
		return null
	## EXTENSIBLE：真实编码在 SubFormat GUID 前 2 字节（0x0001 = PCM）
	if format_tag == 0xFFFE:
		format_tag = 1
	if format_tag != 1:
		return null  ## 非 PCM（如压缩格式）不支持字节级解析
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample >= 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = channels >= 2
	stream.data = pcm
	return stream

## 清除指定兵种的音效缓存（配置变更时调用，确保下次重新加载）
## 同时重置出兵音效规则计数状态（含多条规则的独立状态）
func clear_unit_sound_cache(unit_id: String) -> void:
	_unit_click_sound_cache.erase(unit_id)
	_unit_spawn_sound_cache.erase(unit_id)
	_attack_sound_cache.erase(unit_id)
	## 状态 key 格式为 "unit_id|rule_index"，需清除所有该兵种的状态
	var prefix: String = "%s|" % unit_id
	var keys_to_erase: Array = []
	for key in _unit_spawn_state.keys():
		if String(key).begins_with(prefix):
			keys_to_erase.append(key)
	for key in keys_to_erase:
		_unit_spawn_state.erase(key)

## 清除所有兵种的音效缓存与出兵计数状态
## 音频文件被重命名/删除后调用，避免继续引用失效的 AudioStream
func clear_all_sound_cache() -> void:
	_unit_click_sound_cache.clear()
	_unit_spawn_sound_cache.clear()
	_attack_sound_cache.clear()
	_unit_spawn_state.clear()

## 从对象池获取一个可用的 AudioStreamPlayer
func _get_pooled_player() -> AudioStreamPlayer:
	## 优先复用池中空闲播放器
	for player in _sfx_player_pool:
		if not player.playing:
			return player
	## 池中没有空闲，创建新的并添加到场景树
	var player := AudioStreamPlayer.new()
	add_child(player)
	_sfx_player_pool.append(player)
	return player

## 清理已播放完成的播放器（从活跃列表移除）
func _cleanup_finished_players() -> void:
	var i := 0
	while i < _active_attack_players.size():
		if not _active_attack_players[i].playing:
			_active_attack_players.remove_at(i)
		else:
			i += 1

## 占用节流锁（#3）：开启时记录当前播放器，播完自动释放，保证「同时只播放一条」。
## 关闭时（audio_throttle=false）直接返回，不占锁（纯触发即播）。
func _sfx_throttle_occupy(player: AudioStreamPlayer) -> void:
	if not SettingsManager.audio_throttle:
		return
	_throttle_sfx_lock = player
	player.finished.connect(func() -> void:
		if _throttle_sfx_lock == player:
			_throttle_sfx_lock = null
	, CONNECT_ONE_SHOT)

## 播放指定名称的背景音乐
## name: 音乐资源名称（对应 res://assets/audio/bgm/{name}.mp3）
## 同一首音乐正在播放时不重启，切换到不同曲目才会重新播放
func play_music(name: String) -> void:  ## 播放背景音乐方法
	if _music_player == null:
		return
	## 同一首正在播放，直接返回（避免重启）
	if name == _current_music_name and _music_player.playing:
		return
	## 加载音乐资源（带缓存）
	var stream: AudioStream = _get_music_stream(name)
	if stream == null:
		push_warning("BGM 资源不存在: %s" % name)
		return
	_music_player.stream = stream
	_music_player.stream_paused = false  ## 复位历史暂停残留，防止静音（#9）
	_music_player.play()
	_current_music_name = name

## 当前 BGM 是否处于实际发声状态（#9：供胜利界面播放后校验，未起播则重试）
func is_music_playing() -> bool:
	return _music_player != null and _music_player.playing and not _music_player.stream_paused

## 停止当前播放的背景音乐
func stop_music() -> void:  ## 停止背景音乐方法
	if _music_player != null:
		_music_player.stop()
	_current_music_name = ""

## 暂停当前背景音乐（保留播放位置，供 resume_music 恢复）
## 与 stop_music 不同：不释放流与曲目名，开发控制台打开时用于临时静音
func pause_music() -> void:
	if _music_player != null and _music_player.playing:
		_music_player.stream_paused = true

## 恢复被暂停的背景音乐（从暂停位置继续播放）
func resume_music() -> void:
	if _music_player != null:
		_music_player.stream_paused = false

## 从资源路径加载并播放BGM（自动开启循环），先停止当前BGM
## path: BGM 资源的 res:// 路径，为空或不存在则仅停止当前BGM
## loop: 是否循环。胜利音乐等一次性结算音乐传 false，避免无限重复
func _play_bgm_from_path(path: String, loop: bool = true) -> void:
	if _music_player == null:
		return
	stop_music()
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if stream == null:
		return
	## 设置循环模式（MP3 与 WAV 属性不同）
	## 注意：load() 返回的是共享缓存资源，关闭循环时必须显式写回，否则残留标记会延续到下一次播放。
	## Vorbis 压缩的 AudioStreamWAV 不支持运行时把 loop_mode 设为 LOOP_FORWARD（会整段静音），
	## 故 WAV 一律只写 LOOP_DISABLED；WAV 的循环依赖导入期烘焙，运行时不再改 LOOP_FORWARD（#26）。
	if stream is AudioStreamMP3:
		stream.loop = loop
	elif stream is AudioStreamWAV:
		if not loop:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_music_player.stream = stream
	## 复位 stream_paused：任何历史 pause_music 残留（stream_paused=true）都会让 play() 后
	## 静音，且 stop()/play() 不会自动清除该标志（#9 防御）
	_music_player.stream_paused = false
	_music_player.play()
	## 自定义BGM使用空名称标记，避免与 play_music 的"同名不重启"机制冲突
	_current_music_name = ""

## 播放主菜单BGM
## 若 SettingsManager.menu_bgm 为"默认"则播放游戏自带 menu BGM，否则播放自定义BGM
func play_menu_bgm() -> void:
	_bgm_context = "menu"
	var bgm_name: String = SettingsManager.menu_bgm
	_last_menu_bgm = bgm_name
	## "默认"或空值时回退到游戏自带 menu BGM
	if bgm_name == "默认" or bgm_name == "":
		play_music("menu")
		return
	var path: String = SettingsManager.BGM_PATHS.get(bgm_name, "")
	if path == "":
		play_music("menu")
		return
	_play_bgm_from_path(path)

## 设置变化后自动重播当前场景 BGM（#25：修复随机播放按钮改完设置后音乐不更新的问题）
## 随机播放按钮只改 SettingsManager.menu_bgm/battle_bgm 并写盘，本身不负责播放；
## 原先只有进入场景时的 _ready 调一次 play_menu_bgm，导致设置改了音乐却不切。
## 这里按当前上下文（_bgm_context）重播对应 BGM；deferred 避免同帧 stop+play 不发声。
## #26：仅在“与当前上下文对应的那一路 BGM 设置”真正变化时才重播，
## 避免在主菜单改战斗BGM时误把主菜单BGM也重播一遍。
func _on_settings_bgm_changed() -> void:
	if _bgm_context == "battle":
		if SettingsManager.battle_bgm != _last_battle_bgm:
			call_deferred("play_battle_bgm")
	else:
		if SettingsManager.menu_bgm != _last_menu_bgm:
			call_deferred("play_menu_bgm")

## 显式设定当前 BGM 上下文（由进入战斗/主菜单的场景在连接 settings_changed 之前调用）。
## 关键：避免进战斗初始化阶段 emit 的 settings_changed 按"menu"上下文 deferred 播主菜单 BGM，
## 覆盖了随后同步播放的战斗 BGM（deferred 晚于同步执行 → 覆盖）。
func set_bgm_context(ctx: String) -> void:
	_bgm_context = ctx

## 播放战斗BGM
## 若 SettingsManager.battle_bgm 为"默认"则播放游戏自带 battle BGM，否则播放自定义BGM
func play_battle_bgm() -> void:
	_bgm_context = "battle"
	var bgm_name: String = SettingsManager.battle_bgm
	_last_battle_bgm = bgm_name
	## "默认"或空值时回退到游戏自带 battle BGM
	if bgm_name == "默认" or bgm_name == "":
		play_music("battle")
		return
	var path: String = SettingsManager.BGM_PATHS.get(bgm_name, "")
	if path == "":
		play_music("battle")
		return
	_play_bgm_from_path(path)

## 游戏自带的默认胜利音乐（一次性播放，不循环）
const DEFAULT_VICTORY_BGM: String = "res://assets/audio/bgm/victory.wav"

## 播放胜利BGM（先停止当前BGM）
## "无" → 静音；"默认"/空 → 播放自带 victory.wav；其它 → 播放设置里选定的自定义BGM
## 修复：旧实现在"默认"分支直接 stop_music()，导致默认设置下胜利后完全没有音乐
func play_victory_bgm() -> void:
	if SettingsManager.victory_bgm == "无":
		stop_music()
		return
	if SettingsManager.victory_bgm == "默认" or SettingsManager.victory_bgm == "":
		if ResourceLoader.exists(DEFAULT_VICTORY_BGM):
			_play_bgm_from_path(DEFAULT_VICTORY_BGM, false)
		else:
			stop_music()
		return
	var victory_path: String = SettingsManager.BGM_PATHS.get(SettingsManager.victory_bgm, "")
	if victory_path != "":
		## 自定义胜利音乐同样按一次性播放处理
		_play_bgm_from_path(victory_path, false)
	else:
		stop_music()

## 获取 BGM 资源（带缓存）
## name: 音乐资源名称，加载路径为 res://assets/audio/bgm/{name}.mp3
func _get_music_stream(name: String) -> AudioStream:
	if _music_stream_cache.has(name):
		return _music_stream_cache[name]
	var path := "res://assets/audio/bgm/%s.mp3" % name
	if not ResourceLoader.exists(path):
		_music_stream_cache[name] = null
		return null
	var stream = load(path)
	## AudioStreamMP3 需要开启循环
	if stream is AudioStreamMP3:
		stream.loop = true
	_music_stream_cache[name] = stream
	return stream

func _apply_bus_volumes() -> void:  ## 应用音频总线音量（私有方法）
	var master_idx := AudioServer.get_bus_index("Master")  ## 获取 Master 总线索引
	if master_idx >= 0:  ## 如果 Master 总线存在
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))  ## 设置主总线音量（转换为分贝）

	var music_idx := AudioServer.get_bus_index("Music")  ## 获取 Music 总线索引
	if music_idx >= 0:  ## 如果 Music 总线存在
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume * master_volume))  ## 设置音乐总线音量（音乐音量×主音量）

	var sfx_idx := AudioServer.get_bus_index("SFX")  ## 获取 SFX 总线索引
	if sfx_idx >= 0:  ## 如果 SFX 总线存在
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume * master_volume))  ## 设置音效总线音量（音效音量×主音量）

	volumes_changed.emit()  ## 发出音量变更信号

## 停止所有正在播放的 SFX（对象池中所有播放器）
## 用于游戏结束时立即关闭攻击音效等持续性音效
func stop_all_sfx() -> void:
	for player in _sfx_player_pool:
		if is_instance_valid(player) and player.playing:
			player.stop()
	_active_attack_players.clear()

## 设置主音量
## value: 音量值（0.0 ~ 1.0），超出范围会被钳制
func set_master_volume(value: float) -> void:  ## 设置主音量方法
	## 使用 clampf 将值限制在 0.0 到 1.0 之间
	master_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volumes()  ## 应用总线音量

## 设置音效音量
## value: 音量值（0.0 ~ 1.0），超出范围会被钳制
func set_sfx_volume(value: float) -> void:  ## 设置音效音量方法
	## 使用 clampf 将值限制在 0.0 到 1.0 之间
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volumes()  ## 应用总线音量

## 设置音乐音量
## value: 音量值（0.0 ~ 1.0），超出范围会被钳制
func set_music_volume(value: float) -> void:  ## 设置音乐音量方法
	## 使用 clampf 将值限制在 0.0 到 1.0 之间
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volumes()  ## 应用总线音量

func linear_to_db(linear: float) -> float:  ## 线性音量值转换为分贝值
	if linear <= 0.0:  ## 如果线性值为 0 或负数
		return -80.0  ## 返回 -80 分贝（视为静音）
	return 20.0 * log(linear) / log(10.0)  ## 按公式计算分贝值：20 * log10(linear)
