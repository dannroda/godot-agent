@tool
extends EditorPlugin

const SCENE := "res://main.tscn"


func _enter_tree() -> void:
	if "--repro" in OS.get_cmdline_user_args():
		_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	EditorInterface.open_scene_from_path(SCENE)
	await get_tree().create_timer(1.0).timeout
	for i in 3:
		print("[repro] save_scene() (with preview) ", i)
		EditorInterface.save_scene()
		await get_tree().create_timer(1.0).timeout
	for i in 3:
		print("[repro] save_scene_as(path, false) (no preview) ", i)
		EditorInterface.save_scene_as(SCENE, false)
		await get_tree().create_timer(1.0).timeout
	print("[repro] done")
	get_tree().quit(0)
