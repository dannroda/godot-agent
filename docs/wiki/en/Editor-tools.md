# Editor tools (MCP)

[Home](Home.md) · [Español](../es/Herramientas-del-editor.md)

The agent sees these tools as `godot.<name>` (Claude Code shows them as `mcp__godot__<name>`).

| Group | Tool | What it does |
|---|---|---|
| Read | `project_info` | Godot version, editor binary, project name, main scene, autoloads, input actions, plugins, renderer. |
| | `list_files` | Project files with their resource type; glob filter. |
| | `scene_tree` | A scene's tree: types, scripts, instanced scenes, groups and non-default properties. Without `scene`, the open scene with its unsaved changes. |
| | `get_node` | One node in detail: non-default properties, script, groups, saved signal connections and children. |
| | `editor_state` | Current and open scenes, selection, open script with the caret line, and whether the game is running. |
| | `class_info` | The API of a class in the open editor's Godot version: inheritance, method signatures, properties with defaults, signals, constants, with descriptions. Engine classes, built-in types (`Vector2`…), `@GlobalScope` and project `class_name`s. `member` gives one member's full docs. |
| | `search_api` | Finds classes and members by name or capability ("raycast", "move toward"). |
| Diagnostics | `get_errors` | Errors and warnings from the editor and the last run. It returns a mark; pass it as `since` to see only new ones. |
| | `validate_scripts` | Parses scripts in a separate process (the editor's binary) and returns errors by file and line, without running the game. |
| | `capture_editor_viewport` | An image of the 2D/3D viewport. |
| Edit scenes | `add_nodes` | A whole subtree in one call and one undo step: nested nodes with type, properties, script, groups and instanced scenes. Nothing is created if one item is invalid. |
| | `duplicate_node` | Copies a node with its children, script, groups and properties; next to the original or under another parent. |
| | `add_node`, `set_properties`, `remove_node`, `reparent_node`, `rename_node`, `connect_signal`, `instantiate_scene`, `open_scene`, `save_scene` | Edits on open scenes, each one an undo step in the editor. |
| Edit files | `create_scene`, `attach_script` | New scenes and scripts on disk. `create_scene` also takes the root's script and properties (exported variables included), so a scene is never written by hand. |
| Run | `run_scene` | Runs a scene (with simulated `inputs` if you want) and returns the real errors. |
| | `capture_game_frame` | A frame of the running game. |
| | `stop_scene` | Stops it. |

## Details

- **Undo**: each scene edit is one step of the editor's undo. The tool card in the chat has **↶ undo** while nobody has touched the scene afterwards.
- **Open scenes**: the agent is told to edit open scenes through these tools, never on disk.
- **Playtests**: `run_scene` adds a temporary autoload that captures errors, frames and simulated input, and removes it as soon as the game starts. If the editor dies mid-playtest, the next start cleans it up. The export never includes it.
- **Limits**: **Settings → MCP server** sets the characters per result and the maximum image side, plus extra folders outside the project that the agent may read and write.
- **Security**: the server only listens on `127.0.0.1`, requires a token that changes on every start (**Regenerate token** in Settings), and the log masks it.
