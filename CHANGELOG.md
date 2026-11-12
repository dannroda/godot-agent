# Changelog

All notable changes to Godot Agent Harness. The release workflow publishes the **Unreleased** section as the release notes and turns it into the new version's section, so write entries here, in English, as changes land.

## [Unreleased]

### Added

- **The agent asks to switch modes**: with the new `godot.request_mode`, the agent proposes moving its session to another mode, fixed or one of the [project modes](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#the-agent-asks-to-switch-modes), with a one-line reason. You decide on a card that shows in every mode, Auto included, with no "always"; it warns when the target can do more without asking (Ask → Build, a mode that limits files → one that doesn't). On **Switch**, the agent gets the new mode's rules in the same turn. Denied in One-shot. The system prompt lists the modes with their "when to use" line.

### Changed

- Tested on Godot 4.8-beta3 (was 4.8-beta2), besides 4.7.2 and Godot .NET 4.7.2. 4.8-beta3 still prints the `list.h` error when saving with preview.

### Fixed

- **Tooltips in the composer bar and the dock header no longer close right after opening** while the agent works. Context, plan list, mode, model, Send/Stop, the plan quota, the agent chip and the machine chips all stay open. The context percentage no longer changes width with every update, so the bar stays still under the mouse. Tooltips whose text keeps updating (context, the age of each state) show what they had when you hovered; hover again for the latest.

## [0.1.24] - 2026-11-12

### Added

- **Project modes**: a mode with its own name ("Level design", "Shaders") on top of Ask, Review, Build or Auto, saved as a `.json` in `res://agent_modes/` and shared through git. It lists the files the agent may write (`"editable": ["res://levels/**"]`): any other write is rejected without a card, from the agent's own tools, `fs/write_text_file` or the `godot.*` tools, and shell commands, project tools and other MCP servers always ask, even with base Auto. Its instructions go to the agent's system prompt. It never allows more than its base mode. The composer's mode selector lists them under **Project modes**, as **Level design (Build)**. The folder is in Settings → MCP servers → Advanced and is left out of exports. The model you pick in a project mode is remembered for it, like the fixed modes. **Extensions → Modes** lists and checks them, with three templates. In One-shot, **Builder's project mode** applies one to the builder: what it would make ask is denied instead (a line under the selector says so) and the report lists each denial; verifying the game keeps working. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#project-modes).

### Changed

- **Plans built by an agent that doesn't send its task list** (Antigravity): the plan card now says **Progress not tracked** when the build turn ends without one. Before, it looked as if nothing had been done. The dock doesn't guess progress from the files the agent edited, since several tasks often touch the same file.

## [0.1.23] - 2026-11-12

### Added

- **Ctrl+Enter** in the composer sends and follows the agent: the editor jumps to what it edits during that request, and following turns off by itself when that turn and anything queued after it end. Touching the crosshair keeps your choice; if following was already on, it stays on. **Shift+Enter** still adds a line (Ctrl+Enter no longer does). See [Getting started](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Getting-started.md#3-the-dock).
- **Keep or reject a turn's changes from the Script Editor**: a script the agent's last turn changed shows each change in the gutter, with a bar on its lines and **✓** / **✗** on the first one. **✓** keeps it, **✗** rejects just that change (the same as **Reject** in **View changes**: changes whose lines were edited afterwards, files with unsaved changes and files another session is editing are left alone), and **✗** again puts it back. The status bar under the code counts what is left and says why a change couldn't be rejected. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#changes-of-each-turn).
- **Verify a plan's acceptance criteria by playing**: when you approve a plan with criteria like "WHEN the player touches an enemy, THE GAME SHALL take one life away", after the build an agent plays the game once per criterion, in Review and without changing the project. Failed criteria go back to the agent with what the playtest saw, and only those are played again after the fix (up to two times). A criterion that couldn't be checked is marked ⊘ and isn't retried. The plan card has a **Verify the criteria by playing (N)** checkbox, on by default, that says each criterion is one playtest, and then shows each criterion's state. A final notice sums it up (**4 ✓ · 1 ✗ · 1 ⊘**), and the saved plan gets a `## Verification` section. Up to 6 criteria per plan; the limit and the default are in Settings → MCP servers → Advanced, and **Verify the rest** plays the criteria past the limit. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#verifying-the-criteria-by-playing).
- **Rules by file**, with any agent: a rule in `.agents/rules` (`trigger: glob`), `.claude/rules` (`paths:`) or `.cursor/rules` (`globs:`) now reaches the agent when a turn touches a file that matches it: at the end of a `godot.*` tool's result in the same turn, or with your next message. Each rule goes once per session, as a project instruction like `CLAUDE.md`, and the chat shows **rules: …** under your message. Rules the active agent already loads on its own (Claude Code's `.claude/rules`, Antigravity's `.agents/rules`) aren't sent again, so Codex, Copilot, OpenCode and the rest get them too. The **Instructions** tab of Extensions shows each rule's patterns and who applies it, starts new rules in each format, and **Test** says which rules apply to a path. Turn it off in Settings → MCP servers → Advanced. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#rules-by-file).
- **Several game instances at once** for multiplayer and parallel tests: `run_scene` with `instances` starts up to 4 instances of the scene, each with its own arguments (for example a server and its clients), optionally headless, with its own simulated device and inputs, its own window and its own `user://` folder. The game tools take `instance`, and the new `game_instance` lists them, adds a player while the game runs or drops one. Stopping the game stops them all; the temporary playtest autoload still never stays in `project.godot`. See [Editor tools](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Editor-tools.md).
- **Bake and export from the agent**: the new `bake` tool rebuilds the navigation of NavigationRegion2D/3D nodes after the level changes (one undo step), and bakes LightmapGI and OccluderInstance3D nodes with the editor's own Bake button (the scene must be saved; lightmaps need Forward+ or Mobile). `export_project` exports with one of your export presets in a separate headless Godot and reports errors, time and size; the build goes to a folder outside the project unless you ask for the preset's own path, `pack` checks that the project exports without needing templates, and a missing template gives a clear message. `export_presets.cfg` is never changed. See [Editor tools](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Editor-tools.md).

### Changed

- **Measure regressions** now puts each scene sabotage in place before the scene starts: the scene is instantiated with its `.tscn` values and connections, the sabotage goes on that copy, and only then does it enter the game. A value the game only reads in `_ready`, like a starting health, is now broken too, as if the `.tscn` had the change. Nothing is saved: the `.tscn` and the loaded scene stay as they were. Connections made by code are still not sabotaged.

### Fixed

- **Antigravity**: the plugin's own tools (`godot.run_scene`, `godot.add_node`…) no longer ask for a second permission. Antigravity names them `godot_run_scene`, and the dock didn't recognize them as its own: each one showed an extra card under Other, and a playtest stopped until someone answered it. They also show as `godot.run_scene` in the chat now, and tools from other MCP servers fall in their server's permission group, as with Claude Code.
- **Antigravity**: an edit you allowed no longer shows as failed when you deny the next one in the same turn. Antigravity then reports the edit it already applied as failed too ("denied by pre-tool hook"), even though the file was written. Now an edit whose file the dock already wrote stays completed, with a note that says what the agent reported.

## [0.1.22] - 2026-11-12

### Added

- `capture_game_frame` can show the running game from somewhere else without moving the player's camera: from one of the game's cameras (`camera`), from a point looking at another (`look_from`, `look_at`), or from up to 8 angles around a point (`angles`). The views are rendered off screen and show the world without the game's UI layers.
- **Second opinion**: another agent, read only and without the conversation, reviews a turn's changes, a plan or your question. Pick it in **Settings → Agents → Second opinion** and ask from the footer of a turn that changed files, **Second opinion…** in the plan card, `/second-opinion [question]`, or let the agent call `godot.ask_second_opinion` (the new **Second opinion** permission: Ask, denied in One-shot). It runs in its own session without a tab; reading and diagnostics are allowed and everything else is denied in every mode. A chip shows it working, the answer comes as a folded notice with its tokens, and it reaches the tab's agent only with **Send to the agent**, always inside an untrusted envelope, never as instructions. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#second-opinion).
- **Recipes**: save a request you repeat (a new enemy from a base scene, an options screen, porting a script to C#) as a `.json` in `res://agent_recipes/`, with typed parameters and checks the result must pass. `/recipe <name>` or **+ → Recipe…** opens a form generated from its parameters (text, choices, numbers, yes/no, files with a picker, nodes of the open scene, input actions); **Use** puts the request in the composer, in the recipe's mode, without sending it. After each turn the recipe's checks run (playtest regressions, a command, or a **playtest** where an agent plays to check a goal and passes on a pass verdict) and failures go back to the agent up to the recipe's retry limit. **Plan first** sends it as `/plan`, and the checks start with **Approve and build**. A check's command only runs on a machine where it was approved, so a recipe from someone else's repository runs nothing on its own. The **Recipes** tab of Extensions lists them with their problems, edits the `.json` with live validation and creates new ones from three templates. The folder is in Settings → MCP servers → Advanced and is left out of exports. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#recipes).
- `capture_game_frame` and `capture_editor_viewport` can show the running game or the open scene from somewhere else without moving the player's camera or your view: from one of the game's cameras (`camera`), from a point looking at another (`look_from`, `look_at`), or from up to 8 angles around a point (`angles`). The views are rendered off screen and show the world without the game's UI layers.
- Saved playtest regressions can check the game **on every physics frame** and **measure its performance**: `game.invariant(name, check)` fails the regression at the first frame where the check breaks, with the frame and the value, and `game.budget(metric, limit)` covers `frame_ms_p95`, `physics_ms_p95`, `draw_calls_max`, `nodes_max` and `orphans_end`. A budget without a limit is compared with the baseline the first passing run recorded: counts share one baseline, saved in the regression, and fail above it; times compare with the machine's own baseline, kept in the project's user folder outside the repository, and only warn (for example "frame_ms_p95 2.1× this machine's baseline"). **Measure regressions** says how many mutants the invariants and budgets caught.
- **A model for each mode**: the model you pick in the composer is remembered for the tab's mode, per agent profile, and switching back to that mode picks it again. Plan in Ask with one model and build with another; **Approve and build** switches to Build's model in the same turn. It's your setting, not the project's; **Settings → Agents** lists it with **Forget**. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#a-model-for-each-mode).
- **Project tools**: a project can give the agent its own tools in GDScript. Each `res://agent_tools/<name>.gd` that extends the addon's `agent_tool.gd` (with a description, a JSON schema for its parameters and `_run(args, ctx)`) becomes `godot.<name>`, which the agent finds with `godot.methods` and calls with `godot.run`; an edited tool is used from the next call. A tool is code that runs inside the editor, so it only loads on a machine where its code was approved: a notice names the tools that aren't, with **Approve…** showing the code first, and any change (also by the agent) asks again. Each call asks for the new **Project tools** permission (Ask in Build, One-shot and Auto). The **Tools** tab of Extensions lists them, the folder is in Settings → MCP servers → Advanced, and the export leaves it out. See [Editor tools](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Editor-tools.md#project-tools).
- **Measure regressions** in the review panel checks whether your saved playtest regressions would catch a bug: it makes small changes to the game's scripts (a flipped comparison, a deleted line, a changed number), one at a time and only in the memory of a separate headless Godot, and runs the regressions against each. The result gives a score, the changes nobody noticed (with **Open** at the line) and what each regression caught; the project's files are never written. It also sabotages the regressions' scenes in memory: an exported property set to 0/false/null, a signal connection cut, a node hidden or a collision shape disabled, picking the nodes each regression names. From the command line: `regression_cli.gd -- --mutate[=N] [--min-score=P]`.
- **Project hooks**: run a command, a read/check `godot.*` tool, or ask the agent when a scene or script is saved, a game ends, playtest regressions finish or an export starts. Prompts wait for **Send to the agent** unless you turn on **Send it on its own** (at most 2 in a row). Hooks live in the project's settings and only run on a machine where they were approved. Settings → MCP servers → Advanced → **Project hooks**; see [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#project-hooks).
- When the editor is in the background, a finished turn or an agent waiting for your permission or answer makes the editor window ask for attention, with a desktop notification on Linux (if `notify-send` is installed) and macOS. On by default; turn it off in **Settings → MCP servers → Advanced**. See [Settings](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Settings.md).
- **Ask the agent** in the right-click menu of the FileSystem dock, the Scene dock and selected code in the Script Editor puts the files or nodes (as `@path`) or the selected lines (as a code block with the file and line numbers) in the active tab's message box, without sending it. See [Getting started](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Getting-started.md#3-the-dock).
- With Antigravity, the chat warns once per project that Antigravity writes its own skill to `skills/system/run-workflow/SKILL.md` in the project every time a session opens. The adapter can't be told to put it elsewhere; add `skills/system/` to `.gitignore`. See [Troubleshooting](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Troubleshooting.md).
- **Memory** in Extensions shows what is remembered about the project in one place, each entry editable or deletable: what you saved with `/remember`, what playtests learned (notes, findings marked not a bug, saved scripts), handoffs and approved plans, and Claude Code's own memories of this project for the tab's account (read only when you open the tab; deleting one moves it to the trash). `/remember <fact>` (alias `/recordar`) saves a line in a marked section of the active agent's instructions file (`CLAUDE.md`, `AGENTS.md`…), without touching the rest; the chat shows **Undo** and **View memory**, and the running session gets the fact with your next message, as data and not as instructions.
- **View changes** lets you review a turn's changes one by one: open a script with **▸**, then **Keep** or **Reject** each change. Rejecting undoes only that change in the file, even if the file was edited elsewhere after the turn, and **Undo** puts it back. A change whose lines were edited after the turn is marked and left alone, as is a file with unsaved changes in the editor or one another session is editing. **Reject all in this file** rejects what it can. A scene opens by node: a changed property, an added, removed, moved or renamed node, a node's type, groups or instanced scene, and a signal connection can each be rejected on its own; a removed node comes back in its place among its siblings with the resources it used, and the scene is checked to still load before anything is written. Works in a separate copy too. While the turn runs, a counter above the composer shows what changed so far (**3 files · +42 −7**); click it to look at those changes. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md).
- **New session with a summary**: near the context limit (85 %), a strip above the composer offers to continue in a new session; it also shows in the **+** menu, as `/handoff [what to do next]`, when you click the context percentage once it turns yellow, and in a notice when the agent compacts the conversation. The agent writes a short handoff (goal, done, remaining, decisions, open questions) and a new tab opens with the same agent, account and mode, with that summary in the composer to review before sending. What the harness takes from the session history (requests, last plan, files touched) goes as an attachment marked as context, not instructions. If the agent can't answer, the new session gets only that. Each handoff is saved in `.godot_agent/handoffs/<date>-<session>.md`, and an empty session offers the latest one (**See others** lists the rest).
- `@session:<id>` in the composer brings another session of this project into the message: the `@` menu lists the sessions in the history, and when you send, the harness puts together its requests, last plan, files its tools touched and the agent's last message (up to 3000 characters), marked as context and not as instructions. It works with closed sessions and sessions of another agent. The chat shows it as an attachment with the session's title.
- When the agent compacts the conversation (Claude Code), the chat shows it as its own row: **Compacting the conversation…**, then **Conversation compacted** with the summary the agent kept, folded. A compaction in the middle of a turn stays where it happened, and **New session with a summary** is offered when the turn ends. The row is saved in the history and shows again when you reopen the session.
- A playtest stops when the agent is stuck in a loop: the same game calls (the same keys, the same capture, the same error) several times in a row with the game answering the same every time. On the third time the tool result tells the agent; on the fourth the harness ends the turn and the verdict is **could not test**, saying what the agent was repeating, with the calls and what the game answered as evidence.
- **Export session…** in the dock's **⋯** menu saves the conversation as Markdown, with the game captures as PNG files next to it, in `.godot_agent/reports/<date>-session/`. Tool calls and diffs are folded. Before saving you see a preview and choose what to take out: absolute paths (the project's become relative and your home folder becomes `~`), email addresses, and content that came from the game, the project's scenes or the internet. Each option says how many it found. Secrets such as the MCP token are always removed.

### Security

- **Messages between sessions** (`godot.session_send`) could reach another tab without permission and as a plain prompt: an agent in Ask or Review (or one that had read planted text) could get a tab in Auto to act for it. Now each message asks for permission in its own **Messages to other sessions** group (Ask, denied in One-shot), reaches the other agent inside an untrusted envelope as data from that session, not as instructions, and a message to a session in a mode with more permissions is always denied, whatever the matrix says. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#messages-between-sessions).

### Fixed

- Closing the editor or disabling the plugin now ends every process the harness started, with its children (like `node` under `npx`). A process whose owner was only freed during shutdown, such as an agent terminal or a hook command, could keep running.

## [0.1.21] - 2026-11-11

### Added

- A scene's diff in **View changes** (and in the One-shot's and conflict diffs) is shown by node instead of as `.tscn` text: nodes added, removed, moved or renamed, properties changed with their value before → after, and signal connections. It compares the two scene files directly, so resource ids that Godot renumbers on save don't show up as changes, and a sub-resource is compared by its content (`shape.size`). **View raw** shows the text diff. Large changes are cut to 200 lines. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md).
- When the agent presents a plan from its plan mode (Claude Code's ExitPlanMode, in Ask or Review), the dock shows it as a plan card instead of a generic permission. **Approve and build** switches to Build mode and lets the agent start; its edits still ask for permission as in Build, and the agent's auto, bypass and *clear context* options are not offered. **Edit** lets you change the plan, with a live +N −M count, and sends the agent your changed lines and the whole plan so it presents it again. **Keep planning…** sends it a reason instead. Approved plans are saved in `.godot_agent/plans/`. The plan card doesn't time out. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#approving-the-agents-plan).
- **Plan** (an icon next to the mode selector, also in the **+** menu) and `/plan <request>` ask the agent for a plan before building. The plan has playable criteria, the design in Godot terms and numbered tasks. The session switches to Ask. Claude Code presents the plan with the plan card. Agents without a plan mode end their answer with a ` ```plan ` block, and the harness turns it into the same card: edit it, send it back with a reason, or approve it to build in Build mode, with the plan saved in `.godot_agent/plans/`. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#asking-for-a-plan-plan-and-plan).
- **Project checks after each turn** in Settings → MCP servers → Advanced: the saved playtest regressions, GUT or gdUnit4 tests, or any command, optionally only when files matching some patterns change. In Build and Auto they run after a turn that changes files; a failure goes back to the agent with its output to fix it (sharing the two-turn limit of the script check), and the footer notice shows ✓/✗ for each. They are saved with the project, so a command only runs on a machine where its exact text was approved: one you write in Settings is approved on save, and one that came with the project offers **Approve…** with the command shown first. Commands run without a shell. See [Modes and permissions](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Modes-and-permissions.md#project-checks-after-each-turn).
- **Deny with reason…** on every permission card: it denies, stops the agent's turn and sends it your reason right away, shown as a dimmed harness line. Without it the agent only learns it was denied, and Claude Code keeps trying in the same turn.
- `godot.run_scene` can simulate another device for one run with `device`: a preset (phone, tablet, Steam Deck, 1080p, 4K) or a window size, orientation, scale, touch from the mouse and locale, without touching `project.godot`. The agent can then check a HUD or translated texts in another aspect with `capture_game_frame` and `game_ui`. The report says what was applied, including when the project has no translation for the locale. When the game would run embedded in the Game view, that run opens in its own window and the embed option is left as it was.
- **Follow the agent**: a toggle in the dock header (off by default, per tab) makes the editor jump to what the agent edits, like following a collaborator: the script at the changed line, or the scene with the node it added, changed, renamed or moved selected. Only the active tab is followed, and it never jumps while you're clicking, dragging or typing in the editor: it waits until you stop and goes to the latest change. See [Getting started](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Getting-started.md).

### Changed

- Inline completion builds its project index the first time you open a script in the Script Editor, not when the editor starts or the addon is enabled. With no script open, nothing is indexed and file changes don't trigger a rebuild; on a large project this saves a background thread a few seconds of work at startup. If a script is already open when the editor starts, the index builds right away, as before.
- Enabling the addon in Project Settings › Plugins blocks the editor for about 75 ms instead of about 430 ms. The Settings and Extensions windows are now built the first time you open them, so the first open takes about 0.15 s longer.

### Fixed

- A tab that started a session with an agent that has no modes kept the modes of the tab's previous agent, and the harness asked the new agent to switch to modes it doesn't have.
- The One-shot screen could get stuck too wide when you made the dock wider: the form's scroll area asked for the width of the form, which was computed from that same area. The form now scrolls sideways when needed, and the area keeps a fixed minimum width.
- In a narrow dock with several tabs: with no session, the empty state names the agent and leaves the command line to the tooltip; sessions in a separate copy of the project are named «Session N» with a copy icon (the branch is in the tooltip) instead of a cut-off «(copy)», and the copy's notice is a card with the folder under a collapsible block with **Copy**.
- A permission or question card left unanswered kept its session's chat model alive after the session was gone.
- Disabling the addon right after enabling it, while it was still checking git, printed "A Thread object is being destroyed without its completion having been realized" in the Output. The git command now finishes and closes its thread on its own.

### Changed

- **Project MCP servers now need approval on each machine.** A server saved in *This project* comes with `project_config.tres`, so a cloned project could start any program when a session opens. Now it only starts on a machine where its definition (command, arguments, environment, URL and headers) was approved. If your project already uses project servers, after updating they are left out until you approve them: when a session starts, a notice names them and says why, with **Approve «name»…** for each and **Approve all…**, showing what each one runs first. They start from the next session. Servers you add or edit in Settings are approved when you save; ones imported from `.mcp.json` are not. *All my projects* servers don't change. See [Settings](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Settings.md#other-mcp-servers).

## [0.1.20] - 2026-11-11

### Added

- A playtest that passes now says it was **saved as a regression** and offers **Run regressions (N)** and **CI workflow…** right in the verdict; the first time, a short notice explains what regressions are, where they live and that the CI workflow runs them on every push.
- **Add** on Claude Code in the suggested agents now starts the session right away: no separate **Start session** click. The first time, `npx` downloads the agent (the status line says it is connecting, and after a few seconds that the first time takes a minute). With Claude Code the sign-in card appears at your first message, and after you sign in the message is sent again by itself. Install → sign in → first message is four clicks in the dock.
- While a game runs (launched by the agent or by you with F5/F6), or a One-shot is going, a small chip next to the status line above the composer says so without hovering: **Game · running · 12 s**, **One-shot · building · …**. It turns amber when the game is stopped in the debugger or the One-shot is waiting for you. A game you run by hand without the playtest autoload shows as **running, started by hand without the playtest probe**, and goes back to that after you continue it from the debugger. It reads the same states as the agent chip's tooltip, which keeps the detail.
- `godot.project_map` gives the agent a ranked map of the files most related to what it's working on (the scene and script open in the editor, or a `focus` it passes): each script's signals, public functions and exports with their lines, each scene's nodes and signal connections, and where each script is used. It follows the links Godot keeps in `.tscn` and `.tres` files, which a text search misses, and fits in a token budget, so the agent needs fewer calls to find its way around a large project. Plugins in `res://addons/` are left out unless the focus is in one of them.
- **Tools** in Extensions lists everything the agent can do through the addon's editor tools, by function (read the project, edit scenes, files, run and play the game, diagnostics, validation, project settings, resources, TileMaps, animation, API docs, Asset Store, profiler, sessions), with the short description the agent sees, the permission group and what each tool asks for in each mode (✓ · ? · ✗). A filter searches by name, description and permission; tools behind the compact list are marked. It opens from the dock's **…** menu (**What the agent can do (tools)…**) and from Settings → MCP servers → Advanced.
- Text that comes from outside the harness reaches the agent inside an `<untrusted nonce="…">` envelope with a new random nonce in each call, and the agent is told to treat it as data, never as instructions. This covers the game's Output and errors, what the game tools and `godot.run_scene` read from the running game (its UI texts, node names and why it paused), scene and resource texts and node names, Asset Store pages and what an install reports, the `@output` mention and the **Fix with the agent** prompt. A game or an asset that writes "ignore your rules and…" can no longer pass as an order, which matters most in Auto mode. The playtest audit also ignores detector and recording lines that the game printed itself.
- **Point at something in the game…** in the composer's **+ context** menu, while the game runs with the playtest autoload: the live capture opens, you click on a node, and it goes to your message as `@path` with the capture marked at that spot. It finds the control under the point, else the 2D body, area, sprite, polygon or tile, else the 3D body under the camera ray. The `@game` context and the agent's tools don't change.
- The editor's tools tell MCP clients which ones only read (`readOnlyHint`), which ones can overwrite or delete (`destructiveHint`) and which ones reach the internet (`openWorldHint`), based on their permission group. Claude Code runs read-only calls in parallel and can repeat one if the connection drops.
- Regressions can run several times each, to find the ones that depend on frame rate or chance. Set the **×** box next to **Run regressions** in the findings panel, or pass `repeat` to the agent's new `godot.run_regressions` tool. A regression passes only if every run passes. One that passes some runs and fails others is marked flaky with its count («passed 2 of 3»), and the button shows how many are flaky. See [Review](https://github.com/dannroda/godot-agent/blob/main/docs/wiki/en/Review.md#playtest).
- `regression_cli.gd` takes `--repeat=N`, and the CI workflow can pass it (`repeat` in `godot.write_regressions_workflow`). A flaky regression is reported as `FLAKY` but doesn't fail the run unless you add `--fail-on-flaky`. A regression that fails every run still fails it. When it runs once, a regression already marked flaky that fails is tried up to 3 times, and fails if none of them pass.
- When a game you run by hand (F5/F6, not through the agent) stops in the debugger with an error or ends with errors, the dock shows a notice with the error, the stack folded under **Errors and stack**, and **Fix with the agent**. The button sends the error and the stack to the active session as a harness prompt; nothing goes out on its own. One notice per run; runs started by the agent don't show it. Turn it off in Settings → MCP servers → Advanced.
- `godot.game_monitors` measures the running game for a few seconds: frame time (average, p95, max), draw calls, physics, and how nodes, objects and memory grew. It also lists the orphan nodes, grouped by name, class and script: nodes created and never added to the tree, or removed without `free()`. `godot.profile_run` only sees GDScript, so this is for a game that is slow because of rendering or physics, or that leaks nodes. `godot.run_scene` takes `monitors: true` to add the same summary for the whole run.
- The agent can use the script debugger. `godot.game_breakpoint` sets and clears its own breakpoints, `godot.game_stack` reads the call stack and a frame's local and member variables while the game is stopped at a breakpoint or an error, and `godot.game_debug` continues or steps (into, over, out). Its breakpoints only stop games the agent launches, not the ones you run with F5. Your breakpoints from the script editor are kept apart, and the agent can't clear them. When an agent session closes, its breakpoints go away and a game it left stopped goes on.

### Fixed

- Starting a session with an agent that has no modes, after one that had them in the same tab, kept the previous agent's modes, and the harness kept asking the new agent to switch to them.
- With Claude Code, a `godot.*` call that took more than about 60 seconds failed with "The operation timed out": a long `run_scene` or `profile_run` (up to 120 s), a GDExtension build or test, or any call while its permission card waited for you. A call that takes longer than 2 seconds now streams its answer and reports progress every 10 seconds, so it runs to the end. A call still running after 30 minutes answers with an error instead.
- The One-shot form no longer gets clipped on both sides when the dock is wide and the editor's center is narrow: the example goals wrap instead of forcing the form wider than the space it has.
- The findings panel counts say "1 bug" and "2 bugs", with the category name written out ("2 performance" rather than "2 perf"), and the chips wrap in a narrow dock.
- Prompts the harness sends for you no longer look like messages you typed. This covers One-shot's turns (the goal, *keep going with the plan*, QA and its fixes, the final report), the check after each turn, Review's questions, fixes and playtests, inline edits, what the crash supervisor saw and messages from other sessions. Each one shows as a dimmed line with a label in the interface language. **Show prompt** opens the text the agent got, which stays in English. Queued prompts show the same label. Sessions reopened from the harness's history keep the labels.
- A gamepad connected to your computer no longer interferes with the games the agent runs. Godot reads every gamepad on the system, even when another window has the focus, so a stick left tilted or drifting kept the arrow actions pressed. The player walked by itself, the UI focus jumped to another control, and a text field that got the focus didn't take the agent's typing, so the agent saw its input fail at random. Games launched by `godot.run_scene` (and `profile_run`, the regressions) now ignore real gamepads; the gamepad events the agent sends still work. Pass `real_gamepads: true` to play along with yours. `regression_cli.gd` and the test runner relaunch themselves without them.
- A playtest verdict is now a card with a hierarchy instead of a block of red text: the result and the reason are the title, what to read before trusting it stays in the body, and the evidence, the direct changes, what the detectors saw and the steps to reproduce are collapsible sections with their counts. It fits a narrow dock.

## [0.1.19] - 2026-11-10

### Added

- `godot.profile_run` runs a scene with Godot's script profiler on and returns the slowest GDScript functions by self time, with `path:line`, calls, self and total ms per frame, share of script time and whether the function is typed. Use it to choose what to optimize and to measure before and after. Compare functions with each other rather than trusting absolute times: the profiler slows every call.
- `godot.install_extension` brings a GDExtension from its test project into your game as an addon, but only after its tests pass. It goes to `res://addons/<name>/`, or replaces the copy your game already has, and never adds a second one. Nothing changes in the open editor: the files go in when the editor restarts (`godot.restart_editor`), and if one can't be copied, none are.
- Before installing, `godot.install_extension` checks the `.gdextension`: the entry symbol, `compatibility_minimum`, and that the library this editor loads exists. Platforms not built yet are listed without blocking the install.
- If the editor closes with an extension install still waiting, the dock offers **Restart** to load it or **Discard** to drop it. A failed install is reported in the dock too.
- **CI workflow…** in the findings panel writes a GitHub Actions workflow that runs your saved playtest regressions on every push and pull request with this editor's Godot version. It uploads the report and captures when a regression fails. The agent can write it with `godot.write_regressions_workflow`. The button asks before replacing an existing workflow, and the agent never replaces one. From a .NET editor, the workflow uses the .NET build of Godot and builds the C# project first.
- Hovering the agent chip in the dock header shows what the session is doing, what the running game is doing (launched by the agent or by you) and, during a One-shot, its phase, with how long each has been in that state.

### Fixed

- Variables such as `GIT_AUTHOR_NAME` or `KEYBOARD_LAYOUT` no longer count as secrets just because their name contains a secret-like word. Before, their values (your name, for example) were hidden in the chat, and Settings and MCP servers wouldn't save them as typed values.
- When a GDExtension build crashes the editor while starting, the crash supervisor now restores the `.gdextension` that last worked along with its libraries, not just the libraries.
- The crash supervisor no longer treats extensions inside a project nested in your game (a test project with its own `project.godot`) as the game's. The editor doesn't load them either.
- **↶ undo** shows up again for a `godot.*` edit whose arguments include a secret.
- Signing in through the agent's terminal login keeps your real key when the agent passes it back.

### Security

- Forms the agent asks you to fill in now hide the harness's secrets, as permission cards already did. A value you don't change still goes back to the agent unchanged. See [Secrets](https://github.com/dannroda/godot-agent/blob/main/PRIVACY.md#secrets).
- In Auto mode, a permission card no longer suggests a shell rule that contains a secret. Accepting it would have shown the secret and saved it in your settings.

## [0.1.18] - 2026-11-10

### Changed

- The Agent Log has a `state` channel. When the agent's session, the game launched by `godot.run_scene` or a One-shot run changes state in a way the harness doesn't expect (for example, a One-shot going from preparing straight to paused), the change still happens and a line in this channel names both states.
- When `godot.run_scene` is called while another run is in progress, the error says how long that run has been going and what the game is doing (launching, running, stopped in the debugger, ended).
- If the agent's process ends while it waits for you to sign in, the dock shows the error with **Retry** instead of staying on «Sign-in needed».
- When the agent's process dies, the error card keeps the last lines of its output folded under **Show**, each cut to a readable length with how many characters it left out, so a long dump (the whole prompt, for example) doesn't hide the cause. **Copy** and **Open the log below** still have every line in full.

### Fixed

- When the agent's process dies during a turn or while the session starts, the chat shows one error card, with the cause and the last lines of the log, instead of two cards that each offered **Retry**.
- A short message of yours no longer shows broken into one or two letters per line in the dock (for example «h / ol / a»).

### Security

- The agent's error card showed the last lines of its process output without redacting the harness's secrets: if those lines included the MCP server token or another registered secret, the card showed it and **Copy** copied it. It now redacts them like the Agent Log does.
- The same secrets are now redacted everywhere else they could show, not only in the Agent Log: what the agent sends back (a message, a tool result, an error that quotes the MCP configuration), the permission cards, the status tooltip, the session history on disk and the conversations resumed from it, and the One-shot activity and reports. What the agent writes or runs keeps the real value. The keys named in the agent's profile (variables named like a secret) and the agent's API key variable exported in the editor's environment count as secrets too. Details in [PRIVACY.md › Secrets](PRIVACY.md#secrets).

## [0.1.17] - 2026-11-03

### Added

- Crash supervisor for projects that build a GDExtension: a headless Godot outside the editor that opens the editor and watches it. When the editor has run 30 seconds with a build, it keeps a copy of that build. If a new build crashes the editor while starting, the supervisor puts the last good build back (the crashing one stays next to it as `*.crashed`), disables an extension that never started fine (`.gdextension.disabled`) and reopens the editor; after 3 crashes in 5 minutes it stops. The agent's last session resumes with a message that says what happened, with the extension's part of the backtrace. A notice in the dock offers **Restart under the supervisor** and **Copy the command** to start it from a terminal. Under the supervisor, any editor restart (Project › Reload Current Project, the updater) goes through it, so the new editor stays supervised.
- `godot.restart_editor` saves the scenes and restarts the editor so it loads the GDExtension builds on disk, under the supervisor by default; the agent's session resumes after the restart.

- `godot.build_extension` builds the project's GDExtension with SCons or CMake (godot-cpp) or Cargo (gdext) and returns the compiler errors by file and line (gcc, clang, rustc and MSVC). It finds the SConstruct, CMakeLists.txt or Cargo.toml in the project folder, the folder above it or a `rust/` folder, asks like a shell command, and never loads the build into the open editor. In a project with a native build, the agent's instructions say to test new builds in a separate headless Godot and to ask for an editor restart.
- `godot.test_extension` tests the GDExtension in a separate headless Godot, so a crash kills only the test process and never the editor. It runs the test project's `tests/test_*.gd` files (the format of the gdextension-cpp skill) and checks that the given classes are registered, then returns the failed checks, the extension's load errors and, after a crash, the backtrace with the extension's frames resolved to functions and lines by addr2line (with `debug_symbols=yes`). It finds the test project (`project/` or `demo/` next to the SConstruct, `godot/` next to `rust/`), and imports it first when a `.gdextension` isn't registered yet, never in the project the editor has open. `build_extension` warns when this project has a `.gdextension` with `reloadable = true`, which the editor reloads when the library changes.

## [0.1.16] - 2026-11-02

### Added

- One account per dock tab, for any agent: the agent chip's menu picks the tab's agent and its account, so two sessions can work side by side with different accounts. An account is the agent's configuration folder, passed in its variable: `CLAUDE_CONFIG_DIR` for Claude Code, `GEMINI_HOME` for Google Antigravity, `CODEX_HOME` for Codex; for another agent, its profile can name the variable. The menu finds the default folder and the ones in `~/.<folder>-profiles/` (for example `~/.claude-profiles/work`), shows the email for Claude Code accounts, and **Other folder…** adds any other. The session history remembers each session's account. Extensions follow the active tab's agent and account.

- Skills for every agent: **Use with all agents**, in a project or user skill's menu in **Extensions › Skills**, moves it to `.agents/skills` (the project's, or `~/.agents/skills`), which Google Antigravity, Codex and other agents read, and leaves a link in Claude Code's folder, so all of them use one copy. **Only for Claude Code** undoes it. In the project the link is relative, so it works in other clones.
- Google Antigravity plugins with their manifest in `.antigravity-plugin/plugin.json` or `.gemini-plugin/plugin.json` show their skills in **Extensions**, like those with `plugin.json` at the root.

- One-shot takes reference files: **+ Reference files…** on the form (or a drop from the FileSystem dock) adds a design document (GDD), concept art or any other file. The agent reads them before writing the spec, and the QA evaluator checks the game against them. Files from outside the project are copied into the run's folder.

### Changed

- The session's state (**Ready**, **Working…**, **Waiting for you**, **Cancelling…**, the error) moved from the agent chip in the header to a line right above the composer, where you're looking while you write. The chip keeps the agent's name and the state's color.
- Permission cards offer **Always allow in this session** even when the agent only offers "once" (Google Antigravity). The harness keeps the choice and answers the agent "once", as with any "always". Shell commands never get it, from any agent: it opened every command for the rest of the session, including those on the "always ask" list and after switching to Auto. In Auto, the card proposes an allowlist rule instead.
- The chat's text box grows with what you write (up to 40 % of the dock) instead of staying at three lines with a scroll bar. A bar above it sets the height by hand (up to 70 %), for every tab and remembered across sessions; double-clicking it goes back to following the text.
- **+ context › File…** browses any folder, not just the project. Images from outside go as images, as before; other files (notes, a GDD, a PDF…) go as a link with their full path for the agent to read, instead of being refused.
- One-shot runs in its own dock tab, **One-shot · <goal>**, with the agent and account of the tab it was launched from. Before, it took over the first tab: the session there was replaced and that tab couldn't switch sessions until the run ended. The other tabs now stay normal chats during a run; a resumed run gets a new tab too.

- While a tab is working, **New session** and picking a session from the history open it in a new tab with the same agent and account, instead of being disabled. A session that is already open in another tab is brought to the front instead of being opened twice.

- Agent profiles, MCP servers and completion LLM profiles are stored in Editor Settings as arrays of dictionaries instead of JSON text, so they can be edited there. Existing settings are converted on load.

### Fixed

- **Settings → Agents**: the profile form squeezed its fields to a few characters in a narrow dialog. Labels now go above the fields.
- A turn that the agent never closed (it finished answering but the dock stayed "working") couldn't be stopped: **Stop** stayed on "cancelling" forever. If the agent doesn't confirm the cancellation within 8 seconds, the turn is now closed in the dock, queued messages go out, and a notice offers **Restart the agent**, which reopens the same session.
- One-shot: images and files attached in the chat while a run is going were left in the composer and never reached the agent. They now go with your message to the run's agent.
- One-shot: with the spec waiting for review, a message in the chat is sent as a change to the spec, so the agent updates `spec.md` and waits for approval again instead of starting to build. The spec column and the chat notice now say that changes can be asked for in the chat.
- The plan quota ring's tooltip closed a second after opening: the ring sits at the bottom of the screen and the tooltip is tall, so Godot moved it up under the mouse pointer, which closed it. The details now open in a panel of their own, always above the ring and never under the pointer, with a progress bar for the context, each quota window and each model group, in the ring's color and with its reset time.
- One-shot: the `{"checks": …}` block that the agent and the QA evaluator end their turns with showed in the chat as a long JSON. It now folds into one line ("Checks: 6 ✓ · 1 ✗ · 2 unverified · 4 scores · 3 findings") that opens a readable list, with the raw JSON behind **Show JSON**. It also folds when reopening a session from the history.
- A permission card for a long command (a script of hundreds of lines) took the whole dock and pushed **Allow once**/**Deny** out of view. The title now shows the first line, and the whole command opens under **Show all (N lines)** in a box with its own scroll.
- Google Antigravity: shell commands ignored the allowlist in Auto mode (`cat *` still asked) and the card couldn't propose a rule. Antigravity sends the command as `CommandLine`, which the harness didn't read; it now reads it, also for blocking shell writes to scenes and project files.
- The session history saves during long turns too (on each prompt and every 15 seconds), so a turn that never ends isn't lost from it.

## [0.1.15] - 2026-10-31

### Fixed

- `game_input` by physics frame wasn't exact when the game ran slowly: a hold of 11 frames could last 15. Now it's the same at any frame rate, as the tool promises.
- `get_errors` no longer lists the Godot 4.7 `@implicit_new` engine error that appears while the playtest probe starts; agents took it for an error of the harness. Game results already hid it.
- `validate_physics` and `validate_tilemap` show readable names in the chat ("Validate physics", "Validate tilemap").
- The `save_scene` tool, and saving the open scenes before an add-on update, no longer use the editor's save with preview, which on Godot 4.7.2 can print an engine error (see Known issues). The tool now also reports an error if the scene stays unsaved.

### Known issues

- On Godot 4.7.2, saving a scene with preview (Ctrl+S) can make the engine print `p_I->data != this` (`list.h`); in a project without the add-on it appeared on every save. In sessions where an agent was changing the project, the editor sometimes crashed right after such a save; that crash was never seen without the add-on, and that it comes from this error is likely but not confirmed. Ctrl+S belongs to the editor. Godot 4.8-beta2 still prints the error but didn't crash in 12 runs.

## [0.1.14] - 2026-10-31

### Added

- Saved playtest regressions run from the command line, for CI: `godot --headless --path . --script res://addons/godot_agent/playtest/regression_cli.gd`. A regression can carry a `sabotage` script that breaks what it checks; it then has to fail with it, or it counts as not detecting the bug.

### Fixed

- The editor could crash when a dialog of the add-on (such as the recording player or a confirmation) was open while the editor showed a progress bar: running the game, or reimporting files the agent wrote.
- On Godot 4.7, running the game several times from the agent could crash the editor: the playtest autoload no longer goes through the editor's autoload list.
- `look_at` in `game_script` said the view didn't turn when the mouse had been left over a button by an earlier click.
- Inline completion stopped suggesting a line that appears once elsewhere in the project once its file was about a week old.

## [0.1.13] - 2026-10-31

### Added

- **Run regressions** in the findings panel: a Playtest that passes leaves a script, and this repeats it without the agent and without using tokens.

### Fixed

- Playtest could close the editor: with a time limit, which is on by default, the game's second run crashed it.
- Playtest in Review didn't play: the agent stayed in plan mode and waited for a plan approval. It now plays, and goes back to plan mode at the end.
- `run_scene` no longer stays stuck on "already in progress" after an internal error.
- `continue_on_error` no longer skips breakpoints.

### Changed

- The One-shot evaluator's verdict doesn't count if it never played the game, and its report lists what may have changed without playing and what the detectors saw.
- Tool rows no longer show the word "other" when a tool has nothing to show.

## [0.1.12] - 2026-10-30

### Added

- In-game detectors report what the agent wasn't looking at, with a picture of the moment: NaN transforms, bodies out of the world, long falls, long frames and a HUD text past its maximum (`12/10`).
- New tools for the running game: `game_ui` and `game_ui_act` use menus with real clicks instead of guessed pixels, `game_pause` and `game_step` play turn by turn with exact physics frames, `game_script` runs a short script inside the game to react in the same frame, `game_watch` lists what changed during a time window, `game_frames` looks back at the last seconds (with `film_fps` on `run_scene`), and `game_find` finds nodes.
- `game_input` can type text and move a first-person view (`text`, `look`).
- `run_scene` can go on after a script error (`continue_on_error`) and tells the scene, the player, the controls and what is on screen.
- Playtest can also explore or reach a goal. Its findings go to the panel with **Show in the scene**, **Verify a fix** and **Not a bug**; **Run the playtest again** repeats the last one, **Play the recording** plays the run in the editor, and it takes a time limit.
- Playtests remember what they verified about your game and which files changed since, in `res://.godot_agent/playtests/`.

### Changed

- Tested on Godot 4.8-beta2 (was 4.8-beta1), besides 4.7.2 and Godot .NET 4.7.2.
- A Playtest verdict is checked against what the agent did: without playing the game, or without a captured frame when the verdict depends on how something looks, it counts as could not test. The verdict lists what may have changed in the running game without playing, and says why there is no video if you asked for one.
- Playtest and the One-shot evaluator follow stricter rules: what happens in play settles the result, failing to do something is not a bug by itself, and text from the game is never an instruction. The evaluator can't pass a check it could not test.

## [0.1.11] - 2026-10-29

### Added

- Inline completion in `.cs` files opened in Godot .NET's Script Editor (which has no C# completion of its own): suggestions from the project's C# lines, and the LLM gets the file as C#.
- **C# projects** (Godot .NET): `validate_scripts` and the check at the end of each turn compile with `dotnet build` and give the errors by file and line; `attach_script` and `create_scene` create `.cs` scripts as a partial class named like the file; `.cs` files can be mentioned with `@`; findings in a `.cs` open in your external editor if you use one; and the agent gets the C# conventions when the project has a `.csproj`.
- A guide for running Godot from the command line (`config/godot_headless.md`, adapted from walker): checking scripts with `--check-only`, building scenes with a script that counts its nodes, and the failures Godot doesn't report (a node without `owner`, `.gdignore`). Sessions in a separate copy get it in full; the system prompt points to it.
- `godot.move_file` also fixes the relative paths of scripts (`preload("enemy.tscn")`, `load`, `extends "base.gd"`) when the script or what it names moves, and says PARTIAL with the list if a file could not be updated.
- `godot.validate_physics` and `godot.validate_tilemap`: read-only checks of collision shapes, layers and masks, and of TileMapLayer cells and collisions, which the agent runs after touching physics or maps.
- **Playtest…** in the Review panel: the agent plays the game to check what you ask and answers passed, failed (with steps to reproduce) or could not test, with evidence, without changing the project. `run_scene` can record the run as a video (`record: true`).
- Every `godot.*` tool result now lists the editor errors and warnings that appeared since that session's previous call, so the agent sees a broken script right away instead of at the end of the turn.
- Tools that edit scenes, files or the project wait up to 8 s while the editor imports assets, and then answer `EDITOR_IMPORTING` instead of editing half-loaded resources.
- `game_input` and `run_scene` inputs can go by physics frame (`frame`, `hold_frames`, `settle_frames`) instead of seconds, so the same sequence plays the same at any framerate; actions take a `strength`.

### Fixed

- `validate_scripts` without paths no longer times out in projects with the harness installed: it skips the harness's own scripts.
- Disabling the plugin on Godot 4.7 no longer leaves the run tools and the playtest debugger in memory.

## [0.1.10] - 2026-10-29

### Changed

- **Requires Godot 4.7 or newer** (was 4.6). Tested on 4.7.2 and 4.8-beta1.

### Fixed

- With the language on **auto**, the addon follows the editor's language again on Godot 4.7+ (it used the system's).

## [0.1.9] - 2026-10-29

### Changed

- The One-shot main screen (top bar, next to 2D/3D/Script) is now called **One-shot** instead of **Agent**, so it no longer shares its name with the dock.
- In Review mode, the `findings` JSON the agent writes is folded in the chat into one line ("2 findings · in the Review panel and the Script Editor"); a click shows the JSON.
- A session in another tab shows one editor notice while it waits for you, not one per permission or question.
- **Dock**: one row of controls on top: the agent chip with its state (click to pick the agent), the title, history, **+** (new session or new tab) and **⋯** (Extensions, Settings, Remote Control, sign out). The tab row shows up once there are two sessions. The agent's text no longer sits in a box, and editor tools show names for people ("Connect signal") in aligned columns, with their output nested.
- **Composer**: **+** holds mentions, game images and agent commands; the mode is a pill; the context used is always a percentage next to the quota ring (tokens in its tooltip), in warning color from 80 %.
- With no session, the dock lists the project's previous sessions with **Continue**. **Settings → Interface → When the editor opens** can continue the last one instead.
- With no agents, the dock asks **Choose which agent to work with**: Claude Code (recommended), Codex and Google Antigravity with what each needs, links to the whole ACP registry and to adding one by hand, and the three steps to start; the composer says to add one first. Settings → Agents suggests the same, and with agents shows the list next to the form, with a star for the default.
- Signing in is a neutral card with the main method as a button and **Other ways to sign in**, instead of a red error with six buttons.
- Agent errors say what happened in plain words, show the last lines of the agent's output with **Copy**, and offer the fix (**Edit the agent**, **Reinstall…** for agents downloaded from the ACP registry). **Open the log below** jumps to the error's line, highlighted.
- A pending permission sits in a bar above the composer instead of scrolling away with the chat (Enter allows, Esc denies); once answered it goes back to its place in the chat. The agent chip is a bordered dropdown that says **waiting for you** meanwhile.
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
