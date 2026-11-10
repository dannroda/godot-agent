# Draft: godotengine/godot issue — GDScript profiler: calls already running when the profiler starts are timed from 0

> Draft for the godotengine/godot bug template. Not filed. Review before posting.
> Searched 2026-11-10: no existing issue or PR found.

### Tested versions

- Reproducible in 4.7.2.stable and 4.8.beta2 (official builds).
- The code is the same on `master` (checked 2026-11-10).

### System information

Linux (Arch), X11 under Xvfb, OpenGL 3 (software). Not platform-specific: the cause is in `modules/gdscript/gdscript_vm.cpp`.

### Issue description

If the script profiler starts while a GDScript function is running, that call is recorded with a
`time_taken` equal to the whole time since the engine started. The first profiler frame shows
hundreds of milliseconds (in our runs, 0.8–0.9 s) for a function that really takes about 0.1 µs.
The garbage also goes into the accumulated data, so `servers:profile_total` carries it too.

This happens often, not just in edge cases. The profiler is usually started in the middle of a busy
loop, because the debugger handles the `profiler:servers` message from `EngineDebugger::line_poll()`,
which runs every 2048 GDScript lines (`core/debugger/engine_debugger.h`). In our test, the first
frame was wrong in 3 of 6 runs.

The cause is in `GDScriptFunction::call()` (`modules/gdscript/gdscript_vm.cpp`, 4.7.2):

```cpp
#ifdef DEBUG_ENABLED
	uint64_t function_start_time = 0;
	uint64_t function_call_time = 0;

	if (GDScriptLanguage::get_singleton()->profiling) {
		function_start_time = OS::get_singleton()->get_ticks_usec();
		...
	}
...
	if (GDScriptLanguage::get_singleton()->profiling) {
		uint64_t time_taken = OS::get_singleton()->get_ticks_usec() - function_start_time; // start is 0 if profiling began mid-call
		profile.total_time.add(time_taken);
		profile.self_time.add(time_taken - function_call_time);
		profile.frame_total_time.add(time_taken);
		profile.frame_self_time.add(time_taken - function_call_time);
```

The profiling flag is checked separately at entry and at exit. A call that enters with profiling
off and exits with it on adds `ticks_usec() - 0`. The same pattern exists at the call sites that
measure `call_time` for `function_call_time` (`uint64_t call_time = 0; if (profiling) call_time = ...`).

Note: the call that was running also doesn't increment `frame_call_count`. So in the first frame,
the function that contains the loop may not be listed at all (`profiling_get_frame_data()` skips
functions with `last_frame_call_count == 0`). The functions it calls are listed, with a partial call count
and the huge time.

### Steps to reproduce

1. Use a scene with this script:

   ```gdscript
   extends Node

   const CALLS_PER_FRAME := 2000
   var _acc := 0.0

   func _process(_delta: float) -> void:
   	_hot()

   func _hot() -> void:
   	for i in CALLS_PER_FRAME:
   		_acc += _step(i)

   func _step(i: int) -> float:
   	return sqrt(float(i)) * 0.5
   ```

2. Run it from the editor and start the profiler (Debugger → Profiler → Start). It can also be started from an
   `EditorDebuggerPlugin` with `get_session(id).toggle_profiler("servers", true, [128, false])`.
3. Look at the first frame of script function data.

   Expected: `_step` with 2000 calls and a fraction of a millisecond.

   Actual (in about half of the attempts): `_step` with a partial count (352–1331 in our runs) and
   0.8–0.9 s of self/total time, which is the time since the game started. Later frames are correct.

We observed this through the `servers:profile_frame` messages the editor receives. The editor's
Profiler panel plots the same data. A test that reproduces it automatically is
`addons/godot_agent_dev/profile_check.gd` in [our repository; link before posting].

### Suggested fix

Profile a call only if profiling was already on when it started:

```diff
 #ifdef DEBUG_ENABLED
 	uint64_t function_start_time = 0;
 	uint64_t function_call_time = 0;
+	const bool profile_this_call = GDScriptLanguage::get_singleton()->profiling;

-	if (GDScriptLanguage::get_singleton()->profiling) {
+	if (profile_this_call) {
 		function_start_time = OS::get_singleton()->get_ticks_usec();
 		function_call_time = 0;
 		profile.call_count.increment();
 		profile.frame_call_count.increment();
 	}
@@
 	OPCODES_OUT
 #ifdef DEBUG_ENABLED
-	if (GDScriptLanguage::get_singleton()->profiling) {
+	if (profile_this_call && GDScriptLanguage::get_singleton()->profiling) {
 		uint64_t time_taken = OS::get_singleton()->get_ticks_usec() - function_start_time;
```

Apply the same treatment to the call-site timers: only add `t_taken` to `function_call_time` when
`call_time != 0`, or keep a local flag next to `call_time`. A call that starts before the profiler
then simply isn't counted, as if it had happened before profiling began.
