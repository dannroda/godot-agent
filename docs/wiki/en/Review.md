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
