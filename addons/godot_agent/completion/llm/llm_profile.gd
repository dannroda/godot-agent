@tool
extends RefCounted
## Perfil de un proveedor LLM del completado (spec §16.3, §16.10). Se guarda como Dictionary en
## EditorSettings. La API key nunca se guarda: el perfil tiene el **nombre** de la variable de
## entorno y se lee con `OS.get_environment` al armar cada pedido.

const KIND_OLLAMA := "ollama"
const KIND_LLAMACPP := "llamacpp"
const KIND_CODESTRAL := "codestral"
const KIND_OPENAI := "openai"
const KIND_GEMINI := "gemini"
const KINDS: PackedStringArray = [KIND_OLLAMA, KIND_LLAMACPP, KIND_CODESTRAL, KIND_OPENAI, KIND_GEMINI]
const KIND_LABELS: Dictionary = {
	KIND_OLLAMA: "Ollama (local, FIM)",
	KIND_LLAMACPP: "llama.cpp server (local, FIM)",
	KIND_CODESTRAL: "Codestral · Mistral (remoto, FIM)",
	KIND_OPENAI: "OpenAI-compatible (/v1/completions)",
	KIND_GEMINI: "Gemini (remoto, experimental)",
}
## Plantilla FIM en crudo de Qwen2.5-Coder (para servers sin `suffix`, spec §16.3).
const QWEN_FIM := "<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>"
const QWEN_STOPS: PackedStringArray = ["<|endoftext|>", "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<|fim_pad|>", "<|file_sep|>", "<|repo_name|>", "<|im_end|>"]
## URL, modelo y plantilla con los que arranca un perfil nuevo de cada tipo (verificados en D28):
## - Ollama: los tags `-base` de qwen2.5-coder traen FIM en la plantilla (`suffix`).
## - llama.cpp: el puerto por defecto pasó de 8080 a 9931 (octubre de 2026).
## - Codestral: `api.mistral.ai` es el host de la spec oficial (codestral.mistral.ai usa otra key).
## - OpenAI-compatible: `suffix` no es portable (llama.cpp y vLLM lo rechazan), así que va la
##   plantilla en crudo de Qwen; se vacía para un server que sí acepte `suffix`.
const KIND_DEFAULTS: Dictionary = {
	KIND_OLLAMA: {"url": "http://127.0.0.1:11434", "model": "qwen2.5-coder:1.5b-base"},
	KIND_LLAMACPP: {"url": "http://127.0.0.1:9931", "model": ""},
	KIND_CODESTRAL: {"url": "https://api.mistral.ai", "model": "codestral-latest", "api_key_env": "MISTRAL_API_KEY"},
	KIND_OPENAI: {"url": "http://127.0.0.1:1234", "model": "", "fim_template": QWEN_FIM},
	KIND_GEMINI: {"url": "https://generativelanguage.googleapis.com", "model": "gemini-3.5-flash-lite", "api_key_env": "GEMINI_API_KEY"},
}
var id: String = ""
var display_name: String = ""
var kind: String = KIND_OLLAMA
var url: String = ""
var model: String = ""
## Nombre de la variable de entorno con la key ("" = sin key).
var api_key_env: String = ""
## Plantilla FIM en crudo ("" = el FIM nativo del endpoint: `suffix`, `input_suffix`).
var fim_template: String = ""
var stops: PackedStringArray = []
var temperature: float = 0.15
var max_tokens: int = 96


static func make(p_kind: String, p_id: String = "") -> RefCounted:
	var profile := new()
	profile.kind = p_kind if KINDS.has(p_kind) else KIND_OLLAMA
	profile.id = p_id if not p_id.is_empty() else profile.kind
	profile.display_name = str(KIND_LABELS[profile.kind]).get_slice(" (", 0)
	var defaults: Dictionary = KIND_DEFAULTS[profile.kind]
	profile.url = str(defaults.get("url", ""))
	profile.model = str(defaults.get("model", ""))
	profile.api_key_env = str(defaults.get("api_key_env", ""))
	profile.fim_template = str(defaults.get("fim_template", ""))
	return profile


static func defaults() -> Array:
	return [make(KIND_OLLAMA).to_dict()]


static func from_dict(data: Dictionary) -> RefCounted:
	var profile := make(str(data.get("kind", KIND_OLLAMA)), str(data.get("id", "")))
	profile.display_name = str(data.get("display_name", profile.display_name))
	profile.url = str(data.get("url", profile.url))
	profile.model = str(data.get("model", profile.model))
	profile.api_key_env = str(data.get("api_key_env", profile.api_key_env))
	profile.fim_template = str(data.get("fim_template", profile.fim_template))
	var raw_stops: Variant = data.get("stops", [])
	if raw_stops is Array or raw_stops is PackedStringArray:
		for stop: Variant in raw_stops:
			if not str(stop).is_empty():
				profile.stops.append(str(stop))
	# El JSON se puede editar a mano en Configuración del editor: un número de otro tipo queda en el default.
	var temperature: Variant = data.get("temperature")
	if temperature is float or temperature is int:
		profile.temperature = clampf(float(temperature), 0.0, 2.0)
	var max_tokens: Variant = data.get("max_tokens")
	if max_tokens is float or max_tokens is int:
		profile.max_tokens = clampi(int(max_tokens), 8, 1024)
	return profile


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"kind": kind,
		"url": url,
		"model": model,
		"api_key_env": api_key_env,
		"fim_template": fim_template,
		"stops": Array(stops),
		"temperature": temperature,
		"max_tokens": max_tokens,
	}


## Manda código fuera de la máquina (aviso en Settings, spec §16.3).
func is_remote() -> bool:
	var authority := url.strip_edges().trim_prefix("https://").trim_prefix("http://").get_slice("/", 0)
	var host := authority.get_slice("]", 0).trim_prefix("[") if authority.begins_with("[") else authority.get_slice(":", 0)
	return not host in ["localhost", "127.0.0.1", "::1"]


## Los tipos remotos que no responden sin key.
func needs_key() -> bool:
	return kind == KIND_CODESTRAL or kind == KIND_GEMINI


func is_experimental() -> bool:
	return kind == KIND_GEMINI


## La key del entorno del editor ("" si no hay variable o está vacía).
func api_key() -> String:
	return OS.get_environment(api_key_env) if not api_key_env.is_empty() else ""


## Stops del perfil más los de la plantilla en crudo (los tokens FIM no deben salir en el texto).
func all_stops() -> PackedStringArray:
	var out := stops.duplicate()
	if fim_template.contains("<|fim_"):
		for stop: String in QWEN_STOPS:
			if not out.has(stop):
				out.append(stop)
	return out
