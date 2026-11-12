@tool
extends RefCounted
## Una línea por tool para las personas (m12-46): la pestaña Tools de Extensiones la muestra
## traducida; la descripción que ve el agente (en inglés) queda en el tooltip. test_tool_summaries
## exige una línea por cada tool registrada en mcp/tools/ y ninguna de más.

const I18n := preload("../core/i18n.gd")

const SUMMARIES: Dictionary = {
	# Leer el proyecto
	"project_info": "Project data: Godot version, main scene, autoloads, input actions, plugins",  # i18n
	"list_files": "Lists the project's files with their resource type",  # i18n
	"scene_tree": "The node tree of a scene with types, scripts and changed properties",  # i18n
	"get_node": "Everything about one node: properties, script, groups, connections",  # i18n
	"editor_state": "What is open in the editor: scene, scripts, selection, running game",  # i18n
	"project_map": "A ranked map of the project around a topic, to get oriented",  # i18n
	"get_resource": "Reads a .tres/.res resource file",  # i18n
	"project_settings": "Reads project settings with their value and default",  # i18n
	# Editar escenas
	"add_node": "Adds a node to the open scene",  # i18n
	"add_nodes": "Builds a whole subtree of nodes in one step",  # i18n
	"duplicate_node": "Duplicates a node with its children",  # i18n
	"set_properties": "Changes properties of a node",  # i18n
	"remove_node": "Deletes a node and its children",  # i18n
	"reparent_node": "Moves a node under another parent",  # i18n
	"rename_node": "Renames a node",  # i18n
	"connect_signal": "Connects a signal in the scene",  # i18n
	"instantiate_scene": "Instances a .tscn scene under a parent",  # i18n
	"open_scene": "Opens a scene in the editor",  # i18n
	"save_scene": "Saves the current scene",  # i18n
	"bake": "Bakes the navigation, lightmaps or occluders of the open scene",  # i18n
	"create_scene": "Creates a new .tscn with a root node and optionally its script",  # i18n
	"attach_script": "Attaches a script to a node",  # i18n
	# Archivos
	"copy_file": "Copies a file or folder into the project",  # i18n
	"move_file": "Moves or renames a file or folder, keeping references",  # i18n
	"delete_file": "Deletes a file or folder of the project",  # i18n
	# Correr y jugar el juego
	"run_scene": "Runs a scene and returns the game's errors and Output",  # i18n
	"stop_scene": "Stops the running game",  # i18n
	"game_instance": "Lists, adds or stops instances of the running game",  # i18n
	"capture_game_frame": "Captures the current frame of the running game",  # i18n
	"run_regressions": "Repeats the saved playtest regressions without the agent",  # i18n
	"write_regressions_workflow": "Writes a GitHub Actions workflow that runs the regressions on every push",  # i18n
	"game_tree": "The live node tree of the running game",  # i18n
	"game_get": "Reads properties of a node in the running game",  # i18n
	"game_set": "Changes properties of a node in the running game, live",  # i18n
	"game_call": "Calls a method on a node in the running game",  # i18n
	"game_wait": "Waits in the running game until a condition is true",  # i18n
	"game_input": "Sends keys, actions, mouse and joypad input to the running game",  # i18n
	"game_find": "Finds nodes in the running game by class, group or name",  # i18n
	"game_ui": "What a player sees of the game's UI: texts and controls",  # i18n
	"game_ui_act": "Clicks or fills a control of the game's UI",  # i18n
	"game_script": "Runs a short script inside the running game",  # i18n
	"game_pause": "Pauses or resumes the running game",  # i18n
	"game_step": "Advances the paused game a few frames, playing inputs meanwhile",  # i18n
	"game_watch": "Watches nodes of the running game and lists what changed",  # i18n
	"game_monitors": "Samples the running game's performance monitors",  # i18n
	"game_breakpoint": "Sets or removes the agent's breakpoints in the game's scripts",  # i18n
	"game_stack": "Reads the stack and variables where the game stopped",  # i18n
	"game_debug": "Continues or steps the game stopped in the debugger",  # i18n
	"game_frames": "The frames of the last seconds of play, as files",  # i18n
	"profile_run": "Runs a scene with the script profiler on and returns the slowest functions",  # i18n
	"test_extension": "Tests the project's GDExtension in a separate headless Godot",  # i18n
	# Diagnóstico
	"get_errors": "Errors and warnings from the editor and the game since a mark",  # i18n
	"validate_scripts": "Parses GDScript and compiles C#, and returns the errors",  # i18n
	"capture_editor_viewport": "Captures the editor's 2D or 3D viewport",  # i18n
	# Validación
	"validate_physics": "Checks bodies, shapes and collision layers of a scene",  # i18n
	"validate_tilemap": "Checks the TileMapLayers of a scene",  # i18n
	# Ajustes del proyecto
	"set_project_setting": "Changes a project setting and saves project.godot",  # i18n
	"export_project": "Exports the project with one of its presets, in a separate Godot",  # i18n
	"set_input_action": "Creates or replaces an input action",  # i18n
	"remove_input_action": "Deletes an input action",  # i18n
	"set_autoload": "Adds or changes an autoload",  # i18n
	"remove_autoload": "Removes an autoload",  # i18n
	"plugin_enable": "Enables or disables an editor plugin of the project",  # i18n
	"install_extension": "Brings a tested GDExtension into the game as an addon",  # i18n
	"restart_editor": "Saves the scenes and restarts the editor",  # i18n
	"build_extension": "Builds the project's GDExtension and returns the compiler errors",  # i18n
	# Recursos
	"create_resource": "Creates and saves a .tres resource file",  # i18n
	"set_resource_properties": "Changes properties of a resource file and saves it",  # i18n
	# TileMaps
	"tilemap_get": "Reads a TileMapLayer: its TileSet and a map of the cells",  # i18n
	"tileset_add_atlas": "Adds a texture as an atlas source to a TileSet",  # i18n
	"tileset_add_scenes": "Adds scenes as tiles to a TileSet",  # i18n
	"tilemap_set_cells": "Places tiles on a TileMapLayer",  # i18n
	"tilemap_paint_terrain": "Paints cells with a terrain (autotiling)",  # i18n
	"tilemap_clear": "Empties every cell of a TileMapLayer",  # i18n
	# Animación
	"animation_get": "Reads an AnimationPlayer or the frames of an AnimatedSprite",  # i18n
	"animation_create": "Creates an animation in an AnimationPlayer",  # i18n
	"animation_set_track": "Adds or replaces a track of an animation",  # i18n
	"animation_remove": "Deletes an animation or one of its tracks",  # i18n
	"sprite_frames_set": "Sets the frames of an AnimatedSprite animation",  # i18n
	# Documentación de la API
	"class_info": "The API of a class in this editor's Godot version",  # i18n
	"search_api": "Searches this editor's Godot API by name or capability",  # i18n
	# Asset Store
	"asset_search": "Searches the Godot Asset Store",  # i18n
	"asset_details": "The Asset Store page of an asset",  # i18n
	"asset_install": "Downloads and installs an asset from the Asset Store (always asks)",  # i18n
	"addons_list": "Lists the editor plugins in addons/ and whether they're enabled",  # i18n
	# Sesiones y subagentes
	"sessions": "Lists the other agent sessions open in this editor",  # i18n
	"session_send": "Sends a short message to another agent session",  # i18n
	"request_mode": "Proposes switching the session to another mode, with a card for the user",  # i18n
	"ask_second_opinion": "Asks another agent for a read-only second opinion",  # i18n
}


## La línea traducida de `tool_name`, o «» si no tiene.
static func summary(tool_name: String) -> String:
	return I18n.t(SUMMARIES[tool_name]) if SUMMARIES.has(tool_name) else ""
