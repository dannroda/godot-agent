# Godot Agent Harness wiki

**English** · [Español](../es/Inicio.md)

Godot Agent Harness puts a coding agent inside the Godot editor. The agent runs as a separate process (Claude Code, Gemini CLI, Codex…). The harness talks to it, shows the conversation in a dock, and gives it editor tools: it reads scenes, edits nodes with undo, runs the game and looks at frames. Every change goes through the editor and through a permission policy.

## Pages

| Page | What it covers |
|---|---|
| [Getting started](Getting-started.md) | Install, sign in, the dock, your first prompts, the interface language. |
| [How it works](How-it-works.md) | The pieces: agent process, ACP, MCP server, editor sync, sessions. |
| [Modes and permissions](Modes-and-permissions.md) | Ask, Review, Build, Auto and One-shot, the permission matrix and Remote Control. |
| [Editor tools](Editor-tools.md) | The `godot.*` tools the agent can call, and what each one does. |
| [One-shot](One-shot.md) | Building a whole goal: spec, plan, budgets, checkpoints, quota, switching accounts, report. |
| [Review](Review.md) | Code review with findings in the Script Editor. |
| [Inline completion](Inline-completion.md) | Grey suggestions while you type, local or with an LLM. |
| [Settings](Settings.md) | Where every setting lives, agent profiles, export, updating the addon. |
| [Troubleshooting](Troubleshooting.md) | Common problems and limitations by Godot version. |

## Ground rules

- The harness never merges or pushes. One-shot works on its own branch, and you decide what to merge.
- It never stores API keys: profiles reference environment variables by name.
- It never reads the agent's credentials or its private files.
- The MCP server listens only on `127.0.0.1`, with a token that changes on every start.
- Nothing from the addon reaches an exported game.
