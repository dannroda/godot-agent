extends RefCounted
## Filmación liviana del juego (m15-22): JPEG chicos a pocos fps que el probe le manda al editor, que
## los guarda en disco. Sirve para mirar lo que pasó hace unos segundos y para reproducir el run en el
## dock (m15-23), sin cerrar el juego ni fijarle los fps como el Movie Maker.
## El hilo del juego no espera a la GPU ni al encoder: lectura asíncrona (Forward+ y Mobile) y JPEG en
## el WorkerThreadPool; en Compatibility no hay lectura asíncrona y se usa get_image(), a estos pocos fps.
## Basado en lib/media.gd de Autopilot (ramenvr/autopilot, Apache 2.0).

const MAX_SIDE := 640
const QUALITY := 0.7
## Una lectura que no llegó en este tiempo se abandona (un resize puede perderla).
const STALE_MS := 3000
const FPS_MIN := 0.5
const FPS_MAX := 30.0


class FilmJob:
	extends RefCounted
	var lock := Mutex.new()
	var number := 0
	var game_time := 0.0
	var started_ms := 0
	var read := false
	var use_get_image := false
	var image: Image = null
	var bytes := PackedByteArray()
	var width := 0
	var height := 0
	var format := -1
	var linear := false
	var task := -1
	var jpeg := PackedByteArray()

	func set_read(data: PackedByteArray) -> void:
		lock.lock()
		bytes = data
		read = true
		lock.unlock()

	func fall_back() -> void:
		lock.lock()
		use_get_image = true
		read = true
		lock.unlock()


var running := false
var _host: Node
var _period := 0.25
var _next_at := 0.0
var _number := 0
var _job: FilmJob = null


func _init(host: Node) -> void:
	_host = host


## Por qué no hay imagen, o "" si la hay.
static func no_picture() -> String:
	if DisplayServer.get_name() == "headless":
		return "the game runs headless: nothing is drawn"
	if RenderingServer.get_current_rendering_driver_name() == "dummy":
		return "the game runs without rendering"
	return ""


func start(fps: float) -> void:
	_period = 1.0 / clampf(fps, FPS_MIN, FPS_MAX)
	_next_at = 0.0
	_job = null
	running = true


func stop() -> void:
	running = false
	_job = null


## Cada frame: entrega lo terminado y empieza el próximo frame cuando le toca. `send`: Callable(n, t, jpeg).
func tick(now: float, game_time: float, send: Callable) -> void:
	if not running:
		return
	if _job != null and _advance(_job):
		if not _job.jpeg.is_empty():
			send.call(_job.number, _job.game_time, _job.jpeg)
		_job = null
	if _job != null or now < _next_at or _host.get_tree().paused:
		return  # pausado la imagen no cambia: no gasta disco
	_next_at = now + _period
	_job = FilmJob.new()
	_job.number = _number
	_number += 1
	_job.game_time = game_time
	_job.started_ms = Time.get_ticks_msec()
	var texture := _host.get_viewport().get_texture()
	var device := RenderingServer.get_rendering_device()
	if texture == null:
		_job = null
	elif device == null:
		_job.fall_back()
	else:
		RenderingServer.call_on_render_thread(_read_on_render_thread.bind(device, texture.get_rid(), _job))


## true si el trabajo terminó (bien o mal).
func _advance(job: FilmJob) -> bool:
	if job.task >= 0:
		if not WorkerThreadPool.is_task_completed(job.task):
			return false
		WorkerThreadPool.wait_for_task_completion(job.task)
		job.task = -1
		return true
	job.lock.lock()
	var read := job.read
	var use_get_image := job.use_get_image
	job.lock.unlock()
	if not read:
		return Time.get_ticks_msec() - job.started_ms > STALE_MS
	if use_get_image:
		job.image = _host.get_viewport().get_texture().get_image()
		if job.image == null or job.image.is_empty():
			return true
	job.task = WorkerThreadPool.add_task(_encode.bind(job), false, "Godot Agent film")
	return false


static func _read_on_render_thread(device: RenderingDevice, rid: RID, job: FilmJob) -> void:
	var texture := RenderingServer.texture_get_rd_texture(rid)
	if not texture.is_valid() or not device.texture_is_valid(texture):
		job.fall_back()
		return
	var format: RDTextureFormat = device.texture_get_format(texture)
	var image_format := -1
	var linear := false
	match format.format:
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			image_format = Image.FORMAT_RGBA8
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			image_format = Image.FORMAT_RGBAH
			linear = true
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
			image_format = Image.FORMAT_RGBAF
			linear = true
	if image_format < 0:
		job.fall_back()  # get_image() convierte los demás formatos
		return
	job.lock.lock()
	job.width = format.width
	job.height = format.height
	job.format = image_format
	job.linear = linear
	job.lock.unlock()
	if device.texture_get_data_async(texture, 0, job.set_read) != OK:
		job.fall_back()


## En un worker: escala y codifica.
static func _encode(job: FilmJob) -> void:
	var image := job.image
	if image == null:
		var pixel: int = {Image.FORMAT_RGBA8: 4, Image.FORMAT_RGBAH: 8, Image.FORMAT_RGBAF: 16}.get(job.format, 0)
		var size := job.width * job.height * pixel
		if size <= 0 or job.bytes.size() < size:
			return
		image = Image.create_from_data(job.width, job.height, false, job.format, job.bytes if job.bytes.size() == size else job.bytes.slice(0, size))
	if image == null or image.is_empty():
		return
	if image.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]:
		job.linear = true
	if image.get_format() not in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8]:
		image.convert(Image.FORMAT_RGBA8)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > MAX_SIDE:
		var scale := float(MAX_SIDE) / longest
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	if job.linear:
		image.linear_to_srgb()
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	job.jpeg = image.save_jpg_to_buffer(QUALITY)
