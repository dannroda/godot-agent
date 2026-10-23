@tool
extends RefCounted
## Resaltado de bloques de código para RichTextLabel: devuelve BBCode con [color] por token.
## GDScript y shaders con keywords y tipos; JSON, shell, Python, C#/C++/JS solo con strings,
## números y comentarios; cualquier otro lenguaje queda sin colores. Los colores salen del tema
## del Script Editor (Editor Settings › Text Editor › Theme), con los de Godot por defecto.
## Una línea a la vez: un string de triple comilla que sigue en otra línea no se arrastra.

## lenguaje del fence → familia.
const FAMILIES: Dictionary = {
	"gdscript": "gdscript", "gd": "gdscript", "godot": "gdscript",
	"gdshader": "shader", "shader": "shader", "glsl": "shader", "hlsl": "shader",
	"json": "json", "jsonc": "c",
	"sh": "shell", "bash": "shell", "zsh": "shell", "shell": "shell", "console": "shell", "toml": "shell", "ini": "shell", "cfg": "shell", "yaml": "shell", "yml": "shell",
	"python": "python", "py": "python",
	"c": "c", "cpp": "c", "c++": "c", "h": "c", "hpp": "c", "cs": "c", "csharp": "c", "c#": "c", "js": "c", "javascript": "c", "ts": "c", "typescript": "c", "java": "c", "rust": "c", "rs": "c", "go": "c",
}

const GD_CONTROL_FLOW: PackedStringArray = ["if", "elif", "else", "for", "while", "match", "when", "break", "continue", "pass", "return", "await", "yield"]
const GD_KEYWORDS: PackedStringArray = [
	"func", "var", "const", "class", "class_name", "extends", "signal", "enum", "static", "in", "is", "as", "not", "and", "or",
	"self", "super", "true", "false", "null", "void", "preload", "load", "breakpoint", "PI", "TAU", "INF", "NAN", "set", "get",
]
const GD_BASE_TYPES: PackedStringArray = [
	"bool", "int", "float", "String", "StringName", "NodePath", "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i",
	"Rect2", "Rect2i", "Transform2D", "Transform3D", "Plane", "Quaternion", "AABB", "Basis", "Projection", "Color", "RID",
	"Callable", "Signal", "Dictionary", "Array", "Variant", "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
	"PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array",
	"PackedColorArray", "PackedVector4Array",
]
const SHADER_CONTROL_FLOW: PackedStringArray = ["if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "discard"]
const SHADER_KEYWORDS: PackedStringArray = [
	"shader_type", "render_mode", "uniform", "varying", "const", "struct", "in", "out", "inout", "true", "false",
	"lowp", "mediump", "highp", "flat", "smooth", "instance", "global", "group_uniforms", "void",
]
const SHADER_TYPES: PackedStringArray = [
	"bool", "bvec2", "bvec3", "bvec4", "int", "ivec2", "ivec3", "ivec4", "uint", "uvec2", "uvec3", "uvec4", "float", "vec2", "vec3", "vec4",
	"mat2", "mat3", "mat4", "sampler2D", "isampler2D", "usampler2D", "sampler2DArray", "sampler3D", "samplerCube", "samplerExternalOES",
]
const PYTHON_KEYWORDS: PackedStringArray = [
	"def", "class", "import", "from", "as", "if", "elif", "else", "for", "while", "return", "yield", "with", "try", "except", "finally",
	"raise", "pass", "break", "continue", "lambda", "in", "is", "not", "and", "or", "None", "True", "False", "self", "async", "await",
]
const C_KEYWORDS: PackedStringArray = [
	"if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "class", "struct", "enum",
	"public", "private", "protected", "static", "const", "var", "let", "function", "new", "this", "null", "true", "false", "void",
	"using", "namespace", "import", "export", "async", "await", "fn", "pub", "mut", "impl", "use", "func", "package", "override",
]

## Colores del tema oscuro por defecto de Godot.
const DEFAULT_COLORS: Dictionary = {
	"keyword": "#ff7085", "control_flow": "#ff8ccc", "base_type": "#42ffc2", "engine_type": "#8fffdb",
	"string": "#ffeda1", "number": "#a1ffe0", "comment": "#cdcfd280", "function": "#57b3ff",
	"annotation": "#ffb373", "node_path": "#b8c47d",
}
const SETTINGS: Dictionary = {
	"keyword": "text_editor/theme/highlighting/keyword_color",
	"control_flow": "text_editor/theme/highlighting/control_flow_keyword_color",
	"base_type": "text_editor/theme/highlighting/base_type_color",
	"engine_type": "text_editor/theme/highlighting/engine_type_color",
	"string": "text_editor/theme/highlighting/string_color",
	"number": "text_editor/theme/highlighting/number_color",
	"comment": "text_editor/theme/highlighting/comment_color",
	"function": "text_editor/theme/highlighting/function_color",
	"annotation": "text_editor/theme/highlighting/gdscript/annotation_color",
	"node_path": "text_editor/theme/highlighting/gdscript/node_path_color",
}

## nombre → "#rrggbb[aa]".
var colors: Dictionary = DEFAULT_COLORS.duplicate()
var _regexes: Dictionary = {}  # familia -> RegEx


## Toma los colores del tema del Script Editor.
func use_editor_colors() -> void:
	if not (Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface")):
		return
	var settings := EditorInterface.get_editor_settings()
	for key: String in SETTINGS:
		if settings.has_setting(SETTINGS[key]):
			var value: Variant = settings.get_setting(SETTINGS[key])
			if value is Color:
				colors[key] = "#" + (value as Color).to_html(true)


static func family(language: String) -> String:
	return str(FAMILIES.get(language.strip_edges().to_lower(), ""))


## BBCode del código (sin el [code] de afuera), con el texto escapado.
func highlight(code: String, language: String) -> String:
	var kind := family(language)
	if kind.is_empty():
		return _escape(code)
	var regex := _regex(kind)
	var out: PackedStringArray = []
	for line: String in code.split("\n"):
		out.append(_highlight_line(line, kind, regex))
	return "\n".join(out)


func _highlight_line(line: String, kind: String, regex: RegEx) -> String:
	var result := ""
	var position := 0
	for found: RegExMatch in regex.search_all(line):
		result += _escape(line.substr(position, found.get_start() - position))
		position = found.get_end()
		var token := found.get_string()
		var color := _token_color(token, kind, line, found.get_end())
		result += _escape(token) if color.is_empty() else "[color=%s]%s[/color]" % [color, _escape(token)]
	return result + _escape(line.substr(position))


func _token_color(token: String, kind: String, line: String, end: int) -> String:
	var first := token[0]
	if token.begins_with("#") or token.begins_with("//") or token.begins_with("/*"):
		return colors.comment
	if first == "\"" or first == "'" or first == "`" or (first == "&" or first == "^") and token.length() > 1:
		return colors.string
	if first == "@":
		return colors.annotation
	if first == "$" or first == "%":
		return colors.node_path if kind == "gdscript" else colors.string if kind == "shell" else ""
	if first.is_valid_int() or first == "." and token.length() > 1:
		return colors.number
	var calls := line.substr(end).strip_edges(true, false).begins_with("(")
	match kind:
		"gdscript":
			if token in GD_CONTROL_FLOW:
				return colors.control_flow
			if token in GD_KEYWORDS:
				return colors.keyword
			if token in GD_BASE_TYPES:
				return colors.base_type
			if ClassDB.class_exists(token):
				return colors.engine_type
		"shader":
			if token in SHADER_CONTROL_FLOW:
				return colors.control_flow
			if token in SHADER_KEYWORDS:
				return colors.keyword
			if token in SHADER_TYPES:
				return colors.base_type
		"python":
			if token in PYTHON_KEYWORDS:
				return colors.keyword
		"c":
			if token in C_KEYWORDS:
				return colors.keyword
		"json":
			return colors.keyword if token in ["true", "false", "null"] else ""
		_:
			return ""
	return colors.function if calls else ""


func _regex(kind: String) -> RegEx:
	if _regexes.has(kind):
		return _regexes[kind]
	var comment := "#.*"
	match kind:
		"c", "shader", "json":
			comment = "//.*|/\\*.*?(?:\\*/|$)"
	var strings := "\"(?:[^\"\\\\]|\\\\.)*\"?|'(?:[^'\\\\]|\\\\.)*'?"
	if kind == "gdscript":
		strings = "[&^]?" + "\"(?:[^\"\\\\]|\\\\.)*\"?|'(?:[^'\\\\]|\\\\.)*'?"
	elif kind == "c":
		strings += "|`[^`]*`?"
	var extra := ""
	if kind == "gdscript":
		extra = "|@[A-Za-z_]\\w*|[$%](?:\"[^\"]*\"|[A-Za-z_][\\w/]*)"
	elif kind == "shell":
		extra = "|\\$\\{?\\w+\\}?"
	var number := "0[xX][0-9A-Fa-f_]+|0[bB][01_]+|\\d[\\d_]*(?:\\.[\\d_]*)?(?:[eE][+-]?\\d+)?[fu]?|\\.\\d[\\d_]*"
	var pattern := "%s|%s%s|(?<![\\w.])(?:%s)|[A-Za-z_]\\w*" % [comment, strings, extra, number]
	var regex := RegEx.create_from_string(pattern)
	_regexes[kind] = regex
	return regex


## Igual que MarkdownBBCode.escape (que precarga este script).
static func _escape(text: String) -> String:
	return text.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")
