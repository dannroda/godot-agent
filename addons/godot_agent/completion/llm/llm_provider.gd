@tool
extends "../completion_provider.gd"
## Proveedor LLM (spec §16.3): un `HTTPRequest` reutilizado por proveedor (uno por editor), una
## request en vuelo como máximo, `cancel()` la corta. El texto pasa por el PostProcessor con los
## stops del perfil. Nunca guarda la key ni loguea código: `last_error` y los tamaños son lo único
## que sale para el log.

const LlmProfile := preload("llm_profile.gd")
const LlmClient := preload("llm_client.gd")
const LlmContext := preload("llm_context.gd")
const ProjectContext := preload("../project_context.gd")
const PostProcessor := preload("../post_processor.gd")

const DEFAULT_PREFIX_CHARS := 4000
const DEFAULT_SUFFIX_CHARS := 1000
const DEFAULT_TIMEOUT_S := 8.0
## HTTPRequest no tiene un resultado "cancelado": este va en la señal emitida a mano.
const RESULT_CANCELLED := -1
## Una respuesta de completado es chica; más que esto es un server roto (o hostil).
const BODY_LIMIT := 1 << 20

var profile: LlmProfile
var context: ProjectContext
var prefix_chars: int = DEFAULT_PREFIX_CHARS
var suffix_chars: int = DEFAULT_SUFFIX_CHARS
var context_budget: int = LlmContext.DEFAULT_BUDGET_TOKENS
var max_lines: int = PostProcessor.DEFAULT_MAX_LINES
var timeout_s: float = DEFAULT_TIMEOUT_S
## Del último pedido, para el log y el indicador: "" si salió bien.
var last_error: String = ""
var last_input_chars: int = 0
var last_output_chars: int = 0

var _http: HTTPRequest
var _parent: Node
var _busy: bool = false
var _generation: int = 0


## `parent`: el nodo donde vive el HTTPRequest (CompletionService; en tests, la raíz).
func _init(p_parent: Node = null, p_profile: LlmProfile = null, p_context: ProjectContext = null) -> void:
	_parent = p_parent
	profile = p_profile
	context = p_context


func describe() -> Dictionary:
	var name := "llm"
	if profile:
		name = "%s · %s" % [profile.kind, profile.model] if not profile.model.is_empty() else profile.kind
	return {"name": name, "remote": profile != null and profile.is_remote(), "ai": true}


func is_busy() -> bool:
	return _busy


func complete(request: CompletionRequest) -> CompletionResult:
	if profile == null or _parent == null or not is_instance_valid(_parent):
		last_error = "no profile"
		return null
	cancel()
	# Sin la key no se manda nada (y menos el código a un host remoto que lo va a rechazar).
	if (profile.needs_key() or not profile.api_key_env.is_empty()) and profile.api_key().is_empty():
		if profile.api_key_env.is_empty():
			last_error = "the profile needs a key (environment variable)"
		else:
			last_error = "the environment variable %s is missing from the editor's environment" % profile.api_key_env
		return null
	var started := Time.get_ticks_usec()
	var parts := split(request, prefix_chars, suffix_chars)
	var extra := LlmContext.render(context, request.path, request.text, context_budget) if context and context_budget > 0 else ""
	var http := _request_node()
	var built := LlmClient.build(profile, parts.prefix, parts.suffix, extra, request.path.get_file())
	last_input_chars = str(built.body).length()
	last_output_chars = 0
	_generation += 1
	var generation := _generation
	var error := http.request(built.url, built.headers, HTTPClient.METHOD_POST, built.body)
	if error != OK:
		last_error = "could not send (%s)" % error_string(error)
		return null
	_busy = true
	var response: Array = await http.request_completed
	# Cancelado (o reemplazado por otro pedido) mientras esperaba.
	if generation != _generation:
		return null
	_busy = false
	var status: int = response[0]
	if status != HTTPRequest.RESULT_SUCCESS:
		last_error = _result_name(status)
		return null
	var body := (response[3] as PackedByteArray).get_string_from_utf8()
	var parsed := LlmClient.parse(profile.kind, int(response[1]), body)
	if parsed.has("error"):
		last_error = str(parsed.error).left(160)
		return null
	last_error = ""
	var raw_text: String = parsed.text
	last_output_chars = raw_text.length()
	var text := PostProcessor.process(raw_text, request, max_lines, profile.all_stops())
	if text.is_empty():
		return null
	var result := CompletionResult.make(text, 1.0, CompletionResult.SOURCE_LLM)
	result.latency_usec = Time.get_ticks_usec() - started
	result.seq = request.seq
	return result


## Corta la request en vuelo. `cancel_request()` no emite `request_completed`, así que se emite a
## mano: el `await` de `complete` despierta con una generación vieja y devuelve null.
func cancel() -> void:
	if not _busy:
		return
	_busy = false
	_generation += 1
	if _http and is_instance_valid(_http):
		_http.cancel_request()
		_http.request_completed.emit(RESULT_CANCELLED, 0, PackedStringArray(), PackedByteArray())


func release() -> void:
	cancel()
	if _http and is_instance_valid(_http):
		_http.queue_free()
	_http = null


## {prefix, suffix}: el texto antes y después del caret, recortado a líneas enteras dentro del
## máximo de caracteres (el prefix pierde el comienzo; el suffix, el final).
static func split(request: CompletionRequest, max_prefix: int, max_suffix: int) -> Dictionary:
	var lines := request.text.split("\n")
	var before := "\n".join(lines.slice(0, request.line))
	var prefix := (before + "\n" if request.line > 0 else "") + request.line_prefix
	var after := "\n".join(lines.slice(request.line + 1))
	var suffix := request.line_suffix + ("\n" + after if request.line + 1 < lines.size() else "")
	if prefix.length() > max_prefix:
		prefix = prefix.right(max_prefix)
		var cut := prefix.find("\n")
		if cut >= 0 and cut < prefix.length() - 1:
			prefix = prefix.substr(cut + 1)
	if suffix.length() > max_suffix:
		suffix = suffix.left(max_suffix)
		var cut := suffix.rfind("\n")
		if cut >= 0:
			suffix = suffix.left(cut + 1)
	return {"prefix": prefix, "suffix": suffix}


func _request_node() -> HTTPRequest:
	if _http == null or not is_instance_valid(_http):
		# Sin threads: HTTPClient no bloquea (resuelve y lee por poll en `_process`), y con threads
		# `cancel_request()` espera al thread, que puede estar esperando al server.
		_http = HTTPRequest.new()
		# Una redirección reenviaría el código y la key a otro host; un body enorme se parsearía en
		# el hilo principal.
		_http.max_redirects = 0
		_http.body_size_limit = BODY_LIMIT
		_parent.add_child(_http)
	_http.timeout = timeout_s
	return _http


static func _result_name(status: int) -> String:
	match status:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "could not connect"
		HTTPRequest.RESULT_TIMEOUT:
			return "timed out"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "the server redirects (not followed: the profile URL must be the final one)"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "response too large"
		RESULT_CANCELLED:
			return "cancelled"
	return "network error (%d)" % status
