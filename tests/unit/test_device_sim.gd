extends "test_case.gd"
## m11-51: el dispositivo simulado de run_scene: presets, orientación, validación y el viaje por el
## entorno hasta el juego.

const DeviceSim := preload("res://addons/godot_agent/playtest/runtime/device_sim.gd")


func test_presets_and_overrides() -> void:
	assert_eq(DeviceSim.normalize(null), {}, "sin device, nada")
	var phone: Dictionary = DeviceSim.normalize("phone").device
	assert_eq(phone.size, [1080, 2400], "el teléfono, vertical")
	assert_true(phone.touch, "con táctil")
	assert_eq(DeviceSim.normalize({"preset": "phone", "orientation": "landscape"}).device.size, [2400, 1080], "apaisado da vuelta el tamaño")
	assert_eq(DeviceSim.normalize({"preset": "tablet", "orientation": "landscape"}).device.size, [2048, 1536], "ya apaisada: queda igual")
	var custom: Dictionary = DeviceSim.normalize({"preset": "phone", "size": [720, 1280], "touch": false, "locale": "es", "scale": 2}).device
	assert_eq([custom.size, custom.touch, custom.locale, custom.scale], [[720, 1280], false, "es", 2.0], "lo pasado pisa al preset")
	assert_eq(DeviceSim.normalize({"locale": "ja"}).device, {"name": "", "size": [], "scale": 1.0, "touch": false, "locale": "ja"}, "solo el idioma, sin tocar la ventana")
	assert_eq(DeviceSim.describe(custom), "phone, 720×1280, scale 2.0, locale es", "la línea del informe")


func test_invalid_devices() -> void:
	for bad: Variant in ["watch", {"size": [10, 10]}, {"size": [100]}, {"size": "1080x2400"}, {"orientation": "portrait"}, {"orientation": "sideways", "preset": "phone"}, {"scale": 0}, {"scale": 9}, {}, 3]:
		var result := DeviceSim.normalize(bad)
		assert_true(result.has("error") and not result.has("device"), "rechaza %s · %s" % [bad, result])
	assert_true(str(DeviceSim.normalize("watch").error).contains("phone"), "el error lista los presets")


func test_env_round_trip() -> void:
	var before: Variant = OS.get_environment(DeviceSim.ENV) if OS.has_environment(DeviceSim.ENV) else null
	var device: Dictionary = DeviceSim.normalize({"preset": "steam-deck", "locale": "es"}).device
	var previous: Variant = DeviceSim.set_env(device)
	var read := DeviceSim.from_env()
	assert_eq([read.name, read.size, read.locale], ["steam-deck", [1280, 800], "es"], "el juego lee lo que puso el editor")
	DeviceSim.restore_env(previous)
	assert_eq(OS.get_environment(DeviceSim.ENV) if OS.has_environment(DeviceSim.ENV) else null, before, "y el entorno del editor queda como estaba")
	assert_eq(DeviceSim.from_env(), {} if before == null else DeviceSim.from_env(), "sin la variable, ningún dispositivo")


## El informe dice si el proyecto no tiene la traducción pedida, en vez de dar a entender que cambió.
func test_report_without_translation() -> void:
	var window := (Engine.get_main_loop() as SceneTree).root
	var text := DeviceSim.report(window, {"name": "", "size": [], "scale": 1.0, "touch": true, "locale": "xx"})
	assert_true(text.contains("no translation for it"), "sin traducción · " + text)
	assert_true(text.contains("touch events"), "y el táctil · " + text)
	assert_eq(DeviceSim.report(window, {}), "No simulated device.", "sin dispositivo")
