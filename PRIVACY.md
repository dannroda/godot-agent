# Privacy and data use

**English** · [Español](PRIVACY.es.md)

Godot Agent Harness is an editor addon. It has no server, no account and no telemetry. It doesn't send your project anywhere on its own: the agent you choose does, to its provider and under that provider's terms. This page lists what goes where, what stays on your computer, and how to delete it.

## What the agent receives

The agent (Claude Code, Codex, Google Antigravity or another ACP agent) runs on your computer as a separate program and talks to its own provider (Anthropic, OpenAI, Google…). Everything it receives can reach that provider:

- what you write in the dock and what you attach: files, scene nodes, images, captures of the game or the editor;
- the context the dock adds to a prompt: the open scene and the selected nodes (you can remove them before sending);
- what it reads with the `godot.*` tools: scenes, scripts, project settings, editor and game errors, the Output panel, frames of the running game;
- the harness's instructions: project name and folder, Godot version and the path of the editor's binary;
- everything the agent reads on its own with its own tools (files, shell commands), as allowed by the permissions you set.

How the provider stores or uses that data is set by the provider and your account with it, not by the harness. See their policies: [Anthropic](https://www.anthropic.com/legal/privacy), [OpenAI](https://openai.com/policies/privacy-policy/), [Google](https://policies.google.com/privacy).

Remote Control (Claude Code) shares the session through claude.ai, with your Claude account. It's off until you turn it on.

## Connections the addon makes itself

| When | Where | What is sent |
|---|---|---|
| Editor start, once a day (Settings → Interface → *Check for a new version when the editor opens*) | `api.github.com` (this repository's releases) | A request for the release list. No project data. Updating downloads the zip from GitHub. |
| You open the ACP registry or add an agent from it | `cdn.agentclientprotocol.com` and the agent's download URL | A request for the list and, when you add one, its download (checked against the registry's sha256 when it has one). |
| You search, look at or install an addon from the Asset Store | `store.godotengine.org` | Your search and your Godot version. |
| Inline completion with an LLM (optional, off by default) | The endpoint of the LLM profile you configure | The code around the cursor and a summary of the project (node paths, classes, autoloads, input actions). The local presets (Ollama, LM Studio, llama.cpp) use `127.0.0.1`; remote ones (Mistral, Gemini) need a key and send the code to that provider. |
| You import review comments from a GitHub PR, or push a separate copy as a PR | GitHub, through your `gh` CLI and its login | What `gh` sends for those commands. |
| MCP servers you add in Settings | Those servers | What the agent sends to their tools, with their own permissions. |

The local inline completion (the default) never leaves the editor.

## The editor's MCP server

The addon's MCP server listens only on `127.0.0.1`, with a token that changes every time the editor starts, so other computers can't reach it. The token is hidden in the Agent Log. A small shim for agents that use MCP over stdio lives in `user://godot_agent_mcp_shim/`.

## What is stored on your computer

`user://` is the project's folder in the editor's user data (on Linux, `~/.local/share/godot/app_userdata/<project>/`).

| What | Where | Notes |
|---|---|---|
| Session history (the conversations, to reopen them) | `user://godot_agent/sessions/` | The last 100 sessions. Captures are not saved; long texts are trimmed. |
| Prompts you sent (↑ in the composer) | `user://godot_agent/prompt_history.json` | |
| One-shot runs | `user://godot_agent/oneshot/` | The last 20. |
| Addon updates and Asset Store downloads in progress | `user://godot_agent/update/`, `user://godot_agent/assets/` | Backups of the previous addon version stay in `update/`. |
| Agent profiles, MCP settings, completion settings, language | Editor settings, prefix `godot_agent/` | Profiles name environment variables, never their values (Settings rejects a literal value in a variable named like a secret). |
| Agents downloaded from the ACP registry | The editor's data folder, `godot_agent/agents/` | Shared by all projects. |
| Project permissions, rules, budgets, MCP servers of the project | `res://addons/godot_agent/config/project_config.tres` | Part of the project: commit it or not, as you prefer. No keys. |
| Turn reports, playtest videos and frames, what playtests learned about the game (notes, scripts, saved regressions, findings marked not a bug), One-shot spec and progress, installed-asset list | `res://.godot_agent/` | Inside the project. Never exported with the game. |
| Snapshots of each turn, to show what changed and go back | git refs `refs/godot-agent/turns/*` in the project's repository | Local refs: they are not pushed unless you push them yourself. The last 60 per session. |
| Agent Log | Memory only | Up to 2000 entries, cleared when the editor closes. It leaves the editor only if you copy it. |

## What the harness never does

- It never stores API keys or reads the agent's credential files. To show which account an agent uses, it asks the agent's own CLI (for Claude Code, `claude auth status`); the email appears in the dock but is not written to the log.
- It never pushes or merges in git.
- It never sends analytics or usage data.
- Nothing from the addon ends up in an exported game.

## Deleting your data

- Conversations: delete them one by one from the session history in the dock, or remove `user://godot_agent/sessions/`.
- Everything the addon keeps for a project: remove `user://godot_agent/` and `res://.godot_agent/`.
- Turn snapshots: `git for-each-ref --format='%(refname)' refs/godot-agent/ | xargs -n1 git update-ref -d`.
- Downloaded agents: remove `godot_agent/agents/` from the editor's data folder.
- What the agent's provider kept: ask the provider, with the account you used.

Security problems: see [SECURITY.md](SECURITY.md).
