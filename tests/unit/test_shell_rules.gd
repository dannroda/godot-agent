extends "test_case.gd"
## Clasificador de shell del modo Auto (D57).

const ShellRules := preload("res://addons/godot_agent/session/shell_rules.gd")


func _decision(command: String, rules: Array = ShellRules.default_rules()) -> String:
	return str(ShellRules.classify(command, rules).decision)


func test_allowlist() -> void:
	for command: String in ["ls", "ls -la addons", "git status", "git status -s", "git log --oneline -5", "grep -rn foo .", "git branch", "pwd"]:
		assert_eq(_decision(command), "allow", command)
	assert_eq(_decision("/opt/godot/versions/4.8-beta1/godot --headless --path . --script t.gd"), "allow", "programa con ruta")
	assert_eq(_decision("FOO=1 ls"), "allow", "asignación al principio")
	assert_eq(_decision("git branch -D x"), "ask", "git branch con argumentos no está")
	assert_eq(_decision("npm test"), "ask", "fuera de las listas")
	assert_eq(_decision(""), "ask", "vacío")


func test_ask_list_wins() -> void:
	var rules := ShellRules.default_rules()
	rules.append(ShellRules.make_rule("git *", ShellRules.LIST_ALLOW, ShellRules.ORIGIN_USER))
	assert_eq(_decision("git commit -m x", rules), "allow", "allow amplio del usuario")
	var verdict := ShellRules.classify("git push origin main", rules)
	assert_eq(verdict.decision, "ask", "git push sigue preguntando")
	assert_eq(verdict.rule, "git push *", "regla que decidió")
	assert_eq(_decision("rm -rf build"), "ask", "rm")
	assert_eq(_decision("rm"), "ask", "«rm *» también cubre rm solo")
	assert_eq(_decision("find . -name '*.tmp' -delete"), "ask", "find -delete")
	assert_eq(_decision("find . -exec rm {} \\;"), "ask", "find -exec")
	assert_eq(_decision("/usr/bin/curl https://x"), "ask", "curl con ruta")
	assert_eq(_decision("git diff --output=x.patch"), "ask", "git --output escribe")


func test_compound() -> void:
	assert_eq(_decision("ls && git status"), "allow", "&& con las dos partes permitidas")
	assert_eq(_decision("cat a.txt | grep foo | wc -l"), "allow", "pipes")
	assert_eq(_decision("ls; rm -rf x"), "ask", "una parte en la lista ask")
	assert_eq(_decision("ls || npm test"), "ask", "una parte fuera de la allowlist")
	assert_eq(_decision("ls & rm x"), "ask", "& en segundo plano separa")
	assert_eq(_decision("echo 'a; rm x' && ls"), "allow", "separadores entre comillas no cuentan")
	assert_eq(_decision("echo \"$(rm x)\""), "ask", "sustitución entre comillas dobles")
	assert_eq(_decision("echo '$(rm x)'"), "allow", "entre comillas simples es texto")
	assert_eq(_decision("ls `rm x`"), "ask", "backticks")
	assert_eq(_decision("diff <(ls a) <(ls b)"), "ask", "sustitución de procesos")
	assert_eq(_decision("echo 'abierta"), "ask", "comilla sin cerrar")
	var parsed := ShellRules.split("git status -s && git log -1 | cat")
	assert_eq(Array(parsed.segments), ["git status -s", "git log -1", "cat"], "segmentos")


func test_redirections() -> void:
	assert_eq(_decision("ls 2>/dev/null"), "allow", "a /dev/null")
	assert_eq(_decision("git log 2>&1 | head"), "allow", "2>&1")
	assert_eq(_decision("ls &>/dev/null"), "allow", "&>/dev/null")
	var verdict := ShellRules.classify("echo hola > /tmp/x.txt", ShellRules.default_rules())
	assert_eq(verdict.decision, "ask", "redirección a un archivo")
	assert_true(str(verdict.reason).contains("/tmp/x.txt"), "el motivo nombra el archivo")
	assert_eq(_decision("cat a >> b"), "ask", ">>")
	assert_eq(_decision("grep foo < input.txt"), "allow", "entrada desde un archivo")


func test_patterns() -> void:
	assert_true(ShellRules.matches("npm test", "npm test"), "exacto")
	assert_false(ShellRules.matches("npm test", "npm test --watch"), "exacto no es prefijo")
	assert_true(ShellRules.matches("npm *", "npm"), "«x *» cubre x solo")
	assert_true(ShellRules.matches("npm  run  *", "npm run build"), "espacios normalizados")
	assert_false(ShellRules.matches("", "ls"), "patrón vacío")
	assert_false(ShellRules.matches("ls *", "lsof"), "no coincide un prefijo de palabra")


func test_suggest_pattern() -> void:
	var rules := ShellRules.default_rules()
	assert_eq(ShellRules.suggest_pattern("npm test -- --watch", rules), "npm test *", "subcomando de npm")
	assert_eq(ShellRules.suggest_pattern("ls && make build", rules), "make build", "el primero que no está permitido")
	assert_eq(ShellRules.suggest_pattern("python3 tools/gen.py", rules), "python3 *", "programa solo")
	assert_eq(ShellRules.suggest_pattern("/usr/bin/cargo build --release", rules), "cargo build *", "sin la ruta")
	assert_eq(ShellRules.suggest_pattern("rm -rf build", rules), "", "en la lista ask: una regla allow no ganaría")
	assert_eq(ShellRules.suggest_pattern("echo a > out.txt", rules), "", "redirección: las listas no la juzgan")


func test_default_rules() -> void:
	var rules := ShellRules.default_rules()
	assert_eq(rules.size(), ShellRules.DEFAULT_ALLOW.size() + ShellRules.DEFAULT_ASK.size(), "todas")
	assert_eq(rules[0].origin, "default", "origen")
	assert_eq(rules[0].added, "", "sin fecha")
	var rule := ShellRules.make_rule("  make   test ", ShellRules.LIST_ALLOW, ShellRules.ORIGIN_CARD, "2026-10-22")
	assert_eq(rule, {"pattern": "make test", "list": "allow", "origin": "card", "added": "2026-10-22"}, "make_rule normaliza")


func test_codes() -> void:
	var rules := ShellRules.default_rules()
	var cases := {
		"ls && git status": [ShellRules.CODE_ALLOWED, ""],
		"ls; rm -rf x": [ShellRules.CODE_ASK_LIST, "rm -rf x"],
		"npm test": [ShellRules.CODE_NOT_ALLOWED, "npm test"],
		"echo $(id)": [ShellRules.CODE_SUBSTITUTION, ""],
		"diff <(ls a) <(ls b)": [ShellRules.CODE_SUBSTITUTION, ""],
		"echo hola > out.txt": [ShellRules.CODE_REDIRECT, "out.txt"],
		"echo 'abierta": [ShellRules.CODE_QUOTE, ""],
		"": [ShellRules.CODE_EMPTY, ""],
	}
	for command: String in cases:
		var verdict := ShellRules.classify(command, rules)
		assert_eq([verdict.code, verdict.segment], cases[command], "código y segmento de «%s»" % command)


func test_describe_verdict() -> void:
	var page := load("res://addons/godot_agent/ui/settings/auto_rules_page.gd")
	var rules := ShellRules.default_rules()
	assert_eq(page.describe_verdict(ShellRules.classify("ls && git status -s", rules)), "Runs without asking: every part is on the allowlist (ls *, git status *).", "permitido")
	assert_eq(page.describe_verdict(ShellRules.classify("git push", rules)), "Asks: «git push» is on the «Always ask» list (git push *).", "lista ask")
	assert_eq(page.describe_verdict(ShellRules.classify("echo a > b.txt", rules)), "Asks: it writes its output to a file (b.txt).", "redirección")
