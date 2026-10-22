# Modes and permissions

[Home](Home.md) · [Español](../es/Modos-y-permisos.md)

## Modes

| Mode | What the agent does |
|---|---|
| **Ask** | Answers about the project. It can read, but it can't edit or run anything. |
| **Review** | Reviews scenes and scripts and returns findings (bug, structure, performance, style), shown as marks in the Script Editor. See [Review](Review.md). |
| **Build** | Edits scenes and scripts and runs the game, asking for permission according to the matrix below. |
| **One-shot** | Pursues a whole goal with budgets, checkpoints and playtests, in the Agent screen. See [One-shot](One-shot.md). |

Switching mode also switches the agent's own mode when it publishes one: Ask and Review use `plan`, Build and One-shot use `default`.

## Permissions

Every action belongs to a group, and each group has a decision per mode: **Allow**, **Ask** or **Deny**.

- **Ask** (the decision, not the mode) shows a card in the chat with what the agent wants to do (and the diff, for edits). If nobody answers in 5 minutes (configurable), it's denied.
- **Deny** denies without asking and tells the agent why.

Defaults:

| Group | Ask | Review | Build | One-shot |
|---|---|---|---|---|
| Read | Allow | Allow | Allow | Allow |
| Diagnostics | Allow | Allow | Allow | Allow |
| Edit scenes | Deny | Deny | Ask | Allow |
| Edit files | Deny | Deny | Ask | Allow |
| Run the game | Deny | Ask | Ask | Allow |
| Shell / commands | Deny | Deny | Ask | Ask |
| Project settings, export and addons | Deny | Deny | Ask | Ask |

Change the matrix in **Settings → Permissions**. Only what differs from the defaults is saved, in the project's config (`project_config.tres`), so it can be committed and shared with your team.
