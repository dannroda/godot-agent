@tool
extends AcceptDialog
## Reproduce la filmación de un playtest (m15-23): los JPEG de una carpeta, cargando solo el frame que
## se muestra, con play/pausa y una barra para moverse. Godot no reproduce AVI ni MP4 en el editor.
## Idea del Flipbook de ui/widgets.gd de Autopilot (ramenvr/autopilot, Apache 2.0).

const AgentTheme := preload("agent_theme.gd")
const I18n := preload("../core/i18n.gd")

const DEFAULT_FPS := 4.0

var _folder: String = ""
var _frames: PackedStringArray = []
var _fps: float = DEFAULT_FPS
var _index: int = -1
var _elapsed: float = 0.0
var _playing: bool = true
var _picture: TextureRect
var _scrub: HSlider
var _play: Button
var _time: Label


## Abre el visor de una carpeta con frames. false si no hay ninguno.
static func open(folder: String, near: Node) -> bool:
	var frames := frames_of(folder)
	if frames.is_empty():
		return false
	var dialog: AcceptDialog = new()
	dialog.show_film(folder, frames, near)
	return true


static func frames_of(folder: String) -> PackedStringArray:
	var path := ProjectSettings.globalize_path(folder)
	var frames: PackedStringArray = []
	if DirAccess.dir_exists_absolute(path):
		for name: String in DirAccess.get_files_at(path):
			if name.get_extension() == "jpg":
				frames.append(name)
	frames.sort()
	return frames


func show_film(folder: String, frames: PackedStringArray, near: Node) -> void:
	_folder = ProjectSettings.globalize_path(folder)
	_frames = frames
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(_folder.path_join("film.json")))
	if manifest is Dictionary and float(manifest.get("fps", 0.0)) > 0.0:
		_fps = float(manifest.fps)
	title = I18n.t("Playtest recording")
	ok_button_text = I18n.t("Close")
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var column := VBoxContainer.new()
	add_child(column)
	_picture = TextureRect.new()
	_picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_picture)
	var row := HBoxContainer.new()
	column.add_child(row)
	_play = Button.new()
	_play.pressed.connect(_toggle)
	row.add_child(_play)
	_scrub = HSlider.new()
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrub.max_value = maxi(frames.size() - 1, 0)
	_scrub.value_changed.connect(func(value: float) -> void: _show(int(value)))
	_scrub.drag_started.connect(func() -> void: _set_playing(false))
	row.add_child(_scrub)
	_time = Label.new()
	row.add_child(_time)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	var host: Node = EditorInterface.get_base_control() if AgentTheme.has_editor() else near.get_tree().root
	host.add_child(self)
	popup_centered_ratio(0.7)
	_show(0)
	_set_playing(true)


func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return
	_elapsed += delta
	if _elapsed < 1.0 / _fps:
		return
	_elapsed = 0.0
	if _index + 1 >= _frames.size():
		_set_playing(false)
	else:
		_scrub.value = _index + 1


func _show(index: int) -> void:
	if index == _index or index < 0 or index >= _frames.size():
		return
	_index = index
	var image := Image.load_from_file(_folder.path_join(_frames[index]))
	if image != null and not image.is_empty():
		_picture.texture = ImageTexture.create_from_image(image)
	_time.text = "%.1f / %.1f s" % [index / _fps, (_frames.size() - 1) / _fps]


func _toggle() -> void:
	if not _playing and _index + 1 >= _frames.size():
		_scrub.value = 0
	_set_playing(not _playing)


func _set_playing(playing: bool) -> void:
	_playing = playing
	_play.text = I18n.t("Pause") if playing else I18n.t("Play")
