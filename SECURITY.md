# Security

## Reporting a vulnerability

Please don't open a public issue. Report it privately through GitHub: **Security → Report a vulnerability** in this repository ([new advisory](https://github.com/dannroda/godot-agent/security/advisories/new)). Include the Godot version, the addon version and the steps to reproduce.

## Supported versions

Only the latest release gets security fixes.

## What the harness is designed to protect

- **The editor's MCP server** listens only on `127.0.0.1` and requires a token that changes every time the editor starts.
- **The permission policy** decides, per mode, what the agent may do in the editor and on the shell (Settings → Permissions). Some writes are rejected in every mode, such as writing scenes or `project.godot` by hand from the shell, or launching Godot with a window.
- **Keys** are never stored: agent profiles name environment variables.
- **Secrets are masked** wherever they could show (the Agent Log, the chat, the cards, the saved history, the One-shot report): the MCP server's token and the keys taken from the environment for the agent and for MCP servers. What the agent writes or runs keeps the real value. Details in [PRIVACY.md › Secrets](PRIVACY.md#secrets).
- **Commands that come with a project**: the project's MCP servers and its checks after each turn live in `project_config.tres`, which travels with the project. Each one only runs on a machine where its exact definition was approved, so a cloned project can't start programs through the harness without asking. Approvals are kept per user, in the editor settings. Opening a Godot project you don't trust already runs its code (`@tool` scripts, editor plugins), so this is defense in depth, not a sandbox.
- **Project tools** (`res://agent_tools/*.gd`) are GDScript that runs inside the editor when the agent calls it. Each one only loads on a machine where its code, together with every other script in that folder, was approved; an unapproved tool is never loaded. Any change, including one made by the agent, needs a new approval, and every call also asks for the **Project tools** permission. An approved tool has all the power of a `@tool` script: there is no sandbox. The folder is left out of exports.
- **Downloads** of agents from the ACP registry are checked against the registry's sha256 when it provides one.

## What it does not protect against

- **The agent itself.** It runs as your user, with your permissions. Its own tools (file access, shell) are limited only by the agent's settings and by the permissions you grant in the dock. Auto and One-shot modes run more without asking: use them on projects under version control.
- **Other programs running as your user**, which can read the editor's memory, its settings or the token.
- **MCP servers you add.** They receive what the agent sends to their tools.

## Advisories

- **Up to 0.1.17**: when the agent's process died, the error card in the dock showed the last lines of its output without masking, and **Copy** copied them: if those lines included the editor's MCP server token (valid only on `127.0.0.1`, and only until the editor restarts or you regenerate it) or another registered secret, the card showed it. What the agent sent back (a tool result, an error quoting the MCP configuration) also reached the chat and the saved session history unmasked, with any secret it carried. Fixed in the next release: see [PRIVACY.md › Secrets](PRIVACY.md#secrets). If you shared a crash card or a session history from those versions, press **Regenerate token** in Settings or restart the editor, and rotate any key that showed.

What data goes where: [PRIVACY.md](PRIVACY.md).
