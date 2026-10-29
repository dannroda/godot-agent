# Getting started

[Home](Home.md) · [Español](../es/Primeros-pasos.md)

## 1. Install

1. Copy `addons/godot_agent/` into your project's `addons/` folder.
2. **Project → Project Settings → Plugins** → enable **Godot Agent Harness**.
3. You get three surfaces:
   - the **Agent** dock, on the right: the conversation;
   - the **Agent Log** bottom panel: what goes between the editor and the agent, by channel;
   - the **One-shot** screen in the top bar, next to 2D/3D/Script, where One-shot runs.

Requirements: Godot 4.6+, and for Claude Code, Node.js with `npx`.

## 2. Start a session

The first time there are no agents: the dock suggests Claude Code, Codex and Google Antigravity, each with what it needs. **Add** on Claude Code sets up its profile (`npx -y @agentclientprotocol/claude-agent-acp`; the first time, `npx` downloads it); the others open the ACP registry. Then click **Start session**. Once there are sessions, the dock lists the project's previous ones with **Continue** (Settings → Interface can continue the last one when the editor opens).

If the agent isn't signed in, a card asks you to sign in, with the agent's main method as a button and the rest under **Other ways to sign in**. With Claude Code these are **Claude Subscription** and **Anthropic Console**:

- the button runs the agent's own login and opens the browser;
- if the browser doesn't open, **Open link** does; if the page gives you a code, **Paste code…** hands it to the login;
- when it finishes, the agent restarts and the session opens.

The agent stores its credentials, exactly as `claude` does in a terminal. The harness never reads them, and the pasted code never reaches the log.

Other agents (Codex, Google Antigravity, your own) are set up in **Settings → Agents**: see [Settings](Settings.md#agent-profiles).

## 3. The dock

- **Header**, one row: the agent chip with its state (click it to pick the agent), the session title, **History**, **+** (new session, or a new tab next to this one) and **⋯** (Extensions, Settings, Remote Control and sign out when the agent offers them). The tab row shows up once there are two sessions.
- **Modes**: Ask · Review · Build · Auto · One-shot (see [Modes and permissions](Modes-and-permissions.md)).
- **Conversation**: Markdown (tables, lists, quotes and code blocks with highlighting and a copy button), grouped tool calls (with their duration), diffs, permission cards and the agent's plan. A subagent's work stays folded inside its `Agent` card. Click a screenshot the agent took to see it full size: wheel to zoom, drag to move, **Save PNG…** to keep it. Links to files open them in the editor (`file.gd#L42` goes to the line), and links to images open in the same viewer.
- **Composer**:
  - **Enter** sends; **Ctrl+Enter** or **Shift+Enter** add a line; **Esc** stops the turn;
  - while the agent works, Enter **queues** the message above the composer. You can edit or remove each queued message. When the turn ends, the next one goes out. If the turn is cancelled or fails, the queue waits for **Send now**;
  - **↑** / **↓** at the first or last line walk through the prompts you sent in this project;
  - **+** at the bottom left inserts a mention, attaches an image of the game or starts an agent command. `/` at the start lists the agent's commands, and `@` lists the scene's nodes and the project's files. Dragging nodes from the Scene dock writes them as `@path`. Four mentions bring context when you send: `@errors` (the editor's errors and warnings), `@output` (the end of the Output panel), `@game` (the running game's node tree) and `@docs:Class` (the API reference of a class, for example `@docs:CharacterBody2D`);
  - **+ context** attaches the open scene, the selection, a project file, a viewport capture or a **game screenshot** of the running game. The game screenshot needs the playtest autoload: runs launched by the agent have it, and so do yours if you enable **Use the playtest autoload also when running the game manually** (Settings → MCP server);
  - **Ctrl+V** with an image on the clipboard attaches it (a screenshot, for example), and so do files copied in your file manager. Dragging files from the FileSystem dock attaches them too. Up to 6 images per message, scaled down to 1280 px;
  - the mode pill and the model selector. Claude Code's default option shows the model it uses, for example **Opus 5.5 (default)**.
- **Plan quota and context**: the two rings next to the mode. Their tooltip starts with the context used; from 80 % it also shows in the row. The outer one is the 5-hour window and the inner one the weekly window; they turn yellow at the warning threshold and red at the limit. Hover them for the percentages and reset times. Claude Code reports the quota with the first message of each session, so until then the rings stay grey.

## 4. First prompts

- *Ask*: "What does the Player script do when it gets hit?"
- *Build*: "Add a Label called WaveLabel to the HUD and show the current wave." Watch the scene tree update; **Ctrl+Z** undoes each step.
- *Build*: "Run the main scene, press space twice and tell me what errors appear." The agent runs the game with simulated input and reads the real errors.

## 5. Interface language

The interface is in English and Spanish. It follows the editor language (**Editor → Editor Settings → Interface → Editor Language**). To force one, use **Settings → Interface → Language**; the change applies when you reopen the editor.

What the agent reads (its instructions and the tool descriptions) is always English; the agent answers in your language.
