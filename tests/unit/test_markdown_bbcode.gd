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


func test_edge_inline() -> void:
	var md := _md()
	assert_eq(md.convert("***fuerte***"), "[b][i]fuerte[/i][/b]", "negrita e itálica")
	assert_eq(md.convert("**a *b* c**"), "[b]a [i]b[/i] c[/b]", "itálica dentro de negrita")
	assert_eq(md.convert("\\*no\\* y \\_no\\_"), "*no* y _no_", "escapes con barra")
	assert_eq(md.convert("\\[x\\](y)"), "[lb]x[rb](y)", "corchetes escapados no son link")
	assert_eq(md.convert("``a ` b``"), "[code][color=#c0ffee]a ` b[/color][/code]", "code span con backtick adentro")
	assert_eq(md.convert("`` `x` ``"), "[code][color=#c0ffee]`x`[/color][/code]", "espacios de relleno")
	assert_eq(md.convert("`a` y `b`"), "[code][color=#c0ffee]a[/color][/code] y [code][color=#c0ffee]b[/color][/code]", "dos code spans")
	assert_eq(md.convert("`[x](y)`"), "[code][color=#c0ffee][lb]x[rb](y)[/color][/code]", "link dentro de code no se convierte")
	assert_eq(md.convert("[`run_scene`](https://d.io/a)"), "[url=https://d.io/a][code][color=#c0ffee]run_scene[/color][/code][/url]", "code dentro de link")
	assert_eq(md.convert("[wiki](https://w.org/A_(b))"), "[url=https://w.org/A_(b)]wiki[/url]", "paréntesis en la URL")
	assert_eq(md.convert("[**x**](u)"), "[url=u][b]x[/b][/url]", "énfasis en el texto del link")
	assert_eq(md.convert("ver https://x.com/a_b_c"), "ver https://x.com/a_b_c", "guiones bajos en URL sueltas")
	assert_eq(md.convert("**sin cerrar"), "**sin cerrar", "énfasis sin cerrar queda literal")
	assert_eq(md.convert("`sin cerrar"), "`sin cerrar", "code sin cerrar queda literal")
	assert_eq(md.convert("a [url]b[/url]"), "a [lb]url[rb]b[lb]/url[rb]", "BBCode del agente escapado")
	assert_eq(md.convert("`\\n` literal"), "[code][color=#c0ffee]\\n[/color][/code] literal", "barra dentro de code")


func test_edge_blocks() -> void:
	var md := _md()
	assert_eq(md.convert("- a\n  - b\n    - c"), "  • a\n      ◦ b\n          ◦ c", "listas anidadas")
	assert_eq(md.convert("1. uno\n   sigue acá\n2. dos"), "  1. uno sigue acá\n  2. dos", "continuación de un ítem")
	assert_eq(md.convert("- a\n\ntexto"), "  • a\ntexto", "párrafo después de una lista")
	assert_eq(md.convert("~~~\nx < y\n~~~"), "[bgcolor=#000000][code]x < y[/code][/bgcolor]", "fence con ~~~")
	assert_eq(md.convert("````\n```\nadentro\n```\n````"), "[bgcolor=#000000][code]```\nadentro\n```[/code][/bgcolor]", "fence más largo contiene uno corto")
	assert_eq(md.convert("- item\n  ```\n  code\n  ```"), "  • item\n[bgcolor=#000000][code]  code[/code][/bgcolor]", "bloque dentro de una lista")
	assert_eq(md.convert("uno  \ndos"), "uno\ndos", "salto forzado con dos espacios")
	assert_eq(md.convert("uno\\\ndos"), "uno\ndos", "salto forzado con barra")
	assert_eq(md.convert("> > doble"), "[color=#999999]▎▎ [i]doble[/i][/color]", "cita anidada")
	assert_eq(md.convert("> - en cita"), "[color=#999999]▎ [i]  • en cita[/i][/color]", "lista dentro de cita")
	assert_eq(md.convert("#sin espacio"), "#sin espacio", "no es título")
	assert_eq(md.convert("## `api()` nueva"), "[font_size=%d][b][code][color=#c0ffee]api()[/color][/code] nueva[/b][/font_size]" % md._scaled_size(115), "code en título")
	assert_eq(md.convert("***"), "[color=#999999]────────[/color]", "regla con asteriscos")


## Ninguna entrada deja tags de formato abiertos.
func test_balanced_tags() -> void:
	var md := _md()
	var samples: PackedStringArray = [
		"**a *b** c*", "***x** y*", "_a **b_ c**", "[a](b) **[c](d)**", "~~a **b~~ c**", "`a` **`b`** *c*",
		"- **a\n- b**", "> **a\n> b**", "```\n**a\n```\n**b**",
	]
	var tag := RegEx.create_from_string("\\[(/?)(b|i|s|code|url|color|bgcolor|font_size)(=[^\\]]*)?\\]")
	for sample: String in samples:
		var stack: Array[String] = []
		var ok := true
		for found: RegExMatch in tag.search_all(md.convert(sample)):
			if found.get_string(1).is_empty():
				stack.append(found.get_string(2))
			elif stack.is_empty() or stack.pop_back() != found.get_string(2):
				ok = false
		assert_true(ok and stack.is_empty(), "tags balanceados: %s → %s" % [sample.c_escape(), md.convert(sample)])
