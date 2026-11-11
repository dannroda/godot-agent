extends "test_case.gd"
## Contadores del panel de revisión (m12-43): singular y plural, en inglés y en español.

const ReviewPanel := preload("res://addons/godot_agent/ui/dock/review_panel.gd")
const ReviewStore := preload("res://addons/godot_agent/review/review_store.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")


func test_counter_labels_have_a_plural() -> void:
	I18n.set_locale("en")
	assert_eq(ReviewPanel.counter_label("bug", 1), "1 bug", "singular")
	assert_eq(ReviewPanel.counter_label("bug", 2), "2 bugs", "plural")
	assert_eq(ReviewPanel.counter_label("bug", 0), "0 bugs", "cero en plural")
	assert_eq(ReviewPanel.counter_label("perf", 3), "3 performance", "la categoría con el nombre entero")
	I18n.set_locale("es")
	assert_eq(ReviewPanel.counter_label("bug", 1), "1 bug", "singular en español")
	assert_eq(ReviewPanel.counter_label("bug", 2), "2 bugs", "plural en español")
	assert_eq(ReviewPanel.counter_label("perf", 0), "0 de rendimiento", "sin abreviar («rend»)")
	assert_eq(ReviewPanel.counter_label("order", 1), "1 de orden", "orden")
	assert_eq(ReviewPanel.counter_label("style", 4), "4 de estilo", "estilo")
	I18n.set_locale("en")
	for severity: String in ReviewPanel.COUNTER_ONE:
		assert_true(ReviewPanel.COUNTER_MANY.has(severity), "%s tiene plural" % severity)


## «Medir regresiones» (m11-41): el botón va con las regresiones y pide la medición al apretarlo.
func test_measure_button_requests_a_measurement() -> void:
	var panel: Control = ReviewPanel.new()
	panel.setup(ReviewStore.new(), Color.WHITE)
	panel._ready()
	var button := panel.find_child("MeasureRegressionsButton", true, false) as Button
	assert_true(button != null, "el panel tiene el botón")
	if button == null:
		panel.free()
		return
	assert_false(button.tooltip_text.is_empty(), "el botón explica qué hace")
	var asked := [0]
	var on_measure := func() -> void: asked[0] += 1
	panel.measure_requested.connect(on_measure)
	button.pressed.emit()
	assert_eq(asked[0], 1, "apretarlo pide medir")
	panel.measure_requested.disconnect(on_measure)
	panel.free()
