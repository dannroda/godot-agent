extends "test_case.gd"
## godot.run_tests (m16-26): qué runner se usa, los argumentos de GUT, gdUnit4 y un comando propio,
## los XML JUnit de los dos, el resultado para el agente y una corrida de punta a punta.

const TestRunner := preload("res://addons/godot_agent/core/test_runner.gd")
const TurnChecks := preload("res://addons/godot_agent/core/turn_checks.gd")
const TestTools := preload("res://addons/godot_agent/mcp/tools/test_tools.gd")
const TurnChecksEditor := preload("res://addons/godot_agent/ui/settings/turn_checks_editor.gd")

## Como lo escribe GUT (junit_xml_export.gd): la ruta sin res:// y la línea en el texto.
const GUT_XML := """<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="GutTests" failures="1" tests="3" >
  <testsuite name="test/test_math.gd" tests="3" failures="1" skipped="1" time="0.01" >
    <testcase name="test_adds" assertions="1" status="pass" classname="test/test_math.gd" time="0.001" >
    </testcase>
    <testcase name="test_breaks" assertions="1" status="fail" classname="test/test_math.gd" time="0.002" >
<failure message="failed"><![CDATA[[Failed]:  [4] expected to equal [5]:  four is not five
          at line 7]]></failure>
    </testcase>
    <testcase name="test_later" assertions="0" status="pending" classname="test/test_math.gd" time="0" >
<skipped message="pending"><![CDATA[not yet]]></skipped>
    </testcase>
  </testsuite>
</testsuites>"""

## Como lo escribe gdUnit4 (JUnitXmlReportWriter.gd): archivo y línea en el atributo.
const GDUNIT_XML := """<?xml version="1.0" encoding="UTF-8"?>
<testsuites id="2026-11-18" name="report_1" tests="2" failures="1" skipped="0" flaky="0" time="0.1">
	<testsuite id="0" name="test_math" package="res://test/test_math.gd" tests="2" failures="1" errors="0" skipped="0" time="0.1">
		<testcase name="test_adds" classname="test_math" time="0.01"/>
		<testcase name="test_breaks" classname="test_math" time="0.02">
			<failure message="FAILED: res://test/test_math.gd:12" type="FAILURE">
				<![CDATA[Expecting:
 '5'
 but was
 '4']]>
			</failure>
		</testcase>
	</testsuite>
</testsuites>"""


func _exists(paths: Array) -> Callable:
	return func(path: String) -> bool: return path in paths


func test_detect() -> void:
	var none := TestRunner.detect([], _exists([]))
	assert_true(str(none.get("error", "")).contains("Settings"), "sin runner: dice dónde configurarlo")
	var gut := TestRunner.detect([], _exists([TestRunner.GUT_SCRIPT, TestRunner.GDUNIT_SCRIPT]))
	assert_eq([gut.framework, gut.needs_approval], [TestRunner.GUT, false], "GUT instalado, sin aprobación: el comando es del harness")
	assert_eq(TestRunner.detect([], _exists([TestRunner.GDUNIT_SCRIPT])).framework, TestRunner.GDUNIT, "gdUnit4 instalado")
	var checks := [
		{"name": "Lint", "command": "{godot} --headless -s res://lint.gd"},
		{"name": "Suite", "command": "{godot} --headless --path {project} --script res://tests/run_tests.gd -- --only={files}", "tests": true, "enabled": false},
	]
	var own := TestRunner.detect(checks, _exists([TestRunner.GUT_SCRIPT]))
	assert_eq([own.framework, own.check_name, own.needs_approval], [TestRunner.COMMAND, "Suite", true], "el check marcado gana a GUT, aunque no corra al terminar el turno")
	var gut_check := TestRunner.detect([{"name": "GUT", "command": TurnChecks.PRESETS[1].command, "tests": true}], _exists([]))
	assert_eq(gut_check.framework, TestRunner.GUT, "un check con gut_cmdln.gd se lee como GUT")
	assert_false(TurnChecks.normalize({"kind": "regressions", "tests": true}).tests, "las regresiones no son el runner de tests")


func test_gut_args() -> void:
	var runner := TestRunner.detect([], _exists([TestRunner.GUT_SCRIPT]))
	var how := TestRunner.invocation(runner, PackedStringArray(["res://test/test_a.gd", "res://test/unit/"]), "jump", "/bin/godot", "/p", "/r/results.xml", _exists([]))
	assert_eq(how.program, "/bin/godot", "el binario del editor")
	var args := Array(how.args)
	assert_true(args.has("-gexit") and args.has("-gtest=res://test/test_a.gd") and args.has("-gdir=res://test/unit") and args.has("-ginclude_subdirs"), "scripts y carpetas: %s" % [args])
	assert_true(args.has("-gunit_test_name=jump") and args.has("-gjunit_xml_file=/r/results.xml"), "nombre del test y XML")
	how = TestRunner.invocation(runner, PackedStringArray(), "", "/bin/godot", "/p", "/r/x.xml", _exists(["res://tests"]))
	assert_true(Array(how.args).has("-gdir=res://tests"), "sin .gutconfig.json: las carpetas de siempre que existan")
	how = TestRunner.invocation(runner, PackedStringArray(), "", "/bin/godot", "/p", "/r/x.xml", _exists(["res://tests", TestRunner.GUT_CONFIG]))
	assert_false(str(how.args).contains("-gdir="), "con .gutconfig.json manda la configuración del proyecto")


func test_gdunit_args() -> void:
	var runner := TestRunner.detect([{"name": "gdUnit4", "command": TurnChecks.PRESETS[2].command, "tests": true}], _exists([]))
	var how := TestRunner.invocation(runner, PackedStringArray(["res://test/test_a.gd"]), "jump", "/bin/godot", "/p", "/r", _exists([]))
	var args := Array(how.args)
	assert_eq(args.count("-a"), 1, "los `paths` reemplazan el -a del comando: %s" % [args])
	assert_eq(args[args.find("-a") + 1], "res://test/test_a.gd", "el script pedido")
	assert_true(args.has("-c"), "no corta en la primera falla")
	assert_eq(args.slice(-2), ["-rd", "/r"], "el reporte va a la carpeta del harness")
	assert_true(str(how.notes).contains("test"), "avisa que `test` no se usó")


func test_custom_args() -> void:
	var runner := {"framework": TestRunner.COMMAND, "command": "{godot} --headless --path {project} --script res://tests/run_tests.gd -- --only={files} --name={test}"}
	var how := TestRunner.invocation(runner, PackedStringArray(["res://tests/test_feel.gd", "res://tests/test_player.gd"]), "", "/bin/godot", "/p", "/r", _exists([]))
	assert_eq(Array(how.args), ["--headless", "--path", "/p", "--script", "res://tests/run_tests.gd", "--", "--only=test_feel.gd,test_player.gd"], "{files}: los nombres; un argumento sin valor no va")
	how = TestRunner.invocation(runner, PackedStringArray(), "", "/bin/godot", "/p", "/r", _exists([]))
	assert_false(str(how.args).contains("--only"), "sin paths: corre todo")
	how = TestRunner.invocation({"framework": TestRunner.COMMAND, "command": "./run.sh"}, PackedStringArray(["res://a.gd"]), "x", "/bin/godot", "/p", "/r", _exists([]))
	assert_eq(how.notes.size(), 2, "avisa lo que el comando no puede filtrar")
	how = TestRunner.invocation({"framework": TestRunner.COMMAND, "command": "./run.sh | tee x"}, PackedStringArray(), "", "/bin/godot", "/p", "/r", _exists([]))
	assert_true(str(how.error).contains("shell"), "sin shell")


func test_parse_junit() -> void:
	var gut := TestRunner.parse_junit(GUT_XML)
	assert_eq([gut.ok, gut.total, gut.failed, gut.skipped], [true, 3, 1, 1], "totales de GUT")
	var failure: Dictionary = gut.failures[0]
	assert_eq([failure.test, failure.file, failure.line], ["test_breaks", "res://test/test_math.gd", 7], "GUT: archivo de classname y línea del texto")
	assert_true(str(failure.message).contains("four is not five") and not str(failure.message).contains("at line"), "el mensaje sin la línea: %s" % failure.message)
	var gdunit := TestRunner.parse_junit(GDUNIT_XML)
	assert_eq([gdunit.total, gdunit.failed], [2, 1], "totales de gdUnit4 (testcase vacío incluido)")
	failure = gdunit.failures[0]
	assert_eq([failure.file, failure.line], ["res://test/test_math.gd", 12], "gdUnit4: del atributo")
	assert_true(str(failure.message).contains("but was"), "el texto de la falla")
	assert_false(TestRunner.parse_junit("").ok, "vacío")


func test_report() -> void:
	var wrap := func(text: String) -> String: return "<<%s>>" % text
	var run := {"framework": TestRunner.GUT, "code": 1, "seconds": 3.0, "junit": TestRunner.parse_junit(GUT_XML), "stdout": PackedStringArray(["lots", "of", "output"]), "stderr": PackedStringArray(), "notes": PackedStringArray()}
	var result := TestRunner.report(run, wrap)
	assert_false(result.passed, "una falla")
	assert_true(result.text.begins_with("FAILED: 1 of 3 tests"), result.text)
	assert_true(result.text.contains("✗ test_breaks — res://test/test_math.gd:7") and result.text.contains("<<[Failed]"), "la falla, con el mensaje en sobre")
	assert_false(result.text.contains("lots"), "con XML, nada de la salida")
	assert_eq(result.locations, [{"path": "res://test/test_math.gd", "line": 7}], "para abrirla")
	run = {"framework": TestRunner.COMMAND, "code": 1, "seconds": 9.0, "stdout": PackedStringArray(["start", "120 tests, 1 fallos"]), "stderr": PackedStringArray(["test_feel.gd: test_jump res://tests/test_feel.gd:40 expected 3"]), "notes": PackedStringArray()}
	result = TestRunner.report(run, wrap)
	assert_true(result.text.begins_with("FAILED with exit code 1"), result.text)
	assert_true(result.text.contains("Error output:\n<<test_feel.gd") and result.text.contains("120 tests, 1 fallos"), "stderr y el final de stdout")
	assert_eq(result.locations, [{"path": "res://tests/test_feel.gd", "line": 40}], "las rutas de la salida")
	run.code = 0
	run.stderr = PackedStringArray()
	result = TestRunner.report(run, wrap)
	assert_true(result.passed and result.text.contains("120 tests"), "pasó: el resumen del runner")
	run = {"framework": TestRunner.GUT, "code": 0, "seconds": 1.0, "junit": {}, "stdout": PackedStringArray(), "stderr": PackedStringArray(), "notes": PackedStringArray()}
	result = TestRunner.report(run, wrap)
	assert_true(not result.passed and result.text.begins_with("No tests ran"), "GUT sin tests no es un pase")


## Un runner propio de verdad: el comando del check, con {files}, la aprobación y la salida.
func test_run_tests_tool() -> void:
	var dir := ProjectSettings.globalize_path("user://").path_join("run_tests_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var script := dir.path_join("runner.gd")
	var file := FileAccess.open(script, FileAccess.WRITE)
	file.store_string("extends SceneTree\n\nfunc _init() -> void:\n\tvar only := \"\"\n\tfor arg in OS.get_cmdline_user_args():\n\t\tif arg.begins_with(\"--only=\"):\n\t\t\tonly = arg.trim_prefix(\"--only=\")\n\tprint(\"ran: \", only)\n\tif only.contains(\"run_all\"):\n\t\tprinterr(\"FAIL test_bad res://tests/test_bad.gd:9 boom\")\n\t\tquit(1)\n\telse:\n\t\tquit(0)\n")
	file.close()
	var command := "{godot} --headless --script \"%s\" -- --only={files}" % script
	var approved := {}
	var tools := TestTools.new()
	tools.checks = func() -> Array: return [{"name": "Mine", "command": command, "tests": true}]
	tools.project_dir = "/p/game"
	tools.is_approved = func(key: String) -> bool: return approved.has(key)
	var result: Dictionary = await tools.call(&"_run_tests", {})
	assert_true(result.get("isError", false) and str(result.content[0].text).contains("isn't approved"), "sin aprobar no corre")
	approved[TurnChecks.approval_key("/p/game", command)] = true
	result = await tools.call(&"_run_tests", {"paths": ["res://tests/run_all.gd"]})
	assert_true(result.get("isError", false), "falla")
	var text := str(result.content[0].text)
	assert_true(text.contains("exit code 1") and text.contains("test_bad res://tests/test_bad.gd:9"), text)
	result = await tools.call(&"_run_tests", {"paths": ["res://nope/test_x.gd"]})
	assert_true(str(result.content[0].text).contains("doesn't exist"), "una ruta que no existe")


func test_settings_editor_tests_flag() -> void:
	var editor := TurnChecksEditor.new()
	editor.load_from([{"name": "Suite", "command": "./run.sh", "tests": true}, {"kind": "regressions"}], func(_key: String) -> bool: return true, "/p")
	var rows: Array = editor.get(&"_rows")
	assert_true((rows[0].tests as CheckBox).button_pressed, "carga la marca")
	assert_false((rows[1].tests as CheckBox).visible, "las regresiones no la tienen")
	(rows[0].tests as CheckBox).button_pressed = false
	assert_false(editor.checks()[0].tests, "la guarda")
	editor.call(&"_on_preset", 1)
	assert_true(editor.checks()[2].tests, "el preset de GUT viene marcado")
	editor.free()
