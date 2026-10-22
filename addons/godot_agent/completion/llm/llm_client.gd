@tool
extends RefCounted
## Formato de cada endpoint LLM (spec §16.3; lo verificado está en D28): arma el pedido HTTP
## {url, headers, body} y lee el texto de la respuesta. Sin red ni nodos: lo usa LlmProvider y lo
## prueban los tests con un server falso.

const LlmProfile := preload("llm_profile.gd")

const CURSOR := "<CURSOR>"
## Gemini no tiene FIM: se le pide el texto del cursor con una instrucción (experimental).
const GEMINI_INSTRUCTION := "You are a code completion engine for GDScript (Godot 4). The user message is a GDScript file with the marker <CURSOR>. Reply with only the code to insert at <CURSOR>: no explanations, no Markdown fences, no repetition of the code before or after the cursor. Reply with an empty message if nothing fits."
## OpenAI acepta hasta 4 stops y Gemini hasta 5.
const MAX_STOPS := {LlmProfile.KIND_OPENAI: 4, LlmProfile.KIND_GEMINI: 5}


## {url, headers: PackedStringArray, body: String}. `extra` es el contexto del proyecto (comentarios
## GDScript), que va antes del prefix salvo en llama.cpp (`input_extra`).
static func build(profile: LlmProfile, prefix: String, suffix: String, extra: String = "", file_name: String = "script.gd") -> Dictionary:
	var base := profile.url.strip_edges().trim_suffix("/")
	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := profile.api_key()
	var stops := profile.all_stops()
	if MAX_STOPS.has(profile.kind):
		stops = stops.slice(0, int(MAX_STOPS[profile.kind]))
	var raw := not profile.fim_template.is_empty()
	var prompt := extra + prefix
	var templated := fill_template(profile.fim_template, prompt, suffix)
	var body: Dictionary
	var url: String
	match profile.kind:
		LlmProfile.KIND_OLLAMA:
			url = base + "/api/generate"
			var options := {"num_predict": profile.max_tokens, "temperature": profile.temperature}
			if not stops.is_empty():
				options.stop = Array(stops)
			body = {"model": profile.model, "stream": false, "keep_alive": "30m", "options": options}
			if raw:
				body.prompt = templated
				body.raw = true
			else:
				body.prompt = prompt
				body.suffix = suffix
		LlmProfile.KIND_LLAMACPP:
			url = base + "/infill"
			body = {
				"input_prefix": prefix, "input_suffix": suffix, "n_predict": profile.max_tokens,
				"temperature": profile.temperature, "cache_prompt": true,
			}
			if not extra.is_empty():
				body.input_extra = [{"filename": "project_context.gd", "text": extra}]
			if not stops.is_empty():
				body.stop = Array(stops)
		LlmProfile.KIND_CODESTRAL:
			url = base + "/v1/fim/completions"
			body = {"model": profile.model, "prompt": prompt, "suffix": suffix, "max_tokens": profile.max_tokens, "temperature": profile.temperature, "stream": false}
			if not stops.is_empty():
				body.stop = Array(stops)
		LlmProfile.KIND_OPENAI:
			url = base + "/v1/completions"
			body = {"model": profile.model, "max_tokens": profile.max_tokens, "temperature": profile.temperature, "stream": false}
			if raw:
				body.prompt = templated
			else:
				body.prompt = prompt
				body.suffix = suffix
			if not stops.is_empty():
				body.stop = Array(stops)
		LlmProfile.KIND_GEMINI:
			url = "%s/v1beta/models/%s:generateContent" % [base, profile.model.uri_encode()]
			var config := {"maxOutputTokens": profile.max_tokens, "temperature": profile.temperature}
			if not stops.is_empty():
				config.stopSequences = Array(stops)
			body = {
				"systemInstruction": {"parts": [{"text": GEMINI_INSTRUCTION}]},
				"contents": [{"role": "user", "parts": [{"text": "%s%s%s%s" % [extra, prefix, CURSOR, suffix]}]}],
				"generationConfig": config,
			}
	if not key.is_empty():
		headers.append("x-goog-api-key: " + key if profile.kind == LlmProfile.KIND_GEMINI else "Authorization: Bearer " + key)
	return {"url": url, "headers": headers, "body": JSON.stringify(body)}


static func fill_template(template: String, prefix: String, suffix: String) -> String:
	return template.replace("{prefix}", prefix).replace("{suffix}", suffix)


## {text} o {error}. `code` es el status HTTP.
static func parse(kind: String, code: int, body: String) -> Dictionary:
	# JSON.new().parse: parse_string imprime un error por cada respuesta que no es JSON (HTML de un proxy).
	var json := JSON.new()
	var data: Variant = json.data if not body.is_empty() and json.parse(body) == OK else null
	if code < 200 or code >= 300:
		var message := _error_message(data)
		return {"error": "HTTP %d: %s" % [code, message] if not message.is_empty() else "HTTP %d" % code}
	if not data is Dictionary:
		return {"error": "response is not JSON"}
	var text: Variant = null
	match kind:
		LlmProfile.KIND_OLLAMA:
			text = data.get("response")
		LlmProfile.KIND_LLAMACPP:
			text = data.get("content")
		LlmProfile.KIND_CODESTRAL:
			text = _dig(data, ["choices", 0, "message", "content"])
		LlmProfile.KIND_OPENAI:
			text = _dig(data, ["choices", 0, "text"])
		LlmProfile.KIND_GEMINI:
			var parts: Variant = _dig(data, ["candidates", 0, "content", "parts"])
			if parts is Array:
				var joined := ""
				for part: Variant in parts:
					if part is Dictionary and part.get("text") is String and not part.get("thought", false):
						joined += part.text
				text = _strip_fences(joined)
			elif data.has("candidates") or data.has("promptFeedback"):
				text = ""  # bloqueado o vacío: sin sugerencia, no es un error del perfil
	if not text is String:
		return {"error": "response has no text"}
	return {"text": text}


## Lo que devuelve un modelo instructivo envuelto en ```gdscript ... ```.
static func _strip_fences(text: String) -> String:
	var trimmed := text.strip_edges()
	if not trimmed.begins_with("```"):
		return text
	var first_newline := trimmed.find("\n")
	if first_newline < 0:
		return ""
	trimmed = trimmed.substr(first_newline + 1)
	return trimmed.trim_suffix("```").trim_suffix("\n")


static func _dig(data: Variant, path: Array) -> Variant:
	var current: Variant = data
	for step: Variant in path:
		if step is int and current is Array and int(step) < (current as Array).size():
			current = current[step]
		elif step is String and current is Dictionary and (current as Dictionary).has(step):
			current = current[step]
		else:
			return null
	return current


## Solo los campos de mensaje conocidos: el resto del body puede repetir el prompt (un 422 de
## FastAPI trae el `input`), y el error va al log y al tooltip del indicador.
static func _error_message(data: Variant) -> String:
	if data is Dictionary:
		var error: Variant = data.get("error")
		if error is String:
			return error
		if error is Dictionary and error.get("message") is String:
			return error.message
		if data.get("message") is String:
			return data.message
		var detail: Variant = data.get("detail")
		if detail is String:
			return detail
		if detail is Array and not detail.is_empty() and detail[0] is Dictionary and detail[0].get("msg") is String:
			return detail[0].msg
	return ""
