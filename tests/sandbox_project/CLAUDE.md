# Sandbox One-shot

Proyecto vacío para probar el modo One-shot del Godot Agent Harness.

- Godot 4, GDScript con tipos estáticos.
- Escenas en `res://scenes/`, scripts en `res://scripts/`.
- No toques `res://addons/`: es el harness.
- Para editar escenas abiertas usá las tools `godot.*`; para scripts nuevos, escribí los archivos.
- Verificá cada tarea con `godot.run_scene` (con inputs simulados), `godot.capture_game_frame` y `godot.get_errors`.
- No hagas commits ni cambies de rama: los checkpoints los maneja el harness.
