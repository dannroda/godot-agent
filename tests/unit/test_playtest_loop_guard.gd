extends "res://tests/unit/test_case.gd"
## m11-49: el detector de loops del playtest.

const Guard := preload("res://addons/godot_agent/mcp/tools/playtest_loop_guard.gd")
const ReviewStore := preload("res://addons/godot_agent/review/review_store.gd")


static func _text(value: String) -> Dictionary:
	return {"content": [{"type": "text", "text": value}], "isError": false}


## Un resultado del probe como llega: sobre con nonce nuevo, reloj del juego y tiempo restante.
static func _probe(value: String, nonce: String, time: float) -> Dictionary:
	return _text("<untrusted nonce=\"%s\">%s [game time %.2f s, physics frame %d]</untrusted nonce=\"%s\">\nPlaytest time left: %.1f min." % [nonce, value, time, int(time * 60), nonce, 9.0 - time])


func test_same_call_same_result() -> void:
	var guard := Guard.new()
	var args := {"steps": [{"key": "Space"}]}
	assert_eq(int(guard.observe("game_input", args, _probe("Inputs: 1 of 1 played.", "a1", 1.0)).repeats), 1, "la primera")
	assert_eq(int(guard.observe("game_input", args, _probe("Inputs: 1 of 1 played.", "b2", 1.3)).repeats), 2, "nonce, reloj y tiempo restante no cuentan como progreso")
	var third := guard.observe("game_input", args, _probe("Inputs: 1 of 1 played.", "c3", 1.6))
	assert_eq(int(third.repeats), Guard.WARN_REPEATS, "a la tercera, aviso")
	assert_false(third.cut, "todavía no corta")
	var fourth := guard.observe("game_input", args, _probe("Inputs: 1 of 1 played.", "d4", 1.9))
	assert_true(fourth.cut, "a la cuarta, corta")
	assert_eq(fourth.tools, "game_input", "lo que repetía")
	assert_true((fourth.evidence as PackedStringArray)[0].contains("Space") and (fourth.evidence as PackedStringArray)[0].contains("×4"), "la evidencia lleva la llamada: %s" % [fourth.evidence])
	assert_eq((fourth.evidence as PackedStringArray)[1], "  → Inputs: 1 of 1 played.", "y lo que devolvía, sin sobre ni reloj")


func test_progress_resets() -> void:
	var guard := Guard.new()
	var args := {"path": "Player", "property": "position"}
	for i in 3:
		guard.observe("game_get", args, _text("(0, 0)"))
	assert_eq(int(guard.observe("game_get", args, _text("(4, 0)")).repeats), 1, "el juego cambió: no es un loop")
	assert_eq(int(guard.observe("game_get", {"path": "Enemy"}, _text("(4, 0)")).repeats), 1, "otra llamada tampoco")


func test_cycle_of_two() -> void:
	var guard := Guard.new()
	var image := {"content": [{"type": "text", "text": "Game frame (64x64)"}, {"type": "image", "data": "QUJD", "mimeType": "image/png"}], "isError": false}
	var seen: Dictionary = {}
	for i in 4:
		guard.observe("game_input", {"steps": [{"click": [10, 10]}]}, _text("Inputs: 1 of 1 played."))
		seen = guard.observe("capture_game_frame", {}, image)
	assert_true(seen.cut, "clic y la misma captura, cuatro vueltas: corta")
	assert_eq(seen.tools, "game_input → capture_game_frame", "el ciclo entero")
	var other := Guard.new()
	for i in 4:
		other.observe("game_input", {"steps": [{"click": [10, 10]}]}, _text("Inputs: 1 of 1 played."))
		var changed := image.duplicate(true)
		changed.content[1].data = "frame%d" % i
		seen = other.observe("capture_game_frame", {}, changed)
	assert_false(seen.cut, "si la captura cambia, hay progreso")


func test_same_error() -> void:
	var guard := Guard.new()
	var seen: Dictionary = {}
	for i in 4:
		seen = guard.observe("game_call", {"path": "Menu", "method": "open"}, {"content": [{"type": "text", "text": "Method not found"}], "isError": true})
	assert_true(seen.cut, "el mismo error cuatro veces")
	var guard2 := Guard.new()
	guard2.observe("game_call", {"path": "Menu", "method": "open"}, {"content": [{"type": "text", "text": "Method not found"}], "isError": true})
	assert_eq(int(guard2.observe("game_call", {"path": "Menu", "method": "open"}, _text("Method not found")).repeats), 1, "error y éxito con el mismo texto no son lo mismo")


func test_reset() -> void:
	var guard := Guard.new()
	for i in 3:
		guard.observe("game_tree", {}, _text("Main"))
	guard.reset()
	assert_eq(int(guard.observe("game_tree", {}, _text("Main")).repeats), 1, "un playtest nuevo empieza de cero")


func test_loop_verdict() -> void:
	var guard := Guard.new()
	var seen: Dictionary = {}
	for i in 4:
		seen = guard.observe("game_input", {"steps": [{"key": "Space"}]}, _text("ok"))
	var playtest := ReviewStore.loop_playtest(seen)
	assert_eq(playtest.verdict, "blocked", "could not test")
	assert_eq(playtest.summary, "stopped: the agent kept repeating game_input with no progress", "dice qué repetía")
	var notice := ReviewStore.playtest_notice(ReviewStore.audited_playtest(playtest, {"played": true, "captured": false, "no_video": "", "changes": PackedStringArray(), "video": "", "detectors": []}))
	assert_true(str(notice.title).begins_with("Playtest: could not test · stopped"), "el título")
	assert_true(str(notice.text).contains("4 times in a row"), "el aviso dice por qué")
	assert_true(str(notice.sections[0].text).contains("Space"), "la evidencia va en su sección")
