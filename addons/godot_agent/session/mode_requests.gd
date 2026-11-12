@tool
extends RefCounted
## godot.request_mode (m11-68): el agente propone pasar a otro modo, fijo o del proyecto, y el usuario
## decide con una tarjeta. Acá lo que no depende de la sesión: a qué modo se refiere, si el destino
## tiene más permisos, los textos de la tarjeta y la línea del system prompt.

const SessionModel := preload("session_model.gd")
const PermissionPolicy := preload("permission_policy.gd")
const ProjectModes := preload("../core/project_modes.gd")
const I18n := preload("../core/i18n.gd")

const WHY_MAX := 600
## Los modos fijos a los que se puede pedir pasar. One-shot no: es una pantalla con su run.
const FIXED: Array[int] = [SessionModel.HarnessMode.ASK, SessionModel.HarnessMode.REVIEW, SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]


## `{mode: int, project_mode: Dictionary, error: String}` para `target` (ask, review, build, auto o el
## nombre o slug de un modo del proyecto de `project_modes`).
static func resolve(target: String, project_modes: Array[Dictionary]) -> Dictionary:
	var wanted := target.strip_edges().to_lower()
	if wanted.is_empty():
		return {"error": "`mode` is empty. %s" % available_text(project_modes)}
	for mode: int in FIXED:
		if wanted == str(SessionModel.HARNESS_MODE_LABELS[mode]).to_lower():
			return {"mode": mode, "project_mode": {}, "error": ""}
	if wanted in ["oneshot", "one-shot"]:
		return {"error": "One-shot is not a mode you can switch to: the user starts a One-shot run from its own screen."}
	var found := ProjectModes.find(project_modes, wanted)
	if found.is_empty():
		return {"error": "There is no mode called «%s». %s" % [target.strip_edges(), available_text(project_modes)]}
	return {"mode": int(SessionModel.BASE_MODES.get(str(found.base), SessionModel.HarnessMode.ASK)), "project_mode": found, "error": ""}


## Los modos que se pueden pedir, para el agente.
static func available_text(project_modes: Array[Dictionary]) -> String:
	var names: PackedStringArray = []
	for mode: int in FIXED:
		names.append(str(SessionModel.HARNESS_MODE_LABELS[mode]))
	for mode: Dictionary in project_modes:
		names.append("«%s»" % mode.name)
	return "The modes are: %s." % ", ".join(names)


## La línea del system prompt: cuándo pedir otro modo y cuáles hay, con su «cuándo usarlo».
static func prompt_line(project_modes: Array[Dictionary]) -> String:
	var text := " If the task needs another mode (you are in Ask and the user wants a change, or a project mode below fits the task better), don't work around the current one: propose the switch with `godot.request_mode` {mode, why}. The user decides with a card; it never switches by itself. Fixed modes: Ask, Review, Build, Auto."
	if project_modes.is_empty():
		return text
	var lines: PackedStringArray = []
	for mode: Dictionary in project_modes:
		var when := str(mode.get("when_to_use", "")).strip_edges()
		lines.append("«%s» (based on %s)%s" % [mode.name, SessionModel.HARNESS_MODE_LABELS[SessionModel.BASE_MODES.get(str(mode.base), SessionModel.HarnessMode.ASK)], ": " + when if not when.is_empty() else ""])
	return text + " Project modes: " + "; ".join(lines) + "."


## true si `to` (modo y capa) puede hacer más sin preguntar que `from`: un modo fijo de rango mayor
## (MODE_RANKS de m11-65), o una capa que limita menos (sin archivos limitados, la shell abierta).
static func escalates(from_mode: int, from_layer: Dictionary, to_mode: int, to_layer: Dictionary) -> bool:
	return not escalation_reasons(from_mode, from_layer, to_mode, to_layer).is_empty()


## Qué tiene de más el destino, en palabras (msgids): [] si nada.
static func escalation_reasons(from_mode: int, from_layer: Dictionary, to_mode: int, to_layer: Dictionary) -> PackedStringArray:
	var reasons: PackedStringArray = []
	var from_rank := int(PermissionPolicy.MODE_RANKS.get(from_mode, 0))
	var to_rank := int(PermissionPolicy.MODE_RANKS.get(to_mode, 2))
	if to_rank > from_rank:
		if to_rank >= 2:
			reasons.append("edits without asking")  # i18n
		else:
			reasons.append("can edit files")  # i18n
	if ProjectModes.limits_files(from_layer) and not ProjectModes.limits_files(to_layer) and to_rank > 0:
		reasons.append("isn't limited to some files")  # i18n
	if ProjectModes.shell_denied(from_layer) and not ProjectModes.shell_denied(to_layer):
		reasons.append("can run shell commands")  # i18n
	elif ProjectModes.shell_always_asks(from_layer) and not ProjectModes.shell_always_asks(to_layer) and not ProjectModes.shell_denied(to_layer) and to_rank >= 2:
		reasons.append("runs allowed shell commands without asking")  # i18n
	return reasons


## Para mostrar: «Levels (Construir)» o «Construir». Traducido.
static func label(mode: int, layer: Dictionary) -> String:
	var base := I18n.t(SessionModel.HARNESS_MODE_LABELS[mode])
	return "%s (%s)" % [layer.name, base] if not layer.is_empty() else base


## true si `to` es el modo en que ya está la sesión.
static func is_current(model: SessionModel, mode: int, layer: Dictionary) -> bool:
	if layer.is_empty():
		return model.project_mode.is_empty() and model.harness_mode == mode
	return not model.project_mode.is_empty() and model.project_mode.get("path") == layer.get("path") and model.harness_mode == mode


## El texto de la tarjeta: de dónde a dónde, qué edita el destino, el aviso de permisos y el porqué
## del agente (texto del agente, se muestra entre comillas).
static func card_description(model: SessionModel, mode: int, layer: Dictionary, why: String) -> String:
	var parts: PackedStringArray = []
	parts.append(I18n.t("From %s to %s.") % [model.mode_display(), label(mode, layer)])
	if not layer.is_empty():
		parts.append(ProjectModes.summary(layer, I18n.t(SessionModel.HARNESS_MODE_LABELS[mode])))
	var reasons := escalation_reasons(model.harness_mode, model.project_mode, mode, layer)
	if not reasons.is_empty():
		var shown: PackedStringArray = []
		for reason: String in reasons:
			shown.append(I18n.t(reason))
		parts.append(I18n.t("⚠ More permissions: %s %s.") % [label(mode, layer), ", ".join(shown)])
	parts.append(I18n.t("The agent says: «%s»") % why.strip_edges().left(WHY_MAX))
	return "\n".join(parts)


## Las dos opciones de la tarjeta: sin «siempre» (cada cambio de modo se decide).
static func card_options(model: SessionModel, mode: int, layer: Dictionary) -> Array:
	return [
		{"optionId": "switch", "name": I18n.t("Switch to %s") % label(mode, layer), "kind": "allow_once"},
		{"optionId": "stay", "name": I18n.t("Stay in %s") % model.mode_display(), "kind": "reject_once"},
	]


## Lo que vuelve al agente al aceptar: el modo nuevo y sus reglas, que valen desde ya.
static func switched_text(mode: int, layer: Dictionary, rules: String) -> String:
	var name := "%s (a project mode based on %s)" % [layer.name, SessionModel.HARNESS_MODE_LABELS[mode]] if not layer.is_empty() else str(SessionModel.HARNESS_MODE_LABELS[mode])
	return "The user switched this session to %s. From now on: %s" % [name, rules]
