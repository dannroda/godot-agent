@tool
extends RefCounted
## Variantes en paralelo (m11-90, idea de Capy): el agente propone con godot.propose_variants varias
## formas de hacer lo mismo, el usuario elige cuáles van (y edita o agrega), y cada una se implementa
## en su propia copia (git worktree) a la vez. Las regresiones guardadas del proyecto van a cada copia
## y después las juzgan a todas igual. Acá lo que no depende del editor: limpiar lo propuesto, los
## textos de la pestaña y el prompt de cada copia.

const MIN := 2
const MAX := 4
const GOAL_MAX := 1000
const TEXT_MAX := 300
const LABEL_MAX := 24


## Las variantes sin vacías ni repetidas (sin distinguir mayúsculas), cada una cortada a TEXT_MAX.
static func clean(variants: Array) -> PackedStringArray:
	var result: PackedStringArray = []
	var seen := {}
	for variant: Variant in variants:
		var text := str(variant).strip_edges().left(TEXT_MAX)
		if text.is_empty() or seen.has(text.to_lower()):
			continue
		seen[text.to_lower()] = true
		result.append(text)
	return result


## Por qué no vale lo que propone el agente, o "". Puede proponer más de MAX: el usuario elige.
static func check(goal: String, variants: PackedStringArray) -> String:
	if goal.strip_edges().is_empty():
		return "`goal` is empty: say in one line what all the variants try to achieve."
	if variants.size() < MIN:
		return "Propose at least %d different variants (one line each)." % MIN
	return ""


## El nombre de la pestaña: «V2 · Coyote time + buffer».
static func tab_label(index: int, variant: String) -> String:
	var short := variant.strip_edges()
	if short.length() > LABEL_MAX:
		short = short.left(LABEL_MAX - 1).strip_edges() + "…"
	return "V%d · %s" % [index + 1, short]


## Lo que recibe el agente de la copia `index`: el objetivo, su variante, las otras (para no
## hacerlas) y qué la juzga. `judges`: cuántas regresiones guardadas van a la copia.
static func copy_prompt(goal: String, variants: PackedStringArray, index: int, judges: int) -> String:
	var others: PackedStringArray = []
	for i in variants.size():
		if i != index:
			others.append("- V%d: %s" % [i + 1, variants[i]])
	var judged := "The project's %d saved regressions (res://.godot_agent/playtests/regressions/) will judge every variant the same way, with their invariants and budgets: don't edit, move or delete them, or this variant doesn't count." % judges \
		if judges > 0 else "The project has no saved regressions, so the user will compare the variants by playing them."
	return "You are implementing variant V%d of %d for this goal: %s\n\nYour variant: %s\n\nThe other variants are being built in parallel in their own copies, so don't build them here:\n%s\n\n%s Implement your variant fully and keep the rest of the game working; check it headless as the guide above says. When you are done, end your turn with a short summary of what you changed and anything the user should try when playing it." % [
		index + 1, variants.size(), goal.strip_edges().left(GOAL_MAX), variants[index], "\n".join(others), judged]


## Lo que vuelve al agente que propuso, según lo que eligió el usuario.
static func result_text(opened: PackedStringArray, failed: PackedStringArray) -> String:
	if opened.is_empty():
		return "No copy could be opened: %s" % "; ".join(failed)
	var text := "The user picked %d variants; each one is being built in its own tab and copy: %s. Don't build them here. The user will compare them and apply one." % [opened.size(), ", ".join(opened)]
	if not failed.is_empty():
		text += " Could not open: %s" % "; ".join(failed)
	return text
