# Contributing

Thanks for helping with Godot Agent Harness. Issues and pull requests are welcome in English or Spanish.

## Reporting a bug

Open an [issue](https://github.com/dannroda/godot-agent/issues) with:

- the addon version (**Project Settings → Plugins**), the Godot version and your OS;
- the agent and how you run it (for example Claude Code through `npx @agentclientprotocol/claude-agent-acp`);
- what you did, what you expected and what happened;
- the relevant lines of the **Agent Log** panel (bottom of the editor). Secrets such as tokens are already masked there, but read it before pasting.

If the editor crashed, say so and attach the end of the editor output.

## Proposing a change

For anything bigger than a small fix, open an issue first to agree on the approach. The [spec](GODOT_AGENT_HARNESS_SPEC.md) and [`docs/decisions.md`](docs/decisions.md) explain why things are the way they are. Read the relevant decision before changing what it covers.

## Setting up

You need Godot 4.6 or newer. CI runs 4.6.3, 4.7.2 and 4.8-beta1. The repository is itself a Godot project: the addon is in `addons/godot_agent/`, and `addons/godot_agent_dev/` is a test-only plugin that drives the editor from the command line.

```sh
G=/path/to/godot
$G --headless --path . --import                              # once, after cloning
$G --headless --path . --script tests/run_all.gd             # unit tests
$G --headless --path . --script tests/run_all.gd -- updater  # only the tests whose file or name contains "updater"
$G --headless --path . --script tests/acp_session_check.gd   # ACP against the fake agent
$G --headless --path . --script tests/oneshot_check.gd       # One-shot loop
tests/run_in_xvfb.sh $G --godot-agent-cycle-test             # editor in Xvfb: enable/disable 5 times without leaks
```

The editor checks need `xvfb-run`. The dev plugin has more flags (`--godot-agent-ui-test=`, `--godot-agent-settings-shots=`…), listed at the top of `addons/godot_agent_dev/plugin.gd`. Most of them use the fake agent (`tests/fake_agent.gd` and the scenarios in `tests/scripts/`), so they don't need an account.

To try the addon in a game project, link or copy `addons/godot_agent/` into it. To try One-shot, use a sandbox (`tests/make_sandbox.sh <folder outside the repo>`), never this repository: checkpoints create branches and going back resets the project folder.

If you link the addon into a project whose editor is open, saving a file of the addon makes that editor reload the script. That can crash it. Close the editor first or work on a copy.

## Code

- GDScript with static types everywhere. Follow the style of the file you are editing. Comments in the existing code are in Spanish; new comments can be in English or Spanish.
- No enum or inner class with a one-word name (`SessionState`, not `State`). A one-word name clashes with a game's global class of the same name ([D47](docs/decisions.md)). `test_type_names` fails otherwise.
- No threads in the editor plugin. Processes are read without blocking from the main thread.
- The addon never writes to `project.godot`. The only exception is the temporary playtest autoload.
- Every text the user sees is written in English and wrapped in `I18n.t("…")`. Add its Spanish translation to `addons/godot_agent/i18n/es.po`. `test_i18n` fails if a text has no translation or a translation is no longer used. What the agent reads (prompts, tool descriptions and results) is English only.
- New behavior comes with tests: a unit test in `tests/unit/` for logic, and a dev-plugin check for UI that needs the editor.

## Pull requests

- One topic per pull request, based on `main`.
- Add a line to the **Unreleased** section of [`CHANGELOG.md`](CHANGELOG.md), in English, for anything a user would notice. The release notes come from there.
- Update the [wiki pages](docs/wiki) (English and Spanish) and the READMEs if the change affects what users see or do. If it changes what the README screenshots show, regenerate them with `tests/docs_shots.sh <godot> en` and `… es` (needs `xvfb-run`; it works on a temporary copy of the project and doesn't touch your editor settings). `docs/wiki` is the source of the [GitHub wiki](https://github.com/dannroda/godot-agent/wiki): `python3 .github/scripts/wiki.py <wiki checkout>` copies it there.
- Don't commit `addons/godot_agent/config/project_config.tres`: it's your local project config.
- CI must pass: unit tests, the ACP check and the One-shot check, on the three Godot versions.

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
