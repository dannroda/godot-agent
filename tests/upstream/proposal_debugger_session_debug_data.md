# Draft: godot-proposals — Let EditorDebuggerPlugin sessions see messages the editor already handles (profiler frames)

> Draft for the godot-proposals template. Not filed. Review before posting.
> Source references are to `4.7.2-stable`; `master` (checked 2026-11-10) has the same code at slightly different line numbers.

### Describe the project you are working on

An editor plugin (an AI agent harness) that runs the user's game from the editor and reports back
what it finds: errors, scene state, and, for this proposal, where the frame time goes ("which
script functions are slow in this scene?").

### Describe the problem or limitation you are having in your project

An `EditorDebuggerPlugin` can start the script/servers profiler in the running game:

```gdscript
session.toggle_profiler("servers", true, [128, false]) # [max_functions, include_native]
```

The game then sends `servers:function_signature`, `servers:profile_frame` and
`servers:profile_total` messages. But the plugin never receives them, so it can't read the
data it asked for.

`ScriptEditorDebugger::_parse_message()` (`editor/debugger/script_editor_debugger.cpp:983`)
offers a message to `EditorDebuggerNode::plugins_capture()` only when the message has no built-in
handler:

```cpp
ParseMessageFunc *fn_ptr = parse_message_handlers.getptr(p_msg);
if (fn_ptr) {
	(this->**fn_ptr)(p_thread_id, p_data);
} else {
	...
	bool parsed = EditorDebuggerNode::get_singleton()->plugins_capture(this, p_msg, p_data);
```

`servers:*`, `performance:*`, `visual:*`, `scene:*` and the other built-in messages all have
handlers, so `_has_capture("servers")` / `_capture()` never see them. `EditorDebuggerSession`
exposes only `started`, `stopped`, `breaked` and `continued`.

The result is that a plugin can turn the profiler on but has to go back to the human user, who
has to read the Profiler tab.

### Describe the feature / enhancement and how it helps to overcome the problem or limitation

Give `EditorDebuggerSession` a read-only signal that forwards every message the session receives
from the game, whether or not the editor already handles it:

```
signal debug_data(message: String, data: Array)
```

A plugin connects to it and gets the profiler frames (and any other built-in message) without
consuming them. The editor's own handling is unchanged.

`ScriptEditorDebugger` already emits exactly this signal for every message, as its first
statement in `_parse_message()`. It is registered with `ADD_SIGNAL` (`script_editor_debugger.cpp:2075`),
but it is not reachable through the public API because `ScriptEditorDebugger` is an internal
editor class. So the change only forwards an existing signal.

### Describe how your proposal will work, with code, pseudo-code, mockups, and/or diagrams

Approximate diff against `master`:

```diff
--- a/editor/debugger/editor_debugger_plugin.h
+++ b/editor/debugger/editor_debugger_plugin.h
@@ class EditorDebuggerSession : public RefCounted {
 	void _breaked(bool p_really_did, bool p_can_debug, const String &p_message, bool p_has_stackdump);
 	void _started();
 	void _stopped();
+	void _debug_data(const String &p_message, const Array &p_data);
```

```diff
--- a/editor/debugger/editor_debugger_plugin.cpp
+++ b/editor/debugger/editor_debugger_plugin.cpp
@@ void EditorDebuggerSession::_bind_methods() {
 	ADD_SIGNAL(MethodInfo("started"));
 	ADD_SIGNAL(MethodInfo("stopped"));
 	ADD_SIGNAL(MethodInfo("breaked", PropertyInfo(Variant::BOOL, "can_debug")));
 	ADD_SIGNAL(MethodInfo("continued"));
+	ADD_SIGNAL(MethodInfo("debug_data", PropertyInfo(Variant::STRING, "message"), PropertyInfo(Variant::ARRAY, "data")));
 }
@@
@@ void EditorDebuggerSession::detach_debugger() {
 	debugger->disconnect("breaked", callable_mp(this, &EditorDebuggerSession::_breaked));
+	debugger->disconnect("debug_data", callable_mp(this, &EditorDebuggerSession::_debug_data));
@@
+void EditorDebuggerSession::_debug_data(const String &p_message, const Array &p_data) {
+	emit_signal(SNAME("debug_data"), p_message, p_data);
+}
+
 EditorDebuggerSession::EditorDebuggerSession(ScriptEditorDebugger *p_debugger) {
 	...
 	debugger->connect("breaked", callable_mp(this, &EditorDebuggerSession::_breaked));
+	debugger->connect("debug_data", callable_mp(this, &EditorDebuggerSession::_debug_data));
 }
```

`doc/classes/EditorDebuggerSession.xml` needs a `<signal name="debug_data">`
entry saying that it fires for every message, including ones the editor handles, and that
connecting doesn't consume the message.

Plugin side:

```gdscript
func _setup_session(id: int) -> void:
	var session := get_session(id)
	session.debug_data.connect(_on_debug_data)

func _on_debug_data(message: String, data: Array) -> void:
	match message:
		"servers:function_signature":
			_signatures[data[1]] = data[0] # "res://path.gd::line::name" -> id
		"servers:profile_frame", "servers:profile_total":
			_frames.append(data) # ServersProfilerFrame layout, see servers_debugger.cpp
```

Cost: a signal with no connections costs a lookup per message. The same emit already happens
in `ScriptEditorDebugger`.

#### Alternatives considered

1. **Offer handled messages to `_capture()` too**, but ignore the return value, so plugins can
   observe without consuming. This is a small change in `_parse_message()`, but it changes what
   existing plugins see. A plugin that captures `"scene"` or `"servers"` for its own messages
   would start receiving the editor's messages, and its `_capture()` returning `true` would now
   mean nothing. That is a behavior change for existing plugins.
2. **A specific `profiler_frame(frame: Dictionary)` signal** on `EditorDebuggerSession`, built from the
   deserialized `ServersProfilerFrame`. It is friendlier because the plugin doesn't need to know
   the wire format. But it is more code, it covers only one profiler, and it freezes a dictionary
   layout. The generic signal can come first and this one can be added later if wanted.
3. **Status quo plus the workaround below.**

### If this enhancement will not be used often, can it be worked around with a few lines of script?

There is a workaround, but it relies on internals. A plugin can find the internal
`ScriptEditorDebugger` nodes in the editor tree and connect to their `debug_data` signal
directly:

```gdscript
for dbg in EditorInterface.get_base_control().find_children("*", "ScriptEditorDebugger", true, false):
	dbg.debug_data.connect(_on_debug_data)
```

Problems with it:

- `ScriptEditorDebugger` is not documented or exposed. The class name, the signal and the
  tab layout of `EditorDebuggerNode` can change in any release without a compatibility note.
- Mapping a node to a session index means reproducing `EditorDebuggerNode::plugins_capture()`'s
  `tabs->get_tab_idx_from_control()` logic by hand.
- Sessions are created per run (multiple instances add tabs), so the plugin has to watch for new
  debugger nodes.

### Is there a reason why this should be core and not an add-on in the asset library?

Yes. Add-ons can't change which messages reach `EditorDebuggerPlugin`; only the editor's
debugger can.

### Related

- godotengine/godot#96210: EditorDebuggerPlugin doesn't receive messages (open). Related
  confusion about which messages reach `_capture()`.
- godotengine/godot#102972 (open).
- godotengine/godot#66938: Better expose editor debugger plugins (merged). Introduced
  `EditorDebuggerSession`.
- godotengine/godot#86721: GDExtension debugger tooling (merged).
- godotengine/godot-proposals#13631: Profiler heuristics (open). Could build on the same data.
- godotengine/godot-proposals#8777 (closed).

No existing issue, proposal or PR asks for plugins to receive profiler frames. Searched on
2026-11-10.
