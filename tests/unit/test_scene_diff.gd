extends "test_case.gd"
## Diff por nodos de dos .tscn (m11-57).

const SceneDiff := preload("res://addons/godot_agent/core/scene_diff.gd")
const DiffDialog := preload("res://addons/godot_agent/ui/diff_dialog.gd")

const BEFORE := """[gd_scene format=3 uid="uid://c6m8o5aen5cfj"]

[ext_resource type="Script" uid="uid://dp87lqqu84td0" path="res://player.gd" id="1_player"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_a1"]
size = Vector2(10, 20)

[node name="Main" type="Node2D" unique_id=1]

[node name="Player" type="CharacterBody2D" parent="." unique_id=2 groups=["player"]]
position = Vector2(100, 50)
script = ExtResource("1_player")
speed = 300.0

[node name="Shape" type="CollisionShape2D" parent="Player" unique_id=3]
shape = SubResource("RectangleShape2D_a1")

[node name="Bat" type="Sprite2D" parent="." unique_id=4]

[node name="Enemies" type="Node2D" parent="." unique_id=5]

[node name="Old" type="Node2D" parent="." unique_id=6]

[node name="Child" type="Node2D" parent="Old" unique_id=7]

[node name="Timer" type="Timer" parent="." unique_id=8]
wait_time = 2.0

[connection signal="timeout" from="Timer" to="Player" method="_on_timer_timeout"]
"""

# Mismo contenido con otros ids de recursos (lo que hace Godot al volver a guardar), más: Player se
# mueve en x, Shape cambia de tamaño, Bat va adentro de Enemies, Timer se llama Clock, Old se va con su
# hijo, entra HUD con un Label, speed vuelve al valor por defecto y la conexión pasa a otro método.
const AFTER := """[gd_scene format=3 uid="uid://c6m8o5aen5cfj"]

[ext_resource type="Script" uid="uid://dp87lqqu84td0" path="res://player.gd" id="2_xyz"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_zz"]
size = Vector2(10, 40)

[node name="Main" type="Node2D" unique_id=1]

[node name="Player" type="CharacterBody2D" parent="." unique_id=2 groups=["player"]]
position = Vector2(120, 50)
script = ExtResource("2_xyz")

[node name="Shape" type="CollisionShape2D" parent="Player" unique_id=3]
shape = SubResource("RectangleShape2D_zz")

[node name="Enemies" type="Node2D" parent="." unique_id=5]

[node name="Bat" type="Sprite2D" parent="Enemies" unique_id=4]

[node name="Clock" type="Timer" parent="." unique_id=8]
wait_time = 2.0

[node name="HUD" type="CanvasLayer" parent="." unique_id=9]

[node name="Label" type="Label" parent="HUD" unique_id=10]
text = "Score:
0"

[connection signal="timeout" from="Clock" to="Player" method="_on_tick"]
"""


func test_parse_multiline_values() -> void:
	var scene := SceneDiff.parse(AFTER)
	assert_eq(scene.nodes.size(), 8)
	assert_eq(scene.nodes[7].props.text, "\"Score:\n0\"", "un string en dos líneas queda entero")
	assert_eq(scene.ext, {"2_xyz": "res://player.gd"})
	assert_eq(scene.nodes[1].attrs.groups, "[\"player\"]")


func test_node_diff() -> void:
	var result := SceneDiff.diff(BEFORE, AFTER)
	assert_eq(result.error, "")
	assert_eq(result.added, [{"path": "HUD", "type": "CanvasLayer", "children": 1}], "HUD con su Label, en una línea")
	assert_eq(result.removed, [{"path": "Old", "type": "Node2D", "children": 1}], "Old con su hijo")
	assert_eq(result.moved, [
		{"from": "Bat", "to": "Enemies/Bat", "type": "Sprite2D"},
		{"from": "Timer", "to": "Clock", "type": "Timer"},
	], "reparentado y renombrado; los hijos de un movido no cuentan")
	var changed := {}
	for node: Dictionary in result.changed:
		changed[node.path] = node.props
	assert_eq(changed.keys(), ["Player", "Player/Shape"], "el script con otro id de ExtResource no es un cambio")
	assert_eq(changed.Player, [
		{"name": "position", "before": "Vector2(100, 50)", "after": "Vector2(120, 50)"},
		{"name": "speed", "before": "300.0", "after": null},
	])
	assert_eq(changed["Player/Shape"], [{"name": "shape.size", "before": "Vector2(10, 20)", "after": "Vector2(10, 40)"}],
		"el SubResource se compara por contenido, no por id")
	assert_eq(result.connections_added, PackedStringArray(["timeout: Clock → Player._on_tick()"]))
	assert_eq(result.connections_removed, PackedStringArray(["timeout: Timer → Player._on_timer_timeout()"]))
	assert_eq(SceneDiff.count(result), 9)


func test_same_scene_resaved_is_empty() -> void:
	var resaved := BEFORE.replace("1_player", "9_q").replace("RectangleShape2D_a1", "RectangleShape2D_b2")
	assert_eq(SceneDiff.count(SceneDiff.diff(BEFORE, resaved)), 0, "otros ids, mismo contenido: nada")


func test_without_unique_ids() -> void:
	var before := "[gd_scene format=3]\n\n[node name=\"Root\" type=\"Node\"]\n\n[node name=\"A\" type=\"Node2D\" parent=\".\"]\n\n[node name=\"Box\" type=\"Node2D\" parent=\".\"]\n"
	var after := "[gd_scene format=3]\n\n[node name=\"Root\" type=\"Node\"]\n\n[node name=\"Box\" type=\"Node2D\" parent=\".\"]\n\n[node name=\"A\" type=\"Node2D\" parent=\"Box\"]\n"
	var result := SceneDiff.diff(before, after)
	assert_eq(result.moved, [{"from": "A", "to": "Box/A", "type": "Node2D"}], "sin ids: mismo nombre y tipo, otro lugar")
	assert_eq(result.added, [])
	assert_eq(result.removed, [])


func test_new_and_deleted_scene() -> void:
	var created := SceneDiff.diff("", BEFORE)
	assert_eq(created.added.size(), 1, "una escena nueva es la raíz con todo abajo")
	assert_eq(created.added[0].children, 7)
	assert_eq(SceneDiff.diff(BEFORE, "").removed[0].path, ".")
	assert_eq(SceneDiff.diff("hola", BEFORE).error, "not a text scene (.tscn)")


func test_root_rename_and_instances() -> void:
	var before := "[gd_scene format=3]\n\n[ext_resource type=\"PackedScene\" path=\"res://enemy.tscn\" id=\"1\"]\n\n[node name=\"Main\" type=\"Node2D\"]\n\n[node name=\"E\" parent=\".\" instance=ExtResource(\"1\")]\n"
	var after := before.replace("name=\"Main\"", "name=\"Level\"").replace("res://enemy.tscn", "res://boss.tscn")
	var result := SceneDiff.diff(before, after)
	assert_eq(result.changed, [
		{"path": ".", "type": "Node2D", "props": [{"name": "name", "before": "Main", "after": "Level"}]},
		{"path": "E", "type": "res://boss.tscn", "props": [{"name": "type", "before": "res://enemy.tscn", "after": "res://boss.tscn"}]},
	])


func test_bbcode_is_bounded() -> void:
	var before := "[gd_scene format=3]\n\n[node name=\"Root\" type=\"Node\" unique_id=1]\n"
	var after := before
	for i in 600:
		before += "\n[node name=\"N%d\" type=\"Node2D\" parent=\".\" unique_id=%d]\nposition = Vector2(%d, 0)\n" % [i, i + 2, i]
		after += "\n[node name=\"N%d\" type=\"Node2D\" parent=\".\" unique_id=%d]\nposition = Vector2(%d, 1)\nlabel = \"%s\"\n" % [i, i + 2, i, "x".repeat(500)]
	var text := DiffDialog.scene_bbcode("before", before, "now", after)
	var lines := text.split("\n")
	assert_true(lines.size() <= DiffDialog.SCENE_MAX_LINES + 4, "acotado: %d líneas" % lines.size())
	assert_true(text.contains("more lines"), "dice cuánto quedó afuera")
	assert_false(text.contains("x".repeat(DiffDialog.SCENE_MAX_VALUE + 1)), "los valores largos se cortan")
	assert_eq(DiffDialog.scene_bbcode("a", "func f():\n\tpass", "b", "func g():\n\tpass"), "", "un script no es una escena")


func test_nested_sub_resources_compare_by_content() -> void:
	var before := "[gd_scene format=3]\n\n[sub_resource type=\"Animation\" id=\"Animation_a\"]\nlength = 1.0\n\n[sub_resource type=\"AnimationLibrary\" id=\"AnimationLibrary_a\"]\n_data = {\n&\"walk\": SubResource(\"Animation_a\")\n}\n\n[node name=\"Root\" type=\"Node\" unique_id=1]\n\n[node name=\"AP\" type=\"AnimationPlayer\" parent=\".\" unique_id=2]\nlibraries = {\n&\"\": SubResource(\"AnimationLibrary_a\")\n}\n"
	var renumbered := before.replace("Animation_a", "Animation_q").replace("AnimationLibrary_a", "AnimationLibrary_q")
	assert_eq(SceneDiff.count(SceneDiff.diff(before, renumbered)), 0, "ids anidados distintos, mismo contenido")
	var longer := before.replace("length = 1.0", "length = 2.0")
	var result := SceneDiff.diff(before, longer)
	assert_eq(result.changed.size(), 1, "una animación de la librería cambió: se ve en libraries")
	assert_eq(result.changed[0].props[0].name, "libraries")


func test_bbcode_reads_well() -> void:
	var text := DiffDialog.scene_bbcode("before", BEFORE, "now", AFTER)
	var plain := RegEx.create_from_string("\\[/?[a-z]+(=[^\\]]*)?\\]").sub(text, "", true)
	assert_true(plain.contains("1 node added") or plain.contains("2 nodes added"), plain)
	assert_true(plain.contains("+ HUD (CanvasLayer) with 1 node below"), plain)
	assert_true(plain.contains("→ Timer now Clock (Timer)"), plain)
	assert_true(plain.contains("speed: default") == false and plain.contains("speed: 300.0 → default"), plain)
	assert_true(plain.contains("shape.size: Vector2(10, 20) → Vector2(10, 40)"), plain)
