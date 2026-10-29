@tool
extends RefCounted
## Project settings por el editor (m4-09): project_settings (grupo read) y set_project_setting,
## set_input_action, remove_input_action, set_autoload, remove_autoload (grupo project). Cada
## cambio es una acción del historial global de deshacer del editor y guarda project.godot, así el
## agente no lo escribe a mano (D48).

const McpTool := preload("../mcp_tool.gd")
const ValueCoercion := preload("value_coercion.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const ACTION_PREFIX := "Agent: "
const LIST_LIMIT := 400
## Prefijos con tool propia: set_project_setting no los toca.
const OWN_TOOL_PREFIXES: Dictionary = {
	"input/": "set_input_action / remove_input_action",
	"autoload/": "set_autoload / remove_autoload",
	"editor_plugins/": "plugin_enable",
}
const MOUSE_BUTTONS: Dictionary = {
	"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP, "wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
	"wheel_left": MOUSE_BUTTON_WHEEL_LEFT, "wheel_right": MOUSE_BUTTON_WHEEL_RIGHT,
	"xbutton1": MOUSE_BUTTON_XBUTTON1, "xbutton2": MOUSE_BUTTON_XBUTTON2,
}
const JOY_BUTTONS: Dictionary = {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "guide": JOY_BUTTON_GUIDE, "start": JOY_BUTTON_START,
	"left_stick": JOY_BUTTON_LEFT_STICK, "right_stick": JOY_BUTTON_RIGHT_STICK,
	"left_shoulder": JOY_BUTTON_LEFT_SHOULDER, "right_shoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}
const JOY_AXES: Dictionary = {
	"left_x": JOY_AXIS_LEFT_X, "left_y": JOY_AXIS_LEFT_Y, "right_x": JOY_AXIS_RIGHT_X,
	"right_y": JOY_AXIS_RIGHT_Y, "trigger_left": JOY_AXIS_TRIGGER_LEFT, "trigger_right": JOY_AXIS_TRIGGER_RIGHT,
}
const EVENT_HELP := "Events: a key (\"Space\", \"W\", \"Ctrl+S\", \"key:Escape\"), \"mouse:left|right|middle|wheel_up|wheel_down\", \"joy_button:a|b|x|y|start|dpad_up…\" (or a number), \"joy_axis:left_x:-\" (left_x, left_y, right_x, right_y, trigger_left, trigger_right; + or -)."


func tools() -> Array:
	var project := PermissionPolicy.GROUP_PROJECT
	return [
		McpTool.create("project_settings", PermissionPolicy.GROUP_READ,
			"Reads project settings with their current value and default. With `prefix` (e.g. \"display/window\", \"physics/2d\"), every setting under it; without it, only the ones that differ from the default. Input actions and autoloads are in project_info.",
			{"prefix": {"type": "string"}}, [], _project_settings),
		McpTool.create("set_project_setting", project,
			"Changes a project setting through the editor and saves project.godot (with undo). Never edit project.godot by hand: the harness rejects it. `value` is converted to the setting's type (vectors as [x, y], colors as \"#rrggbb\", enums by name or number); null resets it to the default.",
			{"name": {"type": "string", "description": "Full name, e.g. display/window/size/viewport_width"}, "value": {}},
			["name"], _set_project_setting),
		McpTool.create("set_input_action", project,
			"Creates or replaces an input action with its events and saves project.godot (with undo). " + EVENT_HELP + " `append`=true keeps the existing events.",
			{
				"action": {"type": "string"},
				"events": {"type": "array", "description": "Event specs (strings)"},
				"deadzone": {"type": "number", "description": "Default 0.2 for new actions"},
				"append": {"type": "boolean"},
			}, ["action", "events"], _set_input_action),
		McpTool.create("remove_input_action", project, "Deletes an input action and saves project.godot (with undo).",
			{"action": {"type": "string"}}, ["action"], _remove_input_action),
		McpTool.create("set_autoload", project,
			"Adds or changes an autoload (a .gd or .tscn that is always loaded, reachable by its name as a global) and saves project.godot (with undo).",
			{
				"name": {"type": "string", "description": "Global name, e.g. GameState"},
				"path": {"type": "string", "description": "res://…gd or res://…tscn"},
				"enabled": {"type": "boolean", "description": "Global variable enabled (default true)"},
			}, ["name", "path"], _set_autoload),
		McpTool.create("remove_autoload", project, "Removes an autoload and saves project.godot (with undo).",
			{"name": {"type": "string"}}, ["name"], _remove_autoload),
	]


# --- tools ---------------------------------------------------------------------------------------

func _project_settings(args: Dictionary) -> Dictionary:
	var prefix := McpTool.str_arg(args, "prefix").strip_edges().trim_suffix("/")
	var lines: PackedStringArray = []
	var count := 0
	for info: Dictionary in ProjectSettings.get_property_list():
		var name := str(info.name)
		if not "/" in name or name.begins_with("input/") or name.begins_with("autoload/") or int(info.usage) & PROPERTY_USAGE_CATEGORY:
			continue
		if not prefix.is_empty() and not (name == prefix or name.begins_with(prefix + "/")):
			continue
		var value: Variant = ProjectSettings.get_setting(name)
		var default_value: Variant = ProjectSettings.property_get_revert(name)
		var changed := not _same(value, default_value)
		if prefix.is_empty() and not changed:
			continue
		count += 1
		if count > LIST_LIMIT:
			continue
		lines.append("%s = %s%s" % [name, _value_text(value), "  (default %s)" % _value_text(default_value) if changed else ""])
	if count == 0:
		return McpTool.text("No settings under \"%s\"." % prefix if not prefix.is_empty() else "Every setting has its default value.")
	var header := "%d setting(s)%s%s:" % [count, " under " + prefix if not prefix.is_empty() else " that differ from the default", " (first %d; narrow the prefix)" % LIST_LIMIT if count > LIST_LIMIT else ""]
	return McpTool.text(header + "\n" + "\n".join(lines))


func _set_project_setting(args: Dictionary) -> Dictionary:
	var name := str(args.name).strip_edges()
	if not "/" in name:
		return McpTool.error("`name` must be a full setting path like display/window/size/viewport_width.")
	for prefix: String in OWN_TOOL_PREFIXES:
		if name.begins_with(prefix):
			return McpTool.error("%s is changed with %s, not with set_project_setting." % [name, OWN_TOOL_PREFIXES[prefix]])
	var exists := ProjectSettings.has_setting(name)
	var old_value: Variant = ProjectSettings.get_setting(name) if exists else null
	var new_value: Variant = args.get("value")
	if new_value == null:
		if not exists:
			return McpTool.error("%s does not exist." % name)
		new_value = ProjectSettings.property_get_revert(name)
	elif exists:
		var info := ValueCoercion.property_info(ProjectSettings, name)
		var type := int(info.get("type", typeof(old_value)))
		var converted: Variant = ValueCoercion.convert_value(new_value, type, info)
		if converted is Dictionary and converted.has("__error"):
			return McpTool.error("%s (%s): %s" % [name, type_string(type), converted.__error])
		new_value = converted
	var action := ACTION_PREFIX + "project setting %s" % name
	_commit(action, [[name, new_value, old_value if exists else null]])
	var text := "%s: %s → %s. Saved project.godot." % [name, _value_text(old_value) if exists else "(new)", _value_text(ProjectSettings.get_setting(name))]
	if not exists:
		text += " Note: it did not exist before; check the name if you expected a built-in setting (project_settings with a prefix lists them)."
	if _needs_restart(name):
		text += " This setting is read at startup: it applies the next time the game runs."
	return _done(text, action)


func _set_input_action(args: Dictionary) -> Dictionary:
	var action_name := str(args.action).strip_edges()
	if action_name.is_empty() or action_name.contains("/"):
		return McpTool.error("`action` must be a name without slashes, e.g. jump or move_left.")
	var key := "input/" + action_name
	var existing: Variant = ProjectSettings.get_setting(key) if ProjectSettings.has_setting(key) else null
	var events: Array = []
	if args.get("append") == true and existing is Dictionary:
		events.append_array(existing.get("events", []))
	for spec: Variant in args.events:
		var parsed: Variant = parse_event(spec)
		if parsed is String:
			return McpTool.error(parsed)
		var duplicate := false
		for event: InputEvent in events:
			if event.is_match(parsed, true):
				duplicate = true
		if not duplicate:
			events.append(parsed)
	var deadzone := float(args.get("deadzone", existing.get("deadzone", 0.2) if existing is Dictionary else 0.2))
	var action := ACTION_PREFIX + "input action %s" % action_name
	_commit(action, [[key, {"deadzone": deadzone, "events": events}, existing]])
	var described: PackedStringArray = []
	for event: InputEvent in events:
		described.append(describe_event(event))
	return _done("%s %s: %s (deadzone %s). Saved project.godot. Read it in code with Input.is_action_pressed(\"%s\")." % [
		"Changed" if existing != null else "Created", action_name, ", ".join(described) if not described.is_empty() else "(no events)", deadzone, action_name], action)


func _remove_input_action(args: Dictionary) -> Dictionary:
	var key := "input/" + str(args.action).strip_edges()
	if not ProjectSettings.has_setting(key):
		return McpTool.error("There is no input action %s. Actions: %s." % [args.action, ", ".join(_names_with_prefix("input/"))])
	var action := ACTION_PREFIX + "remove input action %s" % args.action
	_commit(action, [[key, null, ProjectSettings.get_setting(key)]])
	return _done("Deleted the input action %s. Saved project.godot." % args.action, action)


func _set_autoload(args: Dictionary) -> Dictionary:
	var name := str(args.name).strip_edges()
	if not name.is_valid_identifier():
		return McpTool.error("`name` must be a valid identifier, e.g. GameState.")
	var key := "autoload/" + name
	var existing: Variant = ProjectSettings.get_setting(key) if ProjectSettings.has_setting(key) else null
	if existing == null:
		if ClassDB.class_exists(name) or Engine.has_singleton(name):
			return McpTool.error("%s is the name of a Godot class or singleton: choose another one." % name)
		for info: Dictionary in ProjectSettings.get_global_class_list():
			if str(info["class"]) == name:
				return McpTool.error("%s is already a class_name (%s): an autoload cannot have the same name." % [name, info.path])
	var path := str(args.path)
	if not path.begins_with("res://") or path.get_extension() not in ["gd", "cs", "tscn", "scn"]:
		return McpTool.error("`path` must be res://…gd, res://…cs or res://…tscn.")
	if not FileAccess.file_exists(path):
		return McpTool.error("%s does not exist: create it first." % path)
	var value := ("*" if args.get("enabled", true) != false else "") + path
	var action := ACTION_PREFIX + "autoload %s" % name
	_commit(action, [[key, value, existing]])
	return _done("%s autoload %s = %s%s. Saved project.godot." % ["Changed" if existing != null else "Added", name, path, "" if value.begins_with("*") else " (no global variable)"], action)


func _remove_autoload(args: Dictionary) -> Dictionary:
	var key := "autoload/" + str(args.name).strip_edges()
	if not ProjectSettings.has_setting(key):
		return McpTool.error("There is no autoload %s. Autoloads: %s." % [args.name, ", ".join(_names_with_prefix("autoload/"))])
	var action := ACTION_PREFIX + "remove autoload %s" % args.name
	_commit(action, [[key, null, ProjectSettings.get_setting(key)]])
	return _done("Removed the autoload %s. Saved project.godot." % args.name, action)


# --- eventos de input ----------------------------------------------------------------------------

## InputEvent para una especificación de texto, o el error.
static func parse_event(spec: Variant) -> Variant:
	if not spec is String or str(spec).strip_edges().is_empty():
		return "Each event must be a non-empty string. " + EVENT_HELP
	var text := str(spec).strip_edges()
	var kind := text.get_slice(":", 0).to_lower() if ":" in text else "key"
	var rest := text.substr(text.find(":") + 1) if ":" in text else text
	match kind:
		"key":
			var parts := rest.split("+", false)
			if parts.is_empty():
				return "Empty key in \"%s\"." % text
			var event := InputEventKey.new()
			for modifier: String in parts.slice(0, parts.size() - 1):
				match modifier.strip_edges().to_lower():
					"ctrl", "control":
						event.ctrl_pressed = true
					"shift":
						event.shift_pressed = true
					"alt", "option":
						event.alt_pressed = true
					"meta", "cmd", "command", "super":
						event.meta_pressed = true
					"cmdorctrl", "commandorcontrol":
						event.command_or_control_autoremap = true
					_:
						return "Unknown modifier \"%s\" in \"%s\" (Ctrl, Shift, Alt, Meta, CmdOrCtrl)." % [modifier, text]
			var keycode := OS.find_keycode_from_string(parts[parts.size() - 1].strip_edges())
			if keycode == KEY_NONE:
				return "Unknown key \"%s\" in \"%s\" (use Godot names: Space, Enter, Escape, Up, A, F1, Kp 1…)." % [parts[parts.size() - 1], text]
			event.physical_keycode = keycode
			return event
		"mouse":
			var button := rest.strip_edges().to_lower()
			if not MOUSE_BUTTONS.has(button):
				return "Unknown mouse button \"%s\". Valid: %s." % [rest, ", ".join(PackedStringArray(MOUSE_BUTTONS.keys()))]
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTONS[button]
			return mouse
		"joy_button", "joypad", "joy":
			var name := rest.strip_edges().to_lower()
			var index: int = JOY_BUTTONS.get(name, int(name) if name.is_valid_int() else -1)
			if index < 0:
				return "Unknown joypad button \"%s\". Valid: %s, or a number." % [rest, ", ".join(PackedStringArray(JOY_BUTTONS.keys()))]
			var joy := InputEventJoypadButton.new()
			joy.button_index = index
			return joy
		"joy_axis":
			var axis_name := rest.get_slice(":", 0).strip_edges().to_lower()
			var sign_text := rest.get_slice(":", 1).strip_edges() if rest.get_slice_count(":") > 1 else ""
			var axis: int = JOY_AXES.get(axis_name, int(axis_name) if axis_name.is_valid_int() else -1)
			if axis < 0 or not sign_text in ["+", "-"]:
				return "Use joy_axis:<axis>:<+|->, e.g. joy_axis:left_x:-. Axes: %s." % ", ".join(PackedStringArray(JOY_AXES.keys()))
			var motion := InputEventJoypadMotion.new()
			motion.axis = axis
			motion.axis_value = 1.0 if sign_text == "+" else -1.0
			return motion
	return "Unknown event kind \"%s\". %s" % [kind, EVENT_HELP]


static func describe_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var keycode := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var label := OS.get_keycode_string(key.get_modifiers_mask() | keycode)
		if key.command_or_control_autoremap:
			label = "CmdOrCtrl+" + label
		return "key %s%s" % [label, " (physical)" if key.physical_keycode != KEY_NONE else ""]
	if event is InputEventMouseButton:
		var index := (event as InputEventMouseButton).button_index
		for name: String in MOUSE_BUTTONS:
			if MOUSE_BUTTONS[name] == index:
				return "mouse %s" % name
	if event is InputEventJoypadButton:
		var button := (event as InputEventJoypadButton).button_index
		for name: String in JOY_BUTTONS:
			if JOY_BUTTONS[name] == button:
				return "joy_button %s" % name
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		for name: String in JOY_AXES:
			if JOY_AXES[name] == motion.axis:
				return "joy_axis %s%s" % [name, "+" if motion.axis_value > 0 else "-"]
	return event.as_text()


# --- internos ------------------------------------------------------------------------------------

## Una acción de deshacer global con los cambios [clave, nuevo, anterior] (null = no existe) que
## guarda project.godot al hacer y al deshacer.
func _commit(action: String, changes: Array) -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, ProjectSettings)
	for change: Array in changes:
		var key: String = change[0]
		var order := ProjectSettings.get_order(key) if ProjectSettings.has_setting(key) else -1
		undo_redo.add_do_method(ProjectSettings, &"set_setting", key, change[1])
		undo_redo.add_undo_method(ProjectSettings, &"set_setting", key, change[2])
		if order >= 0:
			undo_redo.add_undo_method(ProjectSettings, &"set_order", key, order)
	undo_redo.add_do_method(ProjectSettings, &"save")
	undo_redo.add_undo_method(ProjectSettings, &"save")
	undo_redo.commit_action()


static func _names_with_prefix(prefix: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for info: Dictionary in ProjectSettings.get_property_list():
		if str(info.name).begins_with(prefix):
			names.append(str(info.name).trim_prefix(prefix))
	return names


static func _needs_restart(name: String) -> bool:
	return name.begins_with("display/") or name.begins_with("rendering/") or name.begins_with("application/run/")


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return (a == null and b == null) or (typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(a), float(b)))
	return a == b


static func _value_text(value: Variant) -> String:
	if value is String or value is StringName:
		return "\"%s\"" % value
	return var_to_str(value).replace("\n", " ")


static func _done(text: String, action: String) -> Dictionary:
	return McpTool.text("%s\nUndo step: «%s» (Ctrl+Z in the editor)." % [text, action])
