@tool
extends RefCounted
## A qué cuenta o perfil pasar cuando se termina la cuota (m6-22): los perfiles de Ajustes con sus
## cuentas (las del selector del dock), la del agente que corre primero. «Cambiar de cuenta» las
## muestra; la cadena de reserva (m6-21) recorre la misma lista sin preguntar.
##
## Otra cuenta del mismo perfil retoma la misma sesión (se copia a la carpeta de la otra cuenta, si
## el agente lo sabe hacer); otro perfil es otro agente y abre una sesión nueva.

const AgentAccounts := preload("agent_accounts.gd")
const AgentAdapters := preload("agent_adapters.gd")
const AgentProfile := preload("../../core/agent_profile.gd")
const AccountQuotaBook := preload("../../core/account_quota_book.gd")
const I18n := preload("../../core/i18n.gd")


## [{profile (listo para lanzar, con la cuenta aplicada), profile_id, account_dir, name, label,
## same_agent, current, exhausted, quota}]. `settings` es un HarnessSettings; `current`, el perfil
## con el que corre el agente (null = ninguno: todas cuentan como de otro agente). `pause_at`: el
## umbral de pausa (0..1); una cuenta que quedó en él también cuenta como agotada.
static func list(settings: RefCounted, current: AgentProfile, book: AccountQuotaBook, pause_at: float = 2.0) -> Array[Dictionary]:
	var same: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for base: AgentProfile in settings.call(&"profiles"):
		var plain: AgentProfile = base.with_account("", "")
		var variable := AgentAccounts.variable_of(plain)
		var accounts: Array = AgentAccounts.menu(plain, settings.call(&"accounts", variable)).accounts if not variable.is_empty() else []
		var dirs: PackedStringArray = []
		var names: PackedStringArray = []
		for account: Dictionary in accounts:
			dirs.append(AgentAccounts.choice(plain, str(account.dir)))
			names.append(AgentAccounts.label_of(account) if not str(account.dir).is_empty() else I18n.t("The agent's default"))
		if dirs.is_empty():
			dirs.append("")
			names.append("")
		var is_same := current != null and current.id == base.id
		for i in dirs.size():
			var dir := dirs[i]
			var choice := {
				"profile": AgentAccounts.apply(plain, dir),
				"profile_id": base.id,
				"account_dir": dir,
				"name": base.display_name,
				"account": names[i],
				"same_agent": is_same,
				"current": is_same and dir == current.account_dir,
				"exhausted": book != null and book.is_exhausted(base.id, dir, pause_at),
				"quota": book.describe(base.id, dir) if book else "",
			}
			choice["label"] = label_of(choice)
			(same if is_same else others).append(choice)
	same.append_array(others)
	return same


## «trabajo · ana@empresa.com — agotada, se libera en 2 h» (con el nombre del perfil si es otro agente).
static func label_of(choice: Dictionary) -> String:
	var text := str(choice.account)
	if not bool(choice.same_agent):
		text = str(choice.name) if text.is_empty() else "%s · %s" % [choice.name, text]
	elif text.is_empty():
		text = str(choice.name)
	var quota := str(choice.get("quota", ""))
	return text if quota.is_empty() else "%s — %s" % [text, quota]


## La primera de la lista que no es la actual ni está agotada, del mismo agente si hay (m6-21); {} si
## no queda ninguna.
static func next_available(choices: Array[Dictionary], same_agent_only: bool = false) -> Dictionary:
	for choice: Dictionary in choices:
		if bool(choice.current) or bool(choice.exhausted):
			continue
		if same_agent_only and not bool(choice.same_agent):
			continue
		return choice
	return {}


## La carpeta donde el agente del perfil guarda su login y sus sesiones ("" = no se sabe).
static func effective_dir(profile: AgentProfile) -> String:
	if not profile.account_dir.is_empty():
		return AgentAccounts.normalize(profile.account_dir)
	var adapter := AgentAdapters.for_profile(profile.command, profile.args, profile.id)
	var variable := AgentAccounts.variable_for(profile, adapter)
	return AgentAccounts.base_dir(profile, adapter, variable) if not variable.is_empty() else ""


## Antes de relanzar con otra cuenta del mismo agente: copia la sesión `session_id` a la carpeta de
## la otra cuenta, así session/load la encuentra. true si quedó copiada; si no, se abre una sesión
## nueva con el resumen.
static func carry_session(from: AgentProfile, to: AgentProfile, session_id: String) -> bool:
	if from == null or to == null or session_id.is_empty() or from.id != to.id:
		return false
	var from_dir := effective_dir(from)
	var to_dir := effective_dir(to)
	if from_dir.is_empty() or to_dir.is_empty() or from_dir == to_dir:
		return false
	var adapter := AgentAdapters.for_profile(to.command, to.args, to.id)
	return adapter.carry_session(session_id, from_dir, to_dir)


## El perfil `profile_id` listo para lanzar con la cuenta `account_dir` ("" = la del perfil), como
## lo arma el menú; null si el perfil ya no existe. `settings` es un HarnessSettings.
static func resolve(settings: RefCounted, profile_id: String, account_dir: String) -> AgentProfile:
	var base: AgentProfile = settings.call(&"profile", profile_id)
	return AgentAccounts.apply(base.with_account("", ""), account_dir) if base else null
