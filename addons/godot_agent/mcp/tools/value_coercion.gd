@tool
extends RefCounted
## Convierte valores JSON (lo que manda el agente) al tipo de una propiedad de Godot.
## Acepta, según el tipo:
## - vectores como [x, y], {"x":…, "y":…} o "Vector2(1, 2)";
## - colores como "#rrggbb", nombres ("red") o [r, g, b, a];
## - recursos como ruta res://;
## - enums por número o por nombre.

## Resultado: `{ok: bool, value: Variant, error: String}`.
static func coerce(target: Object, property: String, value: Variant) -> Dictionary:
	var info := property_info(target, property)
	if info.is_empty():
		return _fail("The property '%s' does not exist on %s.%s" % [property, target.get_class(), _suggestion(target, property)])
	var type: int = info.type
	var converted: Variant = convert_value(value, type, info)
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
			if value is String and (value.begins_with("res://") or value.begins_with("uid://")):
				if not ResourceLoader.exists(value):
					return _error("the resource %s does not exist" % value)
				var resource := load(value)
				var hint_class: String = info.get("hint_string", "")
				if resource and not hint_class.is_empty() and info.get("hint", 0) == PROPERTY_HINT_RESOURCE_TYPE:
					var ok := false
					for allowed: String in hint_class.split(","):
						ok = ok or resource.is_class(allowed.strip_edges()) or (resource.get_script() and allowed.strip_edges() == resource.get_script().get_global_name())
					if not ok:
						return _error("%s is %s; expected %s" % [value, resource.get_class(), hint_class])
				return resource
			return _error("expected a res:// path to a resource, or null")
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
