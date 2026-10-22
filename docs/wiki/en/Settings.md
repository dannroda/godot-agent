# Settings and profiles

[Home](Home.md) · [Español](../es/Settings.md)

Open **Settings** from the dock header.

| Section | What's there |
|---|---|
| **Agents** | Agent profiles (see below). |
| **Completion** | [Inline completion](Inline-completion.md). |
| **Permissions** | The [permission matrix](Modes-and-permissions.md#permissions) per mode, and the timeout to answer. |
| **MCP server** | Port, **Regenerate token**, result limits, compact tool list, extra folders. |
| **One-shot and quota** | Default budgets, checkpoints, spec review, loop repeats, QA rounds, game criteria (weight and minimum), quota warning and pause thresholds, what to do when the quota resets. |
| **Interface** | Accent color, dock position, language. |
| **Export** | Checks that every export preset excludes the addon. |

## Where everything is stored

| What | Where | Scope |
|---|---|---|
| Agent profiles, MCP port, quota, accent color, dock position, language, completion (including LLM profiles, without keys) | `EditorSettings`, prefix `godot_agent/` | you, all projects |
| Permissions, budgets, checkpoints, loop threshold, criteria, tool limits, extra folders, project completion options | `res://addons/godot_agent/config/project_config.tres` | the project (can be committed) |
| Session history | `user://godot_agent/sessions/` | you, this project |
| One-shot runs (state, last capture, reports; the last 20) | `user://godot_agent/oneshot/` | you, this project |
| Spec, progress and QA of each run | `.godot_agent/oneshot/<id>/` in the project | the project (travels in the agent's branch) |

The port, the accent color, the dock position and the language apply when you reopen the editor. Since Godot 4.8 the editor remembers where you left the dock, so the setting is only the initial position.

## Agent profiles

**Settings → Agents**: add, edit, remove and set the default. Each profile has a command, its arguments (one per line) and environment variables.

- **Keys**: in the environment, `NAME=$VARIABLE` takes the value of `VARIABLE` from the editor's environment when the agent starts. Settings refuses a literal value in variables with a secret-looking name (`*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`). Example: `ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY`.
- Included profiles:
  - **Claude Code**: `npx -y @agentclientprotocol/claude-agent-acp`;
  - **Gemini CLI**: `gemini`; add the argument your version uses for ACP, for example `--experimental-acp`;
  - **Codex**: no command; set it up with the ACP adapter you use.
- The agent always receives `GODOT`/`GODOT_BIN` with the editor's binary; a profile can override them.

## Export

An export plugin skips all of `addons/godot_agent/` and removes the playtest autoload, so the addon never reaches an exported game.

As a safety net, in case you export with the plugin disabled, add `addons/godot_agent/*` to the **exclude filter** of each preset (Export dialog, Resources tab). **Settings → Export** shows which presets lack it and adds it after asking. Restart the editor after using that button, because the editor keeps the presets in memory.

## Updating the addon

The project's config lives inside the addon folder. To update:

1. Keep `addons/godot_agent/config/project_config.tres` if it exists, and `config/system_prompt.md` or `config/quota_patterns.txt` if you edited them.
2. Delete `addons/godot_agent/` and copy the new version.
3. Put those files back in `config/`.

User settings (`EditorSettings`) and history (`user://`) aren't touched when you replace the folder.
