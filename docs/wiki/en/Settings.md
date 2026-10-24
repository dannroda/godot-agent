# Settings and profiles

[Home](Home.md) · [Español](../es/Settings.md)

Open **Settings** from the dock header.

| Section | What's there |
|---|---|
| **Agents** | Agent profiles (see below). |
| **Completion** | [Inline completion](Inline-completion.md). |
| **Permissions** | The [permission matrix](Modes-and-permissions.md#permissions) per mode, the timeout to answer, and the [Auto mode](Modes-and-permissions.md#auto-mode) lists of shell commands. |
| **MCP servers** | [Other MCP servers](#other-mcp-servers) for the agent; for the addon's own server: port, **Regenerate token**, result limits, compact tool list, extra folders. |
| **One-shot and quota** | Default budgets, checkpoints, spec review, loop repeats, QA rounds, game criteria (weight and minimum), quota warning and pause thresholds, what to do when the quota resets. |
| **Interface** | Accent color, dock position, language, [updates](#updating-the-addon). |
| **Export** | Checks that every export preset excludes the addon. |

## Where everything is stored

| What | Where | Scope |
|---|---|---|
| Agent profiles, MCP port, MCP servers for all your projects, quota, accent color, dock position, language, completion (including LLM profiles, without keys) | `EditorSettings`, prefix `godot_agent/` | you, all projects |
| Permissions, MCP servers of the project, budgets, checkpoints, loop threshold, criteria, tool limits, extra folders, project completion options | `res://addons/godot_agent/config/project_config.tres` | the project (can be committed) |
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

## Other MCP servers

**Settings → MCP servers** lists MCP servers of other programs (Blender, a database, a web service…). The addon passes them to the agent when a session opens, next to its own `godot` server, so they work with any ACP agent. Changes apply from the next session.

- **+ Add server**: a name (letters, digits, `-` and `_`), where it's saved, and either a command with arguments and environment (stdio) or a URL with headers (HTTP; only for agents that accept HTTP servers, otherwise it's left out with a notice).
- **Saved in**: *This project* goes into `project_config.tres` (it can be committed); *All my projects* goes into `EditorSettings`. If both have a server with the same name, the project's wins.
- **Keys**: in arguments, environment and headers, `$VARIABLE` or `${VARIABLE}` takes the value from the editor's environment when the session opens, for example `Authorization: Bearer $SENTRY_TOKEN`. Values with a secret-looking name must use a variable, and the Agent Log hides the resolved values.
- **Import .mcp.json** adds the servers of the project's `.mcp.json` that aren't on the list yet.
- The checkbox turns a server off without removing it.

Claude Code also loads the servers of its own configuration (`claude mcp add`, `.mcp.json`, `~/.claude.json`). Type `/mcp` in the chat to see their status, reconnect them or turn them off.

The tools of each server ask for permission until you allow them: see [MCP servers of other programs](Modes-and-permissions.md#mcp-servers-of-other-programs).

## Extensions

The **Extensions** button in the dock header (next to Settings) opens a window with Claude Code's plugins, marketplaces, every MCP server the agent sees and the project's Godot addons. Changes apply right away through the Claude Code CLI (`claude`), with the agent profile's environment (for example `CLAUDE_CONFIG_DIR`). If `claude` isn't in the `PATH`, the window uses the one the ACP adapter downloads with npx.

- **Plugins**: the installed ones with an on/off switch, **Update** and **Uninstall**, their scope and the MCP servers each one brings (colored by their status); below, the available ones from your marketplaces, the most installed first, with a search box and **Install** (in the scope chosen at the top: user, project or local). If a plugin needs to run a command of its marketplace to install, the window shows the command and asks first.
- **Marketplaces**: add one (a GitHub `owner/repo`, a URL or a folder), update it or remove it.
- **MCP servers**: the addon's own servers from [Other MCP servers](#other-mcp-servers) and the ones Claude Code loads (user, project `.mcp.json`, local, claude.ai and plugins), each with its status: connected, needs auth, failed, pending approval, not configured. **Authenticate** runs `claude mcp login`, which opens the browser. In a session, `/mcp` in the chat reconnects or turns off a server.

- **Godot addons**: the editor plugins in the project's `addons/` with an on/off switch (the harness itself has none), and a search of the [Godot Asset Store](https://store.godotengine.org) for this Godot version, sorted by relevance, recent updates, reviews or newest. **Install** downloads the newest stable release and shows what it will write before touching the project: only the `addons/` folder (zips often carry demos, a README or even a `project.godot`; a checkbox adds them), never overwriting a file that already exists, and **Enable its plugins** turns them on once the editor has imported the files. Paid assets are bought on the store website.

Plugins load when a session opens: after a change, the window offers **New session**. Plugins and marketplaces are Claude Code's; with another agent profile those tabs say so.

## Export

An export plugin skips all of `addons/godot_agent/` and removes the playtest autoload, so the addon never reaches an exported game.

As a safety net, in case you export with the plugin disabled, add `addons/godot_agent/*` to the **exclude filter** of each preset (Export dialog, Resources tab). **Settings → Export** shows which presets lack it and adds it after asking. Restart the editor after using that button, because the editor keeps the presets in memory.

## Updating the addon

When the editor opens (at most once a day), the addon checks the [releases](https://github.com/dannroda/godot-agent/releases) on GitHub. If there's a newer version, a notice shows up at the top of the dock:

- **What's new**: the release notes.
- **Update**: after you confirm, it downloads the release, checks that the zip is that version, saves the open scenes, closes the agent session, replaces `addons/godot_agent/` and restarts the editor.
- **Later**: hides the notice for that version.

**Settings → Interface → Updates** has **Check now** and turns off the check when the editor opens.

The update keeps `config/project_config.tres` (the project's config). If you edited `config/system_prompt.md` or `config/quota_patterns.txt` and the new version changes them, your copy is saved in `user://godot_agent/update/backup-<previous version>/` before replacing it (the Output panel says where). Files you added to the addon folder that aren't code stay. User settings (`EditorSettings`) and history (`user://`) aren't touched.

If `addons/godot_agent` is a link to a clone of the repository, or `addons/godot_agent_dev/` is next to it, the addon is a development copy: it doesn't update itself, update it with git.

To update by hand: keep `config/project_config.tres` and the `config/` files you edited, delete `addons/godot_agent/`, unzip the new version and put those files back. The version is in **Project Settings → Plugins**.
