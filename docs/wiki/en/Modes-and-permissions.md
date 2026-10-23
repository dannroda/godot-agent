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

### MCP servers of other programs

The tools of an MCP server other than `godot` (a [server from Settings](Settings.md#other-mcp-servers), or one the agent loads from its own configuration) belong to a group of their own, **MCP · name**, which is **Ask** in every mode until you change it.

- In **Settings → Permissions**, below the matrix, there's a row for each server on the list and for each one that already asked in this session.
- The card of one of these tools also offers **Always allow «name» in *mode* mode, in this project**, which saves **Allow** in that row. **Always allow in this session** only covers that server.
- When a One-shot starts, the activity warns about the servers that would ask: the run waits at each of their tools.

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

- **Test a command**: type one in the field above the table to see whether it would run or ask, and why. The rule that decided is highlighted in the table. It uses the rules as you are editing them, before saving.
- You can filter for the ones you or the cards added, edit a pattern or move it to the other list, remove rules and restore the defaults (this keeps the rules you added).
- They're saved in `project_config.tres`, with the rest of the project's permissions.

Each decision also goes to the **Agent Log**, perm channel: the command, whether it ran or asked, and the rule that decided it.

## Writes that skip the editor

Whatever the mode, the harness rejects on its own, without a card:

- shell commands that write project files: redirections (`>`), `tee`, `sed -i`, `dd of=`, and Python, Node, Ruby or Perl scripts that open files for writing;
- writing a `.tscn`, `.uid` or `.import` by hand, with the agent's file tools or through the editor's file access;
- running Godot from the shell without `--headless`: it would open the game or an editor in a separate window. To see the game, the agent runs it from the editor (`godot.run_scene`) and captures it (`godot.capture_game_frame`).

The chat shows a "Rejected: …" notice. The agent is told to write scripts with its own file tools (the harness passes them through the editor) and scenes with the `godot.*` tools. Commands that write outside the project, such as to `/tmp`, follow the matrix above as usual.

Change the matrix in **Settings → Permissions**. Only what differs from the defaults is saved, in the project's config (`project_config.tres`), so it can be committed and shared with your team.

## Remote Control

With Claude Code you can continue a dock session from claude.ai/code or the Claude app on your phone. When the agent offers `/remote-control`, a **Remote** button shows on the status line; it turns Remote Control on, with the project's name as the session name. While it's on, a strip under the status line shows the link, **QR** (a QR code of the link, to open it with your phone's camera), **Copy link** and **Turn off**. Click the strip's title to fold it to one line. Typing `/remote-control` or `/remote-control off` in the composer does the same.

- What you write from the phone, and the agent's answers, only show on the phone: Claude Code doesn't send them to the harness. The dock still sees the tool calls that need permission.
- The files that change while Remote Control is on (and no dock turn is running) show up in the chat as one notice per burst: "From Remote Control: modified player.gd · created enemy.gd". **View diff** shows each file before and now, and **Undo** puts them back as they were. Undo is offered when the harness knows the previous text: text files up to 256 KB. Files you save from the editor don't count, and the harness only looks at the first 5000 files of the project.
- Permissions keep following the mode. What the matrix allows or denies, Auto's lists and the rejected writes above are decided by the harness at once, so the phone doesn't ask. When the harness would show a card, the phone asks too, and you can answer on either side. If you answer on the phone, the dock's card closes with "Answered elsewhere".
- Commands Claude Code runs without asking (read-only ones such as `git status`) don't reach the harness at all.
- One-shot runs on its own: the button is hidden in that mode, and starting a One-shot turns Remote Control off. A new session starts with it off.
- Slash commands (`/remote-control`, `/compact`…) are sent alone, without the harness context or attachments: Claude Code only recognizes a command when it's the whole message.
