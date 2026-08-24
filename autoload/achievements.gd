extends Node
## 成就系统（独立，不发放星星）
## 仅记录成就解锁状态，持久化复用 CampaignProgress._achievements
## 触发来源：战斗结算 evaluate_battle + 进度检查 check_progress

## 成就目录：id / 名称 / 描述（纯荣誉激励，无任何数值奖励）
## #13（2026-08-09）批次：新增 7 个成就、修改 4 个成就、删除「尸山血海」、调整 2 个计时成就
## #需求12（2026-08-09）：新增魔法学徒/骑士精神；经验+3、区区小敌、区区强敌、我来我见我征服、大力出奇迹 改隐藏；肉鸽成就更名
const ACHIEVEMENTS: Array[Dictionary] = [
	{id = "first_win", name = "初战告捷", desc = "赢得任意一场战斗"},
	## 原「首次通关任意战役关卡」已改为难度向条件（普通模式过关不再计入）
	{id = "first_hard_win", name = "攻城拔寨", desc = "首次赢得困难模式"},
	{id = "first_hell_win", name = "炼狱归来", desc = "首次赢得地狱模式"},
	{id = "no_damage_win", name = "毫发无伤", desc = "一场胜利且己方基地未受任何伤害"},
	{id = "speed_clear", name = "速战速决", desc = "一场胜利且耗时不足 240 秒"},  ## #需求8：120 → 240
	{id = "blitz_clear", name = "闪电突袭", desc = "任意困难/地狱模式中 240 秒内胜利"},  ## #需求8：90 → 240
	{id = "flawless_commander", name = "指挥若定", desc = "同场战斗无伤且 240 秒内取胜"},  ## #需求8：90 → 240
	{id = "campaign_complete", name = "我来，我见，我征服", desc = "通关全部 10 个战役关卡", hidden = true},  ## 战役征服者 → 更名；#需求12 改隐藏
	{id = "all_units", name = "兵种大师", desc = "解锁全部 24 个兵种"},
	{id = "star_collector", name = "星耀将星", desc = "累计获得 20 颗星"},  ## #16：10 → 20
	{id = "kills_200", name = "百战之师", desc = "累计击杀敌方单位达到 500"},  ## 200 → 500
	{id = "kills_500", name = "血染沙场", desc = "累计击杀敌方单位达到 1000"},  ## 500 → 1000
	{id = "kills_800", name = "万军之敌", desc = "累计击杀敌方单位达到 1500"},  ## 800 → 1500
	## —— 新增成就（2026-08-09）——
	{id = "level_3_clear", name = "区区小敌", desc = "通过第三关", hidden = true},  ## #需求12 改隐藏
	{id = "level_6_clear", name = "区区强敌", desc = "通过第六关", hidden = true},  ## #需求12 改隐藏
	{id = "sword_master", name = "剑术大师", desc = "使用 N2 击杀敌方单位达到 500"},
	{id = "aoe_multi_kill", name = "大力出奇迹", desc = "任意己方兵种一次攻击击杀三名及以上敌方单位", hidden = true},  ## #需求12 改隐藏
	{id = "fast_defeat", name = "经验+3", desc = "任意一关中在 30 秒内被打败", hidden = true},  ## #需求12 改隐藏
	{id = "day_night", name = "日夜交替", desc = "点击左上角太阳", hidden = true},  ## 隐藏成就
	{id = "roguelike_g1", name = "无名小卒还是名扬天下", desc = "肉鸽模式全程只使用 G1 兵种通关一次"},  ## 肉鸽专属；#需求12 更名
	{id = "magic_apprentice", name = "魔法学徒", desc = "使用 N1 击杀敌方单位达到 500"},  ## #需求12 新增
	{id = "knight_spirit", name = "骑士精神", desc = "地狱模式最后一关全程只部署 F 系兵种并获胜"},  ## #需求12 新增
	## #新需求（2026-08-10）：为了欧润橘！—— 隐藏成就，战役模式累计购买 500 次 Doro 兵种触发
	## 达成后 Doro勇士（Hero2）进入兵种解锁池（需 20 颗星，见 CampaignProgress.ACHIEVEMENT_GATED_UNITS）
	{id = "for_orange", name = "为了欧润橘！", desc = "累计购买 500 次 Doro 兵种", hidden = true},
	## #Hero4/Hero5（2026-08-21）：战役模式累计部署 500 次 G系（咕嘎）兵种 → 解锁咕咕嘎嘎Hero
	## 达成后咕咕嘎嘎Hero（Hero4）进入兵种解锁池（需 20 颗星，见 CampaignProgress.ACHIEVEMENT_GATED_UNITS）
	{id = "gugu_legion", name = "咕嘎军团", desc = "累计部署 500 次咕嘎兵种", hidden = true},
	## #Hero5（2026-08-21）：战役模式累计部署 500 次 N系（糯糯）兵种 → 解锁糯糯Hero
	{id = "nuo_legion", name = "糯糯大军", desc = "累计部署 500 次糯糯兵种", hidden = true},
	{id = "anomaly_invasion", name = "异象入侵", desc = "第一次触发异象入侵", hidden = true},
	{id = "parallel_heroes", name = "平行时空的英雄们", desc = "第一次触发特殊事件", hidden = true},
	## #16（2026-08-11）：上帝模式 —— 解锁开发者模式时自动解锁（F11 / 图鉴秘技 abay→G1 待机连按）
	{id = "god_mode", name = "上帝模式", desc = "解锁开发者模式", hidden = true},
	## #自由事件（2026-08-15）：召唤/异象事件成就（判定模式见 _is_achievement_mode：
	## 开发者模式战役/全面/双人都判，非开发者仅战役；#12 用户拍板：全部为隐藏成就）
	{id = "blue_witch_summon", name = "来自异世界的蓝色魔法师", desc = "第一次召唤蓝女巫兵种", hidden = true},
	{id = "death_reaper_summon", name = "死亡使者", desc = "第一次召唤死亡使者", hidden = true},
	{id = "hamster_summon", name = "鼠鼠我呀", desc = "第一次召唤仓鼠士兵", hidden = true},
	{id = "penguin_sacrifice", name = "偏我来时不逢春", desc = "凑企鹅死亡时己方水晶还存在", hidden = true},
	{id = "penguin_irony", name = "我草了老铁，那本来是属于我的", desc = "我方水晶死亡时凑企鹅还存在于场上", hidden = true},
]

## 自定义成就音效（#12 用户拍板）：部分成就解锁成功时播放专属语音
## 键为成就 ID，值为 res:// 音效路径
const ACHIEVEMENT_SOUND_PATHS: Dictionary = {
	"penguin_sacrifice": "res://assets/audio/sfx/achievements/penguin_sacrifice.wav",  ## 偏我来时不逢春
	"penguin_irony": "res://assets/audio/sfx/achievements/penguin_irony.wav",  ## 我草了老铁，那本来是属于我的
}

## 最近一次新解锁的成就（用于结算时弹窗提示）
var _last_unlocked: Dictionary = {}

## #需求12：骑士精神 —— 本局玩家部署过的兵种 ID 集合（战斗开始时清空，出兵时记录）
## 用户拍板判定语义：「本局部署兵种集合只含 F1~F5 即算」通过地狱模式最后一关
var _deployed_units: Dictionary = {}

## 战斗开始时清空本局部署记录（由 battle_root 在每局 _ready 调用）
func reset_deployed_units() -> void:
	_deployed_units.clear()

## 玩家出兵时记录兵种 ID（由 battle_root 在玩家出兵回调调用，仅玩家侧 pid==0）
## 兼作「为了欧润橘！」的 D 系购买计数：战役模式每部署一个 D 前缀兵种 +1（持久计数）
func record_player_deploy(unit_id: String) -> void:
	if unit_id == "":
		return
	_deployed_units[unit_id] = true
	## 出兵计数成就：仅战役模式统计（用户拍板），跨启动持久累加
	if not _is_achievement_mode():
		return
	## 为了欧润橘！：累计部署 D 系兵种
	if String(unit_id).begins_with("D"):
		var total: int = CampaignProgress.add_doro_purchases(1)
		if total >= 500:
			_try_unlock("for_orange")
	## 咕嘎军团：累计部署 G 系（咕嘎）兵种
	elif String(unit_id).begins_with("G"):
		var g: int = CampaignProgress.add_gugu_purchases(1)
		if g >= 500:
			_try_unlock("gugu_legion")
	## 糯糯大军：累计部署 N 系（糯糯）兵种
	elif String(unit_id).begins_with("N"):
		var n: int = CampaignProgress.add_nuo_purchases(1)
		if n >= 500:
			_try_unlock("nuo_legion")

## 本局部署集合是否「只含 F 系兵种」（F1~F5）
## 用户拍板语义：集合非空且所有成员都是 F 系 → 即算「全程只使用 F 兵种」
func _is_f_only_deploy() -> bool:
	if _deployed_units.is_empty():
		return false
	for id in _deployed_units:
		if not String(id).begins_with("F"):
			return false
	return true

## —— 解锁反馈去重（防止同一批解锁被重复处理）——
## _try_unlock 只入队，反馈统一延后到本帧末尾 flush；
## 同一成就只会解锁一次（unlock_achievement 去重），因此批内不存在重复项。
## 本帧内累积的新解锁成就
var _pending_unlocks: Array[Dictionary] = []
## 本帧是否已排入 flush（防止同帧重复排队）
var _flush_scheduled: bool = false
## 提示框顺序播放队列（避免多个 toast 叠在右下角同一坐标）
var _toast_queue: Array[Dictionary] = []
var _toast_busy: bool = false
## 成就解锁音效路径（#20 批量连播用）
const ACHIEVEMENT_SOUND_PATH: String = "res://assets/audio/achievement_unlock.wav"
## #13（2026-08-09）：音效改为「随每个弹窗同时播放」，弹窗停留 3 秒（toast 内部 HOLD_TIME=3.0）。
## 相邻两个提示框的间隔：0.35s 滑入 + 3.0s 停留 + 0.35s 滑出 + 少量缓冲
const TOAST_SPACING: float = 3.6

## 战斗结算时调用，根据战绩解锁对应成就
## stats: battle_root 采集的战绩字典
func evaluate_battle(stats: Dictionary) -> void:
	## 双人模式 / 全面战争模式不计入成就（仅战役模式判定）
	if not _is_achievement_mode():
		return
	## 累计击杀已由 battle_root._on_unit_died 实时入账（#21），结算不再重复累加；
	## 胜负均已在战斗中实时判定过阈值成就，这里只需按战绩解锁其余成就。
	if stats.get("winner_team", 1) != 0:
		## 失败局仍需检查累计类成就（击杀数可能刚好跨过阈值）
		check_progress()
		## #新增：经验+3 —— 任意一关中 30 秒内被打败（先判定失败类再 return）
		if stats.get("elapsed", 999.0) < 30.0:
			_try_unlock("fast_defeat")
		return
	_try_unlock("first_win")
	## 难度向成就：0=普通 1=困难 2=地狱；赢地狱同时满足困难条件，故用 >=
	var difficulty: int = int(stats.get("difficulty", GameManager.current_difficulty))
	if difficulty >= 1:
		_try_unlock("first_hard_win")
	if difficulty >= 2:
		_try_unlock("first_hell_win")
	if stats.get("player_base_damage_taken", 1) <= 0:
		_try_unlock("no_damage_win")
	var elapsed: float = stats.get("elapsed", 999.0)
	## #需求8（2026-08-09）：速战速决 / 闪电突袭 / 指挥若定 三个计时成就统一改 240 秒
	if elapsed < 240.0:
		_try_unlock("speed_clear")
	## 闪电突袭 = 任意困难/地狱模式中 240 秒内胜利
	if difficulty >= 1 and elapsed < 240.0:
		_try_unlock("blitz_clear")
	if elapsed < 240.0 and stats.get("player_base_damage_taken", 1) <= 0:
		_try_unlock("flawless_commander")
	## 新增：区区小敌（通过第三关）/ 区区强敌（通过第六关）
	var level: int = int(stats.get("level", GameManager.selected_campaign_level))
	if level >= 3:
		_try_unlock("level_3_clear")
	if level >= 6:
		_try_unlock("level_6_clear")
	## #需求12：骑士精神 —— 地狱模式（difficulty>=2）最后一关（level>=10）全程只部署 F 系兵种
	if level >= CampaignProgress.MAX_LEVEL and difficulty >= 2 and _is_f_only_deploy():
		_try_unlock("knight_spirit")
	check_progress()

## 进度类成就检查（购买/胜利后调用）
func check_progress() -> void:
	## 双人模式 / 全面战争模式同样跳过进度成就
	if not _is_achievement_mode():
		return
	if CampaignProgress.get_player_unlocked_ids().size() >= CampaignProgress.ALL_UNITS.size():
		_try_unlock("all_units")
	## #16（2026-08-09）：星耀将星 10 → 20 颗星
	if CampaignProgress.get_total_stars() >= 20:
		_try_unlock("star_collector")
	if CampaignProgress.completed_levels.size() >= CampaignProgress.MAX_LEVEL:
		_try_unlock("campaign_complete")
	## 累计击杀阈值成就（阈值函数复用，与实时击杀 record_kill 共用）
	_try_unlock_by_kills(CampaignProgress.get_total_kills())
	## 为了欧润橘！：累计购买 500 次 Doro 兵种（持久计数，兜底判定）
	if CampaignProgress.get_doro_purchases() >= 500:
		_try_unlock("for_orange")
	## 咕嘎军团：累计部署 500 次咕嘎兵种（持久计数，兜底判定）
	if CampaignProgress.get_gugu_purchases() >= 500:
		_try_unlock("gugu_legion")
	## 糯糯大军：累计部署 500 次糯糯兵种（持久计数，兜底判定）
	if CampaignProgress.get_nuo_purchases() >= 500:
		_try_unlock("nuo_legion")

## #21：实时击杀记录（battle_root 每击杀一个敌方单位调用一次）
## 战役模式下累加总击杀并即时判定阈值成就（战斗中实时弹出，不等结算）；
## 双人/全面战争模式由 _is_achievement_mode 拦截，不污染战役累计。
func record_kill(count: int = 1) -> void:
	if count <= 0:
		return
	if not _is_achievement_mode():
		return
	CampaignProgress.add_kills(count)
	_try_unlock_by_kills(CampaignProgress.get_total_kills())

## 剑术大师（N2 击杀 500）：unit_base.die 在击杀发生时实时上报击杀者兵种 ID
## 战役模式下按兵种累加击杀数，N2 击杀满 500 即时解锁（战斗中实时弹出，不等结算）
func record_unit_kill(unit_id: String) -> void:
	if unit_id == "" or not _is_achievement_mode():
		return
	CampaignProgress.record_unit_kill(unit_id)
	if unit_id == "N2" and CampaignProgress.get_unit_kills("N2") >= 500:
		_try_unlock("sword_master")
	## #需求12：魔法学徒 —— 使用 N1 击杀 500 个敌人
	if unit_id == "N1" and CampaignProgress.get_unit_kills("N1") >= 500:
		_try_unlock("magic_apprentice")

## 大力出奇迹：任意己方兵种一次攻击击杀 ≥3 名敌方单位
## unit_base.die 内按「攻击方本次攻击击杀计数」跨目标累计，满 3 即时上报
func record_multi_kill() -> void:
	if not _is_achievement_mode():
		return
	_try_unlock("aoe_multi_kill")

## 按 ID 强制尝试解锁（供非战斗触发点使用，如「日夜交替」点击太阳）
## 内部经 unlock_achievement 去重：已解锁返回 false，不重复发弹窗/音效
func unlock_by_id(id: String) -> bool:
	return _try_unlock(id)

## #自由事件成就（2026-08-15）：带模式门解锁 —— 仅当处于允许判定成就的模式才解锁。
## 开发者模式下战役/全面/双人都判定；非开发者仅战役。用于召唤/异象类成就的实时判定点。
func unlock_by_id_in_mode(id: String) -> bool:
	if not _is_achievement_mode():
		return false
	return _try_unlock(id)

## 肉鸽专属成就「传奇，还是无名小卒？」：全程只使用 G1 兵种通关一次。
## 肉鸽模式不属于战役模式（_is_achievement_mode 会拦截），此路径不经该检查，
## 直接校验 RoguelikeManager 记录的本次 run 部署兵种集合（run 级，start_run 重置）。
func unlock_roguelike_g1_legend() -> void:
	var deployed: Array = RoguelikeManager.run_deployed_ids.keys()
	if deployed.is_empty():
		return
	for id in deployed:
		if str(id) != "G1":
			return
	_try_unlock("roguelike_g1")

## 按累计击杀数尝试解锁阈值成就（500/1000/1500 三档，全部命中时逐个解锁）
## #13（2026-08-09）：200/500/800 → 500/1000/1500（id 保持原样，避免破坏已存档解锁状态）
func _try_unlock_by_kills(kills: int) -> void:
	if kills >= 500:
		_try_unlock("kills_200")
	if kills >= 1000:
		_try_unlock("kills_500")
	if kills >= 1500:
		_try_unlock("kills_800")

## 当前是否处于允许判定成就的模式
## 开发者模式下：战役/全面战争/双人 都判定（便于调试自由事件成就）；
## 非开发者模式：仅战役模式判定，双人/全面战争一律跳过
func _is_achievement_mode() -> bool:
	if DevMode.enabled:
		return true  ## 开发者模式：全部常规模式判定（肉鸽另走专属路径）
	if BattleManager.is_two_player:
		return false
	return GameManager.is_campaign_mode

## 尝试解锁成就，首次解锁返回 true 并把该成就排入本帧反馈队列
## 注意：这里不直接播音效/弹提示，统一交给帧末 _flush_unlock_feedback 去重后处理
func _try_unlock(id: String) -> bool:
	if not CampaignProgress.unlock_achievement(id):
		return false
	_play_achievement_sound(id)  ## #12：成就专属音效（偏我来时不逢春 / 我草了老铁 等，解锁成功即播）
	for e in ACHIEVEMENTS:
		if e.id == id:
			_last_unlocked = e
			_pending_unlocks.append(e)
			break
	_schedule_unlock_feedback()
	return true

## 播放成就专属音效（#12）：该成就配置了 ACHIEVEMENT_SOUND_PATHS 路径时播放
## #14 修复：延迟到帧末播放——解锁瞬间可能紧跟 end_game()（其 AudioManager.stop_all_sfx()
## 会把刚播的成就语音掐断，如「我方水晶死亡」路径先解锁再 end_game）。
## 帧末执行时 stop_all_sfx 已过；且此时树可能已 paused，故用独立 PROCESS_MODE_ALWAYS
## 播放器（不依赖 SFX 池的 PAUSABLE 播放器），失败界面下也能完整听到成就语音。
func _play_achievement_sound(id: String) -> void:
	var path: String = ACHIEVEMENT_SOUND_PATHS.get(id, "")
	if path.is_empty():
		return
	_play_achievement_sound_deferred.call_deferred(path)

func _play_achievement_sound_deferred(path: String) -> void:
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.process_mode = Node.PROCESS_MODE_ALWAYS  ## 暂停树期间也能播（失败界面场景）
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	get_tree().root.add_child(player)
	player.play()
	## 播放完成自动释放（防节点泄漏）
	player.finished.connect(func() -> void:
		if is_instance_valid(player):
			player.queue_free()
	)

## 把反馈刷新排到本帧末尾（同帧多次解锁只排一次）
func _schedule_unlock_feedback() -> void:
	if _flush_scheduled:
		return
	_flush_scheduled = true
	_flush_unlock_feedback.call_deferred()

## 帧末统一反馈：同一批解锁的成就全部入队，提示框依次弹出（_drain_toast_queue 按间隔顺序弹出，不重叠）。
## #13：音效不再提前 stagger 连播，改为每个弹窗弹出时同步播放（见 _drain_toast_queue）。
## 并发说明：若本协程 await 期间又有新成就解锁，会产生第二个 flush 协程，
## 各协程只处理自己 batch 复制的条目，先后顺序由解锁时序保证，不重复、不丢失。
func _flush_unlock_feedback() -> void:
	_flush_scheduled = false
	if _pending_unlocks.is_empty():
		return
	var batch: Array[Dictionary] = _pending_unlocks.duplicate()
	_pending_unlocks.clear()
	for e in batch:
		_toast_queue.append(e)
	_drain_toast_queue()

## 顺序消费提示框队列，避免多个 toast 叠在右下角同一坐标
## #13：每个弹窗弹出时同步播放一次解锁音效（音效随弹窗同时响起）
func _drain_toast_queue() -> void:
	if _toast_busy:
		return
	_toast_busy = true
	while not _toast_queue.is_empty():
		var entry: Dictionary = _toast_queue.pop_front()
		## #24：成就解锁音效必须强制播放，不受音频节流（点击/出兵单并发锁）影响
		AudioManager.play_sound_path(ACHIEVEMENT_SOUND_PATH, true)
		_show_achievement_toast(entry)
		## 结算界面可能处于暂停树，计时器默认 process_always=true 不受影响
		await get_tree().create_timer(TOAST_SPACING).timeout
	_toast_busy = false

## 弹出成就解锁提示框（右下角滑入）
func _show_achievement_toast(entry: Dictionary) -> void:
	var scene: PackedScene = load("res://scenes/ui/achievement_toast.tscn")
	if scene == null:
		return
	var toast: CanvasLayer = scene.instantiate() as CanvasLayer
	if toast == null:
		push_warning("[成就] achievement_toast.tscn 根节点不是 CanvasLayer")
		return
	## 先配置内容再入树：结算界面实例化期间 root 处于「正在初始化子节点」状态，
	## 直接 add_child 会失败，必须 call_deferred；动画由 toast 自身 _ready 触发
	toast.configure(entry)
	## #14 修复：toast 提到最高层（原默认 layer=1 < HUD layer=2）——失败界面（game_over_screen）
	## 全屏背景挂在 HUD 下，layer 更高会把右下角成就弹窗整个盖住（用户反馈「输了的时候成就
	## 不在失败界面右下角弹出」）。提到 100 保证任何结算/暂停界面之下都能显示。
	toast.layer = 100
	get_tree().root.add_child.call_deferred(toast)

## 查询成就是否已解锁
func is_unlocked(id: String) -> bool:
	return CampaignProgress.is_achievement_unlocked(id)

## 返回成就目录（供 UI 展示）
func get_catalog() -> Array[Dictionary]:
	return ACHIEVEMENTS
