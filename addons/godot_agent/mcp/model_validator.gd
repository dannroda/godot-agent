@tool
extends RefCounted
## Revisa un modelo glTF 2.0 antes de que import_model lo copie al proyecto (m11-85).
##
## Lo que se acepta (spec de glTF 2.0 y GLB, con topes para que un archivo raro no trabe al editor):
## - .glb: cabecera "glTF" versión 2 con el largo real del archivo; primero el chunk JSON y, si hay,
##   un chunk BIN; los dos alineados a 4 bytes. Todo adentro: ninguna `uri`.
## - .gltf: el JSON y sus archivos (buffers e imágenes) con rutas relativas que quedan dentro de la
##   carpeta del .gltf; nada de esquemas (`data:`, `file:`, `http:`), rutas absolutas ni `..`.
## - El JSON: UTF-8 válido, un objeto con asset.version "2.0", números finitos y anidado acotado.
## - Ninguna extensión en extensionsRequired: cada una necesitaría su propia revisión.
## - Cantidades acotadas (MAX_ITEMS), cada accessor dentro de su bufferView y cada bufferView dentro
##   de su buffer, imágenes PNG/JPEG/WebP de hasta MAX_IMAGE_SIDE de lado.
## - Los nodos forman árboles disjuntos (spec §3.5.3): ningún nodo con dos padres ni ciclos.
##
## Devuelve {success: true, summary: {bytes, nodes, meshes, materials, skins, images, animations
## (nombres)}, files: [archivos del .gltf]} o {success: false, error}.

const ImageHeader := preload("tools/image_header.gd")

const GLB_MAGIC := 0x46546C67  # "glTF" en little endian
const CHUNK_JSON := 0x4E4F534A  # "JSON"
const CHUNK_BIN := 0x004E4942  # "BIN\0"
const GLB_HEADER := 12
const CHUNK_HEADER := 8

const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_JSON_BYTES := 1024 * 1024
const MAX_DEPTH := 32
const MAX_JSON_VALUES := 100000
const MAX_IMAGE_SIDE := 8192
const MAX_ACCESSOR_ELEMENTS := 1000000
const MAX_TOTAL_ELEMENTS := 4000000
## Topes por colección del documento. Un esqueleto de Blender suma un nodo por hueso.
const MAX_ITEMS := {
	"nodes": 1024, "meshes": 256, "materials": 256, "skins": 32, "animations": 128,
	"images": 64, "textures": 64, "samplers": 64, "accessors": 4096, "bufferViews": 4096, "buffers": 1,
}
## componentType → bytes por componente.
const COMPONENT_BYTES := {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
## type → componentes por elemento.
const TYPE_COMPONENTS := {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]

var _problem := ""
var _values := 0
## Diccionarios del documento cuya `uri` ya se revisó (buffers e imágenes de un .gltf).
var _checked_uris: Array = []


## Un .glb o un .gltf por su ruta (absoluta o res://).
static func inspect_file(path: String) -> Dictionary:
	var extension := path.get_extension().to_lower()
	if extension == "glb":
		if _size_of(path) > MAX_FILE_BYTES:
			return _failure("The GLB is larger than %s." % String.humanize_size(MAX_FILE_BYTES))
		return inspect_glb(FileAccess.get_file_as_bytes(path))
	if extension == "gltf":
		return inspect_gltf(path)
	return _failure("Only .glb and .gltf are supported.")


static func inspect_glb(bytes: PackedByteArray) -> Dictionary:
	var checker := new()
	var result: Variant = checker._glb(bytes)
	return result if result is Dictionary else _failure(checker._problem)


static func inspect_gltf(path: String) -> Dictionary:
	var checker := new()
	var result: Variant = checker._gltf(path)
	return result if result is Dictionary else _failure(checker._problem)


# --- contenedores --------------------------------------------------------------------------------


func _glb(bytes: PackedByteArray) -> Variant:
	var size := bytes.size()
	if size < GLB_HEADER + CHUNK_HEADER or size > MAX_FILE_BYTES:
		return _fail("Not a GLB 2.0 file (bad header or size).")
	if bytes.decode_u32(0) != GLB_MAGIC or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != size:
		return _fail("Not a GLB 2.0 file (bad header or size).")
	# Chunks: [tipo, datos]; el primero es el JSON, el segundo (opcional) el BIN.
	var chunks: Array = []
	var at := GLB_HEADER
	while at < size:
		if chunks.size() == 2:
			return _fail("The GLB has extra chunks after the binary one.")
		if at + CHUNK_HEADER > size:
			return _fail("The GLB ends inside a chunk header.")
		var length := bytes.decode_u32(at)
		var start := at + CHUNK_HEADER
		if length % 4 != 0 or start + length > size:
			return _fail("The GLB %s chunk is malformed." % ("JSON" if chunks.is_empty() else "binary"))
		chunks.append([bytes.decode_u32(at + 4), bytes.slice(start, start + length)])
		at = start + length
	if chunks.is_empty() or chunks[0][0] != CHUNK_JSON or chunks[0][1].is_empty() or chunks[0][1].size() > MAX_JSON_BYTES:
		return _fail("The GLB JSON chunk is malformed.")
	if chunks.size() == 2 and chunks[1][0] != CHUNK_BIN:
		return _fail("The GLB binary chunk is malformed.")
	var doc: Variant = _document(chunks[0][1])
	if doc == null:
		return null
	var binary: PackedByteArray = chunks[1][1] if chunks.size() == 2 else PackedByteArray()
	var buffers: Variant = doc.get("buffers", [])
	var blobs: Array = []
	if buffers is Array and not buffers.is_empty():
		# El primer buffer de un GLB es el chunk BIN (sin uri); el chunk puede tener hasta 3 bytes de relleno.
		var first: Variant = buffers[0]
		if chunks.size() != 2:
			return _fail("The GLB declares a buffer but has no binary chunk.")
		if not first is Dictionary or not _is_count(first.get("byteLength")) or int(first.byteLength) > binary.size() or binary.size() - int(first.byteLength) > 3:
			return _fail("The GLB buffer does not match its binary chunk.")
		blobs.append(binary)
	var summary: Variant = _check(doc, blobs)
	if summary == null:
		return null
	summary.bytes = bytes.size()
	return {"success": true, "summary": summary, "files": PackedStringArray()}


func _gltf(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return _fail("%s does not exist." % path)
	var total := _size_of(path)
	if total > MAX_JSON_BYTES:
		return _fail("The .gltf JSON is larger than %s." % String.humanize_size(MAX_JSON_BYTES))
	var doc: Variant = _document(FileAccess.get_file_as_bytes(path))
	if doc == null:
		return null
	var folder := path.get_base_dir()
	var files: PackedStringArray = []
	var blobs: Array = []
	var buffers: Variant = doc.get("buffers", [])
	if buffers is Array and buffers.size() <= MAX_ITEMS.buffers:
		for buffer: Variant in buffers:
			if not buffer is Dictionary or not buffer.get("uri") is String or not _is_count(buffer.get("byteLength")):
				return _fail("Every .gltf buffer needs a relative uri and a byteLength.")
			var file := _inside(folder, buffer.uri)
			if file.is_empty():
				return _fail("Buffer uri %s must be a relative path inside the folder of the .gltf." % JSON.stringify(buffer.uri))
			if not FileAccess.file_exists(file):
				return _fail("The buffer %s does not exist next to the .gltf." % buffer.uri)
			var size := _size_of(file)
			total += size
			if total > MAX_FILE_BYTES:
				return _fail("The .gltf and its files add up to more than %s." % String.humanize_size(MAX_FILE_BYTES))
			if size < int(buffer.byteLength) or size - int(buffer.byteLength) > 3:
				return _fail("The buffer %s is %d bytes, but the .gltf says %d." % [buffer.uri, size, int(buffer.byteLength)])
			blobs.append(FileAccess.get_file_as_bytes(file))
			files.append(file)
			_checked_uris.append(buffer)
	var images: Variant = doc.get("images", [])
	if images is Array and images.size() <= MAX_ITEMS.images:
		for image: Variant in images:
			if not image is Dictionary or not image.has("uri"):
				continue
			if image.has("bufferView") or not image.uri is String:
				return _fail("An image needs either a relative uri or a bufferView.")
			var file := _inside(folder, image.uri)
			if file.is_empty() or not file.get_extension().to_lower() in IMAGE_EXTENSIONS:
				return _fail("Image uri %s must be a relative .png, .jpg or .webp path inside the folder of the .gltf." % JSON.stringify(image.uri))
			if not FileAccess.file_exists(file):
				return _fail("The image %s does not exist next to the .gltf." % image.uri)
			total += _size_of(file)
			if total > MAX_FILE_BYTES:
				return _fail("The .gltf and its files add up to more than %s." % String.humanize_size(MAX_FILE_BYTES))
			if not _image_ok(FileAccess.get_file_as_bytes(file)):
				return _fail("The image %s is not a PNG, JPEG or WebP of at most %d pixels per side." % [image.uri, MAX_IMAGE_SIDE])
			if not file in files:
				files.append(file)
			_checked_uris.append(image)
	var summary: Variant = _check(doc, blobs)
	if summary == null:
		return null
	summary.bytes = total
	return {"success": true, "summary": summary, "files": files}


# --- documento -----------------------------------------------------------------------------------


## El JSON como diccionario, o null. UTF-8: decodificar y volver a codificar da los mismos bytes
## (un byte inválido sale como U+FFFD y un NUL corta el texto). El relleno de espacios del GLB vuelve igual.
func _document(source: PackedByteArray) -> Variant:
	var text := source.get_string_from_utf8()
	if text.to_utf8_buffer() != source:
		return _fail("The glTF JSON is not valid UTF-8.")
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("The glTF JSON does not parse: %s (line %d)." % [json.get_error_message(), json.get_error_line()])
	if not json.data is Dictionary:
		return _fail("The glTF JSON is not an object.")
	var asset: Variant = json.data.get("asset")
	if not asset is Dictionary or asset.get("version") != "2.0":
		return _fail("Only glTF 2.0 models are accepted (asset.version).")
	return json.data


## Todas las reglas sobre el documento; `blobs`: los bytes de cada buffer. El resumen, o null.
func _check(doc: Dictionary, blobs: Array) -> Variant:
	if not _scan(doc, 0):
		return null
	for key: String in MAX_ITEMS:
		var items: Variant = doc.get(key, [])
		if not items is Array:
			return _fail("%s must be an array." % key)
		if items.size() > MAX_ITEMS[key]:
			return _fail("The model has too many %s (at most %d)." % [key, MAX_ITEMS[key]])
	var required: Variant = doc.get("extensionsRequired", [])
	if not required is Array or not required.is_empty():
		var names := ", ".join(Array(required if required is Array else [required]).map(func(name: Variant) -> String: return str(name)))
		return _fail("The model requires the glTF extensions %s: export it without them." % names)
	var views: Array = doc.get("bufferViews", [])
	if not (_views_fit(views, blobs) and _accessors_fit(doc.get("accessors", []), views)
			and _node_forest(doc.get("nodes", [])) and _embedded_images(doc.get("images", []), views, blobs)):
		return null
	var animations: PackedStringArray = []
	for animation: Variant in doc.get("animations", []):
		animations.append(str(animation.get("name", "")) if animation is Dictionary else "")
	return {
		"bytes": 0,
		"nodes": doc.get("nodes", []).size(),
		"meshes": doc.get("meshes", []).size(),
		"materials": doc.get("materials", []).size(),
		"skins": doc.get("skins", []).size(),
		"images": doc.get("images", []).size(),
		"animations": animations,
	}


## Recorre cada valor: anidado, cantidad, números finitos y ninguna uri que no se haya revisado.
func _scan(value: Variant, depth: int) -> bool:
	_values += 1
	if _values > MAX_JSON_VALUES:
		return _reject("The glTF JSON has too many values.")
	if depth > MAX_DEPTH:
		return _reject("The glTF JSON is nested too deeply.")
	match typeof(value):
		TYPE_FLOAT:
			if not is_finite(value):
				return _reject("The glTF JSON has a non-finite number.")
		TYPE_ARRAY:
			for item: Variant in value:
				if not _scan(item, depth + 1):
					return false
		TYPE_DICTIONARY:
			if value.has("uri") and not _checked_uris.any(func(known: Dictionary) -> bool: return is_same(known, value)):
				return _reject("The model names the file %s: a .glb must embed its buffers and images, and a .gltf may only name files next to it." % JSON.stringify(str(value.uri).left(80)))
			for item: Variant in value.values():
				if not _scan(item, depth + 1):
					return false
	return true


func _views_fit(views: Array, blobs: Array) -> bool:
	for index: int in views.size():
		var view: Variant = views[index]
		if not view is Dictionary:
			return _reject("Buffer view %d is not an object." % index)
		var buffer: Variant = view.get("buffer")
		if not _is_count(buffer) or int(buffer) >= blobs.size():
			return _reject("Buffer view %d points to a buffer that does not exist." % index)
		var offset: Variant = view.get("byteOffset", 0)
		var length: Variant = view.get("byteLength")
		if not _is_count(offset) or not _is_count(length) or int(length) == 0 or int(offset) + int(length) > (blobs[int(buffer)] as PackedByteArray).size():
			return _reject("Buffer view %d is outside buffer %d." % [index, int(buffer)])
		var stride: Variant = view.get("byteStride", 4)
		if not _is_count(stride) or int(stride) < 4 or int(stride) > 252 or int(stride) % 4 != 0:
			return _reject("Buffer view %d has an invalid byteStride." % index)
	return true


func _accessors_fit(accessors: Array, views: Array) -> bool:
	var total := 0
	for index: int in accessors.size():
		var accessor: Variant = accessors[index]
		if not accessor is Dictionary:
			return _reject("Accessor %d is not an object." % index)
		var component: Variant = accessor.get("componentType")
		var kind: Variant = accessor.get("type")
		if not _is_count(component) or not COMPONENT_BYTES.has(int(component)) or not TYPE_COMPONENTS.has(kind):
			return _reject("Accessor %d has an unsupported componentType or type." % index)
		var count: Variant = accessor.get("count")
		if not _is_count(count) or int(count) < 1 or int(count) > MAX_ACCESSOR_ELEMENTS:
			return _reject("Accessor %d has an invalid count (1 to %d)." % [index, MAX_ACCESSOR_ELEMENTS])
		total += int(count)
		if total > MAX_TOTAL_ELEMENTS:
			return _reject("The accessors add up to more than %d elements." % MAX_TOTAL_ELEMENTS)
		if not accessor.has("bufferView"):
			continue  # todo ceros (o sparse): no lee bytes de ningún buffer view
		var view_index: Variant = accessor.bufferView
		if not _is_count(view_index) or int(view_index) >= views.size():
			return _reject("Accessor %d points to a buffer view that does not exist." % index)
		var view: Dictionary = views[int(view_index)]
		var offset: Variant = accessor.get("byteOffset", 0)
		if not _is_count(offset):
			return _reject("Accessor %d has an invalid byteOffset." % index)
		# Las matrices de 1 y 2 bytes llevan relleno por columna: ahí no se calcula el tamaño exacto.
		if str(kind).begins_with("MAT") and int(COMPONENT_BYTES[int(component)]) < 4:
			continue
		var element := int(COMPONENT_BYTES[int(component)]) * int(TYPE_COMPONENTS[kind])
		var stride := int(view.get("byteStride", element))
		if int(offset) + stride * (int(count) - 1) + element > int(view.byteLength):
			return _reject("Accessor %d reads past the end of buffer view %d." % [index, int(view_index)])
	return true


## Spec: los nodos forman árboles disjuntos. Cada hijo existe y tiene un solo padre; todo nodo se
## alcanza desde una raíz (uno que no se alcanza está en un ciclo).
func _node_forest(nodes: Array) -> bool:
	var parent := PackedInt32Array()
	parent.resize(nodes.size())
	parent.fill(-1)
	for index: int in nodes.size():
		var node: Variant = nodes[index]
		if not node is Dictionary or not node.get("children", []) is Array:
			return _reject("Node %d is not a valid node." % index)
		for child: Variant in node.get("children", []):
			if not _is_count(child) or int(child) >= nodes.size():
				return _reject("Node %d has a child that does not exist." % index)
			if parent[int(child)] != -1:
				return _reject("Node %d is a child of two nodes." % int(child))
			parent[int(child)] = index
	var reached := 0
	var pending: Array[int] = []
	for index: int in nodes.size():
		if parent[index] == -1:
			pending.append(index)
	while not pending.is_empty():
		var index: int = pending.pop_back()
		reached += 1
		for child: Variant in nodes[index].get("children", []):
			pending.append(int(child))
	if reached != nodes.size():
		return _reject("The node hierarchy has a cycle.")
	return true


func _embedded_images(images: Array, views: Array, blobs: Array) -> bool:
	for index: int in images.size():
		var image: Variant = images[index]
		if not image is Dictionary:
			return _reject("Image %d is not an object." % index)
		if image.has("uri"):
			continue  # un archivo del .gltf, revisado en _gltf
		var view_index: Variant = image.get("bufferView")
		if not _is_count(view_index) or int(view_index) >= views.size():
			return _reject("Image %d needs a bufferView that exists." % index)
		var view: Dictionary = views[int(view_index)]
		var start := int(view.get("byteOffset", 0))
		var data := (blobs[int(view.get("buffer"))] as PackedByteArray).slice(start, start + int(view.byteLength))
		if not _image_ok(data):
			return _reject("Image %d is not a PNG, JPEG or WebP of at most %d pixels per side." % [index, MAX_IMAGE_SIDE])
	return true


# --- utilidades ----------------------------------------------------------------------------------


## La ruta absoluta de `uri` (relativa, con %XX) dentro de `folder`, o "" si no es relativa o sale.
static func _inside(folder: String, uri: String) -> String:
	var relative := _unescape(uri)
	if relative.is_empty() or relative.begins_with("/") or relative.contains(":") or relative.contains("\\"):
		return ""
	if ".." in relative.split("/"):
		return ""
	var file := folder.path_join(relative).simplify_path()
	return file if file.begins_with(folder.trim_suffix("/") + "/") else ""


## Decodifica %XX en mayúscula o minúscula (String.uri_decode de 4.7 no decodifica "%2e"). "" si un %
## no va seguido de dos dígitos hexadecimales o los bytes no son UTF-8.
static func _unescape(uri: String) -> String:
	var parts := uri.split("%")
	var bytes := parts[0].to_utf8_buffer()
	for i: int in range(1, parts.size()):
		var hex := parts[i].left(2)
		if hex.length() != 2 or not hex.is_valid_hex_number():
			return ""
		bytes.append(hex.hex_to_int())
		bytes.append_array(parts[i].substr(2).to_utf8_buffer())
	var text := bytes.get_string_from_utf8()
	return text if text.to_utf8_buffer() == bytes else ""


static func _image_ok(data: PackedByteArray) -> bool:
	var size := ImageHeader.size_of_bytes(data)
	return size.x > 0 and size.y > 0 and size.x <= MAX_IMAGE_SIDE and size.y <= MAX_IMAGE_SIDE


## Entero no negativo (JSON da float para cualquier número).
static func _is_count(value: Variant) -> bool:
	if value is int:
		return value >= 0
	return value is float and is_finite(value) and value >= 0.0 and value == floorf(value)


static func _size_of(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file else 0


func _reject(message: String) -> bool:
	_problem = message
	return false


func _fail(message: String) -> Variant:
	_problem = message
	return null


static func _failure(message: String) -> Dictionary:
	return {"success": false, "error": message}
