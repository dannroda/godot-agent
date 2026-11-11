# Troubleshooting

[Home](Home.md) · [Español](../es/Problemas-frecuentes.md)

Look at the **Agent Log** first: the `proc` channel shows the command that started the agent and its errors, and `acp` shows the protocol messages.

## The agent doesn't start

- **"Command '…' not found"**: the editor started from the desktop doesn't inherit your shell's PATH (fnm, nvm, volta…). The harness also looks in the usual folders (`~/.local/bin`, `~/.nvm/…`, `/usr/local/bin`, `/opt/homebrew/bin`…). If your `npx` is elsewhere, put its absolute path in the profile's command.
- **"The agent asks for authentication"**: use the sign-in buttons on the notice (see [Getting started](Getting-started.md#2-start-a-session)), or sign in with `claude` in a terminal and click **Retry**.
- **The first start takes long**: `npx` is downloading the adapter. The line above the composer says **Connecting…** meanwhile, and after a few seconds that the first time can take a minute.

## The agent runs another Godot version

The agent gets the path of the running editor's binary in `$GODOT`, in its instructions and in `project_info`, and a `godot` shim goes first in its PATH. If it still uses another one, remind it: "use $GODOT".

## "Plan limit reached"

You hit your plan's window. Wait for the reset (the countdown shows when), or use **Switch account** in the One-shot screen during a One-shot (see [One-shot → switching accounts](One-shot.md#switching-accounts)). Outside One-shot, sign in with another account and start a new session or resume it from **History**.

## A `godot.*` call fails with "The operation timed out"

Claude Code stops waiting for an HTTP tool after 60 seconds with no response. A call that takes longer than 2 seconds (a long `run_scene` or `profile_run`, a GDExtension build or test, or any call while its permission card waits for you) now answers as a stream with progress every 10 seconds, so it runs to the end. If you still see the error:

- you set a total limit with `MCP_TOOL_TIMEOUT` or a `timeout` on the server: progress doesn't reset it, so keep it above 120 seconds, the longest `run_scene`;
- the client doesn't ask for progress: it gets a plain answer, and its own limit applies;
- the call ran for more than 30 minutes: it answers with an error, and the tool may still be running in the editor.

See [Editor tools → Details](Editor-tools.md#details).

## The player moves on its own, or the agent's input fails at random

Godot reads every gamepad connected to the computer, even when another window has the focus, so a stick left tilted or drifting keeps the arrow actions pressed: the player walks, the UI focus jumps to another control, and a text field that got the focus doesn't take typing. Games the agent launches (`run_scene`, `profile_run`, the regressions, `regression_cli.gd`) ignore real gamepads; the gamepad events the agent sends still work. To play along with yours in a run the agent launches, ask it to pass `real_gamepads: true`. Games you run with F5/F6 still read your gamepads: unplug or recalibrate the one that drifts.

## A scene didn't update after the agent changed it

Open scenes without unsaved changes reload by themselves. A scene with unsaved changes is never overwritten: you get a notice with **Reload scene** instead.

## The quota rings are grey

Claude Code reports the plan quota with the first message of each session, so a new session shows grey rings until you send something. Sessions driven from Remote Control don't report it to the dock: their turns don't go through ACP. Other agents may never report it. The harness never estimates it, so without that information One-shot won't pause for quota.

## Limitations by Godot version

| Version | What happens | How the addon handles it |
|---|---|---|
| 4.7 | `EditorDock` exists, but the main screen as a dock arrives in 4.8. | Dock and panel use `EditorDock`; the main screen uses the old API. |
| 4.7.2 | Saving with preview (Ctrl+S) can print an engine error (`p_I->data != this` in `list.h`); in a project without the addon it appeared on every save. In sessions where an agent was changing the project, the editor sometimes crashed a moment after saving; without the addon that crash was never seen, and that it comes from this error is likely but not confirmed. | The addon's own saves (`save_scene`, and saving before an update) skip the preview. Ctrl+S is the editor's: the addon can't change it. 4.8-beta2 still prints the error but didn't crash in 12 runs. |
| 4.8 (betas) | `_has_main_screen()` leaves an orphan `EditorDock` when disabling, and closing the editor with the One-shot screen active gives a focus error. | The main screen uses `add_dock`; before closing, the editor switches to the 2D screen. |

Two known, harmless traces remain in exports: addon paths in `uid_cache.bin`, and the plugin in the enabled plugin list of `project.binary`.

## Reporting a problem

Include the relevant lines of the **Agent Log**, your Godot version and the agent (and its version).
