# How it works

[Home](Home.md) · [Español](../es/Como-funciona.md)

```
┌──────────────── Godot editor ────────────────┐
│  Dock / Agent screen        Script Editor    │
│        │                          ▲          │
│  SessionController ── EditorSync ─┘          │
│     │       ▲                                │
│     │ ACP   │ MCP (HTTP, 127.0.0.1 + token)  │
└─────┼───────┼────────────────────────────────┘
      ▼       │
   Agent process (Claude Code, Gemini CLI…)
```

## The agent process and ACP

The agent runs as a child process of the editor. The harness talks to it over its stdin/stdout with the [Agent Client Protocol](https://agentclientprotocol.com) (JSON-RPC):

- `initialize` and `session/new` open a session in your project's folder;
- `session/prompt` sends what you write, plus a short harness context: the Godot version, the project, the mode and its rules;
- the agent streams back text, thoughts, tool calls, diffs and its plan, which the dock renders as they arrive;
- `session/request_permission` asks before acting, and the harness answers according to the [permission policy](Modes-and-permissions.md);
- `fs/read_text_file` and `fs/write_text_file` go through the editor, so open scripts and unsaved buffers are respected;
- `session/cancel` stops a turn (Esc).

The pipes are read on the editor's main thread, without threads, so reloading an addon script never crashes the editor.

The agent also gets the path of the running editor's binary, in `$GODOT` and in its instructions. When it runs Godot from the command line (`--headless`, `--import`, tests), it uses the same version as your editor, not another `godot` on your PATH.

## The MCP server: the editor tools

The harness starts an MCP server on `127.0.0.1`, never on another interface, with a Bearer token that changes on every start. It passes the server to the agent when the session opens. If an agent can't do MCP over HTTP, a stdio bridge run by the same Godot binary relays it.

Through it the agent calls the `godot.*` tools: read the scene tree, edit nodes, run the game, capture frames, read errors. See [Editor tools](Editor-tools.md). Each call passes through the permission policy first.

## Keeping the editor in sync

Claude Code also writes files with its own tools, straight to disk. The harness catches that and updates the editor, so the "modified outside Godot" dialog doesn't appear:

- open scripts are updated in the Script Editor;
- open scenes without unsaved changes are reloaded. On Godot 4.6, which can't tell whether a scene has unsaved changes, you get a notice with **Reload scene** instead;
- changes to `project.godot` (input actions, autoloads, main scene…) are applied to the editor's project settings, and the editor saves them.

A scene or script with unsaved changes is never overwritten: you get a conflict notice with the diff.

## Sessions and history

Every session is saved in `user://godot_agent/sessions/` once per turn, without images and with long results trimmed. **History** in the dock lists this project's sessions:

- if the agent supports `session/load` (Claude Code does), the session really resumes: the agent gets its context back;
- otherwise you see the conversation read-only, and writing starts a new session.

## The plan quota

Claude Code reports the usage of your plan's windows (5 hours and weekly). The harness shows it, warns at 75 %, pauses One-shot at 90 % and, when the limit hits, blocks sending with a countdown until the window resets. It doesn't estimate the quota from tokens, doesn't call undocumented endpoints and doesn't read the agent's files. See [One-shot → quota](One-shot.md#plan-quota).

## The Agent Log

The bottom panel shows everything by channel:

- `proc`: the agent process;
- `acp`: protocol messages;
- `mcp`: tool calls;
- `fs`: file reads and writes through the editor;
- `perm`: permission decisions;
- `quota`;
- `cmp`: completion latencies.

Secrets are masked. It's the first place to look when something doesn't work: see [Troubleshooting](Troubleshooting.md).
