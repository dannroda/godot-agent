@tool
extends RefCounted
## Tamaño de una imagen leído de la cabecera del archivo, sin cargarla (m11-76): list_files lo muestra
## para que el agente no lo saque con Python. PNG, JPEG y WebP; otro formato o un archivo roto da (0, 0).

## Bytes que se leen de un JPEG buscando el marcador SOF (los EXIF grandes van antes).
const JPEG_SCAN := 262144


static func size_of(path: String) -> Vector2i:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Vector2i.ZERO
	var head := file.get_buffer(32)
	if head.size() >= 4 and head[0] == 0xFF and head[1] == 0xD8:
		file.seek(0)
		return _jpeg(file.get_buffer(JPEG_SCAN))
	return size_of_bytes(head)


## Lo mismo sobre los bytes de la imagen (m11-85: las imágenes que trae un GLB adentro).
static func size_of_bytes(data: PackedByteArray) -> Vector2i:
	if data.size() >= 24 and data.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return Vector2i(_be32(data, 16), _be32(data, 20))
	if data.size() >= 30 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		return _webp(data)
	if data.size() >= 4 and data[0] == 0xFF and data[1] == 0xD8:
		return _jpeg(data.slice(0, JPEG_SCAN))
	return Vector2i.ZERO


static func _webp(head: PackedByteArray) -> Vector2i:
	match head.slice(12, 16).get_string_from_ascii():
		"VP8 ":
			return Vector2i(_le16(head, 26) & 0x3FFF, _le16(head, 28) & 0x3FFF)
		"VP8L":
			var bits := head[21] | (head[22] << 8) | (head[23] << 16) | (head[24] << 24)
			return Vector2i((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
		"VP8X":
			return Vector2i((head[24] | (head[25] << 8) | (head[26] << 16)) + 1, (head[27] | (head[28] << 8) | (head[29] << 16)) + 1)
	return Vector2i.ZERO


static func _jpeg(data: PackedByteArray) -> Vector2i:
	var i := 2
	while i + 9 < data.size():
		if data[i] != 0xFF:
			return Vector2i.ZERO
		var marker := data[i + 1]
		if marker == 0xFF:
			i += 1
			continue
		if marker in [0xD8, 0x01] or (marker >= 0xD0 and marker <= 0xD7):
			i += 2
			continue
		# SOF0..SOF15 salvo DHT (C4), JPG (C8) y DAC (CC).
		if marker >= 0xC0 and marker <= 0xCF and marker not in [0xC4, 0xC8, 0xCC]:
			return Vector2i(_be16(data, i + 7), _be16(data, i + 5))
		i += 2 + _be16(data, i + 2)
	return Vector2i.ZERO


static func _be32(data: PackedByteArray, at: int) -> int:
	return (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3]


static func _be16(data: PackedByteArray, at: int) -> int:
	return (data[at] << 8) | data[at + 1]


static func _le16(data: PackedByteArray, at: int) -> int:
	return data[at] | (data[at + 1] << 8)
