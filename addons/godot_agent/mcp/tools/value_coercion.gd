@tool
extends RefCounted
## Convierte valores JSON (lo que manda el agente) al tipo de una propiedad de Godot.
## Acepta, según el tipo:
## - vectores como [x, y], {"x":…, "y":…} o "Vector2(1, 2)";
## - colores como "#rrggbb", nombres ("red") o [r, g, b, a];
## - recursos como ruta res://, o nuevos inline: {"type": "StyleBoxFlat", "bg_color": "#222"} (con
##   las propiedades al lado de type o en "properties");
## - arrays tipados (Array[ItemData]) elemento por elemento;
## - enums por número o por nombre.

## Resultado: `{ok: bool, value: Variant, error: String}`.
static func coerce(target: Object, property: String, value: Variant) -> Dictionary:
	var info := property_info(target, property)
	if info.is_empty():
		return _fail("The property '%s' does not exist on %s.%s" % [property, target.get_class(), _suggestion(target, property)])
	var type: int = info.type
	var converted: Variant = convert_value(value, type, info)
	var current: Variant = target.get(property)
	if type == TYPE_ARRAY and value is Array and current is Array and (current as Array).is_typed():
		converted = _typed_array(current, value)
	if converted is Dictionary and converted.has("__error"):
		return _fail("'%s' (%s): %s" % [property, type_string(type), converted.__error])
	return {"ok": true, "value": converted, "error": ""}


static func property_info(target: Object, property: String) -> Dictionary:
	for info: Dictionary in target.get_property_list():
		if info.name == property:
			return info
	return {}


static func convert_value(value: Variant, type: int, info: Dictionary = {}) -> Variant:
	if value == null:
		if type == TYPE_OBJECT or type == TYPE_NIL:
			return null
		return _error("cannot be null")
	if type == TYPE_NIL:
		return value  # propiedad Variant: se usa tal cual
	if typeof(value) == type:
		return value
	# Texto con sintaxis de Godot ("Vector2(1, 2)", "Color(1, 0, 0, 1)"…).
	if value is String and type != TYPE_STRING and type != TYPE_STRING_NAME and type != TYPE_NODE_PATH and type != TYPE_OBJECT:
		var text: String = value
		var parsed: Variant = str_to_var(text) if text.contains("(") or text.begins_with("[") or text.begins_with("{") else null
		if parsed != null and typeof(parsed) == type:
			return parsed
	match type:
		TYPE_BOOL:
			if value is float or value is int:
				return value != 0
			if value is String and value.to_lower() in ["true", "false"]:
				return value.to_lower() == "true"
		TYPE_INT:
			if value is float and is_equal_approx(value, roundf(value)):
				return int(value)
			if value is String:
				if value.is_valid_int():
					return int(value)
				var enum_value := _enum_value(value, info)
				if enum_value != null:
					return enum_value
			if value is bool:
				return int(value)
		TYPE_FLOAT:
			if value is int:
				return float(value)
			if value is String and value.is_valid_float():
				return float(value)
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		TYPE_NODE_PATH:
			if value is String:
				return NodePath(value)
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			var components := _components(value, ["x", "y", "z", "w"])
			var size: int = {TYPE_VECTOR2: 2, TYPE_VECTOR2I: 2, TYPE_VECTOR3: 3, TYPE_VECTOR3I: 3, TYPE_VECTOR4: 4, TYPE_VECTOR4I: 4}[type]
			if components.size() == size:
				match type:
					TYPE_VECTOR2: return Vector2(components[0], components[1])
					TYPE_VECTOR2I: return Vector2i(int(components[0]), int(components[1]))
					TYPE_VECTOR3: return Vector3(components[0], components[1], components[2])
					TYPE_VECTOR3I: return Vector3i(int(components[0]), int(components[1]), int(components[2]))
					TYPE_VECTOR4: return Vector4(components[0], components[1], components[2], components[3])
					TYPE_VECTOR4I: return Vector4i(int(components[0]), int(components[1]), int(components[2]), int(components[3]))
			return _error("expected %s as [%s]" % [type_string(type), ", ".join(PackedStringArray(["x", "y", "z", "w"].slice(0, size)))])
		TYPE_RECT2, TYPE_RECT2I:
			var components := _components(value, ["x", "y", "w", "h"])
			if components.size() == 4:
				if type == TYPE_RECT2:
					return Rect2(components[0], components[1], components[2], components[3])
				return Rect2i(int(components[0]), int(components[1]), int(components[2]), int(components[3]))
		TYPE_COLOR:
			if value is String:
				var text: String = value
				if text.begins_with("#") or text.is_valid_html_color():
					return Color.html(text)
				var named := Color.from_string(text, Color(0, 0, 0, -1))
				if named.a >= 0.0:
					return named
			var components := _components(value, ["r", "g", "b", "a"])
			if components.size() == 3:
				return Color(components[0], components[1], components[2])
			if components.size() == 4:
				return Color(components[0], components[1], components[2], components[3])
			return _error("expected a color as \"#rrggbb\", a name or [r, g, b, a]")
		TYPE_OBJECT:
			if value is Dictionary and value.get("type") is String:
				var made: Variant = inline_resource(value)
				if made is String:
					return _error(made)
				return _check_resource_hint(made, info, str(value.type))
			if value is String and (value.begins_with("res://") or value.begins_with("uid://")):
				if not ResourceLoader.exists(value):
					return _error("the resource %s does not exist" % value)
				var resource := load(value)
				return _check_resource_hint(resource, info, value) if resource else _error("could not load %s" % value)
			return _error("expected a res:// path to a resource, {\"type\": \"ClassName\", …properties} for a new one, or null")
		TYPE_ARRAY:
			if value is Array:
				return value
		TYPE_DICTIONARY:
			if value is Dictionary:
				return value
		TYPE_PACKED_STRING_ARRAY:
			if value is Array:
				return PackedStringArray(value)
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if value is Array:
				return PackedFloat32Array(value) if type == TYPE_PACKED_FLOAT32_ARRAY else PackedFloat64Array(value)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			if value is Array:
				return PackedInt32Array(value) if type == TYPE_PACKED_INT32_ARRAY else PackedInt64Array(value)
		TYPE_PACKED_VECTOR2_ARRAY:
			if value is Array:
				var points := PackedVector2Array()
				for point: Variant in value:
					var converted: Variant = convert_value(point, TYPE_VECTOR2)
					if converted is Dictionary:
						return converted
					points.append(converted)
				return points
	return _error("cannot convert %s" % JSON.stringify(value).left(80))


## Recurso nuevo de {"type", "properties"? o propiedades sueltas}. Devuelve el Resource o el error.
static func inline_resource(data: Dictionary) -> Variant:
	var made: Variant = new_resource(str(data.type))
	if made is String:
		return made
	var resource: Resource = made
	var properties: Dictionary = data.get("properties") if data.get("properties") is Dictionary else {}
	for key: Variant in data:
		if not str(key) in ["type", "properties"]:
			properties[key] = data[key]
	for property: String in properties:
		var result := coerce(resource, property, properties[property])
		if not result.ok:
			return "%s: %s" % [data.type, result.error]
		resource.set(property, result.value)
	return resource


## Instancia una clase Resource de Godot o un class_name del proyecto que extiende Resource.
static func new_resource(type_name: String) -> Variant:
	if ClassDB.class_exists(type_name):
		if not ClassDB.is_parent_class(type_name, &"Resource"):
			return "%s is not a Resource." % type_name
		if not ClassDB.can_instantiate(type_name):
			return "%s is abstract: choose a subclass." % type_name
		return ClassDB.instantiate(type_name)
	for global: Dictionary in ProjectSettings.get_global_class_list():
		if global.get("class") == type_name:
			var instance: Variant = instantiate_script_class(str(global.path))
			if instance is String:
				return instance
			if not instance is Resource:
				if instance is Node:
					(instance as Node).free()
				return "%s does not extend Resource." % type_name
			return instance
	return "There is no Resource class '%s' (neither a Godot class nor a project class_name)." % type_name


## Instancia un script con class_name como lo hace el Inspector: la clase nativa base con el script
## puesto. En el editor, `script.new()` falla para scripts sin @tool. Devuelve el objeto o el error.
static func instantiate_script_class(path: String) -> Variant:
	var script := load(path) as Script
	if script == null:
		return "Could not load %s." % path
	var base := script.get_instance_base_type()
	if not ClassDB.can_instantiate(base):
		return "%s extends %s, which is abstract." % [path, base]
	var instance := ClassDB.instantiate(base) as Object
	instance.set_script(script)
	if instance.get_script() != script:
		if instance is Node:
			(instance as Node).free()
		return "Could not attach %s (does it have errors? try validate_scripts)." % path
	return instance


## Un recurso contra el hint de la propiedad ("Texture2D,Material" o un class_name).
static func _check_resource_hint(resource: Resource, info: Dictionary, label: String) -> Variant:
	var hint_class: String = info.get("hint_string", "")
	if hint_class.is_empty() or info.get("hint", 0) != PROPERTY_HINT_RESOURCE_TYPE:
		return resource
	for allowed: String in hint_class.split(","):
		var name := allowed.strip_edges()
		if resource.is_class(name) or (resource.get_script() and _script_is(resource.get_script(), name)):
			return resource
	return _error("%s is %s; expected %s" % [label, resource.get_class(), hint_class])


static func _script_is(script: Script, global_name: String) -> bool:
	var current := script
	while current:
		if current.get_global_name() == global_name:
			return true
		current = current.get_base_script()
	return false


## Array tipado como el valor actual de la propiedad, con cada elemento convertido.
static func _typed_array(current: Array, values: Array) -> Variant:
	var element_type := current.get_typed_builtin()
	var element_info := {}
	if element_type == TYPE_OBJECT:
		var class_hint := String(current.get_typed_class_name())
		var script := current.get_typed_script() as Script
		if script and not script.get_global_name().is_empty():
			class_hint = script.get_global_name()
		element_info = {"hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": class_hint}
	var typed := current.duplicate()
	typed.clear()
	for i: int in values.size():
		var converted: Variant = convert_value(values[i], element_type, element_info)
		if converted is Dictionary and converted.has("__error"):
			return _error("element %d: %s" % [i, converted.__error])
		typed.append(converted)
	return typed


## Un enum por nombre: "Center" o "CENTER" según el hint_string "Left,Center:1,Right".
static func _enum_value(name: String, info: Dictionary) -> Variant:
	if info.get("hint", 0) != PROPERTY_HINT_ENUM:
		return null
	var index := 0
	for item: String in str(info.get("hint_string", "")).split(","):
		var label := item.get_slice(":", 0).strip_edges()
		var number := int(item.get_slice(":", 1)) if item.contains(":") else index
		if label.to_lower().replace(" ", "_") == name.to_lower().replace(" ", "_"):
			return number
		index = number + 1
	return null


static func _components(value: Variant, keys: Array) -> Array:
	var result: Array = []
	if value is Array:
		for item: Variant in value:
			if not (item is float or item is int):
				return []
			result.append(float(item))
	elif value is Dictionary:
		for key: String in keys:
			if value.has(key):
				if not (value[key] is float or value[key] is int):
					return []
				result.append(float(value[key]))
	elif value is float or value is int:
		return []
	return result


static func _suggestion(target: Object, property: String) -> String:
	var scored: Array = []
	var needle := property.to_lower()
	for info: Dictionary in target.get_property_list():
		if not info.usage & PROPERTY_USAGE_EDITOR:
			continue
		var name: String = info.name
		var score := name.to_lower().similarity(needle)
		if name.to_lower().contains(needle) or needle.contains(name.to_lower()):
			score += 0.5
		if score > 0.3:
			scored.append([score, name])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var best: PackedStringArray = []
	for item: Array in scored.slice(0, 5):
		best.append(item[1])
	return " Did you mean: %s?" % ", ".join(best) if not best.is_empty() else ""


static func _error(message: String) -> Dictionary:
	return {"__error": message}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
