extends "test_case.gd"
## Tamaño de imágenes desde la cabecera, para list_files (m11-76).

const ImageHeader := preload("res://addons/godot_agent/mcp/tools/image_header.gd")


func test_sizes() -> void:
	var image := Image.create(37, 21, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.8, 0.5))
	var dir := "user://image_header_test"
	DirAccess.make_dir_recursive_absolute(dir)
	image.save_png(dir + "/a.png")
	image.save_jpg(dir + "/a.jpg")
	image.save_webp(dir + "/lossless.webp", false)
	image.save_webp(dir + "/lossy.webp", true)
	var opaque := Image.create(64, 48, false, Image.FORMAT_RGB8)
	opaque.save_webp(dir + "/opaque.webp", true)
	for name: String in ["a.png", "a.jpg", "lossless.webp", "lossy.webp"]:
		assert_eq(ImageHeader.size_of(dir + "/" + name), Vector2i(37, 21), name)
	assert_eq(ImageHeader.size_of(dir + "/opaque.webp"), Vector2i(64, 48), "webp VP8 sin alfa")
	var text := FileAccess.open(dir + "/x.png", FileAccess.WRITE)
	text.store_string("not an image at all, just text")
	text.close()
	assert_eq(ImageHeader.size_of(dir + "/x.png"), Vector2i.ZERO, "no es imagen")
	assert_eq(ImageHeader.size_of(dir + "/missing.png"), Vector2i.ZERO, "no existe")
	for name: String in ["a.png", "a.jpg", "lossless.webp", "lossy.webp", "opaque.webp", "x.png"]:
		DirAccess.remove_absolute(dir + "/" + name)
	DirAccess.remove_absolute(dir)
