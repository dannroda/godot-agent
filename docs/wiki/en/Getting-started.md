# Getting started

[Home](Home.md) · [Español](../es/Primeros-pasos.md)

## 1. Install

1. Download `godot-agent-harness-vX.Y.Z.zip` from the [latest release](https://github.com/dannroda/godot-agent/releases/latest) and unzip it into your project, so that `addons/godot_agent/` ends up in its `addons/` folder. From a clone of the repository, copy `addons/godot_agent/` instead (not `addons/godot_agent_dev/`, which is the repository's test plugin).
2. **Project → Project Settings → Plugins** → enable **Godot Agent Harness**.
3. You get three surfaces:
   - the **Agent** dock, on the right: the conversation;
   - the **Agent Log** bottom panel: what goes between the editor and the agent, by channel;
   - the **One-shot** screen in the top bar, next to 2D/3D/Script, where One-shot runs.

New versions show up as a notice in the dock, with **Update** (see [Updating the addon](Settings.md#updating-the-addon)).

Requirements: Godot 4.7+, and for Claude Code, Node.js with `npx`. C# projects work with the .NET version of Godot and the .NET SDK (`dotnet`), which the harness uses to compile and report C# errors.

## 2. Start a session

The first time there are no agents: the dock suggests Claude Code, Codex and Google Antigravity, each with what it needs. **Add** on Claude Code sets up its profile (`npx -y @agentclientprotocol/claude-agent-acp`) and starts the session on its own, with no **Start session** click. While it connects, the line above the composer says **Connecting…**; the first time, `npx` downloads the agent, and after a few seconds the line adds that this can take a minute. If it needs an account, the chat shows a sign-in card (with Claude Code, at your first message; after you sign in, the message is sent again by itself). The others open the ACP registry. Once there are sessions, the dock lists the project's previous ones with **Continue** (Settings → Interface can continue the last one when the editor opens).

If the agent isn't signed in, a card asks you to sign in, with the agent's main method as a button and the rest under **Other ways to sign in**. With Claude Code these are **Claude Subscription** and **Anthropic Console**:

- the button runs the agent's own login and opens the browser;
- if the browser doesn't open, **Open link** does; if the page gives you a code, **Paste code…** hands it to the login;
- when it finishes, the agent restarts and the session opens.

The agent stores its credentials, exactly as `claude` does in a terminal. The harness never reads them, and the pasted code never reaches the log.

Other agents (Codex, Google Antigravity, your own) are set up in **Settings → Agents**: see [Settings](Settings.md#agent-profiles).

## 3. The dock

- **Header**, one row: the agent chip (click it to pick the agent; its dot takes the state's color, and its tooltip says what each part is doing and for how long: the session, the running game (launched by the agent or by you) and, during a One-shot, its phase), the session title, the crosshair button (**Follow the agent**, below), **History**, **+** (**New session**, **New tab**, **New tab in a separate copy (git worktree)** and **New session with a summary of this one**) and **⋯** (Extensions, Settings, **What the agent can do (tools)…**, which opens the [tools list](Settings.md#extensions), **Export session…**, and Remote Control and sign out when the agent offers them). The tab row shows up once there are two sessions.
- **Follow the agent** (the crosshair button in the header, off by default, per tab): while it's on, the editor jumps to what the agent edits: the script at the changed line, or the scene with the node it touched selected (the 2D or 3D view comes to front). Reads don't move it. Only the active tab is followed. It never jumps while you're working: if you clicked, dragged or typed outside the dock in the last 2.5 seconds, or a text field outside the dock has the focus, it waits until you stop and then goes to the latest change. If the focus was in the composer, it stays there. **Ctrl+Enter** in the composer sends and turns following on for that request: it turns off by itself when that turn (and anything queued after it) ends, unless you touch the crosshair in the meantime. If following was already on, it stays on.
- **Modes**: Ask · Review · Build · Auto · One-shot, plus the project's own [project modes](Modes-and-permissions.md#project-modes) if it has any (see [Modes and permissions](Modes-and-permissions.md)). The **Plan** icon next to the mode selector asks for a plan before building.
- **Conversation**: Markdown (tables, lists, quotes and code blocks with highlighting and a copy button), grouped tool calls (with their duration), diffs, permission cards and the agent's plan. Prompts the harness sends for you (One-shot's turns, the check after each turn, Review's questions, fixes and playtests, inline edits, what the crash supervisor saw, messages from other sessions, **Fix with the agent**) don't look like your messages: each one is a dimmed line with a label, such as *One-shot · next task in the plan*. **Show prompt** opens the text the agent got, which is always in English. Queued prompts and sessions reopened from **History** keep the same labels. A subagent's work stays folded inside its `Agent` card. Click a screenshot the agent took to see it full size: wheel to zoom, drag to move, **Save PNG…** to keep it. Links to files open them in the editor (`file.gd#L42` goes to the line), and links to images open in the same viewer.
- **Composer**:
  - the line above it says what the agent is doing: **Connecting…**, **Ready**, **Working…** (with the subagents running), **Waiting for you** when a card needs an answer, **Cancelling…** or the error. Next to it, a chip shows what else is going on, without hovering: the running game, launched by the agent or by you with F5/F6 (**Game · running · 12 s**), and a One-shot (**One-shot · building · …**). The chip turns amber when the game is stopped in the debugger or the One-shot is waiting for you. A game you run by hand without the playtest autoload shows as **running, started by hand without the playtest probe**. The chip's tooltip is the agent chip's, with the detail;
  - **Enter** sends; **Ctrl+Enter** sends and follows the agent (see **Follow the agent** above); **Shift+Enter** adds a line; **Esc** stops the turn;
  - the text box grows with what you write, up to 40 % of the dock. Drag the bar above it to set the height yourself (up to 70 %; it applies to every tab and is remembered); double-click the bar to go back to following the text;
  - while the agent works, Enter **queues** the message above the composer. You can edit or remove each queued message. When the turn ends, the next one goes out. If the turn is cancelled or fails, the queue waits for **Send now**;
  - **↑** / **↓** at the first or last line walk through the prompts you sent in this project;
  - **+** at the bottom left inserts a mention, attaches an image of the game, starts an agent command, asks for a plan (`/plan`) or opens a [recipe](Modes-and-permissions.md#recipes) (`/recipe`). `/` at the start lists the agent's commands, and `@` lists the scene's nodes and the project's files. Dragging nodes from the Scene dock writes them as `@path`. Right-click → **Ask the agent** in the FileSystem dock, the Scene dock or on code selected in the Script Editor does the same from the editor: the files or nodes go in as `@path`, and the selection as a code block with its file and lines. Nothing is sent until you press Enter. Five mentions bring context when you send: `@errors` (the editor's errors and warnings), `@output` (the end of the Output panel), `@game` (the running game's node tree) `@docs:Class` (the API reference of a class, for example `@docs:CharacterBody2D`) and `@session:<id>` (what another session of this project asked and did, put together by the harness from the history, as context and not as instructions);
  - **+ context** attaches the open scene, the selection, a file (from the project or from any folder: images go as images, the rest as a link the agent reads), a viewport capture or a **game screenshot** of the running game. The game screenshot needs the playtest autoload: runs launched by the agent have it, and so do yours if you enable **Use the playtest autoload also when running the game manually** (Settings → MCP servers → Advanced);
  - **Point at something in the game…**, also in **+ context**, while the game runs with the playtest autoload: the live capture opens, you click on something, and it goes into your message as `@path`, with the capture marked at that spot. It picks the control under the point; if there's none, the 2D body, area, sprite, polygon or tile; if there's none, the 3D body the camera ray hits;
  - **Ctrl+V** with an image on the clipboard attaches it (a screenshot, for example), and so do files copied in your file manager. Dragging files from the FileSystem dock attaches them too. Up to 6 images per message, scaled down to 1280 px;
  - the mode pill and the model selector. Claude Code's default option shows the model it uses, for example **Opus 5.5 (default)**.
- **New session with a summary**: from 85 % of the context, a strip above the composer offers **New session with a summary** (also in the **+** menu at the top, as `/handoff [what to do next]` and by clicking the context percentage). The agent writes a handoff (goal, done, remaining, decisions, open questions) and a new tab opens with the same agent, account and mode, with the summary in the composer to review before sending; what the harness takes from the history goes as an attachment. Handoffs are saved in `.godot_agent/handoffs/`, and an empty session offers the latest one.
- **Export session…** in the **⋯** menu saves the conversation as Markdown, with the game captures as PNG files next to it, in `.godot_agent/reports/<date>-session/`. Tool calls and diffs are folded. Before saving you see a preview and choose what to take out: absolute paths (the project's become relative and your home folder becomes `~`), email addresses, and content that came from the game, the project's scenes or the internet; each option says how many it found. Secrets such as the MCP token are always removed.
- **Errors of a game you run**: when a game you run by hand (F5/F6, not through the agent) stops in the debugger with an error or ends with errors, the dock shows a notice with the error, the stack folded under **Errors and stack**, and **Fix with the agent**, which sends the error and the stack to the active session. Nothing goes to the agent until you press it. One notice per run; runs the agent launches don't show it, since the agent already gets their errors. Turn it off in Settings → MCP servers → Advanced.
- **Plan quota and context**: the two rings next to the mode. Their tooltip starts with the context used; from 80 % it also shows in the row. The outer one is the 5-hour window and the inner one the weekly window; they turn yellow at the warning threshold and red at the limit. Hovering them opens a panel above them with a bar per window, its percentage and reset time. Claude Code reports the quota with the first message of each session, so until then the rings stay grey.

## 4. First prompts

- *Ask*: "What does the Player script do when it gets hit?"
- *Build*: "Add a Label called WaveLabel to the HUD and show the current wave." Watch the scene tree update; **Ctrl+Z** undoes each step.
- *Build*: "Run the main scene, press space twice and tell me what errors appear." The agent runs the game with simulated input and reads the real errors.
- *Plan*: write "A game over screen when an asteroid hits the ship" and press **Plan**. The agent answers with a plan card and playable criteria; **Approve and build** builds it and then plays the game to check each criterion.

## 5. Interface language

The interface is in English and Spanish. It follows the editor language (**Editor → Editor Settings → Interface → Editor Language**). To force one, use **Settings → Interface → Language**; the change applies when you reopen the editor.

What the agent reads (its instructions and the tool descriptions) is always English; the agent answers in your language.
