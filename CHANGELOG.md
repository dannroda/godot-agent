# Changelog

All notable changes to Godot Agent Harness. The release workflow publishes the **Unreleased** section as the release notes and turns it into the new version's section, so write entries here, in English, as changes land.

## [Unreleased]

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
