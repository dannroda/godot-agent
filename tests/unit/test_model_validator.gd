extends "test_case.gd"
## Validador de modelos e import_model (m11-85), con GLB y .gltf armados a mano.

const ModelValidator := preload("res://addons/godot_agent/mcp/model_validator.gd")
const ModelTools := preload("res://addons/godot_agent/mcp/tools/model_tools.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")

const DIR := "user://unit_tests/model_validator"
const TARGETS := "res://tests/tmp/model_validator"


## Un triángulo: 3 posiciones VEC3 float en un buffer de 36 bytes.
static func triangle() -> Dictionary:
	return {
		"asset": {"version": "2.0", "generator": "hand"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"name": "Tri", "mesh": 0}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
		"accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]}],
		"bufferViews": [{"buffer": 0, "byteLength": 36}],
		"buffers": [{"byteLength": 36}],
	}


static func positions() -> PackedByteArray:
	return PackedFloat32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]).to_byte_array()


static func glb(doc: Variant, bin := PackedByteArray()) -> PackedByteArray:
	var json: PackedByteArray = (str(doc) if doc is String else JSON.stringify(doc)).to_utf8_buffer()
	return glb_raw(json, bin)


static func glb_raw(json: PackedByteArray, bin: PackedByteArray) -> PackedByteArray:
	while json.size() % 4 != 0:
		json.append(0x20)
	var padded := bin.duplicate()
	while padded.size() % 4 != 0:
		padded.append(0)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, ModelValidator.GLB_MAGIC)
	out.encode_u32(4, 2)
	out.encode_u32(12, json.size())
	out.encode_u32(16, ModelValidator.CHUNK_JSON)
	out.append_array(json)
	if not padded.is_empty():
		var head := PackedByteArray()
		head.resize(8)
		head.encode_u32(0, padded.size())
		head.encode_u32(4, ModelValidator.CHUNK_BIN)
		out.append_array(head)
		out.append_array(padded)
	out.encode_u32(8, out.size())
	return out


## Cabecera de un PNG de w×h (lo que lee image_header.gd).
static func png(w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
	for value: int in [w, h]:
		out.append_array(PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]))
	out.append_array(PackedByteArray([8, 6, 0, 0, 0, 0, 0, 0, 0]))
	return out


func _error_of(result: Dictionary) -> String:
	return "" if result.success else str(result.error)


func test_valid_glb() -> void:
	var doc := triangle()
	doc.animations = [{"name": "Idle", "channels": [], "samplers": []}, {"name": "Walk", "channels": [], "samplers": []}]
	var bytes := glb(doc, positions())
	var result := ModelValidator.inspect_glb(bytes)
	assert_true(result.success, _error_of(result))
	assert_eq(result.summary.bytes, bytes.size(), "bytes")
	assert_eq([result.summary.nodes, result.summary.meshes, result.summary.materials, result.summary.skins], [1, 1, 0, 0], "conteos")
	assert_eq(Array(result.summary.animations), ["Idle", "Walk"], "nombres de las animaciones")
	assert_true(ModelValidator.inspect_glb(glb({"asset": {"version": "2.0"}})).success, "un GLB vacío, sin chunk binario")


func test_glb_header_and_chunks() -> void:
	var good := glb(triangle(), positions())
	var bad := good.duplicate()
	bad.encode_u32(0, 0x12345678)
	assert_eq(_error_of(ModelValidator.inspect_glb(bad)), "Not a GLB 2.0 file (bad header or size).", "magic")
	bad = good.duplicate()
	bad.encode_u32(4, 1)
	assert_false(ModelValidator.inspect_glb(bad).success, "versión 1")
	bad = good.duplicate()
	bad.encode_u32(8, good.size() + 4)
	assert_false(ModelValidator.inspect_glb(bad).success, "largo total distinto del archivo")
	assert_false(ModelValidator.inspect_glb(good.slice(0, 12)).success, "cortado")
	bad = good.duplicate()
	bad.encode_u32(16, 0x11111111)
	assert_eq(_error_of(ModelValidator.inspect_glb(bad)), "The GLB JSON chunk is malformed.", "tipo del chunk JSON")
	bad = good.duplicate()
	bad.encode_u32(12, bad.decode_u32(12) + 2)
	assert_false(ModelValidator.inspect_glb(bad).success, "JSON sin alinear")
	bad = good.duplicate()
	bad.encode_u32(20 + good.decode_u32(12) + 4, 0x22222222)
	assert_eq(_error_of(ModelValidator.inspect_glb(bad)), "The GLB binary chunk is malformed.", "tipo del chunk BIN")
	var buffer_without_bin := triangle()
	assert_false(ModelValidator.inspect_glb(glb(buffer_without_bin)).success, "declara un buffer sin chunk binario")
	var short := triangle()
	short.buffers[0].byteLength = 400
	assert_false(ModelValidator.inspect_glb(glb(short, positions())).success, "el buffer no entra en el chunk")


func test_json_rules() -> void:
	var invalid := "{\"asset\":{\"version\":\"2.0\",\"x\":\"".to_utf8_buffer()
	invalid.append_array(PackedByteArray([0xC3, 0x28]))
	invalid.append_array("\"}}".to_utf8_buffer())
	assert_eq(_error_of(ModelValidator.inspect_glb(glb_raw(invalid, PackedByteArray()))), "The glTF JSON is not valid UTF-8.", "UTF-8 roto")
	var with_nul := "{\"asset\":{\"version\":\"2.0\"}}".to_utf8_buffer()
	with_nul.append(0)
	assert_false(ModelValidator.inspect_glb(glb_raw(with_nul, PackedByteArray())).success, "NUL")
	assert_false(ModelValidator.inspect_glb(glb("[1, 2]")).success, "no es un objeto")
	assert_eq(_error_of(ModelValidator.inspect_glb(glb({"asset": {"version": "1.0"}}))), "Only glTF 2.0 models are accepted (asset.version).", "versión del asset")
	assert_false(ModelValidator.inspect_glb(glb("{\"asset\":{\"version\":\"2.0\"},\"extras\":{\"v\":1e999}}")).success, "número infinito")
	var deep: Variant = 1
	for i: int in ModelValidator.MAX_DEPTH + 2:
		deep = [deep]
	assert_eq(_error_of(ModelValidator.inspect_glb(glb({"asset": {"version": "2.0"}, "extras": deep}))), "The glTF JSON is nested too deeply.", "anidado de más")


func test_uris_and_extensions() -> void:
	var external := triangle()
	external.buffers[0].uri = "scene.bin"
	assert_true(_error_of(ModelValidator.inspect_glb(glb(external, positions()))).contains("must embed its buffers"), "un GLB no nombra archivos")
	var data_uri := triangle()
	data_uri.images = [{"uri": "data:image/png;base64,AAAA"}]
	assert_false(ModelValidator.inspect_glb(glb(data_uri, positions())).success, "data: URI")
	var nested := triangle()
	nested.extensions = {"VENDOR_x": {"uri": "http://example.com/a.bin"}}
	assert_false(ModelValidator.inspect_glb(glb(nested, positions())).success, "una uri en cualquier lugar")
	var required := triangle()
	required.extensionsUsed = ["KHR_draco_mesh_compression"]
	required.extensionsRequired = ["KHR_draco_mesh_compression"]
	assert_true(_error_of(ModelValidator.inspect_glb(glb(required, positions()))).contains("KHR_draco_mesh_compression"), "extensión requerida, nombrada")
	var used := triangle()
	used.extensionsUsed = ["KHR_materials_emissive_strength"]
	assert_true(ModelValidator.inspect_glb(glb(used, positions())).success, "usada pero no requerida")


func test_structure_limits() -> void:
	var many := triangle()
	for i: int in ModelValidator.MAX_ITEMS.nodes:
		many.nodes.append({"name": "n%d" % i})
	assert_eq(_error_of(ModelValidator.inspect_glb(glb(many, positions()))), "The model has too many nodes (at most %d)." % ModelValidator.MAX_ITEMS.nodes, "nodos")
	var big := triangle()
	big.accessors[0].count = ModelValidator.MAX_ACCESSOR_ELEMENTS + 1
	assert_false(ModelValidator.inspect_glb(glb(big, positions())).success, "accessor enorme")
	var fractional := triangle()
	fractional.accessors[0].count = 2.5
	assert_false(ModelValidator.inspect_glb(glb(fractional, positions())).success, "count no entero")
	var component := triangle()
	component.accessors[0].componentType = 5124
	assert_eq(_error_of(ModelValidator.inspect_glb(glb(component, positions()))), "Accessor 0 has an unsupported componentType or type.", "componentType")
	var kind := triangle()
	kind.accessors[0].type = "VEC5"
	assert_false(ModelValidator.inspect_glb(glb(kind, positions())).success, "type")
	var escape := triangle()
	escape.bufferViews[0].byteOffset = 24
	assert_eq(_error_of(ModelValidator.inspect_glb(glb(escape, positions()))), "Buffer view 0 is outside buffer 0.", "fuera del binario")
	var overread := triangle()
	overread.accessors[0].count = 4
	assert_eq(_error_of(ModelValidator.inspect_glb(glb(overread, positions()))), "Accessor 0 reads past the end of buffer view 0.", "el accessor no entra en su bufferView")
	var strided := triangle()
	strided.bufferViews[0].byteStride = 6
	assert_false(ModelValidator.inspect_glb(glb(strided, positions())).success, "byteStride no múltiplo de 4")
	var other := triangle()
	other.bufferViews[0].buffer = 1
	assert_false(ModelValidator.inspect_glb(glb(other, positions())).success, "otro buffer")


func test_node_hierarchy() -> void:
	var cycle := triangle()
	cycle.nodes = [{"children": [1]}, {"children": [0]}]
	assert_eq(_error_of(ModelValidator.inspect_glb(glb(cycle, positions()))), "The node hierarchy has a cycle.", "ciclo")
	var two_parents := triangle()
	two_parents.nodes = [{"children": [2]}, {"children": [2]}, {}]
	assert_eq(_error_of(ModelValidator.inspect_glb(glb(two_parents, positions()))), "Node 2 is a child of two nodes.", "dos padres")
	var missing := triangle()
	missing.nodes = [{"children": [7]}]
	assert_false(ModelValidator.inspect_glb(glb(missing, positions())).success, "hijo que no existe")
	var tree := triangle()
	tree.nodes = [{"children": [1, 2]}, {"children": [3]}, {}, {"mesh": 0}]
	assert_true(ModelValidator.inspect_glb(glb(tree, positions())).success, "un árbol está bien")


func test_embedded_images() -> void:
	var bin := positions()
	var image := png(16, 16)
	var doc := triangle()
	doc.bufferViews.append({"buffer": 0, "byteOffset": 36, "byteLength": image.size()})
	doc.images = [{"bufferView": 1, "mimeType": "image/png"}]
	doc.buffers[0].byteLength = 36 + image.size()
	var ok := ModelValidator.inspect_glb(glb(doc, bin + image))
	assert_true(ok.success, _error_of(ok))
	assert_eq(ok.summary.images, 1, "una imagen")
	var huge := png(9000, 16)
	doc.bufferViews[1].byteLength = huge.size()
	doc.buffers[0].byteLength = 36 + huge.size()
	assert_true(_error_of(ModelValidator.inspect_glb(glb(doc, bin + huge))).begins_with("Image 0 is not a PNG"), "más de 8192 de lado")
	doc.images = [{"bufferView": 9}]
	assert_false(ModelValidator.inspect_glb(glb(doc, bin + huge)).success, "bufferView que no existe")
	var not_image := PackedByteArray()
	not_image.resize(40)
	doc.images = [{"bufferView": 1}]
	doc.bufferViews[1].byteLength = 40
	doc.buffers[0].byteLength = 76
	assert_false(ModelValidator.inspect_glb(glb(doc, bin + not_image)).success, "bytes que no son una imagen")


## .gltf con su .bin y una textura al lado; nada fuera de la carpeta.
func test_gltf_files() -> void:
	var folder := ProjectSettings.globalize_path(DIR).path_join("gltf")
	DirAccess.make_dir_recursive_absolute(folder.path_join("textures"))
	_write(folder.path_join("scene.bin"), positions())
	_write(folder.path_join("textures/wood%20dark.png".uri_decode()), png(32, 32))
	var doc := triangle()
	doc.buffers[0].uri = "scene.bin"
	doc.images = [{"uri": "textures/wood%20dark.png"}]
	var path := folder.path_join("scene.gltf")
	_write(path, JSON.stringify(doc).to_utf8_buffer())
	var result := ModelValidator.inspect_file(path)
	assert_true(result.success, _error_of(result))
	assert_eq(Array(result.files), [folder.path_join("scene.bin"), folder.path_join("textures/wood dark.png")], "los archivos que nombra")
	assert_eq(result.summary.bytes, 36 + 33 + FileAccess.get_file_as_bytes(path).size(), "bytes de todo")
	for uri: String in ["../scene.bin", "/etc/hostname", "C:/scene.bin", "%2e%2e/scene.bin", "%2E%2E/scene.bin", "a%2f..%2f..%2fx.bin", "bad%zz.bin", "sub\\..\\..\\x.bin", "file:///etc/hostname", "data:application/octet-stream;base64,AAAA"]:
		doc.buffers[0].uri = uri
		_write(path, JSON.stringify(doc).to_utf8_buffer())
		assert_true(_error_of(ModelValidator.inspect_file(path)).contains("must be a relative path"), "buffer %s" % uri)
	doc.buffers[0].uri = "missing.bin"
	_write(path, JSON.stringify(doc).to_utf8_buffer())
	assert_true(_error_of(ModelValidator.inspect_file(path)).contains("does not exist"), "buffer que falta")
	doc.buffers[0].uri = "scene.bin"
	doc.buffers[0].byteLength = 80
	_write(path, JSON.stringify(doc).to_utf8_buffer())
	assert_true(_error_of(ModelValidator.inspect_file(path)).contains("but the .gltf says 80"), "byteLength distinto")
	doc.buffers[0].byteLength = 36
	doc.images = [{"uri": "scene.bin"}]
	_write(path, JSON.stringify(doc).to_utf8_buffer())
	assert_false(ModelValidator.inspect_file(path).success, "una imagen que no es .png/.jpg/.webp")
	doc.images = [{"uri": "textures/wood%20dark.png", "bufferView": 0}]
	_write(path, JSON.stringify(doc).to_utf8_buffer())
	assert_false(ModelValidator.inspect_file(path).success, "uri y bufferView a la vez")
	assert_eq(_error_of(ModelValidator.inspect_file(folder.path_join("x.obj"))), "Only .glb and .gltf are supported.", "otra extensión")


func test_plan_import() -> void:
	var folder := ProjectSettings.globalize_path(DIR).path_join("plan")
	DirAccess.make_dir_recursive_absolute(folder)
	_remove_tree(ProjectSettings.globalize_path(TARGETS))
	var source := folder.path_join("crate.glb")
	_write(source, glb(triangle(), positions()))
	var tools := ModelTools.new()
	var plan := tools.plan_import({"from": source, "to": TARGETS})
	assert_false(plan.has("error"), str(plan.get("error", "")))
	assert_eq(plan.target, TARGETS + "/crate.glb", "carpeta: mismo nombre de archivo")
	assert_eq(plan.copies, [[source, TARGETS + "/crate.glb"]], "lo que copia")
	assert_eq(tools.plan_import({"from": source, "to": TARGETS + "/box.glb"}).target, TARGETS + "/box.glb", "con nombre")
	assert_true(str(tools.plan_import({"from": source, "to": TARGETS + "/box.gltf"}).error).contains("same extension"), "extensión distinta")
	assert_true(str(tools.plan_import({"from": folder.path_join("x.fbx"), "to": TARGETS}).error).contains("export glTF Binary"), ".fbx: cómo exportar")
	assert_true(str(tools.plan_import({"from": folder.path_join("none.glb"), "to": TARGETS}).error).contains("does not exist"), "no existe")
	assert_true(str(tools.plan_import({"from": source, "to": "/tmp/x"}).error).contains("res://"), "destino fuera del proyecto")
	assert_true(str(tools.plan_import({"from": source, "to": TARGETS, "replace": true}).error).contains("needs an existing model"), "replace sin modelo")
	# Ya existe: sin replace se niega y dice cómo; con replace, se pisa.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TARGETS))
	_write(ProjectSettings.globalize_path(TARGETS + "/crate.glb"), glb(triangle(), positions()))
	assert_true(str(tools.plan_import({"from": source, "to": TARGETS}).error).contains("Pass replace: true"), "ya existe")
	assert_false(tools.plan_import({"from": source, "to": TARGETS, "replace": true}).has("error"), "replace")
	# Un .import con import_script, del origen o del modelo que se pisa, no se importa.
	_write(ProjectSettings.globalize_path(TARGETS + "/crate.glb.import"), "[params]\n\nimport_script/path=\"res://hack.gd\"\n".to_utf8_buffer())
	assert_true(str(tools.plan_import({"from": source, "to": TARGETS, "replace": true}).error).contains("import script res://hack.gd"), "import_script del destino")
	_write(source + ".import", "[params]\n\nimport_script/path=\"res://hack.gd\"\n".to_utf8_buffer())
	assert_true(str(tools.plan_import({"from": source, "to": TARGETS + "/other.glb"}).error).contains("import script"), "import_script del origen")
	DirAccess.remove_absolute(source + ".import")
	# Un modelo inválido no llega a copiarse.
	var broken := triangle()
	broken.nodes = [{"children": [0]}]
	_write(source, glb(broken, positions()))
	assert_true(str(tools.plan_import({"from": source, "to": TARGETS + "/other.glb"}).error).begins_with(source + " was not imported: "), "validado antes de copiar")
	_remove_tree(ProjectSettings.globalize_path(TARGETS))


func test_plan_import_gltf_copies_its_files() -> void:
	var folder := ProjectSettings.globalize_path(DIR).path_join("plan_gltf")
	DirAccess.make_dir_recursive_absolute(folder.path_join("tex"))
	_write(folder.path_join("scene.bin"), positions())
	_write(folder.path_join("tex/a.png"), png(8, 8))
	var doc := triangle()
	doc.buffers[0].uri = "scene.bin"
	doc.images = [{"uri": "tex/a.png"}]
	_write(folder.path_join("scene.gltf"), JSON.stringify(doc).to_utf8_buffer())
	var plan := ModelTools.new().plan_import({"from": folder.path_join("scene.gltf"), "to": TARGETS + "/hut"})
	assert_false(plan.has("error"), str(plan.get("error", "")))
	assert_eq(plan.copies, [
		[folder.path_join("scene.gltf"), TARGETS + "/hut/scene.gltf"],
		[folder.path_join("scene.bin"), TARGETS + "/hut/scene.bin"],
		[folder.path_join("tex/a.png"), TARGETS + "/hut/tex/a.png"],
	], "el .bin y las texturas, en el mismo lugar relativo")


## Traer de afuera o pisar un modelo pregunta como la shell; de res:// a un archivo nuevo, editar archivos.
func test_permission_group() -> void:
	var tool: Variant = ModelTools.new().tools()[0]
	assert_eq(tool.group_of({"from": "res://a.glb", "to": "res://m"}), PermissionPolicy.GROUP_EDIT_FILES, "dentro del proyecto")
	assert_eq(tool.group_of({"from": "/home/u/a.glb", "to": "res://m"}), PermissionPolicy.GROUP_SHELL, "desde afuera")
	assert_eq(tool.group_of({"from": "res://a.glb", "to": "res://m/a.glb", "replace": true}), PermissionPolicy.GROUP_SHELL, "reemplazar")


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _remove_tree(absolute: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	for sub: String in DirAccess.get_directories_at(absolute):
		_remove_tree(absolute.path_join(sub))
	DirAccess.remove_absolute(absolute)
