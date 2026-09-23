extends Node  ## 继承 Node，作为全局单例节点存在
## Web 按需资源包加载器（全局单例，2026-09-14 新增）
## 仅在 Web 导出且 PACK_ENABLED=true 时生效：主包不再包含兵种动画图集（resources/units/*/*_sheet.png
## 与 S1_attack/），这些图集单独导出为 pack_units.pck（导出预设「Web-PackUnits」），首次需要时下载到
## user:// 缓存并挂载进 PackedData，之后本次会话内常驻。
## PACK_ENABLED=false（当前值，单体包模式）：图集已合并进主 pck，Web 端只上传 html+js+wasm+pck 一套
## 文件，不再请求任何外部资源包，所有 ensure_* 立即返回。
## 桌面 / Android 导出未拆包，所有 ensure_* 立即返回，运行行为与从前完全一致。
##
## 使用方式：进入依赖单位动画的场景前 `await WebPackLoader.ensure_units()`；
## 主菜单 / 开屏可无 await 调用做后台预取。重复调用安全（单飞 + 幂等）。

## 资源包文件名（部署在网页同目录）
const PACK_FILE_NAME: String = "pack_units.pck"
## 资源包内容变更（重新导出图集）时把版本号 +1：缓存文件名随之变化，强制浏览器重新下载
const PACK_VERSION: int = 1
const CACHE_DIR: String = "user://pack_cache"
## 单体包开关：false = 图集已合并进主 pck（Web 只需上传 html+js+wasm+pck 一套文件），
## 不再额外下载 pack_units.pck，全部 ensure_* 直接返回。改为 true 即恢复按需分包模式。
const PACK_ENABLED: bool = false

signal units_mounted  ## 图集包挂载成功后发出（预留调试 / 后续扩展）
signal _fetch_finished  ## 下载协程收尾信号（成败都发，让排队的调用方返回）

var _mounted: bool = false  ## 是否已挂载
var _downloading: bool = false  ## 单飞标志：同一时间只允许一个下载协程

func is_units_ready() -> bool:  ## 兵种图集当前是否可直接 load（单体包 / 桌面端恒 true）
	return _mounted or not PACK_ENABLED or not OS.has_feature("web")

func ensure_units() -> void:  ## 确保图集包已挂载；未挂载则等待 / 发起下载
	if is_units_ready():
		return
	if _downloading:
		await _fetch_finished  ## 已有下载在跑：排队等它收尾（若失败则本次直接返回，下次调用会重试）
		return
	_downloading = true
	var ok: bool = await _download_and_mount()
	_downloading = false
	if ok:
		_mounted = true
		units_mounted.emit()
	_fetch_finished.emit()

func _download_and_mount() -> bool:  ## 读缓存或下载 → 写入 user:// → 挂载进 PackedData
	var cache_path: String = "%s/%s_v%d.pck" % [CACHE_DIR, PACK_FILE_NAME.get_basename(), PACK_VERSION]
	if not FileAccess.file_exists(cache_path):
		var body: PackedByteArray = await _download_pack()
		if body.is_empty():
			return false  ## 保持未挂载，后续 ensure_units() 会再次尝试
		body = _inflate_if_gzip(body)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
		var writer: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
		if writer == null:
			push_warning("WebPackLoader: 缓存写入失败 " + cache_path)
			return false
		writer.store_buffer(body)
		writer.close()
	# 注意：ProjectSettings.load_resource_pack() 返回 bool，不是 Error
	var ok_mount: bool = ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(cache_path), true)
	if not ok_mount:
		push_warning("WebPackLoader: 资源包挂载失败 %s" % cache_path)
		return false
	print("WebPackLoader: 兵种图集包已挂载 ", cache_path)
	return true

func _inflate_if_gzip(body: PackedByteArray) -> PackedByteArray:  ## minimize_html_build 插件会把导出目录里的 .pck 压成 gzip，这里按需还原
	if body.size() < 2 or body[0] != 0x1f or body[1] != 0x8b:
		return body  ## 未压缩的原生 pck，原样返回
	var raw: PackedByteArray = body.decompress(FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		push_warning("WebPackLoader: gzip 解压失败，回退按原包处理")
		return body
	print("WebPackLoader: gzip 资源包已解压 %d -> %d 字节" % [body.size(), raw.size()])
	return raw

func _download_pack() -> PackedByteArray:  ## 拉取资源包字节；失败返回空数组
	var url: String = _build_pack_url()
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	var err: Error = http.request(url)
	if err != OK:
		push_warning("WebPackLoader: 资源包请求发起失败 err=%d url=%s" % [err, url])
		http.queue_free()
		return PackedByteArray()
	var result: Array = await http.request_completed  ## [result, response_code, headers, body]
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		push_warning("WebPackLoader: 资源包下载失败 result=%d http=%d url=%s（请确认 pack_units.pck 已导出并与网页同目录部署）" % [result[0], result[1], url])
		return PackedByteArray()
	return result[3]

func _build_pack_url() -> String:  ## 与网页同目录的资源包地址
	var query: String = "?v=%d" % PACK_VERSION
	if OS.has_feature("web"):
		var base: Variant = JavaScriptBridge.eval("new URL('.', window.location.href).href", true)
		if base is String and not String(base).is_empty():
			return String(base) + PACK_FILE_NAME + query
	return "./" + PACK_FILE_NAME + query  ## JS 不可用时兜底相对路径
