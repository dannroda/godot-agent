@tool
extends RefCounted
## Las plantillas de «Nueva receta» (m11-30): tres pedidos que se repiten, para copiar y ajustar. El
## contenido va en inglés como cualquier receta (es del usuario, y el agente lo lee igual); el nombre
## del menú se traduce.

const Recipes := preload("recipes.gd")

## `[{id, label, data}]`: `label` es un msgid; `data`, la receta (pasa Recipes.from_data sin errores).
static func all() -> Array[Dictionary]:
	return [
		{"id": "enemy", "label": "Enemy from a base scene",  # i18n
			"data": {
				"version": Recipes.VERSION,
				"title": "New enemy",
				"description": "A new enemy that inherits a base scene, with its own behavior and speed.",
				"mode": "build",
				"plan": false,
				"prompt": "Create a new enemy called {{name}} as an inherited scene of {{base}}. It should {{behavior}}, moving at {{speed}} pixels per second. Put it next to the base scene, reuse the base scene's script hooks instead of copying code, and add it to {{level}} so it can be tried.",
				"parameters": [
					{"key": "name", "type": "text", "label": "Name"},
					{"key": "base", "type": "scene", "label": "Base scene"},
					{"key": "behavior", "type": "choice", "label": "Behavior", "options": ["patrol between two points", "chase the player when it sees them", "stay still and shoot at the player"], "default": "patrol between two points"},
					{"key": "speed", "type": "number", "label": "Speed", "default": 80},
					{"key": "level", "type": "scene", "label": "Level to place it in"},
				],
				"checks": [
					{"kind": "regressions", "name": "Playtest regressions"},
				],
				"max_retries": 2,
			}},
		{"id": "options", "label": "Options screen",  # i18n
			"data": {
				"version": Recipes.VERSION,
				"title": "Options screen",
				"description": "An options screen that saves the settings and applies them right away.",
				"mode": "build",
				"plan": true,
				"prompt": "Add an options screen to the game with these settings:\n{{settings}}\nOpen it from {{menu}}. Save the values in user://settings.cfg with ConfigFile, load them when the game starts, and apply each change right away. Navigation must work with the keyboard and a gamepad. Apply immediately without a confirm button: {{immediate}}.",
				"parameters": [
					{"key": "settings", "type": "multiline", "label": "Settings", "default": "- Master volume\n- Music volume\n- Fullscreen"},
					{"key": "menu", "type": "scene", "label": "Menu that opens it"},
					{"key": "immediate", "type": "bool", "label": "Apply without confirming", "default": true},
				],
				"checks": [
					{"kind": "playtest", "name": "Options playtest", "goal": "open the options screen from the menu, change every setting with the keyboard, and check the change is applied and still there after closing and opening the screen again", "minutes": 5},
				],
				"max_retries": 2,
			}},
		{"id": "csharp", "label": "Port a script to C#",  # i18n
			"data": {
				"version": Recipes.VERSION,
				"title": "Port to C#",
				"description": "Rewrites a GDScript script in C# with the same behavior, and builds the project.",
				"mode": "build",
				"plan": false,
				"prompt": "Port {{script}} to C#: a partial class with the same name, the same exported properties and signals, and the same behavior. Replace the script on every scene that uses it. Keep the GDScript file: {{keep}}.",
				"parameters": [
					{"key": "script", "type": "script", "label": "Script", "filter": ["gd"]},
					{"key": "keep", "type": "bool", "label": "Keep the .gd file", "default": false},
				],
				"checks": [
					{"kind": "command", "name": "dotnet build", "command": "dotnet build"},
				],
				"max_retries": 3,
			}},
	]


## El texto del .json de una plantilla, como lo escribe «Nueva».
static func text(id: String) -> String:
	for template: Dictionary in all():
		if template.id == id:
			return JSON.stringify(template.data, "\t", false) + "\n"
	return ""


## Una ruta libre en `dir` para `slug` (slug.json, slug_2.json…).
static func free_path(dir: String, slug: String) -> String:
	var path := dir.path_join(slug + "." + Recipes.EXTENSION)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_%d.%s" % [slug, n, Recipes.EXTENSION])
		n += 1
	return path
