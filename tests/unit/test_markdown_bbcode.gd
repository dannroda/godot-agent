extends "test_case.gd"
## Markdown → BBCode (spec §13).

const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")


func _md() -> MarkdownBBCode:
	var md := MarkdownBBCode.new()
	md.code_color = "#c0ffee"
	md.muted_color = "#999999"
	md.code_bg_color = "#000000"
	md.table_border_color = "#111111"
	md.table_header_bg = "#222222"
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
	var gap := "[font_size=%d] [/font_size]" % md._scaled_size(md._GAP_SIZE)
	assert_eq(md.convert("uno\ndos\n\ntres"), "uno dos\n%s\ntres" % gap, "párrafos, con un respiro entre los dos")
	assert_eq(md.convert("uno\n# Título\ndos"), "uno\n[font_size=%d][b]Título[/b][/font_size]\ndos" % md._scaled_size(140), "título sin líneas en blanco: sin respiro")
	assert_eq(md.convert("```gdscript\nvar a := [1]\n```"), "[table=1][cell bg=#000000 padding=8,6,8,6][code][color=#ff7085]var[/color] a := [lb][color=#a1ffe0]1[/color][rb][/code][/cell][/table]", "bloque de código con resaltado")
	assert_eq(md.convert("```\nsin cerrar"), "[table=1][cell bg=#000000 padding=8,6,8,6][code]sin cerrar[/code][/cell][/table]", "bloque sin cerrar")
	assert_eq(md.convert("- a\n- **b**"), "[ul bullet=•]a[/ul]\n[ul bullet=•][b]b[/b][/ul]", "lista")
	assert_eq(md.convert("1. a\n2) b"), "[ul bullet=1.]a[/ul]\n[ul bullet=2.]b[/ul]", "lista ordenada")
	assert_eq(md.convert("3. a\n7. b"), "[ul bullet=3.]a[/ul]\n[ul bullet=7.]b[/ul]", "los números son los del texto")
	assert_eq(md.convert("- [x] hecho\n- [ ] no"), "[ul bullet=▣]hecho[/ul]\n[ul bullet=□]no[/ul]", "tareas")
	assert_eq(md.convert("> cita"), "[color=#999999]▎ [i]cita[/i][/color]", "cita")
	assert_eq(md.convert("### Título"), "[font_size=%d][b]Título[/b][/font_size]" % md._scaled_size(108), "h3")
	assert_eq(md.convert("#### Título"), "[b]Título[/b]", "h4")
	assert_eq(md.convert("## Título ##"), "[font_size=%d][b]Título[/b][/font_size]" % md._scaled_size(122), "h2 con # de cierre")
	assert_eq(md.convert("---"), "[hr color=#999999 height=1 width=100%]", "regla")


func test_tables() -> void:
	var md := _md()
	var head := "[cell bg=#222222 border=#111111 padding=6,3,6,3]"
	var cell := "[cell border=#111111 padding=6,3,6,3]"
	assert_eq(md.convert("| a | b |\n|---|---|\n| 1 | 2 |"),
		"[table=2]%s[b]a[/b][/cell]%s[b]b[/b][/cell]%s1[/cell]%s2[/cell][/table]" % [head, head, cell, cell], "tabla")
	assert_eq(md.convert("a | b\n:-: | --:\n1 | 2"),
		"[table=2]%s[center][b]a[/b][/center][/cell]%s[right][b]b[/b][/right][/cell]%s[center]1[/center][/cell]%s[right]2[/right][/cell][/table]" % [head, head, cell, cell],
		"sin | en los bordes y con alineación")
	assert_eq(md.convert("| x |\n|---|\n| `a|b` \\| c |"),
		"[table=1]%s[b]x[/b][/cell]%s[code][color=#c0ffee]a|b[/color][/code] | c[/cell][/table]" % [head, cell], "| dentro de code y escapado")
	assert_eq(md.convert("| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |"),
		"[table=2]%s[b]a[/b][/cell]%s[b]b[/b][/cell]%s1[/cell]%s[/cell]%s1[/cell]%s2[/cell][/table]" % [head, head, cell, cell, cell, cell],
		"filas cortas se completan, las largas se cortan")
	assert_eq(md.convert("| a | b |\nsin separador"), "| a | b | sin separador", "sin separador no es tabla")
	assert_eq(md.convert("| a |\n|---|\n| 1 |\n\ndespués").get_slice("\n", 2), "después", "la tabla termina en la línea en blanco")


func test_lists() -> void:
	var md := _md()
	assert_eq(md.convert("- a\n  - b\n    - c\n- d"), "[ul bullet=•]a\n[ul bullet=◦]b\n[ul bullet=◦]c[/ul][/ul][/ul]\n[ul bullet=•]d[/ul]", "anidadas")
	assert_eq(md.convert("1. a\n    - b\n2. c"), "[ul bullet=1.]a\n[ul bullet=◦]b[/ul][/ul]\n[ul bullet=2.]c[/ul]", "anidada con 4 espacios")
	assert_eq(md.convert("1. a\n\n2. b\n\n   más de b\n3. c"), "[ul bullet=1.]a[/ul]\n[ul bullet=2.]b[br]más de b[/ul]\n[ul bullet=3.]c[/ul]", "lista suelta: sigue abierta y el párrafo va en el ítem")
	assert_eq(md.convert("lista:\n- a\nperezosa"), "lista:\n[ul bullet=•]a perezosa[/ul]", "continuación sin sangría")
	assert_eq(md.blocks("1. paso\n```sh\nls\n```\n2. otro"), [
		{"bbcode": "[ul bullet=1.]paso[/ul]"}, {"code": "ls", "language": "sh"}, {"bbcode": "[ul bullet=2.]otro[/ul]"},
	], "un bloque de código no reinicia la numeración")
	assert_eq(md.convert("- a\n# T"), "[ul bullet=•]a[/ul]\n[b]T[/b]".replace("[b]T[/b]", "[font_size=%d][b]T[/b][/font_size]" % md._scaled_size(140)), "un título cierra la lista")
	assert_eq(md.convert("- a\n---"), "[ul bullet=•]a[/ul]\n[hr color=#999999 height=1 width=100%]", "una regla cierra la lista")
	assert_eq(md.convert("* * *"), "[hr color=#999999 height=1 width=100%]", "regla con espacios no es lista")


func test_blocks_split() -> void:
	var md := _md()
	assert_eq(md.blocks("a\n```py\nx = 1\n```\nb"), [{"bbcode": "a"}, {"code": "x = 1", "language": "py"}, {"bbcode": "b"}], "texto, código, texto")
	assert_eq(md.blocks("```\nsolo\n```"), [{"code": "solo", "language": ""}], "solo código")
	assert_eq(md.blocks("- item\n  ```gd\n  if x:\n      y\n  ```"), [{"bbcode": "[ul bullet=•]item[/ul]"}, {"code": "if x:\n    y", "language": "gd"}], "la sangría del fence se saca")
	assert_eq(md.blocks(""), [], "vacío")


func test_highlight() -> void:
	var md := _md()
	var colors := md.highlighter.colors
	assert_eq(md.highlighter.highlight("@export var n: Node2D = $A/B # [x]", "gdscript"),
		"[color=%s]@export[/color] [color=%s]var[/color] n: [color=%s]Node2D[/color] = [color=%s]$A/B[/color] [color=%s]# [lb]x[rb][/color]" % [colors.annotation, colors.keyword, colors.engine_type, colors.node_path, colors.comment], "gdscript")
	assert_eq(md.highlighter.highlight("if a: return foo(\"#no\")", "gd"),
		"[color=%s]if[/color] a: [color=%s]return[/color] [color=%s]foo[/color]([color=%s]\"#no\"[/color])" % [colors.control_flow, colors.control_flow, colors.function, colors.string], "# dentro de un string no es comentario")
	assert_eq(md.highlighter.highlight("uniform vec4 c; // x", "gdshader"),
		"[color=%s]uniform[/color] [color=%s]vec4[/color] c; [color=%s]// x[/color]" % [colors.keyword, colors.base_type, colors.comment], "shader")
	assert_eq(md.highlighter.highlight("a[1] # b", "texto"), "a[lb]1[rb] # b", "lenguaje desconocido: solo escapado")
	assert_eq(md.highlighter.highlight("var x2 = 0x1F", "gdscript"), "[color=%s]var[/color] x2 = [color=%s]0x1F[/color]" % [colors.keyword, colors.number], "número pegado a un identificador no")


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
	assert_eq(md.convert("ver https://x.com/a_b_c"), "ver [url=https://x.com/a_b_c]https://x.com/a_b_c[/url]", "URL suelta, con sus guiones bajos")
	assert_eq(md.convert("(ver https://a.b/c.)"), "(ver [url=https://a.b/c]https://a.b/c[/url].)", "URL suelta sin la puntuación final")
	assert_eq(md.convert("https://w.org/A_(b), y"), "[url=https://w.org/A_(b)]https://w.org/A_(b)[/url], y", "URL suelta con paréntesis")
	assert_eq(md.convert("![captura](res://a/shot.png)"), "[url=res://a/shot.png]🖼 captura[/url]", "imagen")
	assert_eq(md.convert("![](res://a/shot.png)"), "[url=res://a/shot.png]🖼 shot.png[/url]", "imagen sin texto")
	assert_eq(md.convert("[x](u \"título\")"), "[url=u]x[/url]", "link con título")
	assert_eq(md.convert("**sin cerrar"), "**sin cerrar", "énfasis sin cerrar queda literal")
	assert_eq(md.convert("`sin cerrar"), "`sin cerrar", "code sin cerrar queda literal")
	assert_eq(md.convert("a [url]b[/url]"), "a [lb]url[rb]b[lb]/url[rb]", "BBCode del agente escapado")
	assert_eq(md.convert("`\\n` literal"), "[code][color=#c0ffee]\\n[/color][/code] literal", "barra dentro de code")


func test_edge_blocks() -> void:
	var md := _md()
	assert_eq(md.convert("1. uno\n   sigue acá\n2. dos"), "[ul bullet=1.]uno sigue acá[/ul]\n[ul bullet=2.]dos[/ul]", "continuación de un ítem")
	assert_eq(md.convert("~~~\nx < y\n~~~"), "[table=1][cell bg=#000000 padding=8,6,8,6][code]x < y[/code][/cell][/table]", "fence con ~~~")
	assert_eq(md.blocks("````\n```\nadentro\n```\n````"), [{"code": "```\nadentro\n```", "language": ""}], "fence más largo contiene uno corto")
	assert_eq(md.convert("uno  \ndos"), "uno\ndos", "salto forzado con dos espacios")
	assert_eq(md.convert("uno\\\ndos"), "uno\ndos", "salto forzado con barra")
	assert_eq(md.convert("> > doble"), "[color=#999999]▎▎ [i]doble[/i][/color]", "cita anidada")
	assert_eq(md.convert("> - en cita"), "[color=#999999]▎ [i]• en cita[/i][/color]", "lista dentro de cita")
	assert_eq(md.convert("#sin espacio"), "#sin espacio", "no es título")
	assert_eq(md.convert("## `api()` nueva"), "[font_size=%d][b][code][color=#c0ffee]api()[/color][/code] nueva[/b][/font_size]" % md._scaled_size(122), "code en título")
	assert_eq(md.convert("***"), "[hr color=#999999 height=1 width=100%]", "regla con asteriscos")


## Ninguna entrada deja tags de formato abiertos.
func test_balanced_tags() -> void:
	var md := _md()
	var samples: PackedStringArray = [
		"**a *b** c*", "***x** y*", "_a **b_ c**", "[a](b) **[c](d)**", "~~a **b~~ c**", "`a` **`b`** *c*",
		"- **a\n- b**", "> **a\n> b**", "```\n**a\n```\n**b**",
		"- a\n  - b\n    - c\nd", "1. a\n\n   b\n2. c\n```\nx\n```", "| *a | b* |\n|---|:-:|\n| **1 | 2** |", "- [x] **a\n- b",
	]
	var tag := RegEx.create_from_string("\\[(/?)(b|i|s|code|url|color|bgcolor|font_size|ul|table|cell|center|right)([ =][^\\]]*)?\\]")
	for sample: String in samples:
		var stack: Array[String] = []
		var ok := true
		for found: RegExMatch in tag.search_all(md.convert(sample)):
			if found.get_string(1).is_empty():
				stack.append(found.get_string(2))
			elif stack.is_empty() or stack.pop_back() != found.get_string(2):
				ok = false
		assert_true(ok and stack.is_empty(), "tags balanceados: %s → %s" % [sample.c_escape(), md.convert(sample)])


func test_link_target() -> void:
	assert_eq(MarkdownBBCode.link_target("res://a/b.gd"), {"path": "res://a/b.gd", "line": 0}, "sin línea")
	assert_eq(MarkdownBBCode.link_target("player/player.gd#L42"), {"path": "player/player.gd", "line": 42}, "#L")
	assert_eq(MarkdownBBCode.link_target("a.gd#L10-L20"), {"path": "a.gd", "line": 10}, "#L con rango")
	assert_eq(MarkdownBBCode.link_target("res://a.gd:7"), {"path": "res://a.gd", "line": 7}, ":línea")
	assert_eq(MarkdownBBCode.link_target("a.gd:7:3"), {"path": "a.gd", "line": 7}, ":línea:columna")
	assert_eq(MarkdownBBCode.link_target("file:///home/x/a%20b.gd"), {"path": "/home/x/a b.gd", "line": 0}, "file:// y %20")
	assert_eq(MarkdownBBCode.link_target("C:/p/a.gd"), {"path": "C:/p/a.gd", "line": 0}, "unidad de Windows")
