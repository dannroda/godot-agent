extends "test_case.gd"
## Rechazar por nodo en una escena (m11-34, fase 1): propiedades y nodos agregados, ida y vuelta, y
## sin pisar lo que cambió después del turno.

const SceneRevert := preload("res://addons/godot_agent/core/scene_revert.gd")
const SceneDiff := preload("res://addons/godot_agent/core/scene_diff.gd")

const BEFORE := """[gd_scene format=3]

[ext_resource type="Script" path="res://player.gd" id="1_p"]

[node name="Main" type="Node2D" unique_id=1]

[node name="Player" type="CharacterBody2D" parent="." unique_id=2]
position = Vector2(100, 50)
script = ExtResource("1_p")
speed = 300.0

[node name="Timer" type="Timer" parent="." unique_id=3]
wait_time = 2.0

[connection signal="timeout" from="Timer" to="Player" method="_on_timer_timeout"]
"""

# El turno: Player se mueve, pierde speed, gana un texto de dos líneas; entra HUD con un Label (y
# una conexión desde el Label) entre Player y Timer; Timer se vuelve one_shot.
const AFTER := """[gd_scene format=3]

[ext_resource type="Script" path="res://player.gd" id="1_p"]

[node name="Main" type="Node2D" unique_id=1]

[node name="Player" type="CharacterBody2D" parent="." unique_id=2]
position = Vector2(120, 50)
script = ExtResource("1_p")
editor_description = "uno
dos"

[node name="HUD" type="CanvasLayer" parent="." unique_id=4]

[node name="Label" type="Label" parent="HUD" unique_id=5]
text = "0"

[node name="Timer" type="Timer" parent="." unique_id=3]
wait_time = 2.0
one_shot = true

[connection signal="timeout" from="Timer" to="Player" method="_on_timer_timeout"]

[connection signal="resized" from="HUD/Label" to="Player" method="_on_resized"]
"""


func _change(changes: Array[Dictionary], label: String) -> Dictionary:
	for change: Dictionary in changes:
		if change.label == label:
			return change
	return {}


func test_changes_list() -> void:
	var changes := SceneRevert.changes(BEFORE, AFTER)
	var labels: Array = changes.map(func(c: Dictionary) -> String: return "%s %s" % [c.label, c.rejectable])
	assert_eq(labels, [
		"+ HUD true",
		"~ Player · position true", "~ Player · editor_description true", "~ Player · speed true",
		"~ Timer · one_shot true",
		"+ resized: HUD/Label → Player._on_resized() true",
	])


func test_reject_and_undo_each() -> void:
	var changes := SceneRevert.changes(BEFORE, AFTER)
	for change: Dictionary in changes:
		if not change.rejectable:
			assert_false(SceneRevert.apply(AFTER, change).ok, "%s no se rechaza" % change.label)
			continue
		var rejected := SceneRevert.apply(AFTER, change)
		assert_true(rejected.ok, "%s: %s" % [change.label, rejected.error])
		var left := SceneDiff.diff(BEFORE, rejected.text)
		assert_eq(SceneDiff.count(left), SceneDiff.count(SceneDiff.diff(BEFORE, AFTER)) - (2 if change.kind == SceneRevert.ADDED else 1),
			"%s: queda todo lo demás (un nodo agregado se lleva su conexión)" % change.label)
		assert_eq(SceneDiff.parse(rejected.text).nodes.size() > 0, true)
		var undone := SceneRevert.apply(rejected.text, change, true)
		assert_true(undone.ok, "deshacer %s: %s" % [change.label, undone.error])
		assert_eq(SceneDiff.count(SceneDiff.diff(AFTER, undone.text)), 0, "deshacer %s vuelve a lo del turno" % change.label)
		assert_false(SceneRevert.apply(rejected.text, change).ok, "%s ya rechazado no se rechaza de nuevo" % change.label)


func test_reject_all_gives_before() -> void:
	var text := AFTER
	for change: Dictionary in SceneRevert.changes(BEFORE, AFTER):
		if change.rejectable:
			var result := SceneRevert.apply(text, change)
			if result.ok:
				text = result.text
			else:  # la conexión del nodo agregado ya se fue con él
				assert_eq([change.kind, result.error], [SceneRevert.CONNECTION, "the connection is not there"], change.label)
	assert_eq(SceneDiff.count(SceneDiff.diff(BEFORE, text)), 0, "todo rechazado = la escena de antes: %s" % text)
	assert_false(text.contains("\n\n\n"), "sin líneas vacías de más")


func test_added_node_goes_back_in_place() -> void:
	var hud := _change(SceneRevert.changes(BEFORE, AFTER), "+ HUD")
	var rejected := SceneRevert.apply(AFTER, hud)
	assert_false(rejected.text.contains("HUD") or rejected.text.contains("_on_resized"), "el nodo, su hijo y su conexión se van")
	var undone := SceneRevert.apply(rejected.text, hud, true)
	assert_eq(undone.text, AFTER, "y vuelven al mismo lugar, texto idéntico")


func test_stale_is_not_overwritten() -> void:
	var changes := SceneRevert.changes(BEFORE, AFTER)
	var position := _change(changes, "~ Player · position")
	var edited := AFTER.replace("Vector2(120, 50)", "Vector2(500, 50)")
	var result := SceneRevert.apply(edited, position)
	assert_false(result.ok, "la posición cambió después del turno")
	assert_eq(result.text, edited, "no tocó nada")
	var hud := _change(changes, "+ HUD")
	var without_hud: String = SceneRevert.apply(AFTER, hud).text
	assert_false(SceneRevert.apply(without_hud, hud).ok, "un nodo que ya no está no se rechaza")
	var label_gone := AFTER.replace("[node name=\"Label\" type=\"Label\" parent=\"HUD\" unique_id=5]\ntext = \"0\"\n\n", "")
	assert_true(SceneRevert.apply(label_gone, hud).ok, "si el usuario borró un hijo, el nodo igual se puede rechazar")
	# Otro nodo con ese nombre pero otro unique_id no es el mismo.
	var other := AFTER.replace("unique_id=4", "unique_id=99")
	assert_false(SceneRevert.apply(other, hud).ok, "por unique_id, no por nombre")
