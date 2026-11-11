extends "res://tests/unit/test_case.gd"
## m11-32: exportar una sesión, con lo que se saca por privacidad.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionExport := preload("res://addons/godot_agent/session/session_export.gd")
const SessionExportDialog := preload("res://addons/godot_agent/ui/dock/session_export_dialog.gd")
const UntrustedText := preload("res://addons/godot_agent/mcp/untrusted_text.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")

const PROJECT := "/home/ana/games/pong"
const HOME := "/home/ana"
const TOKEN := "tok-1234567890abcdef"
## Un PNG de 1×1.
const PNG := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="


func _model() -> SessionModel:
	var model := SessionModel.new()
	model.add_user_message("Fix the paddle in %s/paddle.gd, ping me at ana@example.com" % PROJECT)
	model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Looked at ~/notes and /home/bob/shared/x.txt and /tmp/run-1/log.txt. Token " + TOKEN}})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "t1", "title": "godot.game_get", "kind": "other", "status": "completed",
		"content": [{"type": "content", "content": {"type": "text", "text": "Score: " + UntrustedText.wrap("Player Ana: 12")}}]})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "t2", "title": "godot.capture_game_frame", "kind": "other", "status": "completed",
		"content": [{"type": "content", "content": {"type": "image", "mimeType": "image/png", "data": PNG}}]})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "t3", "title": "Edit paddle.gd", "kind": "edit", "status": "completed",
		"content": [{"type": "diff", "path": PROJECT + "/paddle.gd", "oldText": "a\nspeed = 1\nb", "newText": "a\nspeed = 2\nb"}]})
	return model


## El Agent Log vive mientras el test: el Callable de redact no lo retiene (como el del controller).
var _log: AgentLog


func _context() -> Dictionary:
	if _log == null:
		_log = AgentLog.new()
		_log.add_secret(TOKEN)
	var log := _log
	return {"title": "Paddle", "project": PROJECT, "home": HOME, "emails": PackedStringArray(["ana@example.com"]), "redact": log.redact}


func test_find_counts_what_is_there() -> void:
	var raw := SessionExport.build(_model(), _context(), {})
	var found := SessionExport.find(str(raw.raw), _context())
	assert_true(PROJECT in found.paths, "la ruta del proyecto: %s" % [found.paths])
	assert_true("/home/bob" in found.paths, "la carpeta de otro usuario")
	assert_true("/tmp/run-1/log.txt" in found.paths, "otra ruta absoluta")
	assert_eq(found.emails, PackedStringArray(["ana@example.com"]), "el email")
	assert_eq(int(found.untrusted), 1, "un sobre")
	assert_eq((raw.images as Array).size(), 1, "una captura")


func test_everything_removed() -> void:
	var markdown := str(SessionExport.build(_model(), _context(), {"paths": true, "emails": true, "untrusted": true, "images": true}).markdown)
	assert_false(markdown.contains(HOME) or markdown.contains("/home/") or markdown.contains("/tmp/"), "sin rutas absolutas:\n" + markdown)
	assert_true(markdown.contains("./paddle.gd"), "la del proyecto queda relativa")
	assert_true(markdown.contains("~/notes") and markdown.contains("~/shared/x.txt"), "las carpetas personales como ~")
	assert_true(markdown.contains("<path>"), "las demás, tapadas")
	assert_false(markdown.contains("ana@example.com"), "sin email")
	assert_false(markdown.contains("Player Ana") or markdown.contains("untrusted nonce"), "sin el contenido del sobre")
	assert_true(markdown.contains(SessionExport.UNTRUSTED_REMOVED), "y dice que lo sacó")
	assert_false(markdown.contains(TOKEN), "el secreto no sale")
	assert_true(markdown.contains("(capture removed)") and not markdown.contains("capture-1.png"), "sin capturas")


func test_kept_and_structure() -> void:
	var built := SessionExport.build(_model(), _context(), {})
	var markdown := str(built.markdown)
	assert_true(markdown.begins_with("# Paddle"), "el título")
	assert_true(markdown.contains("## You") and markdown.contains("## Agent"), "pedidos y respuestas")
	assert_true(markdown.contains("Player Ana: 12") and not markdown.contains("untrusted nonce"), "el sobre que queda va sin sus marcas")
	assert_true(markdown.contains(PROJECT) and markdown.contains("ana@example.com"), "lo que no se marcó queda")
	assert_false(markdown.contains(TOKEN), "el secreto sale siempre")
	assert_true(markdown.contains("![godot.capture_game_frame](capture-1.png)"), "la captura enlazada")
	assert_true(markdown.contains("```diff\n-speed = 1\n+speed = 2\n```"), "el diff, solo lo que cambió")
	assert_true(markdown.contains("<details><summary>✓ godot.game_get</summary>"), "las tool calls plegadas")


func test_write() -> void:
	var root := "user://test_session_export"
	var built := SessionExport.build(_model(), _context(), {"paths": true})
	var path := SessionExport.write(root, "2026-11-11_10-00-00", built)
	assert_eq(path, root + "/2026-11-11_10-00-00-session/session.md", "la carpeta del export")
	assert_eq(FileAccess.get_file_as_string(path), built.markdown, "el texto que se vio")
	assert_true(FileAccess.file_exists(path.get_base_dir().path_join("capture-1.png")), "la captura al lado")
	for file: String in DirAccess.get_files_at(path.get_base_dir()):
		DirAccess.remove_absolute(path.get_base_dir().path_join(file))
	DirAccess.remove_absolute(path.get_base_dir())
	DirAccess.remove_absolute(root)


func test_dialog_preview_and_save() -> void:
	var dialog := SessionExportDialog.new()
	dialog.root = "user://test_session_export_dialog"
	dialog.setup(_model(), _context())
	var options := dialog.options()
	assert_true(options.paths and options.emails and options.untrusted, "por defecto saca rutas, emails y lo de afuera")
	assert_false(options.images, "y deja las capturas")
	assert_false(dialog.preview_text().contains(PROJECT) or dialog.preview_text().contains("ana@example.com"), "la vista previa ya va filtrada")
	var boxes: Dictionary = dialog.get(&"_boxes")
	assert_true(str(boxes.emails.text).ends_with("(1)") and str(boxes.paths.tooltip_text).contains("/home/bob"), "cada casilla dice qué encontró")
	boxes.emails.button_pressed = false
	assert_true(dialog.preview_text().contains("ana@example.com"), "desmarcar cambia la vista previa")
	var saved: Array[String] = []
	dialog.saved.connect(func(path: String) -> void: saved.append(path))
	dialog.save()
	assert_eq(saved.size(), 1, "guarda")
	if saved.size() == 1:
		assert_eq(FileAccess.get_file_as_string(saved[0]), dialog.preview_text(), "lo que se guarda es lo que se vio")
		var dir := saved[0].get_base_dir()
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)
		DirAccess.remove_absolute(dialog.root)
	dialog.free()
