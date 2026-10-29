# Godot from the command line (headless)

For when you cannot use the `godot.*` editor tools, like in a session that works in a separate copy of the project. Always use the editor's binary (`$GODOT`) with `--headless`: without it Godot opens a window on the user's screen and the harness rejects the command. Every rule here was checked on Godot 4.7.2 and 4.8. Adapted from walker (github.com/nikbearbrown/walker, MIT), which writes the same ideas for C#.

## Check your work

1. After adding or changing assets (images, sounds, models), import them: `"$GODOT" --headless --path <project> --import`. Import does **not** parse scripts: a broken script passes it silently.
2. Parse each script you changed: `"$GODOT" --headless --path <project> --check-only --script res://path/to/script.gd`. It exits with code 1 and prints `SCRIPT ERROR: Parse Error: …` with the reason when the script is broken, and 0 when it parses.

## Build scenes with a script, not by hand

Never write a `.tscn` by hand. Write a builder script that runs once and saves the scene:

```gdscript
extends SceneTree
# Run: "$GODOT" --headless --path <project> --script res://tools/build_level.gd

func _initialize() -> void:
	var root := Node2D.new()
	root.name = "Level"
	var player := CharacterBody2D.new()
	player.name = "Player"
	root.add_child(player)
	player.owner = root  # every node below the root needs owner = root, or it is not saved
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	player.add_child(shape)
	shape.owner = root
	var expected := _count(root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	var check := packed.instantiate()
	if error != OK or _count(check) != expected:
		push_error("Not saved: %d nodes built, %d packed." % [expected, _count(check)])
		quit(1)
		return
	ResourceSaver.save(packed, "res://scenes/level.tscn")
	check.free()
	root.free()
	quit()


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
```

- Put all the building in `_initialize()`. A builder has no `_ready()` or `_process()`: it is not a node in a running game.
- Count the nodes you built and the nodes the packed scene instantiates, and save only if they match. A node without `owner` is dropped from the saved scene **without any error**: the count is how you catch it.
- Behaviour goes in the scene's own scripts (set with `node.set_script(load("res://player.gd"))` before packing), not in the builder.

## Silent failures

- **`owner` not set**: the node is missing from the saved `.tscn`, with no error (see above).
- **`.gdignore`**: a folder with a `.gdignore` file is not imported. Images, sounds and models in it don't load (`ResourceLoader.exists` is false), with no warning. Scripts in it still load, so the problem shows up only with assets.
- **Shared resources**: `load()` returns the same cached instance everywhere. Changing a property of a loaded `.tres` at runtime changes it for every node that uses it. Call `duplicate()` first when each node needs its own copy.
- **Guessed API names**: enum values, constants and methods change between Godot versions. Check them with `godot.class_info` or `godot.search_api` (read-only tools work in a separate copy too) instead of guessing.
- **Frame-rate dependent smoothing**: `speed *= 0.9` each frame slows down faster at higher frame rates. Use `speed *= exp(-rate * delta)`.

## Video

A recording needs the game's window, so it can't run headless. In the editor, `godot.run_scene` with `record: true` saves an AVI under `res://.godot_agent/playtests/`. In a separate copy there is no way to record: describe what to check and let the user run it.
