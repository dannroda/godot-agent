@tool
extends RefCounted
## Contadores de la sesión por fuente (spec §16.8): latencia p50/p95 de las últimas consultas,
## sugerencias mostradas, aceptadas (enteras o por palabra) y tasa de aceptación. Sin código.

## Latencias que se guardan por fuente (las más viejas se descartan).
const MAX_SAMPLES := 200

## fuente -> {latencies: PackedFloat64Array (ms), shown, accepted, partial, errors}
var sources: Dictionary = {}


func record_latency(source: String, ms: float) -> void:
	var entry := _entry(source)
	var latencies: PackedFloat64Array = entry.latencies
	latencies.append(ms)
	if latencies.size() > MAX_SAMPLES:
		latencies = latencies.slice(latencies.size() - MAX_SAMPLES)
	entry.latencies = latencies


func record(source: String, outcome: String) -> void:
	var entry := _entry(source)
	if entry.has(outcome):
		entry[outcome] = int(entry[outcome]) + 1


## [{source, p50, p95, samples, shown, accepted, partial, errors, acceptance}], en orden de fuente.
func summary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names: Array = sources.keys()
	names.sort()
	for source: String in names:
		var entry: Dictionary = sources[source]
		var sorted: PackedFloat64Array = (entry.latencies as PackedFloat64Array).duplicate()
		sorted.sort()
		out.append({
			"source": source, "samples": sorted.size(),
			"p50": sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0,
			"p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))] if not sorted.is_empty() else 0.0,
			"shown": entry.shown, "accepted": entry.accepted, "partial": entry.partial, "errors": entry.errors,
			"acceptance": float(entry.accepted) / float(entry.shown) if int(entry.shown) > 0 else 0.0,
		})
	return out


## Una línea por fuente, para el log (`cmp`).
func format_line() -> String:
	var parts := PackedStringArray()
	for row: Dictionary in summary():
		parts.append("%s p50 %.1f ms p95 %.1f ms, %d/%d aceptadas" % [row.source, row.p50, row.p95, row.accepted, row.shown])
	return "; ".join(parts)


func clear() -> void:
	sources.clear()


func _entry(source: String) -> Dictionary:
	if not sources.has(source):
		sources[source] = {"latencies": PackedFloat64Array(), "shown": 0, "accepted": 0, "partial": 0, "errors": 0}
	return sources[source]
