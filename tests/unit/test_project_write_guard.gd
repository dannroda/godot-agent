extends "test_case.gd"
## Escrituras al proyecto que se saltean el editor (D48): comandos de shell y escenas escritas a mano.

const ProjectWriteGuard := preload("res://addons/godot_agent/session/project_write_guard.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const OPTIONS := [
	{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
	{"optionId": "reject", "name": "Reject", "kind": "reject_once"},
]
const ROOT := "/home/user/game"


func _target(command: String) -> String:
	return ProjectWriteGuard.shell_write_target(command, ROOT)


## Los comandos del run de great-boy-one (captura del usuario).
func test_commands_from_the_report() -> void:
	var python := "python3 - <<'EOF'\np=\"ui/balloon.gd\"; s=open(p).read()\ns=s.replace(\"a\", \"b\")\nif len(s) > 0:\n    open(p,\"w\").write(s)\nEOF"
	assert_eq(_target(python), "ui/balloon.gd", "python con heredoc que escribe un script")
	var cat := "mkdir -p tests && cat > tests/start_at_boss.gd <<'EOF'\nextends Node\n@export var mission := \"planta\"\nEOF\ncat > tests/boss_planta.tscn <<'EOF'\n[gd_scene format=3]\nEOF\necho ok"
	assert_eq(_target(cat), "tests/start_at_boss.gd", "cat > con heredoc")


func test_shell_writes() -> void:
	assert_eq(_target("echo hi > notes.txt"), "notes.txt", "redirección relativa")
	assert_eq(_target("printf 'x' >> " + ROOT + "/data.json"), ROOT + "/data.json", "redirección absoluta al proyecto")
	assert_eq(_target("git diff | tee patch.diff"), "patch.diff", "tee")
	assert_eq(_target("sed -i 's/a/b/' player/player.gd"), "player/player.gd", "sed -i")
	assert_eq(_target("perl -pi -e 's/a/b/' x.gd"), "x.gd", "perl -pi")
	assert_eq(_target("python3 -c 'open(\"a.gd\", \"w\").write(\"\")'"), "a.gd", "python -c")
	assert_eq(_target("node -e \"require('fs').writeFileSync('levels/l1.json', '{}')\""), "levels/l1.json", "node -e")
	assert_eq(_target("dd if=/dev/zero of=big.bin bs=1 count=1"), "big.bin", "dd of=")


func test_shell_reads_and_outside_writes_pass() -> void:
	assert_eq(_target("ls -la"), "", "ls")
	assert_eq(_target("git status 2>&1 | head"), "", "2>&1")
	assert_eq(_target("\"$GODOT\" --headless --path . --script res://tests/run.gd > /tmp/out.log 2>&1"), "", "a /tmp")
	assert_eq(_target("grep -rn \"a > b\" scripts/"), "", "un > entre comillas")
	assert_eq(_target("cmd &> /dev/null"), "", "/dev/null")
	assert_eq(_target("echo x > \"$TMPDIR/x\""), "", "una variable no se resuelve")
	assert_eq(_target("sed -n '1,20p' player.gd"), "", "sed sin -i")
	assert_eq(_target("python3 - <<'EOF'\nimport json\nprint(json.load(open('data.json'))['seed'])\nif 2 > 1: print('ok')\nEOF"), "", "python que solo lee (con un > en el código)")
	assert_eq(_target("python3 - <<'EOF'\nopen('/tmp/report.txt', 'w').write('x')\nEOF"), "", "python que escribe en /tmp")


func test_edit_tools() -> void:
	var write_scene := {"kind": "edit", "rawInput": {"file_path": ROOT + "/scenes/boss.tscn", "content": "[gd_scene]"}}
	assert_eq(ProjectWriteGuard.blocked_target(write_scene, PermissionPolicy.GROUP_EDIT_FILES, ROOT), ROOT + "/scenes/boss.tscn", "Write de una escena")
	var uid := {"kind": "edit", "locations": [{"path": ROOT + "/player.gd.uid"}]}
	assert_eq(ProjectWriteGuard.blocked_target(uid, PermissionPolicy.GROUP_EDIT_FILES, ROOT), ROOT + "/player.gd.uid", ".uid por locations")
	var script := {"kind": "edit", "rawInput": {"file_path": ROOT + "/player.gd"}}
	assert_eq(ProjectWriteGuard.blocked_target(script, PermissionPolicy.GROUP_EDIT_FILES, ROOT), "", "un script se escribe con las tools del agente")
	var outside := {"kind": "edit", "rawInput": {"file_path": "/tmp/x.tscn"}}
	assert_eq(ProjectWriteGuard.blocked_target(outside, PermissionPolicy.GROUP_EDIT_FILES, ROOT), "", "fuera del proyecto")
	var settings := {"kind": "edit", "rawInput": {"file_path": ROOT + "/project.godot"}}
	assert_eq(ProjectWriteGuard.blocked_target(settings, PermissionPolicy.GROUP_EDIT_FILES, ROOT), ROOT + "/project.godot", "project.godot a mano (m4-09)")
	assert_true(ProjectWriteGuard.alternative_for("project.godot").contains("set_project_setting"), "el rechazo nombra la tool")
	var tres := {"kind": "edit", "rawInput": {"file_path": ROOT + "/data/sword.tres"}}
	assert_eq(ProjectWriteGuard.blocked_target(tres, PermissionPolicy.GROUP_EDIT_FILES, ROOT), ROOT + "/data/sword.tres", ".tres a mano (m4-13)")
	assert_true(ProjectWriteGuard.alternative_for("a/sword.tres").contains("create_resource"), "el rechazo de .tres nombra la tool")
	assert_eq(_target("sed -i 's/a/b/' project.godot"), "project.godot", "sed -i sobre project.godot")
	var shell := {"kind": "execute", "rawInput": {"command": "echo a > b.txt"}}
	assert_eq(ProjectWriteGuard.blocked_target(shell, PermissionPolicy.GROUP_SHELL, ROOT), "b.txt", "shell por blocked_target")


func test_file_commands() -> void:
	assert_eq(_target("mv player.gd actors/player.gd"), "player.gd", "mv dentro del proyecto")
	assert_eq(_target("rm -rf assets/old"), "assets/old", "rm -rf")
	assert_eq(_target("cp ~/Downloads/hero.png sprites/hero.png"), "sprites/hero.png", "cp hacia el proyecto")
	assert_eq(_target("cp sprites/hero.png /tmp/hero.png"), "", "cp del proyecto hacia afuera")
	assert_eq(_target("git mv a.gd b.gd"), "a.gd", "git mv")
	assert_eq(_target("rm -f build.log"), "build.log", "una ruta relativa cuenta como del proyecto")
	assert_eq(_target("cd /tmp && rm -f build.log"), "", "después de cd /tmp, la relativa es de /tmp (m11-69)")
	assert_eq(_target("rm /tmp/report.txt && echo ok"), "", "rm fuera del proyecto")
	assert_eq(_target("sudo rm " + ROOT + "/x.tscn"), ROOT + "/x.tscn", "con sudo y ruta absoluta")
	assert_eq(_target("git status && git diff"), "", "git de lectura")
	assert_eq(_target("echo 'rm -rf res'"), "", "rm dentro de un string")


## Las rutas relativas se resuelven contra el último cd del comando (m11-69).
func test_cd_changes_where_relative_paths_go() -> void:
	assert_eq(_target("cd /tmp && echo x > f"), "", "cd /tmp && echo > f")
	assert_eq(_target("cd $T; echo > f"), "", "cd a una variable: no se sabe dónde, no se bloquea")
	assert_eq(_target("(cd /tmp && x); echo > f"), "f", "un cd dentro de ( … ) no vale después")
	assert_eq(_target("cd sub && echo > f"), ROOT + "/sub/f", "cd a una subcarpeta del proyecto")
	assert_eq(_target("cd " + ROOT + "/sub && rm a"), ROOT + "/sub/a", "cd absoluto al proyecto y rm")
	var report := "cd /tmp && rm -rf gm_test; T=$(mktemp -d); cd $T; git init -q; echo 9.9-nope > .godot-version"
	assert_eq(_target(report), "", "el comando de la sesión de Godot Manager")
	assert_eq(_target("cd /tmp && echo x > " + ROOT + "/a.txt"), ROOT + "/a.txt", "una absoluta al proyecto se bloquea igual")
	assert_eq(_target("cd /tmp && echo x > ../" + ROOT.trim_prefix("/") + "/a.txt"), ROOT + "/a.txt", "una relativa que vuelve al proyecto")
	assert_eq(_target("cd ~ && echo x > f; cd - ; echo y > g"), "", "cd ~ y cd -: no se resuelven")
	assert_eq(_target("cd /tmp && cd .. && echo x > f"), "", "cd .. desde /tmp")
	assert_eq(_target("cd /tmp | cat; echo > f"), "f", "antes de un | corre en una subshell")
	assert_eq(_target("cd /tmp || exit 1; echo > f"), "", "cd /tmp || exit: sigue en /tmp")
	assert_eq(_target("echo $(cd /tmp && pwd) > f"), "f", "un cd en $( … ) no vale afuera")
	assert_eq(_target("echo $(echo x > g)"), "g", "una escritura dentro de $( … ) se ve")
	assert_eq(_target("x=1 && { cd /tmp; echo > f; }"), "", "cd dentro de { … } vale (misma shell)")


func test_pushd_popd_and_file_commands_after_cd() -> void:
	assert_eq(_target("pushd /tmp && echo > f && popd && echo > g"), "g", "popd vuelve al proyecto")
	assert_eq(_target("pushd /tmp >/dev/null; mv a b; cp x y; sed -i 's/a/b/' c.txt"), "", "mv/cp/sed -i después de pushd /tmp")
	assert_eq(_target("cd /tmp; sed -i 's/a/b/' " + ROOT + "/c.gd"), ROOT + "/c.gd", "sed -i con ruta absoluta al proyecto")
	assert_eq(_target("cd -P /tmp && rm a"), "", "cd con opción")
	assert_eq(_target("echo x 2>&1 > f"), "f", "2>&1 no corta el comando")
	assert_eq(_target("echo x &> f"), "f", "&> f")
	assert_eq(_target("echo x >| f"), "f", ">| f")


func test_start_dir() -> void:
	assert_eq(ProjectWriteGuard.shell_write_target("echo x > f", ROOT, "/tmp/work"), "", "la terminal corre en /tmp")
	assert_eq(ProjectWriteGuard.shell_write_target("echo x > f", ROOT, ROOT + "/sub"), ROOT + "/sub/f", "la terminal corre en una subcarpeta")
	assert_eq(ProjectWriteGuard.shell_write_target("echo x > f", ROOT, "sub"), ROOT + "/sub/f", "una carpeta relativa es del proyecto")
	assert_eq(ProjectWriteGuard.shell_write_target("cd " + ROOT + " && echo x > f", ROOT, "/tmp"), "f", "cd al proyecto desde /tmp")


## Antigravity manda dónde corre el comando (rawInput.Cwd).
func test_antigravity_cwd() -> void:
	var outside := {"kind": "execute", "rawInput": {"CommandLine": "echo x > f", "Cwd": "/tmp/work"}}
	assert_eq(ProjectWriteGuard.blocked_target(outside, PermissionPolicy.GROUP_SHELL, ROOT), "", "Cwd fuera del proyecto")
	var inside := {"kind": "execute", "rawInput": {"CommandLine": "echo x > f", "Cwd": ROOT}}
	assert_eq(ProjectWriteGuard.blocked_target(inside, PermissionPolicy.GROUP_SHELL, ROOT), "f", "Cwd en el proyecto")


func _ask(controller: SessionController, id: String, kind: String, raw: Dictionary) -> Variant:
	return await controller.permissions.call(&"on_request_permission", {"sessionId": "s", "toolCall": {"toolCallId": id, "kind": kind, "title": "x", "rawInput": raw}, "options": OPTIONS})


## Un rechazo automático le llega al agente con el motivo (m11-69), no solo «el usuario rechazó».
func test_auto_rejection_reaches_the_agent_with_its_reason() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), ROOT)
	controller.model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	var feedback: Array[String] = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	var result: Variant = await _ask(controller, "w1", "execute", {"command": "echo hi > notes.txt"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "escribir el proyecto desde la shell se rechaza solo")
	assert_eq(feedback.size(), 1, "con un motivo para el agente")
	if feedback.size() == 1:
		assert_true(feedback[0].contains("notes.txt") and feedback[0].contains("godot.move_file") and feedback[0].contains("/tmp"), "dice qué escribe, qué usar y que afuera se puede: %s" % feedback[0])
		assert_true(feedback[0].contains("not the user"), "aclara que no fue el usuario")

	feedback.clear()
	var answers: Array = []
	var ask_tmp := func() -> void: answers.append(await _ask(controller, "w2", "execute", {"command": "cd /tmp && echo hi > notes.txt"}))
	ask_tmp.call()
	assert_eq(controller.model.pending_permissions.size(), 1, "cd /tmp && echo > notes.txt pregunta como cualquier comando, no se rechaza solo")
	assert_true(feedback.is_empty(), "sin motivo de rechazo")
	if not controller.model.pending_permissions.is_empty():
		controller.model.pending_permissions[0].select("reject")
	var tree := Engine.get_main_loop() as SceneTree
	for i in 3:
		await tree.process_frame
	assert_true(feedback.is_empty(), "rechazar la tarjeta sin motivo no manda nada")

	result = await _ask(controller, "w3", "execute", {"command": "godot --path . res://main.tscn"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "Godot con ventana se rechaza solo")
	assert_true(feedback.size() == 1 and feedback[0].contains("--headless"), "con el motivo: %s" % [feedback])

	feedback.clear()
	controller.model.set_harness_mode(SessionModel.HarnessMode.ASK)
	result = await _ask(controller, "w4", "edit", {"file_path": ROOT + "/a.gd"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "Preguntar no deja editar")
	assert_true(feedback.size() == 1 and feedback[0].contains("Edit files"), "con el motivo del modo: %s" % [feedback])


## En un One-shot, el motivo va como la guía del run (al terminar el turno), sin cortar el turno.
func test_reject_feedback_in_oneshot_goes_to_the_run() -> void:
	var dock: Control = load("res://addons/godot_agent/ui/dock/agent_dock.gd").new()
	var taken: Array[String] = []
	dock.submit_interceptor = func(text: String, take_blocks: Callable) -> bool:
		taken.append(text)
		return take_blocks.call().is_empty()
	dock.call(&"_on_reject_feedback", "why")
	assert_eq(taken, ["why"] as Array[String], "lo toma el One-shot")
	dock.free()
