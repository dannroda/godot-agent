### Tested versions

- Reproducible in: v4.7.2.stable.official [ed1daf0bf] (error on every save in the attached project; a SIGSEGV seen only in a session with an addon, see below)
- Reproducible in: v4.8.beta2.official (same error, as `p_element->data != this`; no crash seen in 12 runs)
- Reproducible in: v4.8.beta3.official [c51ff06e8] (same error, as `p_element->data != this`)

### System information

Linux (Arch, kernel 7.2), X11 editor under Xvfb, Compatibility renderer (Mesa llvmpipe).

### Issue description

In the attached project, every save that goes through `EditorNode::_save_scene_with_preview` (Ctrl+S, `EditorInterface.save_scene()`) prints the following. It isn't universal: in another session of the same editor version, a save with preview printed nothing.

```
ERROR: Condition "p_I->data != this" is true. Returning: false
   at: erase (./core/templates/list.h:228)
```

The scene doesn't matter (an empty `Node2D` is enough), and nothing has to change on disk. Saving the same scene with `EditorInterface.save_scene_as(path, false)`, which skips the preview and the "Saving Scene" `EditorProgress`, prints nothing.

The error means a `List::Element` is being erased from a list it does not belong to. Possibly related, but not confirmed: in a larger editor session (an addon reloading an externally modified scene and an external write to `project.godot` before the save), the editor crashed with signal 11 within 1.5 s after `save_scene()` in about 3 of 4 runs. With the preview-less save, that same session never crashed (0 of 16 runs). Without the addon I never saw the crash (96 saves with preview, the error on every one), so I can't say the crash is this bug and not something the addon contributes. Official builds are stripped, so the backtrace only shows the main loop:

```
[1] libc.so.6(+0x3e6f0)
[2] /opt/godot/current() [0x2b2cba5]
[3] /opt/godot/current() [0x2b512e4]
[4] /opt/godot/current() [0x5661f9]
[5] /opt/godot/current() [0x42c157]
```

Unverified guess, from reading the 4.7.2 source: `ProgressDialog::_reparent_and_show()` reparents the dialog (a root `Control`) into the last exclusive window, and `Control::NOTIFICATION_EXIT_CANVAS` erases `data.RI` through `get_viewport()->_gui_remove_root_control()`. If `RI` was added to a different viewport's `gui.roots`, that produces exactly this error, and a crash once that list's memory is gone. I haven't confirmed this with a debug build.

### Steps to reproduce

1. Open the attached project in the editor with `-- --repro`, for example:
   `godot --path . -e -- --repro`
2. The `repro` plugin opens `main.tscn`, calls `EditorInterface.save_scene()` three times and then `EditorInterface.save_scene_as("res://main.tscn", false)` three times, and quits.

Output:

```
[repro] save_scene() (with preview) 0
ERROR: Condition "p_I->data != this" is true. Returning: false
   at: erase (./core/templates/list.h:228)
[repro] save_scene() (with preview) 1
ERROR: Condition "p_I->data != this" is true. Returning: false
   at: erase (./core/templates/list.h:228)
[repro] save_scene() (with preview) 2
ERROR: Condition "p_I->data != this" is true. Returning: false
   at: erase (./core/templates/list.h:228)
[repro] save_scene_as(path, false) (no preview) 0
[repro] save_scene_as(path, false) (no preview) 1
[repro] save_scene_as(path, false) (no preview) 2
[repro] done
```

### Minimal reproduction project (MRP)

`save_preview_list_erase/` (zip it before attaching).
