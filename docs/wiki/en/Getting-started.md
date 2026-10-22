# Getting started

[Home](Home.md) · [Español](../es/Primeros-pasos.md)

## 1. Install

1. Copy `addons/godot_agent/` into your project's `addons/` folder.
2. **Project → Project Settings → Plugins** → enable **Godot Agent Harness**.
3. You get three surfaces:
   - the **Agent** dock, on the right: the conversation;
   - the **Agent Log** bottom panel: what goes between the editor and the agent, by channel;
   - the **Agent** screen in the top bar, next to 2D/3D/Script: the One-shot view.

Requirements: Godot 4.6+, and for Claude Code, Node.js with `npx`.

## 2. Start a session

Click **Start session** in the dock. The default profile launches Claude Code through its ACP adapter (`npx -y @agentclientprotocol/claude-agent-acp`); the first time, `npx` downloads it.

If the agent isn't signed in, the error notice offers one button per sign-in method the agent supports. With Claude Code these are **Sign in · Claude Subscription** and **Sign in · Anthropic Console**:

- the button runs the agent's own login and opens the browser;
- if the browser doesn't open, **Open link** does; if the page gives you a code, **Paste code…** hands it to the login;
- when it finishes, the agent restarts and the session opens.

The agent stores its credentials, exactly as `claude` does in a terminal. The harness never reads them, and the pasted code never reaches the log.

Other agents (Gemini CLI, Codex, your own) are set up in **Settings → Agents**: see [Settings](Settings.md#agent-profiles).

## 3. The dock

- **Header**: agent profile, session title, **History**, **New session** and **Settings**.
- **Modes**: Ask · Review · Build · Auto · One-shot (see [Modes and permissions](Modes-and-permissions.md)).
- **Conversation**: Markdown, grouped tool calls (with their duration), diffs, permission cards and the agent's plan. A subagent's work stays folded inside its `Agent` card.
- **Composer**:
  - **Enter** sends; **Ctrl+Enter** or **Shift+Enter** add a line; **Esc** stops the turn;
  - while the agent works, Enter **queues** the message above the composer. You can edit or remove each queued message. When the turn ends, the next one goes out. If the turn is cancelled or fails, the queue waits for **Send now**;
  - **↑** / **↓** at the first or last line walk through the prompts you sent in this project;
  - `/` at the start lists the agent's commands, and `@` lists the scene's nodes and the project's files;
  - **+ context** attaches the open scene, the selection, a project file, a viewport capture or a **game screenshot** of the running game. The game screenshot needs the playtest autoload: runs launched by the agent have it, and so do yours if you enable **Use the playtest autoload also when running the game manually** (Settings → MCP server);
  - **Ctrl+V** with an image on the clipboard attaches it (a screenshot, for example), and so do files copied in your file manager. Dragging files from the FileSystem dock attaches them too. Up to 6 images per message, scaled down to 1280 px;
  - model selector and context meter.
- **Plan quota**: if the agent reports it, the dock shows the 5-hour and weekly windows with their reset time.

## 4. First prompts

- *Ask*: "What does the Player script do when it gets hit?"
- *Build*: "Add a Label called WaveLabel to the HUD and show the current wave." Watch the scene tree update; **Ctrl+Z** undoes each step.
- *Build*: "Run the main scene, press space twice and tell me what errors appear." The agent runs the game with simulated input and reads the real errors.

## 5. Interface language

The interface is in English and Spanish. It follows the editor language (**Editor → Editor Settings → Interface → Editor Language**). To force one, use **Settings → Interface → Language**; the change applies when you reopen the editor.

What the agent reads (its instructions and the tool descriptions) is always English; the agent answers in your language.
