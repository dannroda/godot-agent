extends "test_case.gd"
## Reporte del turno (m11-06): lo que contó el agente, los archivos y las capturas.

const TurnReport := preload("res://addons/godot_agent/session/turn_report.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")


func test_collect_and_write() -> void:
	var model := SessionModel.new()
	model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Before the turn."}})
	var first := model.entries().size()
	model.add_user_message("add a jump")
	model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "I added the jump."}})
	var png := Image.create(2, 2, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "c1", "title": "godot.capture_game_frame", "kind": "other", "status": "completed",
		"content": [{"type": "content", "content": {"type": "image", "mimeType": "image/png", "data": Marshalls.raw_to_base64(png)}}]})
	var collected := TurnReport.collect(model, first)
	assert_eq(collected.summary, "I added the jump.", "solo lo del turno")
	assert_eq(collected.images.size(), 1, "la captura")
	var root := ProjectSettings.globalize_path("user://unit_tests/turn_report")
	AddonUpdater._remove_tree(root)
	var path := TurnReport.write(root, "2026-10-27_20-00-00", "Turn report", collected, [{"path": "player.gd", "status": "M", "added": 3, "removed": 1}])
	assert_eq(path, root.path_join("2026-10-27_20-00-00/report.md"), "report.md en su carpeta")
	var text := FileAccess.get_file_as_string(path)
	assert_true(text.contains("I added the jump.") and text.contains("`player.gd` changed (+3 −1)") and text.contains("](capture-1.png)"), "resumen, archivos y captura: %s" % text)
	assert_eq(FileAccess.get_file_as_bytes(root.path_join("2026-10-27_20-00-00/capture-1.png")), png, "la captura tal cual")
