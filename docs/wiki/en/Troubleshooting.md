# Troubleshooting

[Home](Home.md) · [Español](../es/Problemas-frecuentes.md)

Look at the **Agent Log** first: the `proc` channel shows the command that started the agent and its errors, and `acp` shows the protocol messages.

## The agent doesn't start

- **"Command '…' not found"**: the editor started from the desktop doesn't inherit your shell's PATH (fnm, nvm, volta…). The harness also looks in the usual folders (`~/.local/bin`, `~/.nvm/…`, `/usr/local/bin`, `/opt/homebrew/bin`…). If your `npx` is elsewhere, put its absolute path in the profile's command.
- **"The agent asks for authentication"**: use the sign-in buttons on the notice (see [Getting started](Getting-started.md#2-start-a-session)), or sign in with `claude` in a terminal and click **Retry**.
- **The first start takes long**: `npx` is downloading the adapter.

## The agent runs another Godot version

The agent gets the path of the running editor's binary in `$GODOT`, in its instructions and in `project_info`, and a `godot` shim goes first in its PATH. If it still uses another one, remind it: "use $GODOT".

## "Plan limit reached"

You hit your plan's window. Wait for the reset (the countdown shows when), or use **Switch account** in the One-shot screen during a One-shot (see [One-shot → switching accounts](One-shot.md#switching-accounts)). Outside One-shot, sign in with another account and start a new session or resume it from **History**.

## A scene didn't update after the agent changed it

On Godot 4.6, the editor can't tell whether a scene has unsaved changes, so instead of reloading it on its own you get a notice with **Reload scene**. On 4.7+ open scenes without unsaved changes reload by themselves. A scene with unsaved changes is never overwritten.

## The quota rings are grey

Claude Code reports the plan quota with the first message of each session, so a new session shows grey rings until you send something. Sessions driven from Remote Control don't report it to the dock: their turns don't go through ACP. Other agents may never report it. The harness never estimates it, so without that information One-shot won't pause for quota.

## Limitations by Godot version

| Version | What happens | How the addon handles it |
|---|---|---|
| 4.6 | `EditorInterface.get_unsaved_scenes()` doesn't exist. | If the agent changes an open scene on disk, you get **Reload scene** instead of an automatic reload. |
| 4.6–4.7 | `EditorDock` exists, but the main screen as a dock arrives in 4.8. | Dock and panel use `EditorDock`; the main screen uses the old API. |
| 4.8-beta1 | `_has_main_screen()` leaves an orphan `EditorDock` when disabling, and closing the editor with the One-shot screen active gives a focus error. | The main screen uses `add_dock`; before closing, the editor switches to the 2D screen. |

Two known, harmless traces remain in exports: addon paths in `uid_cache.bin`, and the plugin in the enabled plugin list of `project.binary`.

## Reporting a problem

Include the relevant lines of the **Agent Log**, your Godot version and the agent (and its version).
