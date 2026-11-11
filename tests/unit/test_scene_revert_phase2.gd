extends "test_case.gd"
## Rechazar por nodo en una escena, fase 2 (m11-59): nodos borrados de vuelta en su lugar entre sus
## hermanos, movidos y renombrados, encabezado, conexiones y propiedades con recursos, con los
## ext_resource y sub_resource rearmados sin chocar ids. Cada escena que queda se carga (validate()) y
## su árbol tiene que ser el de antes: nombres, orden de los hijos, propiedades y conexiones.

const SceneRevert := preload("res://addons/godot_agent/core/scene_revert.gd")
const SceneDiff := preload("res://addons/godot_agent/core/scene_diff.gd")

const DIR := "user://unit_tests/scene_revert"
const GRADIENT := DIR + "/gradient.tres"
const SIGNATURE_PATH := DIR + "/signature.tscn"

# Antes del turno.
const BEFORE := """[gd_scene load_steps=4 format=3]

[ext_resource type="Gradient" path="GRADIENT" id="1_g"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_a"]
size = Vector2(10, 10)

[sub_resource type="GradientTexture1D" id="GradientTexture1D_t"]
gradient = ExtResource("1_g")

[node name="Main" type="Node2D" unique_id=1]

[node name="Player" type="CharacterBody2D" parent="." unique_id=2]
position = Vector2(100, 50)

[node name="Shape" type="CollisionShape2D" parent="Player" unique_id=3]
shape = SubResource("RectangleShape2D_a")

[node name="Sprite" type="Sprite2D" parent="Player" unique_id=4]
texture = SubResource("GradientTexture1D_t")

[node name="Timer" type="Timer" parent="." unique_id=5 groups=["timers"]]
wait_time = 2.0

[node name="Label" type="Label" parent="." unique_id=6]
text = "hi"

[connection signal="timeout" from="Timer" to="Label" method="hide"]
"""

# El turno: la raíz se llama Game; Sprite se borra (con su textura y su gradiente) y entra Icon con
# otra textura que usa el mismo id; Shape crece; Timer pierde el grupo; Label pasa a Player/Score
# (y su conexión con él); entra una conexión nueva.
const AFTER := """[gd_scene load_steps=3 format=3]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_a"]
size = Vector2(20, 20)

[sub_resource type="GradientTexture1D" id="GradientTexture1D_t"]
width = 64

[node name="Game" type="Node2D" unique_id=1]

[node name="Player" type="CharacterBody2D" parent="." unique_id=2]
position = Vector2(100, 50)

[node name="Shape" type="CollisionShape2D" parent="Player" unique_id=3]
shape = SubResource("RectangleShape2D_a")

[node name="Score" type="Label" parent="Player" unique_id=6]
text = "hi"

[node name="Timer" type="Timer" parent="." unique_id=5]
wait_time = 2.0

[node name="Icon" type="Sprite2D" parent="." unique_id=7]
texture = SubResource("GradientTexture1D_t")

[connection signal="timeout" from="Timer" to="Player/Score" method="hide"]

[connection signal="timeout" from="Timer" to="Player" method="hide"]
"""


func _setup() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var gradient := Gradient.new()
	gradient.set_color(0, Color.RED)
	ResourceSaver.save(gradient, GRADIENT)
	SceneRevert.rng.seed = 59


func _before() -> String:
	_setup()
	return BEFORE.replace("GRADIENT", GRADIENT)


func _change(changes: Array[Dictionary], label: String) -> Dictionary:
	for change: Dictionary in changes:
		if change.label == label:
			return change
	return {}


func test_changes_list() -> void:
	var labels: Array = SceneRevert.changes(_before(), AFTER).map(func(c: Dictionary) -> String: return "%s %s %s" % [c.kind, c.label, c.rejectable])
	assert_eq(labels, [
		"added + Icon true",
		"removed − Player/Sprite true",
		"moved → Player/Score ← Label true",
		"header ~ . · name true",
		"prop ~ Player/Shape · shape.size true",
		"header ~ Timer · groups true",
		"connection + timeout: Timer → Player/Score.hide() true",
		"connection + timeout: Timer → Player.hide() true",
		"connection − timeout: Timer → Label.hide() true",
	])


## Cada cambio, solo: se rechaza, la escena carga con lo que se espera, el cambio ya no está, y
## deshacerlo vuelve a lo del turno (y también carga).
func test_each_round_trip() -> void:
	var before := _before()
	var total := SceneDiff.count(SceneDiff.diff(before, AFTER))
	for change: Dictionary in SceneRevert.changes(before, AFTER):
		var rejected := SceneRevert.apply(AFTER, change)
		if change.label == "− timeout: Timer → Label.hide()":
			assert_eq(rejected.error, "Label is not there", "sola no: Label está en Player/Score")
			continue
		assert_true(rejected.ok, "%s: %s" % [change.label, rejected.error])
		if not rejected.ok:
			continue
		assert_eq(SceneRevert.validate(rejected.text, rejected.expect), "", "%s: la escena carga" % change.label)
		assert_true(SceneDiff.count(SceneDiff.diff(before, rejected.text)) < total, "%s: queda menos para rechazar" % change.label)
		assert_false(rejected.text.contains("\n\n\n"), "%s: sin líneas vacías de más:\n%s" % [change.label, rejected.text])
		assert_false(SceneRevert.apply(rejected.text, change).ok, "%s: ya rechazado no se rechaza de nuevo" % change.label)
		var undone := SceneRevert.apply(rejected.text, change, true)
		assert_true(undone.ok, "deshacer %s: %s" % [change.label, undone.error])
		assert_eq(SceneDiff.count(SceneDiff.diff(AFTER, undone.text)), 0, "deshacer %s vuelve a lo del turno:\n%s" % [change.label, undone.text])
		assert_eq(SceneRevert.validate(undone.text, undone.expect), "", "deshacer %s: carga" % change.label)


func test_reject_all_gives_before() -> void:
	var before := _before()
	var text := AFTER
	for change: Dictionary in SceneRevert.changes(before, AFTER):
		var result := SceneRevert.apply(text, change)
		if result.ok:
			text = result.text
	assert_eq(SceneDiff.count(SceneDiff.diff(before, text)), 0, "todo rechazado = la escena de antes:\n%s" % text)
	assert_eq(_signature(text), _signature(before), "el árbol cargado es el de antes")
	assert_eq(SceneRevert.validate(text), "")
	assert_false(text.contains("\n\n\n"), "sin líneas vacías de más")


func test_removed_node_brings_its_resources_without_clashing() -> void:
	var before := _before()
	var sprite := _change(SceneRevert.changes(before, AFTER), "− Player/Sprite")
	var result := SceneRevert.apply(AFTER, sprite)
	assert_true(result.ok, result.error)
	var text: String = result.text
	# El id GradientTexture1D_t ya es de la textura de Icon: la de Sprite vuelve con otro.
	var all := SceneRevert.sections(text)
	var subs: Array = all.filter(func(s: Dictionary) -> bool: return s.kind == "sub_resource").map(func(s: Dictionary) -> String: return s.attrs.id)
	assert_eq(subs.size(), 3, "las dos texturas y la forma: %s" % [subs])
	assert_true(text.contains("[ext_resource type=\"Gradient\" path=\"%s\" id=\"1_g\"]" % GRADIENT), "el gradiente vuelve con su id (estaba libre)")
	assert_true(text.begins_with("[gd_scene load_steps=5 format=3]"), "load_steps cuenta los dos recursos nuevos")
	var sprite_section: Dictionary = SceneRevert._node_at(all, "Player/Sprite")
	var texture := str(sprite_section.props.texture.value)
	assert_false(texture == "SubResource(\"GradientTexture1D_t\")", "no usa la textura de Icon")
	var new_id := texture.trim_prefix("SubResource(\"").trim_suffix("\")")
	assert_true(new_id.begins_with("GradientTexture1D_") and new_id.length() == "GradientTexture1D_".length() + 5, new_id)
	# La textura nueva va antes del primer nodo y después del ext que usa.
	var ext_line := text.find("[ext_resource")
	var sub_line := text.find("id=\"%s\"" % new_id)
	assert_true(ext_line < sub_line and sub_line < text.find("[node"), "en orden: ext, sub, nodos")
	# En su lugar: el segundo hijo de Player, después de Shape.
	assert_eq(_children(text, "Player"), ["Shape", "Sprite", "Score"], "Sprite vuelve después de Shape")
	assert_eq(SceneRevert.validate(text, result.expect), "")
	var loaded := _load(text)
	var restored := loaded.get_node("Player/Sprite") as Sprite2D
	assert_eq((restored.texture as GradientTexture1D).gradient.get_color(0), Color.RED, "con su gradiente")
	assert_eq((loaded.get_node("Icon") as Sprite2D).texture.get_width(), 64, "Icon sigue con la suya")
	loaded.free()
	# Deshacer: se van la textura y el gradiente que trajo, Icon queda como estaba.
	var undone := SceneRevert.apply(text, sprite, true)
	assert_eq(undone.text, AFTER, "deshacer deja el texto del turno, idéntico")


func test_undo_keeps_resources_used_since() -> void:
	var before := _before()
	var sprite := _change(SceneRevert.changes(before, AFTER), "− Player/Sprite")
	var text: String = SceneRevert.apply(AFTER, sprite).text
	# Después de rechazar, el usuario le pone el mismo gradiente a otra cosa.
	text = text.replace("[node name=\"Game\" type=\"Node2D\" unique_id=1]", "[node name=\"Game\" type=\"Node2D\" unique_id=1]\nmetadata/g = ExtResource(\"1_g\")")
	var undone := SceneRevert.apply(text, sprite, true)
	assert_true(undone.ok)
	assert_true(str(undone.text).contains("[ext_resource type=\"Gradient\""), "el gradiente queda: lo usa otro")
	assert_eq(SceneRevert.sections(undone.text).filter(func(s: Dictionary) -> bool: return s.kind == "sub_resource").size(), 2, "la textura que trajo se va")


func test_ext_id_clash() -> void:
	_setup()
	var before := """[gd_scene format=3]

[ext_resource type="Gradient" path="%s" id="1_g"]

[node name="Main" type="Node2D" unique_id=1]

[node name="A" type="Node" parent="." unique_id=2]
metadata/g = ExtResource("1_g")
""" % GRADIENT
	# En el turno, A se va y 1_g pasa a ser otra cosa.
	var after := """[gd_scene format=3]

[ext_resource type="Script" path="res://tests/unit/test_case.gd" id="1_g"]

[node name="Main" type="Node2D" unique_id=1]
metadata/s = ExtResource("1_g")
"""
	var a := _change(SceneRevert.changes(before, after), "− A")
	var result := SceneRevert.apply(after, a)
	assert_true(result.ok, result.error)
	var exts: Array = SceneRevert.sections(result.text).filter(func(s: Dictionary) -> bool: return s.kind == "ext_resource")
	assert_eq(exts.size(), 2)
	var gradient_id := str(exts[1].attrs.id)
	assert_true(gradient_id != "1_g" and gradient_id.begins_with("2_"), "el gradiente con un id nuevo: %s" % gradient_id)
	assert_true(str(result.text).contains("metadata/g = ExtResource(\"%s\")" % gradient_id), "A lo nombra con el id nuevo")
	assert_true(str(result.text).contains("metadata/s = ExtResource(\"1_g\")"), "lo de la raíz no se toca")
	assert_eq(SceneDiff.count(SceneDiff.diff(before, result.text)) , SceneDiff.count(SceneDiff.diff(before, after)) - 1)
	# Si el recurso ya está (misma ruta), se reusa.
	var same := after.replace("res://tests/unit/test_case.gd", GRADIENT).replace("type=\"Script\"", "type=\"Gradient\"")
	var reused := SceneRevert.apply(same, _change(SceneRevert.changes(before, same), "− A"))
	assert_eq(SceneRevert.sections(reused.text).filter(func(s: Dictionary) -> bool: return s.kind == "ext_resource").size(), 1, "reusa el que ya está")


const SIBLINGS := """[gd_scene format=3]

[node name="Main" type="Node" unique_id=1]

[node name="A" type="Node" parent="." unique_id=2]

[node name="A1" type="Node" parent="A" unique_id=21]

[node name="B" type="Node" parent="." unique_id=3]

[node name="B1" type="Node" parent="B" unique_id=31]

[node name="C" type="Node" parent="." unique_id=4]

[node name="D" type="Node" parent="." unique_id=5]
"""


func test_removed_node_keeps_its_place_among_siblings() -> void:
	# El turno borra A y B; después del turno el usuario agrega E después de C y borra D.
	var after := SIBLINGS.replace("[node name=\"A\" type=\"Node\" parent=\".\" unique_id=2]\n\n[node name=\"A1\" type=\"Node\" parent=\"A\" unique_id=21]\n\n", "") \
		.replace("[node name=\"B\" type=\"Node\" parent=\".\" unique_id=3]\n\n[node name=\"B1\" type=\"Node\" parent=\"B\" unique_id=31]\n\n", "")
	var changes := SceneRevert.changes(SIBLINGS, after)
	var now := after.replace("[node name=\"D\" type=\"Node\" parent=\".\" unique_id=5]\n", "[node name=\"E\" type=\"Node\" parent=\".\" unique_id=6]\n")
	assert_eq(_children(now, "."), ["C", "E"])
	var b := SceneRevert.apply(now, _change(changes, "− B"))
	assert_true(b.ok, b.error)
	assert_eq(_children(b.text, "."), ["B", "C", "E"], "sin A, B va primero (después del padre)")
	assert_eq(_children(b.text, "B"), ["B1"], "con su hijo")
	var a := SceneRevert.apply(b.text, _change(changes, "− A"))
	assert_eq(_children(a.text, "."), ["A", "B", "C", "E"], "A primero")
	assert_eq(SceneRevert.validate(a.text, a.expect), "")
	# Al revés: primero A, después B va después del subárbol de A.
	var a_first := SceneRevert.apply(now, _change(changes, "− A"))
	var b_second := SceneRevert.apply(a_first.text, _change(changes, "− B"))
	assert_eq(_children(b_second.text, "."), ["A", "B", "C", "E"])
	assert_eq(b_second.text, a.text, "el mismo texto en cualquier orden")


func test_removed_node_stale_cases() -> void:
	var after := SIBLINGS.replace("[node name=\"B\" type=\"Node\" parent=\".\" unique_id=3]\n\n[node name=\"B1\" type=\"Node\" parent=\"B\" unique_id=31]\n\n", "")
	var b := _change(SceneRevert.changes(SIBLINGS, after), "− B")
	var clash := after.replace("[node name=\"C\" type=\"Node\" parent=\".\" unique_id=4]", "[node name=\"B\" type=\"Node\" parent=\".\" unique_id=9]")
	assert_eq(SceneRevert.apply(clash, b).error, "there is another node with that name there")
	var back := SceneRevert.apply(after, b)
	assert_eq(SceneRevert.apply(back.text, b).error, "the node is already there")
	# Un nodo borrado debajo de un padre que ya no está.
	var after_b1 := SIBLINGS.replace("[node name=\"B1\" type=\"Node\" parent=\"B\" unique_id=31]\n\n", "")
	var b1 := _change(SceneRevert.changes(SIBLINGS, after_b1), "− B/B1")
	var no_parent := after_b1.replace("[node name=\"B\" type=\"Node\" parent=\".\" unique_id=3]\n\n", "")
	assert_eq(SceneRevert.apply(no_parent, b1).error, "its parent is not there")
	# El padre se renombró después del turno: vuelve debajo de él igual (por unique_id).
	var renamed := after_b1.replace("name=\"B\" type", "name=\"Bee\" type")
	var under := SceneRevert.apply(renamed, b1)
	assert_true(under.ok, under.error)
	assert_eq(_children(under.text, "Bee"), ["B1"], "debajo del padre con su nombre nuevo")


func test_moved_node_goes_back() -> void:
	var before := _before()
	var label := _change(SceneRevert.changes(before, AFTER), "→ Player/Score ← Label")
	var result := SceneRevert.apply(AFTER, label)
	assert_true(result.ok, result.error)
	assert_eq(_children(result.text, "."), ["Player", "Timer", "Label", "Icon"], "Label vuelve después de Timer, con su nombre")
	assert_eq(_children(result.text, "Player"), ["Shape"])
	assert_true(str(result.text).contains("[connection signal=\"timeout\" from=\"Timer\" to=\"Label\" method=\"hide\"]"), "su conexión lo sigue")
	assert_eq(result.expect.present, ["Label"])
	# Si el usuario lo volvió a mover, no se toca.
	var moved_again := AFTER.replace("[node name=\"Score\" type=\"Label\" parent=\"Player\"", "[node name=\"Points\" type=\"Label\" parent=\"Player\"")
	assert_eq(SceneRevert.apply(moved_again, label).error, "changed after the turn")


func test_header_and_connections() -> void:
	var before := _before()
	var changes := SceneRevert.changes(before, AFTER)
	var name := SceneRevert.apply(AFTER, _change(changes, "~ . · name"))
	assert_true(str(name.text).contains("[node name=\"Main\" type=\"Node2D\" unique_id=1]"))
	var groups := SceneRevert.apply(AFTER, _change(changes, "~ Timer · groups"))
	assert_true(str(groups.text).contains("[node name=\"Timer\" type=\"Timer\" parent=\".\" unique_id=5 groups=[\"timers\"]]"), groups.text)
	var loaded := _load(groups.text)
	assert_true(loaded.get_node("Timer").is_in_group("timers"), "el grupo vuelve")
	loaded.free()
	var added := SceneRevert.apply(AFTER, _change(changes, "+ timeout: Timer → Player.hide()"))
	assert_false(str(added.text).contains("to=\"Player\" method"), "la conexión nueva se va")
	var removed := SceneRevert.apply(AFTER, _change(changes, "− timeout: Timer → Label.hide()"))
	assert_false(removed.ok, "Label ya no está ahí: no se puede volver a conectar")
	assert_eq(removed.error, "Label is not there")


func test_type_and_instance() -> void:
	_setup()
	var before := """[gd_scene format=3]

[node name="Main" type="Node2D" unique_id=1]

[node name="Thing" type="Node2D" parent="." unique_id=2]
"""
	var packed := PackedScene.new()
	var piece := Sprite2D.new()
	piece.name = "Piece"
	packed.pack(piece)
	piece.free()
	ResourceSaver.save(packed, DIR + "/piece.tscn")
	var after := """[gd_scene format=3]

[ext_resource type="PackedScene" path="%s" id="1_p"]

[node name="Main" type="Node2D" unique_id=1]

[node name="Thing" parent="." unique_id=2 instance=ExtResource("1_p")]
""" % (DIR + "/piece.tscn")
	var change := _change(SceneRevert.changes(before, after), "~ Thing · type")
	assert_false(change.is_empty())
	var result := SceneRevert.apply(after, change)
	assert_true(result.ok, result.error)
	assert_eq(result.text, before, "vuelve a ser un Node2D y la escena instanciada se va")
	var undone := SceneRevert.apply(result.text, change, true)
	assert_eq(undone.text, after, "deshacer la vuelve a instanciar")
	var loaded := _load(undone.text)
	assert_true(loaded.get_node("Thing") is Sprite2D)
	loaded.free()


func test_property_inside_a_shared_sub_resource() -> void:
	var before := _before().replace("[node name=\"Timer\"", "[node name=\"Other\" type=\"CollisionShape2D\" parent=\".\" unique_id=8]\nshape = SubResource(\"RectangleShape2D_a\")\n\n[node name=\"Timer\"")
	var after := AFTER.replace("[node name=\"Timer\"", "[node name=\"Other\" type=\"CollisionShape2D\" parent=\".\" unique_id=8]\nshape = SubResource(\"RectangleShape2D_a\")\n\n[node name=\"Timer\"")
	var size := _change(SceneRevert.changes(before, after), "~ Player/Shape · shape.size")
	assert_false(size.rejectable, "la forma la usan dos nodos: solo con «Volver atrás»")


# --- las escenas del repo ------------------------------------------------------------------------

## Con cada escena del repo: borrar un nodo al azar (semilla fija) como lo haría el turno, y
## rechazarlo: vuelve igual (texto comparable) y, si la escena carga acá, con el mismo árbol.
func test_repo_scenes_remove_and_restore() -> void:
	var output: Array = []
	if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "ls-files", "*.tscn"], output) != 0:
		return
	var paths: PackedStringArray = str(output[0]).strip_edges().split("\n", false)
	assert_true(paths.size() >= 41, "las escenas del repo: %d" % paths.size())
	var pick := RandomNumberGenerator.new()
	pick.seed = 5959
	SceneRevert.rng.seed = 59
	var loaded := 0
	for path: String in paths:
		var text := FileAccess.get_file_as_string("res://" + path)
		var nodes: Array = SceneRevert.sections(text).filter(func(s: Dictionary) -> bool: return s.kind == "node" and s.path != ".")
		if nodes.is_empty():
			continue
		var node: Dictionary = nodes[pick.randi_range(0, nodes.size() - 1)]
		var uid := str(node.attrs.get("unique_id", ""))
		var after: String = SceneRevert._remove(text, {"uid": uid}, node.path).text
		var change := {}
		for candidate: Dictionary in SceneRevert.changes(text, after):
			if candidate.kind == SceneRevert.REMOVED and candidate.path == node.path:
				change = candidate
		if change.is_empty():
			_fail("%s: no ve %s borrado" % [path, node.path])
			continue
		var result := SceneRevert.apply(after, change)
		if not result.ok:
			_fail("%s: %s no vuelve: %s" % [path, node.path, result.error])
			continue
		var left := SceneDiff.diff(text, result.text)
		assert_eq(SceneDiff.count(left), 0, "%s: %s vuelve igual: %s" % [path, node.path, left])
		if _loads_here(path, text):
			loaded += 1
			assert_eq(SceneRevert.validate(result.text, result.expect), "", "%s carga" % path)
			assert_eq(_signature(result.text), _signature(text), "%s: el mismo árbol con %s de vuelta" % [path, node.path])
		var undone := SceneRevert.apply(result.text, change, true)
		assert_true(undone.ok and SceneDiff.count(SceneDiff.diff(after, undone.text)) == 0, "%s: deshacer lo vuelve a borrar" % path)
	assert_true(loaded >= 8, "varias se cargaron de verdad: %d" % loaded)


## Si es de este proyecto (no de una carpeta con .gdignore o su propio project.godot, como
## completion_eval o map_fixture: sus scripts no compilan acá), sus dependencias existen y carga.
func _loads_here(path: String, text: String) -> bool:
	var dir := path.get_base_dir()
	while not dir.is_empty() and dir != ".":
		if FileAccess.file_exists("res://%s/.gdignore" % dir) or FileAccess.file_exists("res://%s/project.godot" % dir):
			return false
		dir = dir.get_base_dir()
	for section: Dictionary in SceneRevert.sections(text):
		if section.kind == "ext_resource" and not ResourceLoader.exists(str(section.attrs.get("path", ""))):
			return false
	return SceneRevert.validate(text) == ""


# --- ayudas --------------------------------------------------------------------------------------

## Los nombres de los hijos de un nodo, en orden, como quedan en el texto.
func _children(text: String, parent: String) -> Array:
	var names: Array = []
	for section: Dictionary in SceneRevert.sections(text):
		if section.kind == "node" and str(section.attrs.get("parent", "")) == parent:
			names.append(str(section.attrs.name))
	return names


func _load(text: String) -> Node:
	_setup()
	var file := FileAccess.open(SIGNATURE_PATH, FileAccess.WRITE)
	var lines := text.split("\n")
	lines[0] = SceneRevert._set_attr(lines[0], "uid", null)
	file.store_string("\n".join(lines))
	file.close()
	var packed := ResourceLoader.load(SIGNATURE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return packed.instantiate() if packed else null


## El árbol cargado: cada nodo en orden con su clase y sus propiedades guardadas, y las conexiones.
func _signature(text: String) -> Array:
	var root := _load(text)
	if root == null:
		return ["no carga"]
	var out: Array = []
	_walk(root, root, out)
	var packed := ResourceLoader.load(SIGNATURE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var state := packed.get_state()
	var connections: Array = []
	for i in state.get_connection_count():
		connections.append("%s %s %s %s" % [state.get_connection_source(i), state.get_connection_signal(i), state.get_connection_target(i), state.get_connection_method(i)])
	connections.sort()
	out.append(connections)
	root.free()
	return out


func _walk(node: Node, root: Node, out: Array) -> void:
	var props: PackedStringArray = []
	for property: Dictionary in node.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			props.append("%s=%s" % [property.name, _show(node.get(property.name), 0)])
	out.append("%s %s %s" % [root.get_path_to(node), node.get_class(), ",".join(props)])
	for child in node.get_children():
		_walk(child, root, out)


func _show(value: Variant, depth: int) -> String:
	if value is Resource:
		var resource := value as Resource
		if not resource.resource_path.is_empty() and not resource.resource_path.contains("::"):
			return "<%s>" % resource.resource_path
		if depth > 2:
			return resource.get_class()
		var parts: PackedStringArray = [resource.get_class()]
		for property: Dictionary in resource.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name != "resource_path" and property.name != "resource_local_to_scene":
				parts.append("%s=%s" % [property.name, _show(resource.get(property.name), depth + 1)])
		return "{%s}" % ",".join(parts)
	if value is Object:
		return (value as Object).get_class() if value else "null"
	return var_to_str(value)


## La red de seguridad: lo que no carga, o carga sin el nodo donde se esperaba, no pasa.
func test_validate() -> void:
	var before := _before()
	assert_eq(SceneRevert.validate(before, {"present": ["Player/Sprite"], "absent": ["Ghost"]}), "")
	assert_eq(SceneRevert.validate(before, {"present": ["Player/Ghost"]}), "Player/Ghost is not in the scene tree")
	assert_eq(SceneRevert.validate(before, {"absent": ["Timer"]}), "Timer is still in the scene tree")
	var broken := before.replace("[node name=\"Shape\" type=\"CollisionShape2D\" parent=\"Player\"", "[node name=\"Shape\" type=\"CollisionShape2D\" parent=\"Nowhere\"")
	assert_eq(SceneRevert.validate(broken, {"present": ["Player/Shape"]}), "Player/Shape is not in the scene tree", "un padre que no está: el nodo no queda")
	assert_eq(SceneRevert.validate(before.replace("SubResource(\"RectangleShape2D_a\")", "SubResource(\"Missing\")")), "the scene does not load")
	assert_false(FileAccess.file_exists(SceneRevert.CHECK_PATH), "no deja la copia")
