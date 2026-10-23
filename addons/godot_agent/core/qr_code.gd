@tool
extends RefCounted
## Código QR en GDScript (m7-25), para el link de Remote Control: modo byte, corrección M,
## versiones 1 a 10 (hasta 213 bytes). Datos → bloques con Reed-Solomon → matriz con patrones fijos
## → la máscara con menos penalización.
##
## Traducido de «QR Code generator library» (https://www.nayuki.io/page/qr-code-generator-library):
## Copyright (c) Project Nayuki. MIT License.
## Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
## associated documentation files (the "Software"), to deal in the Software without restriction,
## including without limitation the rights to use, copy, modify, merge, publish, distribute,
## sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions: the above copyright notice and this
## permission notice shall be included in all copies or substantial portions of the Software.
## The Software is provided "as is", without warranty of any kind, express or implied.
## `QrCode.new(texto)` arma la matriz; `is_dark` la consulta y `to_image` la dibuja con zona de silencio.

const MAX_VERSION := 10
## Por versión (índice 0 sin usar), nivel M.
const ECC_CODEWORDS_PER_BLOCK: PackedInt32Array = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const NUM_ERROR_CORRECTION_BLOCKS: PackedInt32Array = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
## Bits de formato del nivel M.
const FORMAT_BITS_M := 0
const PENALTY_N1 := 3
const PENALTY_N2 := 3
const PENALTY_N3 := 40
const PENALTY_N4 := 10

var size: int = 0
var version: int = 0
var mask: int = -1
## Fila por fila: _modules[y * size + x].
var _modules: PackedByteArray = []
var _function: PackedByteArray = []


## Matriz del texto (UTF-8). Si no entra en la versión 10, queda vacía (size 0).
## `forced_mask` (0–7) fija la máscara en lugar de elegir la de menos penalización.
func _init(text: String = "", forced_mask: int = -1) -> void:
	if not text.is_empty():
		_build(text.to_utf8_buffer(), forced_mask)


func is_dark(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size and _modules[y * size + x] == 1


## Imagen en blanco y negro, `scale` píxeles por módulo y `border` módulos de zona de silencio.
func to_image(scale: int = 4, border: int = 4) -> Image:
	var side := (size + border * 2) * scale
	var image := Image.create(maxi(side, 1), maxi(side, 1), false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	for y in size:
		for x in size:
			if is_dark(x, y):
				image.fill_rect(Rect2i((x + border) * scale, (y + border) * scale, scale, scale), Color.BLACK)
	return image


## Una fila por línea, «#» oscuro y «.» claro (para los tests).
func to_text() -> String:
	var lines: PackedStringArray = []
	for y in size:
		var line := ""
		for x in size:
			line += "#" if is_dark(x, y) else "."
		lines.append(line)
	return "\n".join(lines)


func _build(data: PackedByteArray, forced_mask: int) -> void:
	for candidate in range(1, MAX_VERSION + 1):
		var count_bits := 8 if candidate < 10 else 16
		if 4 + count_bits + data.size() * 8 <= _num_data_codewords(candidate) * 8:
			version = candidate
			break
	if version == 0:
		return
	size = version * 4 + 17
	_modules.resize(size * size)
	_modules.fill(0)
	_function.resize(size * size)
	_function.fill(0)
	_draw_function_patterns()
	_draw_codewords(_add_ecc_and_interleave(_data_codewords(data)))
	mask = forced_mask
	if mask < 0:
		var best := 0x7FFFFFFF
		for candidate in 8:
			_apply_mask(candidate)
			_draw_format_bits(candidate)
			var penalty := _penalty()
			if penalty < best:
				best = penalty
				mask = candidate
			_apply_mask(candidate)  # la máscara es un XOR: aplicarla de nuevo la saca
	_apply_mask(mask)
	_draw_format_bits(mask)


# --- datos ---------------------------------------------------------------------------------------

func _data_codewords(data: PackedByteArray) -> PackedByteArray:
	var bits: Array[int] = []
	_append_bits(bits, 0b0100, 4)  # modo byte
	_append_bits(bits, data.size(), 8 if version < 10 else 16)
	for byte in data:
		_append_bits(bits, byte, 8)
	var capacity := _num_data_codewords(version) * 8
	_append_bits(bits, 0, mini(4, capacity - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var result := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var byte := 0
		for j in 8:
			byte = (byte << 1) | bits[i + j]
		result.append(byte)
	var pad := 0xEC
	while result.size() < _num_data_codewords(version):
		result.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	return result


static func _append_bits(bits: Array[int], value: int, length: int) -> void:
	for i in range(length - 1, -1, -1):
		bits.append((value >> i) & 1)


func _add_ecc_and_interleave(data: PackedByteArray) -> PackedByteArray:
	var num_blocks := NUM_ERROR_CORRECTION_BLOCKS[version]
	var block_ecc_len := ECC_CODEWORDS_PER_BLOCK[version]
	var raw_codewords := _num_raw_data_modules(version) / 8
	var num_short_blocks := num_blocks - raw_codewords % num_blocks
	var short_block_len := raw_codewords / num_blocks
	var divisor := _rs_divisor(block_ecc_len)
	var blocks: Array[PackedByteArray] = []
	var k := 0
	for i in num_blocks:
		var length := short_block_len - block_ecc_len + (0 if i < num_short_blocks else 1)
		var block := data.slice(k, k + length)
		k += length
		var ecc := _rs_remainder(block, divisor)
		if i < num_short_blocks:
			block.append(0)  # relleno para que los bloques midan lo mismo; no se escribe
		block.append_array(ecc)
		blocks.append(block)
	var result := PackedByteArray()
	for i in blocks[0].size():
		for j in blocks.size():
			if i != short_block_len - block_ecc_len or j >= num_short_blocks:
				result.append(blocks[j][i])
	return result


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result.fill(0)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _rs_multiply(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _rs_multiply(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	result.fill(0)
	for byte in data:
		var factor := byte ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in divisor.size():
			result[i] ^= _rs_multiply(divisor[i], factor)
	return result


static func _rs_multiply(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = ((z << 1) ^ ((z >> 7) * 0x11D)) & 0xFF
		z ^= ((y >> i) & 1) * x
	return z


static func _num_raw_data_modules(ver: int) -> int:
	var result := (16 * ver + 128) * ver + 64
	if ver >= 2:
		var num_align := ver / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if ver >= 7:
			result -= 36
	return result


static func _num_data_codewords(ver: int) -> int:
	return _num_raw_data_modules(ver) / 8 - ECC_CODEWORDS_PER_BLOCK[ver] * NUM_ERROR_CORRECTION_BLOCKS[ver]


# --- matriz --------------------------------------------------------------------------------------

func _set_function(x: int, y: int, dark: bool) -> void:
	_modules[y * size + x] = 1 if dark else 0
	_function[y * size + x] = 1


func _draw_function_patterns() -> void:
	for i in size:
		_set_function(6, i, i % 2 == 0)
		_set_function(i, 6, i % 2 == 0)
	_draw_finder(3, 3)
	_draw_finder(size - 4, 3)
	_draw_finder(3, size - 4)
	var positions := _alignment_positions()
	var count := positions.size()
	for i in count:
		for j in count:
			if not ((i == 0 and j == 0) or (i == 0 and j == count - 1) or (i == count - 1 and j == 0)):
				_draw_alignment(positions[i], positions[j])
	_draw_format_bits(0)  # reserva el lugar; el valor real va con la máscara elegida
	_draw_version()


func _draw_finder(x: int, y: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var xx := x + dx
			var yy := y + dy
			if xx >= 0 and xx < size and yy >= 0 and yy < size:
				var dist := maxi(absi(dx), absi(dy))
				_set_function(xx, yy, dist != 2 and dist != 4)


func _draw_alignment(x: int, y: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_function(x + dx, y + dy, maxi(absi(dx), absi(dy)) != 1)


func _alignment_positions() -> PackedInt32Array:
	if version == 1:
		return PackedInt32Array()
	var num_align := version / 7 + 2
	var step := (version * 8 + num_align * 3 + 5) / (num_align * 4 - 4) * 2
	var result := PackedInt32Array([6])
	for i in range(num_align - 2, -1, -1):
		result.append(size - 7 - i * step)
	return result


func _draw_format_bits(mask_value: int) -> void:
	var data := FORMAT_BITS_M << 3 | mask_value
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := (data << 10 | rem) ^ 0x5412
	for i in range(0, 6):
		_set_function(8, i, _bit(bits, i))
	_set_function(8, 7, _bit(bits, 6))
	_set_function(8, 8, _bit(bits, 7))
	_set_function(7, 8, _bit(bits, 8))
	for i in range(9, 15):
		_set_function(14 - i, 8, _bit(bits, i))
	for i in range(0, 8):
		_set_function(size - 1 - i, 8, _bit(bits, i))
	for i in range(8, 15):
		_set_function(8, size - 15 + i, _bit(bits, i))
	_set_function(8, size - 8, true)


func _draw_version() -> void:
	if version < 7:
		return
	var rem := version
	for i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits := version << 12 | rem
	for i in 18:
		var dark := _bit(bits, i)
		var a := size - 11 + i % 3
		var b := i / 3
		_set_function(a, b, dark)
		_set_function(b, a, dark)


func _draw_codewords(data: PackedByteArray) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if _function[y * size + x] == 0 and i < data.size() * 8:
					_modules[y * size + x] = 1 if _bit(data[i >> 3], 7 - (i & 7)) else 0
					i += 1
		right -= 2


func _apply_mask(mask_value: int) -> void:
	for y in size:
		for x in size:
			if _function[y * size + x] == 1:
				continue
			var invert := false
			match mask_value:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				_modules[y * size + x] ^= 1


# --- penalización ---------------------------------------------------------------------------------

func _penalty() -> int:
	var result := 0
	for pass_index in 2:  # filas y después columnas
		for a in size:
			var run_color := 0
			var run_length := 0
			var history: Array[int] = [0, 0, 0, 0, 0, 0, 0]
			for b in size:
				var color: int = _modules[a * size + b] if pass_index == 0 else _modules[b * size + a]
				if color == run_color:
					run_length += 1
					if run_length == 5:
						result += PENALTY_N1
					elif run_length > 5:
						result += 1
				else:
					_add_history(run_length, history)
					if run_color == 0:
						result += _count_finder_patterns(history) * PENALTY_N3
					run_color = color
					run_length = 1
			result += _terminate_and_count(run_color, run_length, history) * PENALTY_N3
	for y in size - 1:
		for x in size - 1:
			var color := _modules[y * size + x]
			if color == _modules[y * size + x + 1] and color == _modules[(y + 1) * size + x] and color == _modules[(y + 1) * size + x + 1]:
				result += PENALTY_N2
	var dark := 0
	for value in _modules:
		dark += value
	var total := size * size
	var k := (absi(dark * 20 - total * 10) + total - 1) / total - 1
	result += k * PENALTY_N4
	return result


func _count_finder_patterns(history: Array[int]) -> int:
	var n := history[1]
	var core := n > 0 and history[2] == n and history[3] == n * 3 and history[4] == n and history[5] == n
	return (1 if core and history[0] >= n * 4 and history[6] >= n else 0) + (1 if core and history[6] >= n * 4 and history[0] >= n else 0)


func _terminate_and_count(run_color: int, run_length: int, history: Array[int]) -> int:
	if run_color == 1:
		_add_history(run_length, history)
		run_length = 0
	run_length += size  # borde claro después del final
	_add_history(run_length, history)
	return _count_finder_patterns(history)


func _add_history(run_length: int, history: Array[int]) -> void:
	if history[0] == 0:
		run_length += size  # borde claro antes del principio
	for i in range(history.size() - 1, 0, -1):
		history[i] = history[i - 1]
	history[0] = run_length


static func _bit(value: int, index: int) -> bool:
	return (value >> index) & 1 != 0
