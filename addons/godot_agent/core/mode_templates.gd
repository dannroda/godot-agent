@tool
extends RefCounted
## Las plantillas de «Nuevo modo» (m11-39): tres modos del proyecto que se repiten, para copiar y
## ajustar. El contenido va en inglés como cualquier modo (lo lee el agente); el nombre del menú se traduce.

const ProjectModes := preload("project_modes.gd")


## `[{id, label, data}]`: `label` es un msgid; `data`, el modo (pasa ProjectModes.from_data sin errores).
static func all() -> Array[Dictionary]:
	return [
		{"id": "levels", "label": "Level design",  # i18n
			"data": {
				"version": ProjectModes.VERSION,
				"name": "Level design",
				"base": "build",
				"when_to_use": "Building and tweaking levels: layout, props, enemies and pickups",
				"instructions": "Work only on level scenes and their resources. Build levels by instancing the existing scenes (props, enemies, pickups) instead of creating new scripts. After a change, run the level with godot.run_scene and check the player can get from the start to the exit.",
				"editable": ["res://levels/**"],
				"shell": "ask",
				"icon": "TileMap",
			}},
		{"id": "shaders", "label": "Shaders",  # i18n
			"data": {
				"version": ProjectModes.VERSION,
				"name": "Shaders",
				"base": "build",
				"when_to_use": "Writing and tuning shaders and materials",
				"instructions": "Work only on shaders and materials. Keep uniforms with hints (source_color, hint_range) so they can be tuned in the inspector. Check the result with godot.capture_game_frame.",
				"editable": ["*.gdshader", "*.gdshaderinc", "res://materials/**"],
				"shell": "deny",
				"icon": "Shader",
			}},
		{"id": "tests", "label": "Tests only",  # i18n
			"data": {
				"version": ProjectModes.VERSION,
				"name": "Tests only",
				"base": "build",
				"when_to_use": "Writing tests without touching the game's code",
				"instructions": "Write and fix tests only. If a test fails because of the game's code, don't change the game: explain the bug and where it is.",
				"editable": ["res://tests/**"],
				"shell": "ask",
				"icon": "Debug",
			}},
	]


static func text(id: String) -> String:
	for template: Dictionary in all():
		if template.id == id:
			return JSON.stringify(template.data, "\t") + "\n"
	return ""
