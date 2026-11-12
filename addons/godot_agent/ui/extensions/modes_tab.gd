@tool
extends "recipes_tab.gd"
## Pestaña «Modes» de Extensions (m11-39): los modos del proyecto de su carpeta, con su estado (✓ o
## cuántos errores), y el .json del elegido en un editor que valida mientras se escribe. «New» copia una
## plantilla (core/mode_templates.gd); «Use in the dock» lo elige en el dock. La misma pestaña que las
## recetas, con otro formato.

const ProjectModes := preload("../../core/project_modes.gd")
const ModeTemplates := preload("../../core/mode_templates.gd")


func _init() -> void:
	super()
	name = "Modes"


func _texts() -> Dictionary:
	return {
		"intro": I18n.t("Modes with their own name, instructions and the files they may edit, on top of Ask, Review, Build or Auto. One .json per mode in the project's modes folder, shared through git. Pick them in the composer's mode selector."),
		"new": I18n.t("New mode"),
		"new_tooltip": I18n.t("A new mode from a template, saved in the modes folder."),
		"use_tooltip": I18n.t("Switch the agent dock to this mode."),
		"empty": I18n.t("No modes in %s yet. «New mode» copies a template there."),
		"dirty": I18n.t("Save or revert «%s» before opening another mode."),
		"valid": I18n.t("✓ The mode is valid."),
		"invalid_use": I18n.t("Save a valid mode first."),
	}


func _load_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for item: Dictionary in ProjectModes.load_dir(recipes_dir()):
		var mode: Dictionary = item.mode
		var base := I18n.t(SessionModelLabels.label(str(mode.base)))
		items.append({"path": mode.path, "title": str(mode.name) if not str(mode.name).is_empty() else str(mode.slug),
			"description": ProjectModes.summary(mode, base), "errors": item.errors})
	return items


func _parse_errors(text: String, path: String) -> PackedStringArray:
	return ProjectModes.parse(text, path).errors


func _templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for template: Dictionary in ModeTemplates.all():
		result.append({"id": template.id, "label": template.label, "slug": str(template.id), "text": ModeTemplates.text(str(template.id))})
	return result


func _default_dir() -> String:
	return ProjectModes.DEFAULT_DIR


func mode_count() -> int:
	return recipe_count()


## Los nombres de los modos base para mostrar, sin cargar SessionModel (msgids).
class SessionModelLabels:
	const LABELS := {"ask": "Ask", "review": "Review", "build": "Build", "auto": "Auto"}

	static func label(base: String) -> String:
		return LABELS.get(base, base)
