# Inline completion

[Home](Home.md) · [Español](../es/Completado-inline.md)

Grey suggestions while you type in the Script Editor. By default they are **local only**: no AI, no agent, nothing leaves the editor. An LLM is optional.

## Keys

| Key | What it does |
|---|---|
| **Tab** | Accepts the suggestion (one undo step). With no suggestion, or with Godot's completion popup open, Tab works as usual. |
| **Ctrl+→** | Accepts word by word. |
| **Esc** | Dismisses it. |
| **Alt+\\** | Asks for one by hand (in hybrid mode, straight to the LLM). |
| **Alt+Shift+\\** | Turns completion on or off. |

## Where suggestions come from

- **Godot rules**:
  - `@onready var ` proposes the scene's child nodes with type and path;
  - `func _` proposes the base class's virtual methods with their signature;
  - `$` and `%` propose node paths;
  - there are rules for input actions, groups, `.connect(`, `func _on_`, `preload("` and `extends `.
- **Project lines**: a line that repeats in other scripts is suggested as you type its beginning. If it repeats with another name (`enemy_` instead of `player_`), it's adapted. On an empty line, what usually follows the line above is suggested, or a short block if the project always writes it the same way.
- **n-gram**: a model of the project's tokens completes the line while it's confident.
- **History**: what you wrote in this session.

Multi-line suggestions show the first line in place and the rest in a box below. When two options are too close, nothing is shown.

The project index builds in the background and leaves `addons/` out of the suggested lines.

## Settings

**Settings → Completion** edits everything and shows each source's latency (p50/p95) and acceptance rate for the session. Changes apply without restarting.

- on/off;
- debounce, threshold and margin;
- multi-line and maximum lines;
- each source on or off;
- extra corpus: folders of other projects of yours that only train the n-gram.

The **● Completion** indicator in the Script Editor bar shows the state: green active, amber waiting for the LLM, red error, grey off. Clicking it toggles completion.

## With an LLM (optional)

Pick the mode in **Settings → Completion**:

- **Local only** (default): no network.
- **Hybrid**: local suggestions as always. If there's nothing local, after 200 ms without typing the LLM is asked.
- **LLM only**.

| Profile | Default URL | Notes |
|---|---|---|
| Ollama | `http://127.0.0.1:11434` | `ollama pull qwen2.5-coder:1.5b-base` (`-base` models have FIM). |
| llama.cpp (`llama-server`) | `http://127.0.0.1:9931` | `/infill` endpoint; load a model with FIM. |
| Codestral | `https://api.mistral.ai` | Key in `MISTRAL_API_KEY`. |
| OpenAI-compatible (LM Studio, vLLM…) | `http://127.0.0.1:1234` | `/v1/completions` with the model's FIM template. |
| Gemini (experimental) | Google | Key in `GEMINI_API_KEY`; no FIM, slower. |

- Keys are never stored: the profile has the **name** of the environment variable, and the value is read from the editor's environment for each request.
- A remote profile warns you that the code around the cursor, and a summary of the project (nodes, autoloads, actions), is sent to that server.
- LLM suggestions end with a small dot; you can turn it off.
- The Agent Log (`cmp` channel) records latencies and sizes, never code, unless you turn on **"Raw" log**.

## Ask the agent for a change (Alt+I)

Different from the suggestions above, this goes to the agent. Select some code (or leave the cursor where something should go) and press **Alt+I**, or right-click → **Ask the agent to change this…**. Write what you want ("make these constants", "add a jump with coyote time") and press Enter.

The request goes to the session of the dock's active tab, with the file, the lines and the selected code, and the agent answers with just the new code. It shows up as a diff next to the code: **Accept** replaces the selection (or inserts at the cursor) as one Ctrl+Z step, without saving the file; **Reject** leaves it as it was. If you changed that code while the agent was answering, the proposal is not applied. The request and the answer also stay in the chat. A session has to be started in the dock, and free (not in the middle of a turn).
