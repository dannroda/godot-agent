# Changelog

All notable changes to Godot Agent Harness. The release workflow publishes the **Unreleased** section as the release notes and turns it into the new version's section, so write entries here, in English, as changes land.

## [Unreleased]

### Fixed

- In a narrow dock, the composer's bottom row no longer cuts off the model selector and **Send**: it compacts step by step (**Send**/**Stop** as just the symbol, then without the context counter and the `/`, `@` and screenshot buttons, and finally shortening the model name with "…").

## [0.1.5] - 2026-10-23

### Added

- The README has a quick start with screenshots, in English and Spanish.
- MIT license and a contributing guide (`CONTRIBUTING.md`).

### Changed

- Everything in the release zip is inside `addons/godot_agent/`: the READMEs, the changelog and the license travel with the addon instead of landing next to it in your project.

### Fixed

- A long first line of the agent's thinking no longer makes the chat wider than the dock, which cut off the right side of every message.

## [0.1.4] - 2026-10-23

### Added

- **Updater**: when the editor opens (once a day), the addon checks GitHub for a new release and shows a notice in the dock with the release notes and **Update**, which downloads it, replaces `addons/godot_agent/` (keeping `project_config.tres` and backing up your edited `system_prompt.md` / `quota_patterns.txt`) and restarts the editor. **Settings → Interface → Updates** has **Check now** and turns the check off.

## [0.1.3] - 2026-10-23

### Added

- **Extensions** window, from the dock header: install, enable, update and uninstall Claude Code plugins, search the plugins of your marketplaces, add and remove marketplaces, and see every MCP server the agent loads with its status (connected, needs auth, failed), with **Authenticate** for the ones that need it.

## [0.1.2] - 2026-10-23

### Added

- **Settings → MCP servers**: MCP servers of other programs (Blender, a database, a web service…) for the agent, per project or for all your projects. They're passed to the agent over ACP, so they work with any agent. Keys go as `$VARIABLE` from the editor's environment; **Import .mcp.json** brings the project's servers.
- Each MCP server other than `godot` has its own row in the permission matrix (Ask by default). Its permission card can allow it for good in the current mode, and a One-shot warns at the start about servers that would ask.
- MCP tools show up as `server.tool` in the chat (for example `blender.get_objects_summary`).

## [0.1.1] - 2026-10-23

First public release.

### Agent chat in the editor

- **Agent** dock that talks to any [ACP](https://agentclientprotocol.com) agent: Claude Code (default, through `@agentclientprotocol/claude-agent-acp`), Gemini CLI, Codex or a custom command. Sign in from the dock, session history, model selector, slash commands, and `@` mentions of nodes and files.
- Five modes in a selector next to the model: **Ask**, **Review**, **Build**, **Auto** (Build that runs allowlisted shell commands without asking) and **One-shot**.
- The agent's Markdown is rendered: tables, lists with hanging indent, quotes, headings, links (`file.gd#L42` opens the script at that line), and code blocks with syntax highlighting and a copy button.
- Screenshots the agent takes open full size with a click: zoom, pan and **Save PNG…**.
- Attach the viewport or the running game as an image, paste images and files, or drag them from the FileSystem.
- Messages written while the agent works are queued; **Send now** on a queued message stops the current turn and sends it right away.
- Plan quota and context usage as rings next to the composer, with the reset time.
- Remote Control: continue the session from claude.ai/code or the phone, with a QR code of the link.
- **Agent Log** bottom panel with every ACP, MCP, file, permission and process message.

### Editor tools for the agent (MCP)

- Read scenes, scripts, the selection, errors and the API of the running Godot version.
- Edit scenes and nodes, resources, project settings, input actions, autoloads, tile maps, animations and sprite frames; every change is one undo step.
- Run the game with simulated input, read and change live nodes, wait for conditions and capture frames.
- Move, copy and delete files keeping uids and `res://` references.

### Safety

- Permission cards per mode; Auto mode with editable shell allow and ask rules, and a tester in Settings.
- Rejected without asking: shell commands that write project files, hand-written `.tscn`/`.uid`/`.import`, and Godot launched from the shell without `--headless`.
- Scripts written by the agent and `project.godot` changes are synced into the open editor without the "modified outside" dialog.
- Nothing from the addon reaches an exported game; the harness never merges, pushes or stores keys.

### One-shot

- Pursues a whole goal with a spec, a plan, budgets (quota, time, tokens, playtests), git checkpoints with "Go back here", playtests with captures and a QA evaluator.
- Pauses and resumes around plan limits, can switch accounts, and writes a measured report at the end.

### Review and completion

- **Review** mode: findings as marks in the Script Editor with **Apply fix** and export to `CLAUDE.md`.
- Inline completion in the Script Editor: local (rules, project index, n-gram) or with an LLM (Ollama, llama.cpp, Codestral, OpenAI-compatible, Gemini).

### Interface

- English and Spanish; follows the editor language.
- Requires Godot 4.6 or newer; tested on 4.6.3, 4.7.2 and 4.8-beta1.
