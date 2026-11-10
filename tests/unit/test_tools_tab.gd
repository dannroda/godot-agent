extends "test_case.gd"
## m12-46: la lista de tools del agente en Extensiones: por categoría, con permiso por modo, el
## filtro, y la marca de las que esconde la lista compacta.

const ToolsTab := preload("res://addons/godot_agent/ui/extensions/tools_tab.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")

const CATALOG: Array[Dictionary] = [
	{"name": "scene_tree", "category": "read", "group": "read", "summary": "The scene tree.", "description": "The scene tree. With depth.", "extended": false},
	{"name": "run_scene", "category": "run", "group": "run", "summary": "Runs a scene.", "description": "Runs a scene. Captures a frame.", "extended": false},
	{"name": "paint_cells", "category": "tilemap", "group": "edit_scene", "summary": "Paints cells.", "description": "Paints cells.", "extended": true},
	{"name": "odd", "category": "mystery", "group": "other", "summary": "Odd.", "description": "Odd.", "extended": false},
]


func _tab(compact: bool = false, overrides: Dictionary = {}) -> ToolsTab:
	var tab := ToolsTab.new()
	tab.catalog_provider = func() -> Array[Dictionary]: return CATALOG
	tab.policy_provider = func() -> PermissionPolicy: return PermissionPolicy.new(overrides)
	tab.compact_provider = func() -> bool: return compact
	(Engine.get_main_loop() as SceneTree).root.add_child(tab)
	tab.refresh()
	return tab


func _rows(tab: ToolsTab) -> Dictionary:
	var rows := {}
	var tree: Tree = tab.get(&"_tree")
	for category: TreeItem in tree.get_root().get_children():
		for item: TreeItem in category.get_children():
			rows[item.get_text(ToolsTab.COLUMN_NAME)] = item
	return rows


func test_groups_permissions_and_filter() -> void:
	I18n.set_locale("en")
	var tab := _tab()
	assert_eq(tab.tool_count(), 4, "cuenta las tools")
	var tree: Tree = tab.get(&"_tree")
	var categories := tree.get_root().get_children().map(func(item: TreeItem) -> String: return item.get_text(0))
	assert_eq(categories, ["Read the project (1)", "Run the game (1)", "TileMaps (1)", "Mystery (1)"], "categorías en orden, las desconocidas al final · %s" % [categories])
	assert_false(tree.get_root().get_first_child().collapsed, "la primera abierta")
	assert_true(tree.get_root().get_first_child().get_next().collapsed, "las demás plegadas")
	var rows := _rows(tab)
	var run: TreeItem = rows["godot.run_scene"]
	assert_eq(run.get_text(ToolsTab.COLUMN_SUMMARY), "Runs a scene and returns the game's errors and Output", "la línea para las personas (ToolSummaries)")
	assert_true(run.get_tooltip_text(ToolsTab.COLUMN_SUMMARY).ends_with("Runs a scene. Captures a frame."), "la descripción del agente en el tooltip")
	assert_eq(rows["godot.odd"].get_text(ToolsTab.COLUMN_SUMMARY), "Odd.", "sin línea propia, la primera oración")
	assert_eq(run.get_text(ToolsTab.COLUMN_GROUP), "Run the game", "el grupo de permisos")
	# run: Preguntar ✗, Revisar ✓ (solo lectura del juego), Construir ✓, Auto ✓, One-shot ✓ según la spec §7.
	var expected := PackedStringArray()
	for mode in ToolsTab.MODES:
		expected.append(ToolsTab.MARKS[PermissionPolicy.new().matrix_value("run", mode)])
	assert_eq(run.get_text(ToolsTab.COLUMN_MODES), " ".join(expected), "una marca por modo, de la política")
	assert_true(run.get_tooltip_text(ToolsTab.COLUMN_MODES).begins_with("Ask: ") and run.get_tooltip_text(ToolsTab.COLUMN_MODES).contains("\nOne-shot: "), "el tooltip explica modo por modo · " + run.get_tooltip_text(ToolsTab.COLUMN_MODES))
	assert_true((tab.get(&"_count") as Label).text == "4 tools", "el contador · " + (tab.get(&"_count") as Label).text)
	assert_false((tab.get(&"_note") as Label).visible, "sin lista compacta no hay nota")
	(tab.get(&"_filter") as LineEdit).text = "cells"
	(tab.get(&"_filter") as LineEdit).text_changed.emit("cells")
	rows = _rows(tab)
	assert_eq(rows.keys(), ["godot.paint_cells"], "el filtro deja la que coincide · %s" % [rows.keys()])
	assert_false(tree.get_root().get_first_child().collapsed, "con filtro, abiertas")
	assert_eq((tab.get(&"_count") as Label).text, "1 of 4 tools", "el contador con filtro")
	(tab.get(&"_filter") as LineEdit).text_changed.emit("Edit scenes")
	assert_eq(_rows(tab).keys(), ["godot.paint_cells"], "también por el nombre del permiso")
	tab.free()


func test_compact_marks_and_overrides() -> void:
	I18n.set_locale("en")
	var tab := _tab(true, {"run": {"ask": "allow"}})
	var rows := _rows(tab)
	assert_true(rows.has("godot.paint_cells ⋯") and not rows.has("godot.paint_cells"), "la escondida por la lista compacta lleva ⋯ · %s" % [rows.keys()])
	assert_true(str(rows["godot.paint_cells ⋯"].get_tooltip_text(ToolsTab.COLUMN_NAME)).contains("godot.methods"), "y el tooltip lo explica")
	assert_true((tab.get(&"_note") as Label).visible and (tab.get(&"_note") as Label).text.begins_with("⋯ 1 tools"), "la nota cuenta las escondidas · " + (tab.get(&"_note") as Label).text)
	assert_true(rows["godot.run_scene"].get_text(ToolsTab.COLUMN_MODES).begins_with("✓ "), "el override del proyecto se ve (run permitido en Preguntar) · " + rows["godot.run_scene"].get_text(ToolsTab.COLUMN_MODES))
	I18n.set_locale("es")
	tab.refresh()
	var categories := (tab.get(&"_tree") as Tree).get_root().get_children().map(func(item: TreeItem) -> String: return item.get_text(0))
	assert_true("Leer el proyecto (1)" in categories, "categorías traducidas · %s" % [categories])
	I18n.set_locale("en")
	tab.free()
