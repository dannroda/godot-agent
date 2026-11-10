extends "test_case.gd"
## Qué nombres de variables y headers son de secretos (m13-28): palabras enteras, no subcadenas.

const SecretNames := preload("res://addons/godot_agent/core/secret_names.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const ExternalMcpServers := preload("res://addons/godot_agent/mcp/external_mcp_servers.gd")


func test_secret_names() -> void:
	for name: String in ["ANTHROPIC_API_KEY", "OPENAI_APIKEY", "GITHUB_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "DB_PASSWORD", "MYSQL_PASSWD", "AWS_SECRET_ACCESS_KEY", "AUTH", "Authorization", "X-Api-Key", "x-auth-token", "authToken", "apiKey", "GOOGLE_APPLICATION_CREDENTIALS", "session.cookie", "PGPASSWORD", "API_KEYS", "SECRETS", "DB_PASSWORDS", "ACCESSKEY", "PRIVATEKEY", "SESSIONTOKEN", "HFToken", "GHToken", "OpenAIAPIKey"]:
		assert_true(SecretNames.is_secret(name), "%s es de un secreto" % name)


func test_names_that_only_contain_the_word() -> void:
	for name: String in ["GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "KEYBOARD_LAYOUT", "XKB_DEFAULT_KEYMAP", "MONKEY_PATCH", "TOKENIZERS_PARALLELISM", "OAUTHLIB_INSECURE_TRANSPORT", "SECRETARY", "PWD", "PATH", "Author", "TURKEY_MODE", "DONKEY", "HOCKEY_TEAM"]:
		assert_false(SecretNames.is_secret(name), "%s no es de un secreto" % name)


func test_words() -> void:
	assert_eq(SecretNames.words("X-Api-Key"), PackedStringArray(["X", "API", "KEY"]), "headers con guiones")
	assert_eq(SecretNames.words("authToken"), PackedStringArray(["AUTH", "TOKEN"]), "camelCase")
	assert_eq(SecretNames.words("HFToken"), PackedStringArray(["HF", "TOKEN"]), "sigla seguida de palabra")
	assert_eq(SecretNames.words("GIT_AUTHOR_NAME"), PackedStringArray(["GIT", "AUTHOR", "NAME"]), "snake_case")


## El caso del bug: el nombre del usuario en GIT_AUTHOR_NAME no se registra como secreto (se taparía
## en todo el chat), y Ajustes y los servers MCP no lo rechazan como «key escrita a mano».
func test_git_author_is_not_a_secret_anywhere() -> void:
	var env := {"GIT_AUTHOR_NAME": "Daniel Rodriguez Aires", "ANTHROPIC_API_KEY": "sk-ant-0123456789"}
	assert_eq(AgentProfile.secret_env_values(env), PackedStringArray(["sk-ant-0123456789"]), "solo la key")
	var server := ExternalMcpServers.make("git", ExternalMcpServers.TRANSPORT_STDIO)
	server.command = "git-mcp"
	server.env = {"GIT_AUTHOR_NAME": "Daniel Rodriguez Aires"}
	assert_eq(ExternalMcpServers.validate([server]), "", "un server MCP con GIT_AUTHOR_NAME se puede guardar")
	server.env = {"GITHUB_TOKEN": "ghp_0123456789"}
	assert_false(ExternalMcpServers.validate([server]).is_empty(), "uno con un token escrito a mano no")
