extends "test_case.gd"
## Markdown → BBCode (spec §13).

const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")


func _md() -> MarkdownBBCode:
	var md := MarkdownBBCode.new()
	md.code_color = "#c0ffee"
	md.muted_color = "#999999"
	md.code_bg_color = "#000000"
	return md


func test_inline_formats() -> void:
	var md := _md()
	assert_eq(md.convert("**negrita** y *itálica*"), "[b]negrita[/b] y [i]itálica[/i]", "énfasis")
	assert_eq(md.convert("__b__ _i_ ~~t~~"), "[b]b[/b] [i]i[/i] [s]t[/s]", "variantes")
	assert_eq(md.convert("usá `foo()` ya"), "usá [code][color=#c0ffee]foo()[/color][/code] ya", "code span")
	assert_eq(md.convert("`**no**`"), "[code][color=#c0ffee]**no**[/color][/code]", "sin énfasis dentro de code")
	assert_eq(md.convert("[docs](https://x.y/z)"), "[url=https://x.y/z]docs[/url]", "link")
	assert_eq(md.convert("<https://a.b>"), "[url=https://a.b]https://a.b[/url]", "autolink")


func test_escapes_brackets() -> void:
	var md := _md()
	assert_eq(md.convert("array[0] y [b]"), "array[lb]0[rb] y [lb]b[rb]", "corchetes escapados")
	assert_eq(md.convert("`a[1]`"), "[code][color=#c0ffee]a[lb]1[rb][/color][/code]", "corchetes en code")
	assert_eq(md.convert("snake_case_name y 2*3*4"), "snake_case_name y 2*3*4", "sin falsos énfasis")


func test_blocks() -> void:
	var md := _md()
	assert_eq(md.convert("uno\ndos\n\ntres"), "uno dos\ntres", "párrafos")
	assert_eq(md.convert("```gdscript\nvar a := [1]\n```"), "[bgcolor=#000000][code]var a := [lb]1[rb][/code][/bgcolor]", "bloque de código")
	assert_eq(md.convert("```\nsin cerrar"), "[bgcolor=#000000][code]sin cerrar[/code][/bgcolor]", "bloque sin cerrar")
	assert_eq(md.convert("- a\n- **b**"), "  • a\n  • [b]b[/b]", "lista")
	assert_eq(md.convert("1. a\n2) b"), "  1. a\n  2. b", "lista ordenada")
	assert_eq(md.convert("- [x] hecho\n- [ ] no"), "  ☑ hecho\n  ☐ no", "tareas")
	assert_eq(md.convert("> cita"), "[color=#999999]▎ [i]cita[/i][/color]", "cita")
	assert_eq(md.convert("### Título"), "[b]Título[/b]", "título chico")
	assert_true(md.convert("# Grande").begins_with("[font_size="), "título grande")
	assert_eq(md.convert("| a | b |\n|---|---|\n| 1 | 2 |"), "[code]| a | b |[/code]\n[code]| 1 | 2 |[/code]", "tabla")
