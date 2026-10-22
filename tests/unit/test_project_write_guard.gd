extends "test_case.gd"
## Escrituras al proyecto que se saltean el editor (D48): comandos de shell y escenas escritas a mano.

const ProjectWriteGuard := preload("res://addons/godot_agent/session/project_write_guard.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
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
	assert_eq(_target("cd /tmp && rm -f build.log"), "build.log", "una ruta relativa cuenta como del proyecto")
	assert_eq(_target("rm /tmp/report.txt && echo ok"), "", "rm fuera del proyecto")
	assert_eq(_target("sudo rm " + ROOT + "/x.tscn"), ROOT + "/x.tscn", "con sudo y ruta absoluta")
	assert_eq(_target("git status && git diff"), "", "git de lectura")
	assert_eq(_target("echo 'rm -rf res'"), "", "rm dentro de un string")
