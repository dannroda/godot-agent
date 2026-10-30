# Editor tools (MCP)

[Home](Home.md) · [Español](../es/Herramientas-del-editor.md)

The agent sees these tools as `godot.<name>` (Claude Code shows them as `mcp__godot__<name>`).

**Compact tool list** (on by default, **Settings → MCP server**): every tool description takes context on every turn, so the tool list only carries the core (reading, diagnostics, scene editing and running the game) plus two more:

- `godot.methods` lists the other tools, one line each (`query` filters; `method` shows its description and parameters);
- `godot.run` calls one: `{"method": "tilemap_set_cells", "params": {…}}`. It validates the parameters and asks the same permission as the tool itself.

The extra ones are API docs (`class_info`, `search_api`), project settings, the Asset Store, files, resources, tilemaps, animation and the live game. With the compact list, tools/list goes from about 30,000 characters to about 11,000. The setting applies from the next session.

| Group | Tool | What it does |
|---|---|---|
| Read | `project_info` | Godot version, editor binary, project name, main scene, autoloads, input actions, plugins, renderer. |
| | `list_files` | Project files with their resource type; glob filter. |
| | `scene_tree` | A scene's tree: types, scripts, instanced scenes, groups and non-default properties. Without `scene`, the open scene with its unsaved changes. |
| | `get_node` | One node in detail: non-default properties, script, groups, saved signal connections and children. |
| | `editor_state` | Current and open scenes, selection, open script with the caret line, and whether the game is running. |
| | `class_info` | The API of a class in the open editor's Godot version: inheritance, method signatures, properties with defaults, signals, constants, with descriptions. Engine classes, built-in types (`Vector2`…), `@GlobalScope` and project `class_name`s. `member` gives one member's full docs. |
| | `project_settings` | Settings under a prefix with value and default; without a prefix, the ones that differ from the default. |
| | `search_api` | Finds classes and members by name or capability ("raycast", "move toward"). |
| Diagnostics | `get_errors` | Errors and warnings from the editor and the last run. It returns a mark; pass it as `since` to see only new ones. |
| | `validate_scripts` | Parses scripts in a separate process (the editor's binary) and returns errors by file and line, without running the game. In a C# project it also compiles with `dotnet build`. |
| | `validate_physics`, `validate_tilemap` | Read-only checks the agent runs after touching physics or maps: bodies and areas without a shape, shapes outside a body, collision masks that match no layer in the scene; TileMapLayers without a TileSet, cells the TileSet doesn't have, placed tiles without collision. |
| | `capture_editor_viewport` | An image of the 2D/3D viewport. |
| Edit scenes | `add_nodes` | A whole subtree in one call and one undo step: nested nodes with type, properties, script, groups and instanced scenes. Nothing is created if one item is invalid. |
| | `duplicate_node` | Copies a node with its children, script, groups and properties; next to the original or under another parent. |
| | `add_node`, `set_properties`, `remove_node`, `reparent_node`, `rename_node`, `connect_signal`, `instantiate_scene`, `open_scene`, `save_scene` | Edits on open scenes, each one an undo step in the editor. |
| Edit files | `create_scene`, `attach_script` | New scenes and scripts on disk (`.gd`, or `.cs` in Godot .NET, created as a partial class named like the file). `create_scene` also takes the root's script and properties (exported variables included), so a scene is never written by hand. |
| Project | `set_project_setting`, `set_input_action`, `remove_input_action`, `set_autoload`, `remove_autoload` | Project settings, input actions (keys, mouse, joypad) and autoloads through the editor: each change is an undo step and saves `project.godot`. Editing `project.godot` by hand is rejected. |
| Asset Store | `asset_search`, `asset_details`, `addons_list` (read), `asset_install`, `plugin_enable` | Search the [Godot Asset Store](https://store.godotengine.org) for this Godot version, read an asset's page, license and releases, and list the project's plugins. `asset_install` downloads a release and writes only what goes in `addons/` (unless `include_other_files`), never overwrites a file and enables its plugins; it's in its own permission group, **Install from the Asset Store**, which asks in every mode. `plugin_enable` turns a plugin on or off (not the harness). `addons_list` with `check_updates` finds newer releases of the project's plugins, and `asset_install` with `update` replaces the installed version. Paid assets are bought on the store website. |
| Tilemaps | `tileset_add_atlas`, `tileset_add_scenes`, `tilemap_set_cells`, `tilemap_paint_terrain`, `tilemap_clear` (+ `tilemap_get` to read) | On a `TileMapLayer`: a texture becomes an atlas (tiles for every non-transparent cell, optional full collision), tiles by cell or rectangle, terrains already set up in the TileSet, and an ASCII map with a legend to read it. Each change is an undo step. |
| Animation | `animation_create`, `animation_set_track`, `animation_remove`, `sprite_frames_set` (+ `animation_get` to read) | Animations of an AnimationPlayer with value tracks (keys converted to the property type) and method tracks; SpriteFrames of an AnimatedSprite2D/3D from images or a sprite sheet. Each change is an undo step. |
| Resources | `create_resource`, `set_resource_properties` (+ `get_resource` to read) | `.tres` files of a Godot class or a project `class_name`, with sub-resources inline (`{"type": "StyleBoxFlat", …}`) and typed arrays. Changes are an undo step and are saved. Writing a `.tres` by hand is rejected. |
| Files | `move_file`, `copy_file`, `delete_file` | Move or rename keeping the uid and rewriting every `res://` reference and the relative `preload`/`load`/`extends` paths of scripts; copy as a new resource (also from outside the project); delete only if nothing references it (to the trash). `mv`, `cp` and `rm` on project files are rejected. |
| Run | `run_scene` | Runs a scene (with simulated `inputs` if you want) and returns the real errors. |
| | `capture_game_frame` | A frame of the running game. |
| | `stop_scene` | Stops it. |
| Live game | `game_tree`, `game_get` (read), `game_set`, `game_call`, `game_wait`, `game_input` | With the game running (launched by `run_scene`, or a manual run with «Use the playtest autoload also when running the game manually»): the live node tree, read and change properties, call methods, wait until an expression is true or a signal is emitted, and send keys, actions, clicks and joypad input, by time or by physics frame (the same sequence plays the same at any framerate). Changes are live only; the scene files stay as they were. Game errors raised meanwhile come back with the result. |
| | `game_find`, `game_ui` (read), `game_ui_act` | Find nodes by class, group or name. See the game's texts and controls with their ids, and use them with a real click: something on top of a control blocks it and comes back as an error. |
| | `game_pause`, `game_step` | Pause the game and advance it exact physics frames with input: play turn by turn, even a fast game. |
| | `game_script` | A short GDScript that runs inside the game: many reads and inputs in one call, reacting in the same frame. It stops at its timeout, lets go of the keys and can't use files or start processes. |
| | `game_watch`, `game_frames` (read) | What changed in some nodes during a time window, with times, and the frames of the last seconds (with `film_fps` on `run_scene`). |

## Details

- **Undo**: each scene edit is one step of the editor's undo. The tool card in the chat has **↶ undo** while nobody has touched the scene afterwards.
- **Open scenes**: the agent is told to edit open scenes through these tools, never on disk.
- **Playtests**: `run_scene` adds a temporary autoload that captures errors, frames and simulated input, and removes it as soon as the game starts. If the editor dies mid-playtest, the next start cleans it up. The export never includes it.
- **Limits**: **Settings → MCP server** sets the characters per result and the maximum image side, plus extra folders outside the project that the agent may read and write.
- **Security**: the server only listens on `127.0.0.1`, requires a token that changes on every start (**Regenerate token** in Settings), and the log masks it.
