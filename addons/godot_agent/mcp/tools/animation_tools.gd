@tool
extends RefCounted
## Tools de animación (m4-12): animation_get (grupo read) y animation_create, animation_set_track,
## animation_remove y sprite_frames_set (grupo edit_scene). set_properties no llega a pistas ni
## keyframes: sin estas tools el agente animaba por código o escribía la biblioteca a mano.
## Deshacer: cada cambio a una animación arma una copia editada y la acción cambia la copia por la
## original en su AnimationLibrary (y al revés). SpriteFrames se restaura cuadro por cuadro.

const McpTool := preload("../mcp_tool.gd")
const SceneAccess := preload("scene_access.gd")
const ValueCoercion := preload("value_coercion.gd")
const EditorUndo := preload("../../editor/editor_undo.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const ACTION_PREFIX := "Agent: "
const SCENE_ARG := {"type": "string", "description": "res://…tscn scene; opened if it is not the current one (default: the open one)"}
const PLAYER_ARG := {"type": "string", "description": "NodePath of the AnimationPlayer"}
const LOOP_MODES: Dictionary = {"none": Animation.LOOP_NONE, "linear": Animation.LOOP_LINEAR, "pingpong": Animation.LOOP_PINGPONG}
const INTERPOLATIONS: Dictionary = {
	"nearest": Animation.INTERPOLATION_NEAREST, "linear": Animation.INTERPOLATION_LINEAR, "cubic": Animation.INTERPOLATION_CUBIC,
	"linear_angle": Animation.INTERPOLATION_LINEAR_ANGLE, "cubic_angle": Animation.INTERPOLATION_CUBIC_ANGLE,
}
const UPDATE_MODES: Dictionary = {"continuous": Animation.UPDATE_CONTINUOUS, "discrete": Animation.UPDATE_DISCRETE, "capture": Animation.UPDATE_CAPTURE}
const KEYS_SHOWN := 24

## Callable(tool_name: String, args: Dictionary, undo_info: Dictionary): cada acción commiteada.
var on_action: Callable


func tools() -> Array:
	var scene := PermissionPolicy.GROUP_EDIT_SCENE
	return [
		McpTool.create("animation_get", PermissionPolicy.GROUP_READ,
			"Reads an AnimationPlayer (libraries, animations with length, loop and tracks) or an AnimatedSprite2D/3D (SpriteFrames animations). With `animation`, every key of that animation.",
			{"node_path": {"type": "string"}, "animation": {"type": "string"}, "scene": SCENE_ARG}, ["node_path"], _animation_get),
		McpTool.create("animation_create", scene,
			"Creates an animation in an AnimationPlayer (or changes the length/loop of an existing one), with undo. `name` may be \"library/anim\"; without a library it goes to the default one. `autoplay`=true plays it when the scene starts.",
			{
				"node_path": PLAYER_ARG, "name": {"type": "string"}, "length": {"type": "number"},
				"loop": {"type": "string", "enum": LOOP_MODES.keys()}, "autoplay": {"type": "boolean"}, "scene": SCENE_ARG,
			}, ["node_path", "name"], _animation_create),
		McpTool.create("animation_set_track", scene,
			"Adds a track to an animation, or replaces the keys of an existing one with the same path, in one undo step. Value track: `track` = \"NodePath:property\" relative to the player's root_node (e.g. \"Sprite2D:modulate\", \".:position\", \"Body:position:y\"); keys [{time, value, transition?}] with the value converted to the property type (vectors as [x, y], colors as \"#rrggbb\"). Method track: `type`=\"method\", `track` = \"NodePath\", keys [{time, method, args?}].",
			{
				"node_path": PLAYER_ARG, "animation": {"type": "string"}, "track": {"type": "string"},
				"type": {"type": "string", "enum": ["value", "method"]}, "keys": {"type": "array"},
				"interpolation": {"type": "string", "enum": INTERPOLATIONS.keys()},
				"update_mode": {"type": "string", "enum": UPDATE_MODES.keys()}, "scene": SCENE_ARG,
			}, ["node_path", "animation", "track", "keys"], _animation_set_track),
		McpTool.create("animation_remove", scene,
			"Deletes an animation from an AnimationPlayer, or only one of its tracks when `track` is given (with undo).",
			{"node_path": PLAYER_ARG, "animation": {"type": "string"}, "track": {"type": "string"}, "scene": SCENE_ARG},
			["node_path", "animation"], _animation_remove),
		McpTool.create("sprite_frames_set", scene,
			"Sets the frames of an animation of an AnimatedSprite2D/3D (creating its SpriteFrames if it has none), with undo. Frames from `frames` (image paths, in order) or from a sprite sheet `sheet` {texture, hframes, vframes, frames?: [indices] (default all)}. `fps` default 10, `loop` default true. `autoplay`=true plays it when the scene starts.",
			{
				"node_path": {"type": "string"}, "animation": {"type": "string"}, "frames": {"type": "array"},
				"sheet": {"type": "object"}, "fps": {"type": "number"}, "loop": {"type": "boolean"},
				"autoplay": {"type": "boolean"}, "scene": SCENE_ARG,
			}, ["node_path", "animation"], _sprite_frames_set),
	]


# --- tools ---------------------------------------------------------------------------------------

func _animation_get(args: Dictionary) -> Dictionary:
	var found := _node(args, ["AnimationPlayer", "AnimatedSprite2D", "AnimatedSprite3D"])
	if found.has("error"):
		return McpTool.error(found.error)
	var node: Node = found.node
	if node is AnimationPlayer:
		return McpTool.text(_player_text(node, McpTool.str_arg(args, "animation")))
	var frames: SpriteFrames = node.get(&"sprite_frames")
	if frames == null:
		return McpTool.text("%s has no SpriteFrames: create them with sprite_frames_set." % node.name)
	var lines: PackedStringArray = ["%s (%s), autoplay: %s" % [node.name, node.get_class(), node.get(&"autoplay") if not str(node.get(&"autoplay")).is_empty() else "(none)"]]
	for anim: StringName in frames.get_animation_names():
		var textures: PackedStringArray = []
		for i: int in frames.get_frame_count(anim):
			textures.append(_texture_text(frames.get_frame_texture(anim, i)))
		lines.append("- %s: %d frames, %s fps, loop %s: %s" % [anim, frames.get_frame_count(anim), frames.get_animation_speed(anim), frames.get_animation_loop(anim), ", ".join(textures.slice(0, KEYS_SHOWN))])
	return McpTool.text("\n".join(lines))


func _animation_create(args: Dictionary) -> Dictionary:
	var found := _node(args, ["AnimationPlayer"])
	if found.has("error"):
		return McpTool.error(found.error)
	var player: AnimationPlayer = found.node
	var names := _split_name(str(args.name))
	if str(names.anim).is_empty() or RegEx.create_from_string("[/:,\\[]").search(names.anim) != null:
		return McpTool.error("`name` is not a valid animation name (no \"/\", \":\", \",\" or \"[\").")
	var existing := _animation(player, names)
	var edited: Animation = existing.duplicate(true) as Animation if existing else Animation.new()
	if args.has("length"):
		if float(args.length) <= 0.0:
			return McpTool.error("`length` must be positive (seconds).")
		edited.length = float(args.length)
	if args.has("loop"):
		edited.loop_mode = LOOP_MODES[args.loop]
	var full_name := _full_name(names)
	var action := ACTION_PREFIX + "%s animation %s" % ["change" if existing else "create", full_name]
	var undo_redo := _begin(action, found.root)
	var library := _library_for(player, names.library, undo_redo)
	undo_redo.add_do_method(library, &"add_animation", names.anim, edited)
	if existing:
		undo_redo.add_undo_method(library, &"add_animation", names.anim, existing)
	else:
		undo_redo.add_undo_method(library, &"remove_animation", names.anim)
	if args.get("autoplay") == true:
		undo_redo.add_do_property(player, &"autoplay", full_name)
		undo_redo.add_undo_property(player, &"autoplay", player.autoplay)
	_commit(undo_redo, library, "animation_create", args, action, found.root)
	return _done("%s %s: length %ss, loop %s%s. Add tracks with animation_set_track." % [
		"Changed" if existing else "Created", full_name, edited.length, _loop_name(edited.loop_mode), ", autoplay" if args.get("autoplay") == true else ""], action)


func _animation_set_track(args: Dictionary) -> Dictionary:
	var found := _node(args, ["AnimationPlayer"])
	if found.has("error"):
		return McpTool.error(found.error)
	var player: AnimationPlayer = found.node
	var names := _split_name(str(args.animation))
	var existing := _animation(player, names)
	if existing == null:
		return McpTool.error("There is no animation %s in %s. Create it with animation_create. Animations: %s." % [args.animation, player.name, ", ".join(player.get_animation_list())])
	var is_method: bool = args.get("type") == "method"
	var track_path := NodePath(str(args.track))
	if is_method and track_path.get_subname_count() > 0:
		return McpTool.error("A method track points to a node, without \":property\".")
	if not is_method and track_path.get_subname_count() == 0:
		return McpTool.error("A value track needs \"NodePath:property\", e.g. \"Sprite2D:modulate\" or \".:position\".")
	var anim_root := player.get_node_or_null(player.root_node)
	var target: Node = anim_root.get_node_or_null(NodePath(str(track_path.get_concatenated_names()) if track_path.get_name_count() > 0 else ".")) if anim_root else null
	if target == null:
		return McpTool.error("The track path %s does not point to a node from the player's root_node (%s). Paths are relative to it, e.g. \"Sprite2D:modulate\"." % [args.track, player.root_node])
	var property := str(track_path.get_concatenated_subnames())
	var info := {}
	if not is_method:
		var current: Variant = target.get_indexed(NodePath(property))
		var base_info := ValueCoercion.property_info(target, property.get_slice(":", 0))
		if base_info.is_empty():
			return McpTool.error("%s (%s) has no property %s." % [target.name, target.get_class(), property])
		info = base_info if not ":" in property else {"type": typeof(current)}
	var edited := existing.duplicate(true) as Animation
	var track := edited.find_track(track_path, Animation.TYPE_METHOD if is_method else Animation.TYPE_VALUE)
	var replaced := track >= 0
	if replaced:
		while edited.track_get_key_count(track) > 0:
			edited.track_remove_key(track, 0)
	else:
		track = edited.add_track(Animation.TYPE_METHOD if is_method else Animation.TYPE_VALUE)
		edited.track_set_path(track, track_path)
	var keys_text: PackedStringArray = []
	for key: Variant in args.keys:
		if not key is Dictionary or not (key.get("time") is float or key.get("time") is int):
			return McpTool.error("Each key needs {\"time\": seconds, …}; got %s." % JSON.stringify(key))
		var time := float(key.time)
		if time < 0.0 or time > edited.length + 0.0001:
			return McpTool.error("Key at %ss is outside the animation (length %ss): change the length with animation_create." % [time, edited.length])
		if is_method:
			if not key.get("method") is String:
				return McpTool.error("A method key needs `method`.")
			var call_args: Array = key.get("args", []) if key.get("args") is Array else []
			edited.track_insert_key(track, time, {"method": StringName(key.method), "args": call_args})
			if not target.has_method(key.method):
				keys_text.append("%ss %s() (note: %s has no method %s yet)" % [time, key.method, target.name, key.method])
			else:
				keys_text.append("%ss %s()" % [time, key.method])
			continue
		if not key.has("value"):
			return McpTool.error("A value key needs `value`.")
		var converted: Variant = ValueCoercion.convert_value(key.value, int(info.get("type", TYPE_NIL)), info)
		if converted is Dictionary and converted.has("__error"):
			return McpTool.error("Key at %ss, %s (%s): %s" % [time, property, type_string(int(info.get("type", TYPE_NIL))), converted.__error])
		edited.track_insert_key(track, time, converted, float(key.get("transition", 1.0)))
		keys_text.append("%ss %s" % [time, SceneAccess.format_value(converted)])
	if not is_method:
		var type := int(info.get("type", TYPE_NIL))
		var smooth := type in [TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION, TYPE_RECT2, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_BASIS]
		edited.value_track_set_update_mode(track, UPDATE_MODES.get(args.get("update_mode"), Animation.UPDATE_CONTINUOUS if smooth else Animation.UPDATE_DISCRETE))
		if args.has("interpolation"):
			edited.track_set_interpolation_type(track, INTERPOLATIONS[args.interpolation])
	var action := ACTION_PREFIX + "%s track %s in %s" % ["replace" if replaced else "add", args.track, _full_name(names)]
	var undo_redo := _begin(action, found.root)
	var library := player.get_animation_library(names.library)
	undo_redo.add_do_method(library, &"add_animation", names.anim, edited)
	undo_redo.add_undo_method(library, &"add_animation", names.anim, existing)
	_commit(undo_redo, library, "animation_set_track", args, action, found.root)
	return _done("%s track %s (%s) in %s, %d keys: %s." % ["Replaced" if replaced else "Added", args.track, "method" if is_method else "value", _full_name(names), keys_text.size(), ", ".join(keys_text)], action)


func _animation_remove(args: Dictionary) -> Dictionary:
	var found := _node(args, ["AnimationPlayer"])
	if found.has("error"):
		return McpTool.error(found.error)
	var player: AnimationPlayer = found.node
	var names := _split_name(str(args.animation))
	var existing := _animation(player, names)
	if existing == null:
		return McpTool.error("There is no animation %s. Animations: %s." % [args.animation, ", ".join(player.get_animation_list())])
	var library := player.get_animation_library(names.library)
	var track_text := McpTool.str_arg(args, "track")
	var action: String
	var undo_redo: EditorUndoRedoManager
	if track_text.is_empty():
		action = ACTION_PREFIX + "delete animation %s" % _full_name(names)
		undo_redo = _begin(action, found.root)
		undo_redo.add_do_method(library, &"remove_animation", names.anim)
		undo_redo.add_undo_method(library, &"add_animation", names.anim, existing)
		if player.autoplay == _full_name(names):
			undo_redo.add_do_property(player, &"autoplay", "")
			undo_redo.add_undo_property(player, &"autoplay", player.autoplay)
	else:
		var edited := existing.duplicate(true) as Animation
		var removed := 0
		for i: int in range(edited.get_track_count() - 1, -1, -1):
			if str(edited.track_get_path(i)) == track_text:
				edited.remove_track(i)
				removed += 1
		if removed == 0:
			return McpTool.error("%s has no track %s. Tracks: %s." % [_full_name(names), track_text, ", ".join(_track_paths(existing))])
		action = ACTION_PREFIX + "delete track %s in %s" % [track_text, _full_name(names)]
		undo_redo = _begin(action, found.root)
		undo_redo.add_do_method(library, &"add_animation", names.anim, edited)
		undo_redo.add_undo_method(library, &"add_animation", names.anim, existing)
	_commit(undo_redo, library, "animation_remove", args, action, found.root)
	return _done("Deleted %s." % (_full_name(names) if track_text.is_empty() else "track %s of %s" % [track_text, _full_name(names)]), action)


func _sprite_frames_set(args: Dictionary) -> Dictionary:
	var found := _node(args, ["AnimatedSprite2D", "AnimatedSprite3D"])
	if found.has("error"):
		return McpTool.error(found.error)
	var sprite: Node = found.node
	var anim := StringName(str(args.animation))
	var textures: Array[Texture2D] = []
	if args.get("frames") is Array:
		for path: Variant in args.frames:
			var texture := load(str(path)) as Texture2D if ResourceLoader.exists(str(path)) else null
			if texture == null:
				return McpTool.error("%s is not a texture of the project." % path)
			textures.append(texture)
	if args.get("sheet") is Dictionary:
		var sheet: Variant = _sheet_frames(args.sheet)
		if sheet is String:
			return McpTool.error(sheet)
		textures.append_array(sheet)
	if textures.is_empty():
		return McpTool.error("Pass `frames` (image paths) or `sheet` {texture, hframes, vframes, frames?}.")
	var frames: SpriteFrames = sprite.get(&"sprite_frames")
	var created := frames == null
	var undo_redo: EditorUndoRedoManager
	var action := ACTION_PREFIX + "frames %s of %s" % [anim, sprite.name]
	var fps := float(args.get("fps", 10.0))
	var loop: bool = args.get("loop", true) != false
	if created:
		frames = SpriteFrames.new()
		if frames.has_animation(&"default") and anim != &"default":
			frames.remove_animation(&"default")
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		_fill(frames, anim, textures, fps, loop)
		undo_redo = _begin(action, found.root)
		undo_redo.add_do_property(sprite, &"sprite_frames", frames)
		undo_redo.add_undo_property(sprite, &"sprite_frames", null)
	else:
		undo_redo = _begin(action, found.root)
		var had := frames.has_animation(anim)
		if not had:
			undo_redo.add_do_method(frames, &"add_animation", anim)
		else:
			undo_redo.add_do_method(frames, &"clear", anim)
		undo_redo.add_do_method(frames, &"set_animation_speed", anim, fps)
		undo_redo.add_do_method(frames, &"set_animation_loop", anim, loop)
		for texture: Texture2D in textures:
			undo_redo.add_do_method(frames, &"add_frame", anim, texture)
		if not had:
			undo_redo.add_undo_method(frames, &"remove_animation", anim)
		else:
			undo_redo.add_undo_method(frames, &"clear", anim)
			undo_redo.add_undo_method(frames, &"set_animation_speed", anim, frames.get_animation_speed(anim))
			undo_redo.add_undo_method(frames, &"set_animation_loop", anim, frames.get_animation_loop(anim))
			for i: int in frames.get_frame_count(anim):
				undo_redo.add_undo_method(frames, &"add_frame", anim, frames.get_frame_texture(anim, i), frames.get_frame_duration(anim, i))
	if args.get("autoplay") == true:
		undo_redo.add_do_property(sprite, &"autoplay", String(anim))
		undo_redo.add_undo_property(sprite, &"autoplay", sprite.get(&"autoplay"))
		undo_redo.add_do_property(sprite, &"animation", anim)
		undo_redo.add_undo_property(sprite, &"animation", sprite.get(&"animation"))
	_commit(undo_redo, frames if not created else null, "sprite_frames_set", args, action, found.root)
	return _done("%s: animation %s with %d frames at %s fps, loop %s%s." % [sprite.name, anim, textures.size(), fps, loop, ", autoplay" if args.get("autoplay") == true else ""], action)


# --- internos ------------------------------------------------------------------------------------

## {node, root} o {error}; el nodo tiene que ser de alguna de las clases.
func _node(args: Dictionary, classes: Array) -> Dictionary:
	var scene := McpTool.str_arg(args, "scene")
	var root := EditorInterface.get_edited_scene_root()
	if not scene.is_empty() and (root == null or root.scene_file_path != scene):
		if not ResourceLoader.exists(scene, "PackedScene"):
			return {"error": "The scene %s does not exist." % scene}
		EditorInterface.open_scene_from_path(scene)
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "There is no open scene. Open one with open_scene."}
	var node := SceneAccess.find_node(root, str(args.node_path))
	if node == null:
		return {"error": "There is no node '%s' in %s. Use scene_tree." % [args.node_path, root.scene_file_path.get_file()]}
	for type: String in classes:
		if node.is_class(type):
			return {"node": node, "root": root}
	return {"error": "%s is %s; expected %s." % [node.name, node.get_class(), " or ".join(PackedStringArray(classes))]}


static func _split_name(text: String) -> Dictionary:
	if "/" in text:
		return {"library": text.get_slice("/", 0), "anim": text.substr(text.find("/") + 1)}
	return {"library": "", "anim": text}


static func _full_name(names: Dictionary) -> String:
	return names.anim if str(names.library).is_empty() else "%s/%s" % [names.library, names.anim]


static func _animation(player: AnimationPlayer, names: Dictionary) -> Animation:
	if not player.has_animation_library(names.library):
		return null
	var library := player.get_animation_library(names.library)
	return library.get_animation(names.anim) if library.has_animation(names.anim) else null


## La biblioteca de un nombre; si no existe, la crea dentro de la misma acción.
static func _library_for(player: AnimationPlayer, library_name: String, undo_redo: EditorUndoRedoManager) -> AnimationLibrary:
	if player.has_animation_library(library_name):
		return player.get_animation_library(library_name)
	var library := AnimationLibrary.new()
	undo_redo.add_do_method(player, &"add_animation_library", library_name, library)
	undo_redo.add_do_reference(library)
	undo_redo.add_undo_method(player, &"remove_animation_library", library_name)
	return library


func _begin(action: String, root: Node) -> EditorUndoRedoManager:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	return undo_redo


## Cierra la acción; si el recurso tocado es un archivo propio (.tres), se guarda al hacer y deshacer.
func _commit(undo_redo: EditorUndoRedoManager, resource: Resource, tool_name: String, args: Dictionary, action: String, root: Node) -> void:
	if resource and not resource.resource_path.is_empty() and not resource.resource_path.contains("::"):
		undo_redo.add_do_method(ResourceSaver, &"save", resource, resource.resource_path)
		undo_redo.add_undo_method(ResourceSaver, &"save", resource, resource.resource_path)
	undo_redo.commit_action()
	if on_action.is_valid():
		on_action.call(tool_name, args, EditorUndo.record(action, root))


static func _fill(frames: SpriteFrames, anim: StringName, textures: Array[Texture2D], fps: float, loop: bool) -> void:
	frames.clear(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for texture: Texture2D in textures:
		frames.add_frame(anim, texture)


## Cuadros de una hoja: AtlasTexture por celda. Devuelve el array o el error.
static func _sheet_frames(sheet: Dictionary) -> Variant:
	var path := str(sheet.get("texture", ""))
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture == null:
		return "`sheet.texture` (%s) is not a texture of the project." % path
	var hframes := int(sheet.get("hframes", 1))
	var vframes := int(sheet.get("vframes", 1))
	if hframes < 1 or vframes < 1:
		return "`hframes` and `vframes` must be at least 1."
	var size := Vector2(texture.get_width() / float(hframes), texture.get_height() / float(vframes))
	var indices: Array = sheet.get("frames") if sheet.get("frames") is Array else range(hframes * vframes)
	var result: Array[Texture2D] = []
	for index: Variant in indices:
		var i := int(index)
		if i < 0 or i >= hframes * vframes:
			return "Frame %d is outside the sheet (%d×%d = %d frames)." % [i, hframes, vframes, hframes * vframes]
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(i % hframes, i / hframes) * size, size)
		result.append(atlas)
	return result


static func _player_text(player: AnimationPlayer, only: String) -> String:
	var lines: PackedStringArray = ["%s · root_node %s · autoplay %s" % [player.name, player.root_node, player.autoplay if not player.autoplay.is_empty() else "(none)"]]
	var names := player.get_animation_list()
	if names.is_empty():
		lines.append("No animations: create one with animation_create.")
	for full_name: String in names:
		if not only.is_empty() and full_name != only:
			continue
		var anim := player.get_animation(full_name)
		lines.append("- %s: length %ss, loop %s, %d tracks" % [full_name, anim.length, _loop_name(anim.loop_mode), anim.get_track_count()])
		for track: int in anim.get_track_count():
			var line := "    %s [%s] %d keys" % [anim.track_get_path(track), ["value", "position_3d", "rotation_3d", "scale_3d", "blend_shape", "method", "bezier", "audio", "animation"][anim.track_get_type(track)], anim.track_get_key_count(track)]
			if not only.is_empty():
				var keys: PackedStringArray = []
				for key: int in mini(anim.track_get_key_count(track), KEYS_SHOWN):
					var value: Variant = anim.track_get_key_value(track, key)
					keys.append("%ss %s" % [snappedf(anim.track_get_key_time(track, key), 0.001), "%s()" % value.method if anim.track_get_type(track) == Animation.TYPE_METHOD and value is Dictionary else SceneAccess.format_value(value)])
				line += ": " + ", ".join(keys)
			lines.append(line)
	if not only.is_empty() and not only in names:
		lines.append("There is no animation %s. Animations: %s." % [only, ", ".join(names)])
	return "\n".join(lines)


static func _track_paths(anim: Animation) -> PackedStringArray:
	var paths: PackedStringArray = []
	for track: int in anim.get_track_count():
		paths.append(str(anim.track_get_path(track)))
	return paths


static func _loop_name(mode: int) -> String:
	for name: String in LOOP_MODES:
		if LOOP_MODES[name] == mode:
			return name
	return str(mode)


static func _texture_text(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		return "%s[%d,%d]" % [atlas.atlas.resource_path.get_file() if atlas.atlas else "?", atlas.region.position.x, atlas.region.position.y]
	return texture.resource_path.get_file() if texture else "?"


static func _done(text: String, action: String) -> Dictionary:
	return McpTool.text("%s\nUndo step: «%s»." % [text, action])
