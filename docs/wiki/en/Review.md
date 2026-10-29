# Review

[Home](Home.md) · [Español](../es/Revisar.md)

In **Review** mode, the agent reviews scenes and scripts and returns findings instead of editing.

1. Pick **Review** in the dock and ask: "Review the scripts in `player/`" or "Review the open scene".
2. The agent reads with the editor tools and answers with its findings. Each finding has:
   - a category: bug, structure, performance or style;
   - a file and a line;
   - an explanation and, when it can, a fix.
3. The findings show up:
   - as **marks in the Script Editor**, on the right lines, with a card: **Apply fix**, **Ask** (continues the conversation about it) and **Dismiss**;
   - in the **findings list** in the dock, to jump to each one.

**Apply fix** switches to Build and asks the agent for that fix. The edit goes through the permission matrix like any other. If the turn ends well, the finding leaves the review. The dock's findings list can also send several fixes at once.

## Export to CLAUDE.md

The review can be exported to the project's `CLAUDE.md` as conventions, for example "use static types everywhere" or "don't use `get_parent()` for behaviour". You see a preview first. From then on the agent follows them in every mode.

## Playtest

**Playtest…** in the findings panel asks what to check by playing ("the player can jump onto the second platform"). The agent runs the game, sends input by physics frame so the run is reproducible, reads the live state and captures frames, and answers with a verdict that shows in the chat: **passed**, **failed** with the steps that reproduce it, or **could not test** with the reason, plus what it observed. It does not change the project. With **Record a video of the run**, `run_scene` saves an AVI under `res://.godot_agent/playtests/`: the game runs at a fixed 30 fps while it records and closes by itself at the end.

## Comments from a GitHub pull request

**From a GitHub PR…** in the findings panel brings the review comments of a pull request as findings, with the [GitHub CLI](https://cli.github.com) (`gh`, signed in with `gh auth login`). Write its number, or leave it empty for the pull request of the current branch. Each comment on a line of a file of this project becomes a finding with its text and author, marked in the Script Editor like the agent's; replies within a thread are left out. From there, **Fix in Build mode** asks the agent to address them. It only reads: nothing is posted to GitHub.

The other direction is optional: with **Offer to push and open a GitHub pull request when closing a separate copy** (Settings → MCP servers, off by default), closing a [session in a separate copy](How-it-works.md#several-sessions-at-once) offers **Push and open a PR**, which pushes its branch to `origin` and opens a pull request against the branch you were on.
