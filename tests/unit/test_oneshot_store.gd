extends "test_case.gd"
## Runs del One-shot en disco (D37): guardar y cargar, el último a medias, versión y limpieza.

const OneShotStore := preload("res://addons/godot_agent/oneshot/oneshot_store.gd")


func test_save_load_and_interrupted() -> void:
	var store := OneShotStore.new(temp_dir("oneshot_store"))
	assert_true(store.load_interrupted().is_empty(), "vacío")
	assert_true(store.save({"id": "20261020-100000", "active": false, "goal": "viejo"}), "guarda")
	assert_true(store.save({"id": "20261021-100000", "active": true, "goal": "a medias"}), "guarda otro")
	assert_eq(store.load_run("20261021-100000").goal, "a medias", "carga")
	assert_eq(store.load_interrupted().goal, "a medias", "el más nuevo, a medias")
	store.save({"id": "20261022-100000", "active": false, "goal": "terminado"})
	assert_true(store.load_interrupted().is_empty(), "si el más nuevo terminó, no se ofrece uno viejo")
	FileAccess.open(store.dir.path_join("20261022-100000.report.json"), FileAccess.WRITE).store_string("{}")
	assert_eq(store.ids(), PackedStringArray(["20261022-100000", "20261021-100000", "20261020-100000"]), "ids sin el informe")
	assert_false(FileAccess.file_exists(store.dir.path_join("20261022-100000.json.tmp")), "sin temporales")
	FileAccess.open(store.dir.path_join("20261019-100000.json"), FileAccess.WRITE).store_string("{\"id\": \"20261019-100000\", \"version\": 99}")
	assert_true(store.load_run("20261019-100000").is_empty(), "otra versión no se carga")
	FileAccess.open(store.dir.path_join("20261018-100000.json"), FileAccess.WRITE).store_string("roto")
	assert_true(store.load_run("20261018-100000").is_empty(), "JSON roto no se carga")


func test_prune_and_capture() -> void:
	var store := OneShotStore.new(temp_dir("oneshot_store_prune"))
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	for i in OneShotStore.KEEP + 3:
		store.save({"id": "202610%02d-000000" % (i + 1), "active": false}, image if i == 0 else null)
	assert_true(store.load_capture("20261001-000000") != null, "captura")
	store.prune()
	assert_eq(store.ids().size(), OneShotStore.KEEP, "quedan los últimos %d" % OneShotStore.KEEP)
	assert_true(store.load_run("20261001-000000").is_empty() and store.load_capture("20261001-000000") == null, "el más viejo se fue con su captura")
	assert_false(OneShotStore.new().is_enabled(), "sin carpeta no guarda")
	assert_false(OneShotStore.new().save({"id": "x"}), "y save no hace nada")
