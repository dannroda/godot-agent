# Modes and permissions

[Home](Home.md) · [Español](../es/Modos-y-permisos.md)

## Modes

| Mode | What the agent does |
|---|---|
| **Ask** | Answers about the project. It can read, but it can't edit or run anything. |
| **Review** | Reviews scenes and scripts and returns findings (bug, structure, performance, style), shown as marks in the Script Editor. See [Review](Review.md). |
| **Build** | Edits scenes and scripts and runs the game, asking for permission according to the matrix below. |
| **Auto** | Like Build, but without cards for what can be undone: it edits scenes, scripts and project settings and runs the game on its own. Shell commands run on their own only if they're on the allowlist; see [Auto mode](#auto-mode). |
| **One-shot** | Pursues a whole goal with budgets, checkpoints and playtests, in the Agent screen. See [One-shot](One-shot.md). |

Switching mode also switches the agent's own mode when it publishes one: Ask and Review use `plan`; Build, Auto and One-shot use `default`.

## Permissions

Every action belongs to a group, and each group has a decision per mode: **Allow**, **Ask** or **Deny**.

- **Ask** (the decision, not the mode) shows a card in the chat with what the agent wants to do (and the diff, for edits). If nobody answers in 5 minutes (configurable), it's denied.
- **Deny** denies without asking and tells the agent why.

Defaults:

| Group | Ask | Review | Build | Auto | One-shot |
|---|---|---|---|---|---|
| Read | Allow | Allow | Allow | Allow | Allow |
| Diagnostics | Allow | Allow | Allow | Allow | Allow |
| Edit scenes | Deny | Deny | Ask | Allow | Allow |
| Edit files | Deny | Deny | Ask | Allow | Allow |
| Run the game | Deny | Ask | Ask | Allow | Allow |
| Shell / commands | Deny | Deny | Ask | Ask¹ | Ask |
| Project settings, export and addons | Deny | Deny | Ask | Allow | Allow |

¹ In Auto, the [Auto mode lists](#auto-mode) decide first; only what they don't allow shows a card.

## Auto mode

Auto is for working in the chat without approving every step. Edits can be undone (the ↶ on each card, the editor's undo), so they go through on their own. The shell is different, so each command is checked against two lists of patterns:

- **Allowlist**: runs without asking. By default, read-only and build commands: `ls`, `cat`, `grep`, `find`, `git status/diff/log/show`, `godot --headless …` and similar.
- **Always ask**: shows a card even if a broader allowlist pattern matches. By default: `rm`, `mv`, `sudo`, `chmod`, `git push/reset/checkout/clean/rebase`, `curl`, `wget`, `ssh`, package installers, `find -delete/-exec`.
- Anything else shows a card.

How a command is checked:

- A command with `&&`, `||`, `;` or `|` runs on its own only if **every part** is on the allowlist.
- Command substitution (`$(…)`, backticks) and redirection to a file (`> out.txt`) always show a card. `2>&1` and `> /dev/null` are fine.
- In a pattern, `*` matches anything, and `git log *` also matches `git log` alone. A program with a path (`/opt/godot/godot`) is matched by its name.
- Writing project files from the shell is still rejected, whatever the lists say (see below).

When a command shows a card, the card proposes a pattern, such as `npm test` for `npm test`, which you can edit, for example to `npm test *`. **Always allow** adds the pattern to the allowlist and allows this command. The card doesn't offer "Always allow in this session" for the shell in Auto, so the whole shell group is never opened at once.

**Reviewing the lists**: **Settings → Permissions → Auto mode: shell commands** shows every rule with its list, its origin (default, added by you, from a permission card) and the date it was added.

- You can filter for the ones you or the cards added, edit a pattern or move it to the other list, remove rules and restore the defaults (this keeps the rules you added).
- They're saved in `project_config.tres`, with the rest of the project's permissions.

Each decision also goes to the **Agent Log**, perm channel: the command, whether it ran or asked, and the rule that decided it.

## Writes that skip the editor

Whatever the mode, the harness rejects on its own, without a card:

- shell commands that write project files: redirections (`>`), `tee`, `sed -i`, `dd of=`, and Python, Node, Ruby or Perl scripts that open files for writing;
- writing a `.tscn`, `.uid` or `.import` by hand, with the agent's file tools or through the editor's file access.

The chat shows a "Rejected: …" notice. The agent is told to write scripts with its own file tools (the harness passes them through the editor) and scenes with the `godot.*` tools. Commands that write outside the project, such as to `/tmp`, follow the matrix above as usual.

Change the matrix in **Settings → Permissions**. Only what differs from the defaults is saved, in the project's config (`project_config.tres`), so it can be committed and shared with your team.
