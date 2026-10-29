# Changelog

All notable changes to Godot Agent Harness. The release workflow publishes the **Unreleased** section as the release notes and turns it into the new version's section, so write entries here, in English, as changes land.

## [Unreleased]

### Changed

- The One-shot main screen (top bar, next to 2D/3D/Script) is now called **One-shot** instead of **Agent**, so it no longer shares its name with the dock.
- In Review mode, the `findings` JSON the agent writes is folded in the chat into one line ("2 findings · in the Review panel and the Script Editor"); a click shows the JSON.
- A session in another tab shows one editor notice while it waits for you, not one per permission or question.
- **Dock**: one row of controls on top: the agent chip with its state (click to pick the agent), the title, history, **+** (new session or new tab) and **⋯** (Extensions, Settings, Remote Control, sign out). The tab row shows up once there are two sessions. The agent's text no longer sits in a box, and editor tools show names for people ("Connect signal") in aligned columns, with their output nested.
- **Composer**: **+** holds mentions, game images and agent commands; the mode is a pill; the context used moves into the quota ring's tooltip and comes back to the row from 80 %.
- With no session, the dock lists the project's previous sessions with **Continue**. **Settings → Interface → When the editor opens** can continue the last one instead.
- With no agents, the dock suggests Claude Code, Codex and Google Antigravity with what each needs, and the composer says to add one first. Settings → Agents suggests the same, and with agents shows the list next to the form, with a star for the default.
- Signing in is a neutral card with the main method as a button and **Other ways to sign in**, instead of a red error with six buttons.
- Agent errors say what happened in plain words, show the last lines of the agent's output with **Copy**, and offer the fix (**Edit the agent**, **Reinstall…** for agents downloaded from the ACP registry). **Open the log below** jumps to the error's line, highlighted.
- What a turn changed is a footer line with **View changes** and **Undo turn**.
- **Settings**: Save and Cancel sit together on the right and a dot marks sections with unsaved changes; permission cells are colored, changed ones are highlighted and each column has a reset; MCP servers and Completion keep their fine-tuning under **Advanced**; the plan quota has its own section; Export says to create a preset first.
- **ACP registry**: added agents first, then the suggested ones, then the rest; each card says how it installs (npx, uvx or a download, with its size when the registry has it). The suggested agents have their own translated descriptions.
- **Extensions**: Skills has a scope filter, **+ Skill** that asks where, and the actions in a **⋯** menu; Instructions lists the files with who reads each one; tabs without an agent say so and offer to set one up; lists show placeholder rows while loading. **Godot addons** is now **Project addons**: the installed plugins first, and the Asset Store search on demand.
- **One-shot**: the form says which agent runs it and what's missing to start, and uses two columns (goal with examples, and the agent, budgets and options).
- **Alt+I** while waiting shows the request, the agent, a spinner and the elapsed time.
- An agent's question no longer shows a second time as a tool.

### Fixed

- Reinstalling an agent from the ACP registry deletes the installed version first; before, adding it again reused what was on disk.
- With an unfinished One-shot and no saved agents, the dock offers **Resume One-shot** again.
- The old **Gemini CLI** preset and the **Codex** preset without a command, left over from versions before 0.1.8, are removed once from Settings → Agents and the dock's agent selector. A profile you edited stays.

## [0.1.8] - 2026-10-28

### Added

- **Agent terminals**: agents that run their commands through the editor (ACP `terminal/*`, used by Codex and others) go through the same shell rules as the rest: the mode's permission, the Auto lists, and the guards that block writing scenes by hand or opening Godot in its own window. The output shows live in the tool card. A command that sets environment variables always asks, and the card shows them.
- **Agent forms and links** (ACP elicitation): when the agent needs an answer (text, options, a confirmation) or wants you to open a link to finish something, it shows as a card in the chat. Only web links (http/https) are accepted, and the address is shown before you open it. A session in another tab shows **⚠** and a notice while it waits for your answer.
- **Agent sessions in the history**: for agents that keep their own sessions (such as Google Antigravity), the history menu also lists them and resumes them. Deleting a session asks first, and deletes it in the agent too when it supports that.
- **Sign out** in the status line, for agents that support it (Claude Code, Google Antigravity).
- **Quota for more agents**: Google Antigravity (each model group in the quota ring's tooltip), Codex (its 5-hour and weekly limits), and the limit errors of OpenCode, Copilot and Cursor.
- The Extensions window works with every agent profile, not only Claude Code: skills, instructions, rules and workflows in the folders each agent reads (Codex, Google Antigravity, Copilot, Cursor, OpenCode), and the MCP servers from their config files.
- On first launch there are no preset agents: the dock offers **Set up an agent…**, which opens Settings → Agents.

### Changed

- Adding an agent from the ACP registry shows the download progress, has no timeout for big programs, and reuses a version that's already installed.
- Agent errors show their details, and **Open the log below** reopens the panel even when it was closed.

### Fixed

- Godot 4.8 crashed when closing the editor with the plugin enabled.
- An agent could cancel a request and still have a command start.

## [0.1.7] - 2026-10-27

### Added

- **Skills** tab in the Extensions window: Claude Code's skills of the project (`.claude/skills`), of the user and of the installed plugins, with their description. A switch turns a user or project skill off for this project (from the next session the agent doesn't see it and it leaves the `/` menu; plugin skills go with their plugin). Create a skill from a template, import a skill folder or a zip, copy a user skill into the project, and install the Godot skills of the [godot-agent marketplace](https://github.com/dannroda/godot-agent-plugins) with one click.
- **Subagents** permission group and a **Subagents at once** limit per mode (Settings → Permissions): Claude Code's subagents can be denied or asked for in a mode, and one past the limit is rejected with a notice. The chat follows each subagent through its own session (its prompt, tools, text and report, also for one in the background), and the status line counts the ones running.
- **Several agent sessions at once**, each in its own tab of the dock (**+** opens another). They don't step on each other: a file one session writes in its turn is off limits to the others until that turn ends, the game runs for one session at a time (another's `run_scene` waits in line), and `godot.sessions` / `godot.session_send` let the agents see what the others are doing and leave each other messages.
- **From a GitHub PR…** in the Review findings: the review comments of a pull request (with the `gh` CLI) become findings marked in the Script Editor, ready for **Fix in Build mode**. Optionally (off by default), closing a separate copy can push its branch and open a pull request.
- **New session in a separate copy** (the **+** of the session tabs): the agent works in a git worktree of the project on its own branch, outside the project folder, without touching the open editor. Closing its tab offers to apply its changes to the project (uncommitted, without a merge), keep the branch or discard it.
- Mentions that bring context when you send: `@errors`, `@output`, `@game` (the running game's tree) and `@docs:Class`. Nodes dragged from the Scene dock into the composer are written as `@path`.
- **Instructions** tab in the Extensions window: read and edit the project's `CLAUDE.md`, `AGENTS.md` and `GEMINI.md`, and add the project facts the harness reads on its own (autoloads, named layers, input actions, main scene, folders), which update in place.
- **Save report** in the end-of-turn notice: a folder with `report.md` (what the agent said and the files it changed) and the screenshots it took during the turn, to look at later or share.
- **Alt+I in the Script Editor** (or right-click → **Ask the agent to change this…**): ask the agent for a change to the selected code; its answer shows as a diff next to the code, to accept (one Ctrl+Z step) or reject.
- **Changes of each turn** (Build and Auto, in a git repo): a turn that changed files ends with a notice to **View changes** (each file with its diff and **Go back**) or **Go back to before this turn**, which can be undone. The snapshots are git commits outside your branches; your branch, index and stash are not touched.
- **+ From the ACP registry…** in Settings → Agents: pick any agent of the public ACP registry (Claude, Codex, Gemini CLI, Copilot, Cursor, Google Antigravity, Goose, OpenCode and more) and the harness creates its profile, running it with `npx`/`uvx` or downloading and checking its program for this platform.
- A session tab shows **⚠** while it waits for your permission, and the editor shows a notice when that session isn't in view.
- **Check after each turn** (Build and Auto): when a turn ends, the scripts that changed are validated; if one doesn't parse, the agent gets the errors to fix them (up to two turns in a row), otherwise they stay as a notice. On by default; Settings → MCP servers.
- Session tabs can be renamed (double-click a tab): the name is also how the agents refer to that session in `godot.sessions` and `godot.session_send`, so two sessions can't share it. Leaving it empty goes back to «Session N».
- The dock's status line shows the Claude Code account each session is signed in with (from `claude auth status`, so each agent profile shows its own); its tooltip adds the organization and the plan.

### Fixed

- The **+** that opens another session tab and the **Extensions** button were much smaller than the header's other icons.
- The status line's tooltip (the error, the running subagents) never showed.
- When Claude Code works on something the editor never received (a message from another of its sessions through `SendMessage`, or a background task that finished), the chat now says so instead of showing an answer with no question. The agent is told to use `godot.sessions` / `godot.session_send` with the other sessions in the editor: those messages show in the chat, and they also reach a session that has no prompt yet.
- Updating an addon from the Asset Store only replaces the folders that asset installed, and never writes inside the harness's own folders. A failed update turns its plugins back on, and an Asset Store result with an empty field no longer breaks the search.

## [0.1.6] - 2026-10-24

### Added

- **Godot addons** tab in the Extensions window: search the [Godot Asset Store](https://store.godotengine.org) for your Godot version, install an addon (only its `addons/` folder by default, never overwriting your files, with a preview of what it writes) and enable or disable the project's plugins. It also finds newer versions of the project's plugins and updates them: the addon's folder is replaced, files the new version dropped are removed and its plugins stay enabled. Installs are recorded in `.godot_agent/assets.json`; plugins installed by hand are matched with the store by name.
- The agent can search the Asset Store, suggest addons and install them (`godot.asset_search`, `asset_details`, `asset_install`, `addons_list`, `plugin_enable`), and find and apply plugin updates (`addons_list` with `check_updates`, `asset_install` with `update`). Installing has its own permission group, **Install from the Asset Store**, which asks in every mode, Auto and One-shot included.

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
