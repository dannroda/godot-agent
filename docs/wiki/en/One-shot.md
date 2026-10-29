# One-shot

[Home](Home.md) · [Español](../es/One-shot.md)

One-shot gives the agent a whole goal ("a 2-player Pong with score", "a top-down shooter with three enemy types") and lets it work on its own. The harness keeps it on track:

- a plan and a spec;
- budgets;
- git checkpoints you can go back to;
- playtests with captures;
- checks it must report.

## Starting a run

1. Pick **One-shot** in the dock: the **One-shot** screen opens.
2. Write the goal. The editor grows with your screen, so long goals fit.
3. Review the budgets (time, tokens, playtests) and the options:
   - **Create a git checkpoint before each One-shot task**: one commit per task on an agent branch;
   - **Review the spec before building**: the agent writes the spec first and waits for you.
4. Start. If you have uncommitted changes, the harness asks first; they go into a "WIP" commit on the agent's branch, never on yours.

Never run One-shot on a repository where you don't want new branches. To try it, `tests/make_sandbox.sh <folder>` creates a throwaway project.

## How a run goes

1. **Spec**: the agent writes `spec.md`, a high-level description of the game: mechanics, game loop, visual direction and what "done" means. With **Review the spec before building**, the run waits in "Spec to review": the plan column shows the spec, **Edit** opens it and **Approve spec** starts the build. If you write in the chat instead, the agent revises it and waits again.
2. **Plan**: the agent turns the spec into tasks. You can edit the plan while it runs; the agent rereads it when its turn ends. Each task shows how long it took, and the current one counts live.
3. **Build and verify**: for each task, the agent edits, runs the game (`run_scene`), looks at frames (`capture_game_frame`), reads errors and reports **checks** (`pass`, `fail`, `pending`). It keeps `progress.md` up to date.
4. **Checkpoints**: each task (or each playtest, if the agent doesn't report a plan) is a `cpN` commit on the `agent/<date>` branch.
   - **Restore here** puts the project back exactly as it was at that checkpoint and pauses the run;
   - **Resume** continues from there.
5. **QA**: when the agent says the game is done, a separate evaluator checks it (see below). If it doesn't pass, its findings go back to the agent for another round.
6. **End**: when QA passes, the QA rounds run out, or a budget runs out, the run finishes (with a budget, the agent writes a final report first).
   - **Review changes** lists the files; double-click shows the diff against the start;
   - **Accept all** makes a final commit on `agent/<date>`. You do the merge;
   - **Report** shows what the harness measured (see below).

## The One-shot screen

- **Top bar**:
  - goal and phase;
  - budget bars: plan quota, time, tokens, playtests;
  - the active quota rule;
  - **Budgets**, **Switch account**, **Spec and progress**, **Pause**/**Resume** and **Stop**.
- **Plan**: tasks with their status and duration.
- **Activity**: everything that happened, with timestamps:
  - tool calls with their duration;
  - turns ("Turn 3 · 4 min 12 s · 9 tools");
  - checkpoints, playtests, quota and budget events;
  - your guidance.
- **Side**: the last playtest capture, the checks and the checkpoint list.
- **Bottom bar**: summary of changed files, **Review changes**, **Accept all**.

## QA evaluator

The agent that builds tends to be lenient with its own work, so the harness doesn't take its checks at face value.

- When the agent says it's done, a **new session** opens for an evaluator. It doesn't see the builder's conversation: only the goal, the spec, the builder's notes (as claims to verify), the checks it reported and the game criteria with their scoring examples.
- The evaluator **plays the game**: `run_scene` with inputs, live input, `game_get`/`game_wait` to check facts, frames and errors, and it reads the code. It **can't edit**: editing files, scenes or project settings and the shell are denied while it evaluates.
- It answers with checks, a score per criterion and concrete findings (what fails, how to reproduce it, where). Its report goes to `qa-<n>.md`.
- Its verdict decides the checks. The game passes when every check passes and every criterion reaches its minimum.
- If it doesn't pass, the run goes back to the builder's session with the failing checks, the criteria below the minimum and the findings as the next turn. When the builder says it's done again, a new QA round starts.
- **QA rounds** (Settings → One-shot, 2 by default) is how many evaluations a run gets; 0 turns the evaluator off. QA turns count toward the budgets, and a run with no budget left ends without another round.
- During an evaluation the phase reads **Evaluating · QA round n**, the activity shows each round's verdict and findings, and **Pause** works as usual (Resume evaluates again). The report has a table with the rounds.

## Guiding the agent

While a One-shot runs, whatever you write in the dock's chat goes to the run's agent. If the agent is in the middle of a turn, the message waits:

- the activity shows **guide · queued: …** and the chat says so;
- when the turn ends it's sent, and the activity shows **guide · sent: …**.

## Budgets

- **Time**, **tokens** and **playtests**.
- At 80 % you get a warning. At 100 % the agent is asked for its final report and the run ends.
- **Budgets** in the top bar changes them while the run is going: 0 means no limit, and **Unlimited** removes all of them. If the run was closing because of a budget and the new one is enough, it continues.

## Loops

If the agent repeats itself without progress, the run asks it to try another approach. That covers:

- the same check failing the same way;
- the same tool call failing with the same arguments;
- the same edit over and over.

If it happens again, the run pauses and waits for you to guide it. The number of repeats is set in **Settings → One-shot**.

## Spec, progress and QA files

They live in `.godot_agent/oneshot/<id>/` inside the project: `spec.md`, `progress.md` and `qa-<n>.md`.

- **Spec and progress** opens them in tabs, with **Show in folder** and **Open in external editor**. Clicking their path in the chat opens the same viewer.
- If the run has to continue in a new session, the agent rereads them.
- The folder has a `.gdignore`: it stays out of the FileSystem dock and the export. It travels in the checkpoints of the agent's branch; if you don't want it in your branch, delete it before merging.

## Game criteria

The agent knows from the start how its work will be judged:

- playability;
- functionality;
- visuals and feel;
- code.

Each criterion has a weight and a minimum score from 0 to 10, which you can change in **Settings → One-shot**.

## Plan quota

If the agent reports its plan quota (Claude Code does):

- **Warning** at 75 %.
- **Pause** at 90 %: the run pauses when the current task or turn ends, so a task isn't cut in half. If neither happens within 10 minutes, or the quota reaches 98 %, it stops the turn anyway and pauses with a `-quota` checkpoint. The banner says when it will pause.
- **Limited**: when the limit hits, sending is blocked with a countdown, and a `cpN-quota` checkpoint saves the state. When the window resets, the run resumes on its own or waits for your confirmation (**Settings → One-shot and quota**). **Resume** tries right away.

### Switching accounts

If you have another account, you don't have to wait for the reset. Open **Switch account** in the top bar:

- **Sign in with another account · <method>** runs the agent's login from the editor. When it finishes, the run continues;
- **I already signed in with another account (in a terminal)**: for when you did it yourself (`claude`, then `/login`).

Either way the harness restarts the agent so it picks up the new credentials, forgets the old account's quota and resumes **the same session** (`session/load`): the agent keeps its context.

## Closing the editor mid-run

The run is saved in `user://` while it goes. If the editor closes or crashes:

- on reopening, the run is back in the One-shot screen with its activity and a notice in the chat;
- if it was waiting for the quota, it keeps waiting and resumes on its own at the reset time. **Resume** or **Switch account** skip the wait;
- otherwise it's paused: **Resume** reopens the agent's session (or a new one with a summary of the plan);
- **Stop** ends it.

The dock's **Retry** button, during a One-shot, resumes the run in its own session.

## The report

When the run ends, **Report** shows what the harness measured, not what the agent claims:

- duration per task;
- times: working time, turns (average and longest), time waiting for the quota, paused or reviewing the spec;
- tokens and playtests;
- tools with uses, failures and time;
- how many times each check failed;
- permissions, errors, quota pauses, loops, account switches and changed files.

It's saved in `user://godot_agent/oneshot/<id>.report.json` to compare runs, and **Copy Markdown** copies it.

## Without git

Without git, or in a repository with no commits, there are no checkpoints. The harness warns you before starting.
