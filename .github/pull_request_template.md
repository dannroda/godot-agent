## What and why

<!-- What changes, and the problem it solves. Link the issue if there is one (Fixes #123). -->

## How it was tested

<!-- Which tests you ran and on which Godot versions; for UI changes, a screenshot. -->

## Checklist

- [ ] Unit tests pass: `godot --headless --path . --script tests/run_all.gd`
- [ ] New behavior has a test (`tests/unit/` or a dev-plugin check)
- [ ] User-facing texts use `I18n.t()` and have their Spanish translation in `es.po`
- [ ] A line under **Unreleased** in `CHANGELOG.md`, in English (if users would notice the change)
- [ ] Wiki and READMEs updated in English and Spanish (if it changes what users see or do)
- [ ] `addons/godot_agent/config/project_config.tres` is not in the diff

See [CONTRIBUTING.md](https://github.com/dannroda/godot-agent/blob/main/CONTRIBUTING.md).
