@tool
extends RefCounted
## Si el nombre de una variable de entorno o de un header HTTP es el de un secreto (API keys, tokens,
## contraseñas). Lo usan la redacción del Agent Log (los valores del entorno del agente, m13-25) y
## las validaciones de Ajustes y de los servers MCP, que no dejan escribir un secreto a mano.
## Compara palabras enteras del nombre (m13-28): `ANTHROPIC_API_KEY`, `X-Api-Key`, `authToken` sí;
## `GIT_AUTHOR_NAME`, `KEYBOARD_LAYOUT` o `TOKENIZERS_PARALLELISM` no. Antes bastaba con contener
## «key» o «auth», y el valor de GIT_AUTHOR_NAME (el nombre del usuario) se tapaba en todo el chat.

## Palabras que hacen secreto a un nombre. Una palabra es lo que queda entre `_`, `-`, `.` y los
## cambios de minúscula a mayúscula.
const WORDS: PackedStringArray = ["KEY", "APIKEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "AUTH", "AUTHORIZATION", "CREDENTIAL", "CREDENTIALS", "BEARER", "COOKIE"]

static var _camel := RegEx.create_from_string("([a-z0-9])([A-Z])")
static var _separator := RegEx.create_from_string("[^A-Za-z0-9]+")


static func is_secret(name: String) -> bool:
	for word: String in words(name):
		if word in WORDS:
			return true
	return false


## Las palabras del nombre, en mayúsculas: "X-Api-Key" → ["X", "API", "KEY"], "authToken" → ["AUTH", "TOKEN"].
static func words(name: String) -> PackedStringArray:
	var spaced := _separator.sub(_camel.sub(name, "$1 $2", true), " ", true)
	var result: PackedStringArray = []
	for word: String in spaced.split(" ", false):
		result.append(word.to_upper())
	return result
