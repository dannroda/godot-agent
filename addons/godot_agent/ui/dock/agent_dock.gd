@tool
extends VBoxContainer
## Dock "Agent". M0: esqueleto con el aviso de presets de export sin filtro.

const ExportPresetsPatcher := preload("../../export/export_presets_patcher.gd")

## export_presets.cfg no pasa por EditorFileSystem: se mira su fecha de modificación cada tanto.
const PRESETS_POLL_INTERVAL_S := 2.0

var _presets_mtime: int = -1

@onready var _export_banner: PanelContainer = %ExportBanner
@onready var _export_banner_label: Label = %ExportBannerLabel
@onready var _add_filter_button: Button = %AddFilterButton
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmPatchDialog
@onready var _result_dialog: AcceptDialog = %PatchResultDialog
@onready var _presets_poll_timer: Timer = %PresetsPollTimer


func _ready() -> void:
	_add_filter_button.pressed.connect(_on_add_filter_pressed)
	_confirm_dialog.confirmed.connect(_on_patch_confirmed)
	visibility_changed.connect(refresh_export_banner)
	_presets_poll_timer.wait_time = PRESETS_POLL_INTERVAL_S
	_presets_poll_timer.timeout.connect(_on_presets_poll)
	refresh_export_banner()


func refresh_export_banner() -> void:
	if not is_node_ready():
		return
	var missing := ExportPresetsPatcher.presets_missing_filter()
	_export_banner.visible = not missing.is_empty()
	if _export_banner.visible:
		_export_banner_label.text = (
			"Los presets de export %s no excluyen '%s'. Si exportás con el plugin deshabilitado, el addon llega al juego."
			% [", ".join(missing), ExportPresetsPatcher.FILTER]
		)


func _on_presets_poll() -> void:
	if not is_visible_in_tree():
		return
	var mtime: int = 0
	if ExportPresetsPatcher.presets_file_exists():
		mtime = FileAccess.get_modified_time(ExportPresetsPatcher.PRESETS_PATH)
	if mtime != _presets_mtime:
		_presets_mtime = mtime
		refresh_export_banner()


func _on_add_filter_pressed() -> void:
	var missing := ExportPresetsPatcher.presets_missing_filter()
	_confirm_dialog.dialog_text = (
		"Se va a agregar '%s' al filtro de exclusión de estos presets:\n\n• %s\n\nSe modifica %s."
		% [ExportPresetsPatcher.FILTER, "\n• ".join(missing), ExportPresetsPatcher.PRESETS_PATH]
	)
	_confirm_dialog.popup_centered()


func _on_patch_confirmed() -> void:
	var patched := ExportPresetsPatcher.patch_presets()
	refresh_export_banner()
	if patched.is_empty():
		_result_dialog.dialog_text = "No se modificó ningún preset. Revisá el panel Output."
	else:
		_result_dialog.dialog_text = (
			"Filtro agregado a: %s.\n\nReiniciá el editor antes de abrir el diálogo de Exportar: si no, puede pisar el cambio al guardar los presets."
			% ", ".join(patched)
		)
	_result_dialog.popup_centered()
